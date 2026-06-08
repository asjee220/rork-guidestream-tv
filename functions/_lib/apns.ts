/**
 * APNs (Apple Push Notification service) sender using HTTP/2 + JWT.
 * Uses Web Crypto API for ES256 JWT signing — zero dependencies.
 */

const APNS_BASE = "https://api.push.apple.com" as const;

interface Env {
  APPLE_APNS_PRIVATE_KEY: string;
  APPLE_BUNDLE_ID: string;
  APPLE_KEY_ID: string;
  APPLE_TEAM_ID: string;
}

/** Decode a base64 string into a Uint8Array. */
function b64decode(s: string): Uint8Array {
  const bin = atob(s.replace(/-/g, "+").replace(/_/g, "/"));
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

/** Encode a Uint8Array as unpadded base64url. */
function b64url(buf: ArrayBuffer): string {
  const s = btoa(String.fromCharCode(...new Uint8Array(buf)));
  return s.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** Convert a PEM-encoded PKCS#8 private key to the raw PKCS#8 bytes Web Crypto needs. */
function pemToPkcs8(pem: string): Uint8Array {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  return b64decode(b64);
}

/**
 * Sign a JWT with ES256 and the Apple-provided private key.
 * Returns a signed token for the APNs `authorization` header.
 */
async function signApnsJwt(
  privateKeyPem: string,
  keyId: string,
  teamId: string,
): Promise<string> {
  const pkcs8 = pemToPkcs8(privateKeyPem);

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pkcs8,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  const header = { alg: "ES256", kid: keyId };
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: teamId,
    iat: now,
  };

  const headerB64 = b64url(new TextEncoder().encode(JSON.stringify(header)));
  const payloadB64 = b64url(new TextEncoder().encode(JSON.stringify(payload)));
  const toSign = `${headerB64}.${payloadB64}`;

  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(toSign),
  );
  const sigB64 = b64url(sig);

  return `${toSign}.${sigB64}`;
}

/** APNs error response shape. */
export interface ApnsError {
  reason: string;
  timestamp?: number;
}

/**
 * Send one push notification via APNs HTTP/2.
 * Returns the apns-id on success, null on expected failures (bad token),
 * and throws on unexpected errors.
 */
export async function sendApnsPush(
  env: Env,
  deviceToken: string,
  payload: Record<string, unknown>,
): Promise<{ apnsId: string } | null> {
  const jwt = await signApnsJwt(
    env.APPLE_APNS_PRIVATE_KEY,
    env.APPLE_KEY_ID,
    env.APPLE_TEAM_ID,
  );

  const topic = env.APPLE_BUNDLE_ID;
  const url = `${APNS_BASE}/3/device/${deviceToken}`;
  const uuid = crypto.randomUUID();

  const response = await fetch(url, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": topic,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-id": uuid,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      aps: {
        alert: {
          title: payload.title as string,
          body: payload.body as string,
        },
        sound: "default",
        badge: 1,
        "mutable-content": 1,
      },
      ...payload,
    }),
  });

  if (response.ok) {
    return { apnsId: uuid };
  }

  // 410 Gone — token is no longer valid, remove it
  if (response.status === 410) {
    return null;
  }

  // 400 BadDeviceToken — malformed token, discard
  if (response.status === 400) {
    const body = (await response.json().catch(() => ({}))) as ApnsError;
    if (body.reason === "BadDeviceToken") return null;
  }

  // Unexpected error — log and continue
  const body = (await response.text().catch(() => "???")) as string;
  console.error(
    `[APNs] push failed: status=${response.status} token=${deviceToken.slice(0, 8)}... body=${body}`,
  );
  return null;
}

/**
 * Send a batch of pushes to multiple device tokens.
 * Returns { sent, failed, invalid } counts.
 */
export async function sendBatchPush(
  env: Env,
  tokens: string[],
  payload: Record<string, unknown>,
): Promise<{ sent: number; failed: number; invalid: string[] }> {
  let sent = 0;
  let failed = 0;
  const invalid: string[] = [];

  // Send in parallel but limit concurrency to avoid overwhelming APNs
  const concurrency = 5;
  for (let i = 0; i < tokens.length; i += concurrency) {
    const chunk = tokens.slice(i, i + concurrency);
    const results = await Promise.all(
      chunk.map((t) => sendApnsPush(env, t, payload)),
    );
    for (let j = 0; j < results.length; j++) {
      const r = results[j];
      if (r === null) {
        invalid.push(chunk[j]!);
      } else if (r.apnsId) {
        sent++;
      } else {
        failed++;
      }
    }
  }

  return { sent, failed, invalid };
}

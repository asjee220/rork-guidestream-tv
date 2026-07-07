/**
 * FCM (Firebase Cloud Messaging) sender for Android push notifications.
 * Uses the FCM HTTP v1 API with OAuth2 service account JWT signing via Web Crypto.
 * Zero dependencies — mirrors the APNs sender pattern.
 *
 * Required env: FIREBASE_SERVICE_ACCOUNT_KEY (JSON string of the service account key)
 */

interface FcmEnv {
  FIREBASE_SERVICE_ACCOUNT_KEY?: string;
}

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
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

/** Convert a PEM private key to PKCS#8 bytes for Web Crypto. */
function pemToPkcs8(pem: string): Uint8Array {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  return b64decode(b64);
}

/** Parse the service account key JSON from the env. */
function parseServiceAccount(env: FcmEnv): ServiceAccount | null {
  const raw = env.FIREBASE_SERVICE_ACCOUNT_KEY;
  if (!raw) return null;
  try {
    return JSON.parse(raw) as ServiceAccount;
  } catch {
    return null;
  }
}

/** Sign a JWT with RS256 for Google OAuth2 service account auth. */
async function signJwt(
  sa: ServiceAccount,
  audience: string,
  scope: string,
): Promise<string> {
  const pkcs8 = pemToPkcs8(sa.private_key);
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pkcs8,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const header = { alg: "RS256", typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: sa.client_email,
    scope,
    aud: audience,
    iat: now,
    exp: now + 3600,
  };

  const headerB64 = b64url(new TextEncoder().encode(JSON.stringify(header)));
  const payloadB64 = b64url(new TextEncoder().encode(JSON.stringify(payload)));
  const toSign = `${headerB64}.${payloadB64}`;
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(toSign),
  );
  return `${toSign}.${b64url(sig)}`;
}

/** Get an OAuth2 access token for the FCM scope. */
async function getAccessToken(sa: ServiceAccount): Promise<string> {
  const audience = "https://oauth2.googleapis.com/token";
  const scope = "https://www.googleapis.com/auth/firebase.messaging";
  const jwt = await signJwt(sa, audience, scope);

  const response = await fetch(audience, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}`,
  });

  if (!response.ok) {
    const body = await response.text().catch(() => "???");
    throw new Error(`FCM OAuth2 failed: ${response.status} ${body.slice(0, 200)}`);
  }

  const data = (await response.json()) as { access_token: string };
  return data.access_token;
}

/**
 * Send one FCM push notification via the HTTP v1 API.
 * Returns true on success, false on failure (bad token, etc.).
 */
export async function sendFcmPush(
  env: FcmEnv,
  deviceToken: string,
  payload: Record<string, unknown>,
): Promise<boolean> {
  const sa = parseServiceAccount(env);
  if (!sa) {
    console.error("[FCM] No service account key configured — skipping FCM sends");
    return false;
  }

  try {
    const accessToken = await getAccessToken(sa);
    const url = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

    const title = (payload.title as string) ?? "GuideStream TV";
    const body = (payload.body as string) ?? "";
    const deepLink = (payload.deep_link as string) ?? undefined;

    const message: Record<string, unknown> = {
      token: deviceToken,
      notification: { title, body },
      android: {
        notification: {
          channel_id: "gs_episodes",
          priority: "high",
          sound: "default",
        },
      },
      data: {},
    };

    // Pass through custom data fields for deep linking
    if (deepLink) {
      (message.data as Record<string, string>).deep_link = deepLink;
    }
    if (payload.title_id) {
      (message.data as Record<string, string>).title_id = String(payload.title_id);
    }
    if (payload.platform_id) {
      (message.data as Record<string, string>).platform_id = String(payload.platform_id);
    }

    const response = await fetch(url, {
      method: "POST",
      headers: {
        authorization: `Bearer ${accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ message }),
    });

    if (response.ok) return true;

    // 404 = invalid token, 400 = malformed — treat as invalid
    if (response.status === 404 || response.status === 400) {
      const errBody = await response.text().catch(() => "???");
      console.error(
        `[FCM] push failed: status=${response.status} token=${deviceToken.slice(0, 8)}... body=${errBody.slice(0, 200)}`,
      );
      return false;
    }

    console.error(`[FCM] push failed: status=${response.status}`);
    return false;
  } catch (err) {
    console.error(`[FCM] error: ${(err as Error).message}`);
    return false;
  }
}

/**
 * Send a batch of FCM pushes to multiple Android device tokens.
 * Returns { sent, failed, invalid }.
 */
export async function sendBatchFcm(
  env: FcmEnv,
  tokens: string[],
  payload: Record<string, unknown>,
): Promise<{ sent: number; failed: number; invalid: string[] }> {
  let sent = 0;
  let failed = 0;
  const invalid: string[] = [];

  const concurrency = 5;
  for (let i = 0; i < tokens.length; i += concurrency) {
    const chunk = tokens.slice(i, i + concurrency);
    const results = await Promise.all(
      chunk.map((t) => sendFcmPush(env, t, payload)),
    );
    for (let j = 0; j < results.length; j++) {
      if (results[j]) {
        sent++;
      } else {
        failed++;
        invalid.push(chunk[j]!);
      }
    }
  }

  return { sent, failed, invalid };
}

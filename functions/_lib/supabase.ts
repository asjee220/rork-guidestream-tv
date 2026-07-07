/**
 * Supabase REST API helper for the Cloudflare Worker.
 * Uses the project's anon key — all relevant tables have permissive RLS.
 */

const SUPABASE_URL = "https://qwxxkubkbanridcqsqjo.supabase.co" as const;
const SUPABASE_ANON_KEY =
  "sb_publishable_b4OuwPfvEivzdiLNXgxv1g_3iGLhSE5" as const;

/** Generic fetch wrapper for Supabase REST API. */
async function supabaseGet<T = unknown>(
  path: string,
  params?: Record<string, string>,
): Promise<T[]> {
  const url = new URL(`${SUPABASE_URL}/rest/v1/${path}`);
  if (params) {
    for (const [k, v] of Object.entries(params)) {
      url.searchParams.set(k, v);
    }
  }

  const response = await fetch(url.toString(), {
    headers: {
      apikey: SUPABASE_ANON_KEY,
      authorization: `Bearer ${SUPABASE_ANON_KEY}`,
      accept: "application/json",
    },
  });

  if (!response.ok) {
    const body = await response.text().catch(() => "???");
    throw new Error(
      `Supabase GET ${path} failed: ${response.status} ${body.slice(0, 200)}`,
    );
  }

  return response.json() as Promise<T[]>;
}

async function supabasePost<T = unknown>(
  path: string,
  body: unknown,
): Promise<T> {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    method: "POST",
    headers: {
      apikey: SUPABASE_ANON_KEY,
      authorization: `Bearer ${SUPABASE_ANON_KEY}`,
      "content-type": "application/json",
      accept: "application/json",
      prefer: "return=representation",
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const text = await response.text().catch(() => "???");
    throw new Error(
      `Supabase POST ${path} failed: ${response.status} ${text.slice(0, 200)}`,
    );
  }

  return response.json() as Promise<T>;
}

async function supabaseDelete(
  path: string,
  params?: Record<string, string>,
): Promise<void> {
  const url = new URL(`${SUPABASE_URL}/rest/v1/${path}`);
  if (params) {
    for (const [k, v] of Object.entries(params)) {
      url.searchParams.set(k, v);
    }
  }

  const response = await fetch(url.toString(), {
    method: "DELETE",
    headers: {
      apikey: SUPABASE_ANON_KEY,
      authorization: `Bearer ${SUPABASE_ANON_KEY}`,
    },
  });

  if (!response.ok) {
    const body = await response.text().catch(() => "???");
    throw new Error(
      `Supabase DELETE ${path} failed: ${response.status} ${body.slice(0, 200)}`,
    );
  }
}

/**
 * Upsert rows into a table, resolving conflicts on the given column(s).
 * Uses Prefer: resolution=merge-duplicates so existing rows are updated.
 */
export async function supabaseUpsert(
  path: string,
  rows: unknown[],
  onConflict: string,
): Promise<void> {
  if (rows.length === 0) return;
  const url = new URL(`${SUPABASE_URL}/rest/v1/${path}`);
  url.searchParams.set("on_conflict", onConflict);
  const response = await fetch(url.toString(), {
    method: "POST",
    headers: {
      apikey: SUPABASE_ANON_KEY,
      authorization: `Bearer ${SUPABASE_ANON_KEY}`,
      "content-type": "application/json",
      prefer: "resolution=merge-duplicates,return=minimal",
    },
    body: JSON.stringify(rows),
  });
  if (!response.ok) {
    const text = await response.text().catch(() => "???");
    throw new Error(
      `Supabase UPSERT ${path} failed: ${response.status} ${text.slice(0, 200)}`,
    );
  }
}

// ── Row types ──────────────────────────────────────────────────────────

export interface NewEpisode {
  id: string;
  title_id: string;
  title: string | null;
  season: number | null;
  episode: number | null;
  platform: string | null;
  poster_url: string | null;
  is_new: boolean;
  released_at: string;
}

export interface UserStream {
  id: string;
  user_id: string | null;
  device_id: string | null;
  title_id: string;
  title: string | null;
}

export interface PushToken {
  user_id: string;
  apns_token: string;
  device_type: string;
  platform: string | null;
}

export interface PushLog {
  id?: string;
  push_sent_at: string;
  new_episode_id: string;
  title_id: string;
  title: string | null;
  season: number | null;
  episode: number | null;
  user_count: number;
}

// ── Query helpers ──────────────────────────────────────────────────────

/**
 * Fetch new episodes that haven't had a push sent yet.
 * Looks at the last 7 days to keep the query efficient.
 */
export async function fetchUnscheduledEpisodes(): Promise<NewEpisode[]> {
  const sevenDaysAgo = new Date(
    Date.now() - 7 * 24 * 60 * 60 * 1000,
  ).toISOString();
  return supabaseGet<NewEpisode>("new_episodes", {
    select: "*",
    is_new: "eq.true",
    released_at: `gte.${sevenDaysAgo}`,
    order: "released_at.desc",
    limit: "50",
  });
}

/**
 * Find the user_ids that follow a given title (by title_id) in their watch list.
 */
export async function fetchFollowerUserIds(
  titleId: string,
): Promise<string[]> {
  const rows = await supabaseGet<{ user_id: string | null }>("user_streams", {
    select: "user_id",
    title_id: `eq.${titleId}`,
  });
  return [...new Set(rows.map((r) => r.user_id).filter(Boolean) as string[])];
}

/**
 * Fetch push tokens for a list of user_ids.
 * Also checks that the user has notifications enabled (notify_push = true).
 */
export async function fetchPushTokensForUsers(
  userIds: string[],
): Promise<PushToken[]> {
  if (userIds.length === 0) return [];

  // Supabase `in` filter: comma-separated values
  const inClause = `(${userIds.map((id) => `"${id}"`).join(",")})`;

  return supabaseGet<PushToken>("push_tokens", {
    select: "user_id,apns_token,device_type,platform",
    user_id: `in.${inClause}`,
  });
}

/**
 * Remove invalid (410) tokens from the push_tokens table.
 */
export async function deleteInvalidTokens(tokens: string[]): Promise<void> {
  if (tokens.length === 0) return;
  const inClause = `(${tokens.map((t) => `"${t}"`).join(",")})`;
  await supabaseDelete("push_tokens", {
    apns_token: `in.${inClause}`,
  });
}

/**
 * Mark an episode as push-notified (is_new = false).
 */
export async function markEpisodeNotified(episodeId: string): Promise<void> {
  // Use PATCH to update
  const response = await fetch(
    `${SUPABASE_URL}/rest/v1/new_episodes?id=eq.${episodeId}`,
    {
      method: "PATCH",
      headers: {
        apikey: SUPABASE_ANON_KEY,
        authorization: `Bearer ${SUPABASE_ANON_KEY}`,
        "content-type": "application/json",
        prefer: "return=minimal",
      },
      body: JSON.stringify({ is_new: false }),
    },
  );
  if (!response.ok) {
    const body = await response.text().catch(() => "???");
    console.error(
      `[Supabase] markEpisodeNotified failed: ${response.status} ${body.slice(0, 200)}`,
    );
  }
}

/** Log a push batch for diagnostics. */
export async function logPushBatch(log: PushLog): Promise<void> {
  try {
    await supabasePost("push_logs", log);
  } catch (err) {
    console.error("[Supabase] logPushBatch failed:", (err as Error).message);
  }
}

// ── Debug ──────────────────────────────────────────────────────────────

export async function debugStatus(userId: string) {
  // Check user's streams (watch list)
  const streams = await supabaseGet<{ title_id: string; title: string | null }>(
    "user_streams",
    { select: "title_id,title", user_id: `eq.${userId}` },
  );

  // Check user's push token
  const tokens = await supabaseGet<{ apns_token: string; device_type: string }>(
    "push_tokens",
    { select: "apns_token,device_type", user_id: `eq.${userId}` },
  );

  // Check new episodes for the user's titles
  let matchingEpisodes: unknown[] = [];
  if (streams.length > 0) {
    const titleIds = streams.map((s) => `"${s.title_id}"`).join(",");
    matchingEpisodes = await supabaseGet("new_episodes", {
      select: "id,title_id,title,season,episode,is_new,released_at",
      title_id: `in.(${titleIds})`,
      is_new: "eq.true",
      order: "released_at.desc",
      limit: "20",
    });
  }

  return {
    userId,
    watchlistCount: streams.length,
    watchlist: streams.map((s) => ({ title_id: s.title_id, title: s.title })),
    pushTokenCount: tokens.length,
    pushTokens: tokens.map((t) => ({
      device_type: t.device_type,
      token_preview: `${t.apns_token.slice(0, 8)}...`,
    })),
    matchingNewEpisodes: matchingEpisodes,
    diagnosis: diagnose(streams, tokens, matchingEpisodes),
  };
}

function diagnose(
  streams: unknown[],
  tokens: unknown[],
  episodes: unknown[],
): string {
  if (streams.length === 0) return "No titles in watch list — add shows to get episode notifications.";
  if (tokens.length === 0) return "No push token stored — enable notifications in the app first.";
  if (episodes.length === 0) return "No new episodes found for your watch list titles. The EpisodeTrackerService may need to run.";
  return `Ready: ${episodes.length} new episode(s) pending. Run /cron/send-push to dispatch.`;
}

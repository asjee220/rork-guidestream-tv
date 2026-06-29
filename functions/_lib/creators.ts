/**
 * Live creator search across YouTube and Twitch.
 *
 * Keeps the platform API keys server-side. Results are normalized into the
 * shape of the `content_sources` table so the client can render them with the
 * same UI it uses for seeded creators, and discovered creators are upserted
 * into `content_sources` (and `live_status` for Twitch) so following, opening
 * the creator detail, and future episode detection all work seamlessly.
 */

import { supabaseUpsert } from "./supabase";

export interface CreatorSearchEnv {
  YOUTUBE_API_KEY?: string;
  TWITCH_CLIENT_ID?: string;
  TWITCH_CLIENT_SECRET?: string;
}

/** Normalized creator result — matches the client ContentSource shape. */
export interface CreatorResult {
  title_id: string;
  source_type: "youtube" | "twitch";
  display_name: string;
  handle: string | null;
  image_url: string | null;
  channel_url: string | null;
  external_id: string | null;
  category: string | null;
  description: string | null;
  is_live?: boolean;
  stream_title?: string | null;
  viewer_count?: number | null;
}

// ── YouTube ─────────────────────────────────────────────────────────────

interface YouTubeSearchItem {
  id?: { channelId?: string };
  snippet?: {
    title?: string;
    description?: string;
    channelTitle?: string;
    thumbnails?: Record<string, { url?: string }>;
  };
}

async function searchYouTube(
  query: string,
  apiKey: string,
): Promise<CreatorResult[]> {
  const url = new URL("https://www.googleapis.com/youtube/v3/search");
  url.searchParams.set("part", "snippet");
  url.searchParams.set("type", "channel");
  url.searchParams.set("maxResults", "8");
  url.searchParams.set("q", query);
  url.searchParams.set("key", apiKey);

  const res = await fetch(url.toString());
  if (!res.ok) {
    const body = await res.text().catch(() => "???");
    throw new Error(`YouTube search failed: ${res.status} ${body.slice(0, 200)}`);
  }
  const json = (await res.json()) as { items?: YouTubeSearchItem[] };
  const items = json.items ?? [];

  const results: CreatorResult[] = [];
  const channelIds: string[] = [];
  for (const item of items) {
    const channelId = item.id?.channelId;
    if (!channelId) continue;
    channelIds.push(channelId);
    const snippet = item.snippet ?? {};
    const thumbs = snippet.thumbnails ?? {};
    const image =
      thumbs.high?.url ?? thumbs.medium?.url ?? thumbs.default?.url ?? null;
    results.push({
      title_id: `yt:${channelId}`,
      source_type: "youtube",
      display_name: snippet.title ?? snippet.channelTitle ?? "YouTube channel",
      handle: null,
      image_url: image,
      channel_url: `https://www.youtube.com/channel/${channelId}`,
      external_id: channelId,
      category: null,
      description: snippet.description ?? null,
    });
  }

  // Enrich with channel topicDetails (YouTube's own categorization).
  if (channelIds.length > 0) {
    const topicsMap = await fetchYouTubeTopics(channelIds, apiKey);
    for (const r of results) {
      const externalId = r.external_id;
      if (externalId && topicsMap.has(externalId)) {
        r.category = topicsMap.get(externalId) ?? null;
      }
    }
  }

  return results;
}

// ── YouTube Channel Topic Enrichment ───────────────────────────────────

interface YouTubeChannelResponse {
  items?: Array<{
    id?: string;
    topicDetails?: {
      topicCategories?: string[];
    };
  }>;
}

/**
 * Fetches topicDetails for a batch of channel IDs and maps Freebase/Wikipedia
 * topic URLs to human-readable category strings (e.g. "Automobile, Vehicle").
 */
async function fetchYouTubeTopics(
  channelIds: string[],
  apiKey: string,
): Promise<Map<string, string>> {
  const result = new Map<string, string>();
  try {
    const url = new URL("https://www.googleapis.com/youtube/v3/channels");
    url.searchParams.set("part", "topicDetails");
    url.searchParams.set("id", channelIds.join(","));
    url.searchParams.set("key", apiKey);

    const res = await fetch(url.toString());
    if (!res.ok) {
      console.error(
        `[youtube] channels.list failed: ${res.status}`,
      );
      return result;
    }
    const json = (await res.json()) as YouTubeChannelResponse;
    for (const item of json.items ?? []) {
      const id = item.id;
      const topics = item.topicDetails?.topicCategories ?? [];
      if (!id || topics.length === 0) continue;
      const labels = topics
        .map(topicUrlToLabel)
        .filter((l): l is string => l !== null);
      if (labels.length > 0) {
        result.set(id, labels.join(", "));
      }
    }
  } catch (err) {
    console.error("[youtube] topic enrichment error:", (err as Error).message);
  }
  return result;
}

/**
 * Converts a YouTube topic URL (Freebase → Wikipedia redirect) to a
 * human-readable label. Returns null for overly generic or unparseable topics.
 *
 * Example: "https://en.wikipedia.org/wiki/Automobile" → "Automobile"
 */
function topicUrlToLabel(url: string): string | null {
  // Extract the article title from a Wikipedia URL.
  const match = url.match(/\/wiki\/(.+?)(?:#|$)/);
  if (!match) return null;
  let label = decodeURIComponent(match[1]).replace(/_/g, " ").trim();
  // Skip overly broad / non-descriptive topics that add no content signal.
  const skip: Set<string> = new Set([
    "lifestyle (sociology)", "lifestyle",
    "entertainment", "entertainment (culture)",
    "society",
    "culture",
    "technology",
    "music",
    "sports",
    "food",
    "travel",
    "film",
    "television",
    "video game culture",
    "internet culture",
    "hobby",
    "do it yourself", "diy",
    "how-to", "tutorial",
    "vlog",
    "review",
    "unboxing",
    "reaction",
    "commentary",
    "gaming",
    "comedy",
    "news",
    "politics",
    "education",
    "science",
    "health",
    "fitness",
    "cooking",
    "fashion",
    "beauty",
    "art",
    "photography",
    "animals", "pets",
    "kids", "family",
    "business",
    "finance",
    "marketing",
    "podcast",
    "blog",
    "social media",
    "streaming",
    "content creator",
  ]);
  if (skip.has(label.toLowerCase())) return null;
  // Clean parenthetical disambiguation like "Automobile (Vehicle)" → "Automobile"
  const parenIdx = label.indexOf(" (");
  if (parenIdx > 0) label = label.slice(0, parenIdx);
  return label.length >= 2 ? label : null;
}

/**
 * Public entry point: enrich a batch of YouTube title_ids with categories
 * from the YouTube Data API. Used by the /enrich/creators endpoint and called
 * from the client when followed creators lack categories.
 */
export async function enrichYouTubeCategories(
  titleIds: string[],
  apiKey: string,
): Promise<Map<string, string>> {
  const channelIds: string[] = [];
  const idMap = new Map<string, string>(); // channelId → titleId
  for (const tid of titleIds) {
    if (tid.startsWith("yt:")) {
      const cid = tid.slice(3);
      channelIds.push(cid);
      idMap.set(cid, tid);
    }
  }
  if (channelIds.length === 0) return new Map();

  const topicsMap = await fetchYouTubeTopics(channelIds, apiKey);
  const result = new Map<string, string>();
  for (const [cid, category] of topicsMap) {
    const tid = idMap.get(cid);
    if (tid) result.set(tid, category);
  }
  return result;
}

// ── Twitch ──────────────────────────────────────────────────────────────

let cachedTwitchToken: { token: string; expiresAt: number } | null = null;

async function getTwitchToken(
  clientId: string,
  clientSecret: string,
): Promise<string> {
  const now = Date.now();
  if (cachedTwitchToken && cachedTwitchToken.expiresAt > now + 60_000) {
    return cachedTwitchToken.token;
  }
  const url = new URL("https://id.twitch.tv/oauth2/token");
  url.searchParams.set("client_id", clientId);
  url.searchParams.set("client_secret", clientSecret);
  url.searchParams.set("grant_type", "client_credentials");

  const res = await fetch(url.toString(), { method: "POST" });
  if (!res.ok) {
    const body = await res.text().catch(() => "???");
    throw new Error(`Twitch token failed: ${res.status} ${body.slice(0, 200)}`);
  }
  const json = (await res.json()) as {
    access_token: string;
    expires_in: number;
  };
  cachedTwitchToken = {
    token: json.access_token,
    expiresAt: now + json.expires_in * 1000,
  };
  return json.access_token;
}

interface TwitchChannel {
  broadcaster_login?: string;
  display_name?: string;
  id?: string;
  thumbnail_url?: string;
  is_live?: boolean;
  title?: string;
  game_name?: string;
}

async function searchTwitch(
  query: string,
  clientId: string,
  clientSecret: string,
): Promise<CreatorResult[]> {
  const token = await getTwitchToken(clientId, clientSecret);
  const url = new URL("https://api.twitch.tv/helix/search/channels");
  url.searchParams.set("query", query);
  url.searchParams.set("first", "8");

  const res = await fetch(url.toString(), {
    headers: {
      "client-id": clientId,
      authorization: `Bearer ${token}`,
    },
  });
  if (!res.ok) {
    const body = await res.text().catch(() => "???");
    throw new Error(`Twitch search failed: ${res.status} ${body.slice(0, 200)}`);
  }
  const json = (await res.json()) as { data?: TwitchChannel[] };
  const channels = json.data ?? [];

  const results: CreatorResult[] = [];
  for (const ch of channels) {
    const login = ch.broadcaster_login?.toLowerCase();
    if (!login) continue;
    results.push({
      title_id: `tw:${login}`,
      source_type: "twitch",
      display_name: ch.display_name ?? login,
      handle: `@${login}`,
      image_url: ch.thumbnail_url ?? null,
      channel_url: `https://www.twitch.tv/${login}`,
      external_id: ch.id ?? null,
      category: ch.game_name ?? null,
      description: null,
      is_live: ch.is_live ?? false,
      stream_title: ch.title ?? null,
      viewer_count: null,
    });
  }
  return results;
}

// ── Public entry point ──────────────────────────────────────────────────

export type CreatorSearchType = "all" | "youtube" | "twitch";

/**
 * Search YouTube and/or Twitch for creators matching `query`, persist the
 * discovered creators into Supabase, and return the normalized results.
 * Missing API keys for a platform are skipped gracefully rather than failing
 * the whole request.
 */
export async function searchCreators(
  query: string,
  type: CreatorSearchType,
  env: CreatorSearchEnv,
): Promise<CreatorResult[]> {
  const trimmed = query.trim();
  if (!trimmed) return [];

  const tasks: Promise<CreatorResult[]>[] = [];

  if ((type === "all" || type === "youtube") && env.YOUTUBE_API_KEY) {
    tasks.push(
      searchYouTube(trimmed, env.YOUTUBE_API_KEY).catch((err) => {
        console.error("[search] youtube error:", (err as Error).message);
        return [];
      }),
    );
  }
  if (
    (type === "all" || type === "twitch") &&
    env.TWITCH_CLIENT_ID &&
    env.TWITCH_CLIENT_SECRET
  ) {
    tasks.push(
      searchTwitch(trimmed, env.TWITCH_CLIENT_ID, env.TWITCH_CLIENT_SECRET).catch(
        (err) => {
          console.error("[search] twitch error:", (err as Error).message);
          return [];
        },
      ),
    );
  }

  const settled = await Promise.all(tasks);
  const results = settled.flat();

  // Persist discovered creators so follow / detail / detection work later.
  await persistCreators(results);

  return results;
}

async function persistCreators(results: CreatorResult[]): Promise<void> {
  if (results.length === 0) return;
  try {
    const sourceRows = results.map((r) => ({
      title_id: r.title_id,
      source_type: r.source_type,
      display_name: r.display_name,
      handle: r.handle,
      image_url: r.image_url,
      external_id: r.external_id,
      channel_url: r.channel_url,
      category: r.category,
      description: r.description,
    }));
    await supabaseUpsert("content_sources", sourceRows, "title_id");

    const liveRows = results
      .filter((r) => r.source_type === "twitch")
      .map((r) => ({
        title_id: r.title_id,
        is_live: r.is_live ?? false,
        stream_title: r.stream_title ?? null,
        viewer_count: r.viewer_count ?? null,
        updated_at: new Date().toISOString(),
      }));
    if (liveRows.length > 0) {
      await supabaseUpsert("live_status", liveRows, "title_id");
    }
  } catch (err) {
    // Persistence is best-effort; never fail the search because of it.
    console.error("[search] persist error:", (err as Error).message);
  }
}

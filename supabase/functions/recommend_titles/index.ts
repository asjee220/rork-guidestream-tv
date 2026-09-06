// recommend_titles
// Server-side scorer behind the "Recommended for You" home rail on iOS, tvOS
// and Android. Companion to recommend_creators, which does the same job for
// creators/podcasts — this one recommends TMDB titles.
//
// Body: { userId?, deviceId?, subscribedServices: string[], limit?, force? }
// Returns: { items: [...], cached, seed_count, signal_fingerprint, computed_at }
//
// WHY A SERVER FUNCTION. Three clients, one scorer. The creator recommender was
// moved server-side for exactly this reason ("so iOS and Android score
// identically and the algorithm never drifts between platforms") and the same
// applies here, with the added constraint that the signals live in six tables
// no client reads in full.
//
// SIGNALS (all four groups the product asked for), keyed on the owner —
// users.id::text when signed in, device_id for guests, which is the convention
// every signal table already follows:
//
//   explicit    user_streams (watchlist)        weight 5
//               title_likes                     weight 5
//               title_watched                   weight 4  (taste, not a target)
//               release_reminders               weight 4
//   trailers    trailer_liked                   weight 4
//               trailer_watched                 weight 3
//               trailer_viewed                  weight 2
//   browse      deeplink_fired                  weight 4  (they went to watch it)
//               watchlist_added / watched_toggled weight 3
//               episode_detail_viewed           weight 2
//               card_tapped                     weight 1  (noisiest, kept lowest)
//   affinity    team_favorites                  genre nudge, not a seed
//               followed creators               genre nudge, not a seed
//
// Every weight decays with a 30-day half-life, so taste moves as the user does.
//
// TEAMS AND CREATORS ARE DELIBERATELY NOT SEEDS. A favourited NFL team has no
// TMDB title to recommend from, and a followed YouTube channel is not a movie.
// Turning either into a seed would mean guessing at a TMDB search, which is how
// a recommender starts confidently suggesting the wrong thing. They shape the
// GENRE histogram instead: teams nudge Documentary, creators nudge the genres
// their content_sources category maps to. That is a real contribution to
// ranking without inventing a relationship the data does not support.
//
// SUBSCRIBED-ONLY. Every returned title is watchable on a service the user
// already pays for. Two mechanisms, because neither alone is enough:
//   1. /discover with with_watch_providers + watch_region=US returns
//      subscribed-only candidates in ONE call, but knows nothing about taste
//      beyond genre.
//   2. /{type}/{id}/recommendations knows taste but ignores availability, so
//      those candidates are provider-checked individually, bounded.
// The two pools are merged and scored together.
//
// CACHE AND FRESHNESS. public.title_recommendations is keyed by owner and holds
// a signal_fingerprint — a digest of the owner's signal counts and latest
// timestamps, computed from the rows this function already had to read, so it
// costs nothing extra. A cached row is served only when the fingerprint AND the
// subscribed-service set both still match and the row is inside its TTL.
// Saving a title, liking a trailer or changing services therefore rebuilds the
// rail on the very next open, while an idle user costs zero TMDB calls. The TTL
// is a backstop for catalogue churn, not the primary freshness mechanism.
// deno-lint-ignore-file no-explicit-any
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const env = (k: string): string => Deno.env.get(k) ?? "";
const TMDB_KEY = env("TMDB_API_KEY");

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...CORS, "content-type": "application/json" } });

const supabase = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"));

const HOME_REGION = "US";
const TTL_MS = 24 * 60 * 60 * 1000;
const HALF_LIFE_DAYS = 30;
const MAX_SEEDS = 10;          // TMDB /recommendations calls per rebuild
const PROVIDER_CHECKS = 24;    // bounded availability checks on taste candidates
const PROVIDER_CONCURRENCY = 6;
const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 60;
const SIGNAL_LOOKBACK_DAYS = 180;

type MediaType = "tv" | "movie";
type Seed = { tmdbId: number; mediaType: MediaType; weight: number };
type Candidate = {
  tmdb_id: number;
  media_type: MediaType;
  title: string;
  poster_path: string | null;
  backdrop_path: string | null;
  genre_ids: number[];
  vote_average: number;
  popularity: number;
  taste: number;       // from seed recommendations
  fromDiscover: boolean;
  seedHits: number;
};

const clamp = (n: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, n));
const norm = (s: string): string => (s || "").toLowerCase().replace(/[^a-z0-9]/g, "");

// 30-day half-life. A like from today counts double one from a month ago.
function decay(iso: string | null): number {
  if (!iso) return 0.5;
  const days = (Date.now() - new Date(iso).getTime()) / 86_400_000;
  if (!Number.isFinite(days) || days < 0) return 1;
  return Math.pow(0.5, days / HALF_LIFE_DAYS);
}

// user_streams.title_id doubles as a creator id for followed channels, so a
// non-numeric value is a follow, not a title. Callers that want seeds must use
// this rather than Number() directly.
function asTmdbId(v: unknown): number | null {
  const s = String(v ?? "").trim();
  if (!/^\d+$/.test(s)) return null;
  const n = Number(s);
  return Number.isSafeInteger(n) && n > 0 ? n : null;
}

const asMediaType = (v: unknown, isTv?: unknown): MediaType => {
  const s = String(v ?? "").toLowerCase();
  if (s === "movie") return "movie";
  if (s === "tv") return "tv";
  return isTv === false ? "movie" : "tv";
};

async function tmdb(path: string, params: Record<string, string> = {}): Promise<any | null> {
  if (!TMDB_KEY) return null;
  const qs = new URLSearchParams({ api_key: TMDB_KEY, ...params });
  try {
    const res = await fetch(`https://api.themoviedb.org/3${path}?${qs}`);
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}

// ---- Subscribed services -> TMDB provider ids --------------------------------
// The clients do not agree on what they send: iOS and tvOS send catalog ids
// ("prime"), Android sends display names ("Prime Video"). Match on catalog_id,
// any alias, and the display name so both shapes resolve.
async function providerIdsFor(services: string[]): Promise<{ ids: number[]; catalogIds: Set<string> }> {
  if (!services.length) return { ids: [], catalogIds: new Set() };
  const wanted = new Set(services.map(norm).filter(Boolean));
  const { data } = await supabase
    .from("provider_brand_map")
    .select("tmdb_provider_id, display_name, catalog_id, aliases");
  const ids: number[] = [];
  const catalogIds = new Set<string>();
  for (const row of (data ?? []) as any[]) {
    const keys = [row.catalog_id, row.display_name, ...(row.aliases ?? [])].map(norm);
    if (!keys.some((k) => k && wanted.has(k))) continue;
    if (Number(row.tmdb_provider_id) > 0) ids.push(Number(row.tmdb_provider_id));
    if (row.catalog_id) catalogIds.add(String(row.catalog_id));
  }
  return { ids: [...new Set(ids)], catalogIds };
}

// ---- Signals -----------------------------------------------------------------

const EVENT_WEIGHTS: Record<string, number> = {
  deeplink_fired: 4,
  trailer_liked: 4,
  trailer_watched: 3,
  watchlist_added: 3,
  watched_toggled: 3,
  trailer_viewed: 2,
  episode_detail_viewed: 2,
  card_tapped: 1,
};

type Signals = {
  seeds: Seed[];
  excluded: Set<string>;       // "tv:123" already saved or watched
  creatorIds: string[];
  teamCount: number;
  fingerprint: string;
};

async function gatherSignals(userId: string | null, deviceId: string | null): Promise<Signals> {
  const since = new Date(Date.now() - SIGNAL_LOOKBACK_DAYS * 86_400_000).toISOString();
  const ownerFilter = (q: any) =>
    userId ? q.eq("user_id", userId) : q.eq("device_id", deviceId);

  const [streams, likes, watched, reminders, teams, events] = await Promise.all([
    ownerFilter(supabase.from("user_streams").select("title_id, is_tv, added_at")).limit(300),
    ownerFilter(supabase.from("title_likes").select("tmdb_id, media_type, title_id, created_at")).limit(300),
    ownerFilter(supabase.from("title_watched").select("tmdb_id, media_type, title_id, created_at")).limit(300),
    ownerFilter(supabase.from("release_reminders").select("tmdb_id, media_type, title_id, created_at")).limit(200),
    ownerFilter(supabase.from("team_favorites").select("id, created_at")).limit(100),
    ownerFilter(
      supabase.from("watch_intent_events")
        .select("event_type, title_id, metadata, created_at")
        .in("event_type", Object.keys(EVENT_WEIGHTS))
        .gte("created_at", since)
        .order("created_at", { ascending: false }),
    ).limit(600),
  ]);

  const weights = new Map<string, Seed>();
  const excluded = new Set<string>();
  const creatorIds: string[] = [];
  let latest = "";
  let rows = 0;

  const note = (iso: string | null) => { rows++; if (iso && iso > latest) latest = iso; };

  const add = (tmdbId: number | null, mt: MediaType, w: number, iso: string | null) => {
    if (!tmdbId) return;
    const k = `${mt}:${tmdbId}`;
    const prev = weights.get(k);
    const inc = w * decay(iso);
    if (prev) prev.weight += inc;
    else weights.set(k, { tmdbId, mediaType: mt, weight: inc });
  };

  for (const r of (streams.data ?? []) as any[]) {
    note(r.added_at);
    const id = asTmdbId(r.title_id);
    if (id === null) { creatorIds.push(String(r.title_id)); continue; }
    const mt = asMediaType(null, r.is_tv);
    add(id, mt, 5, r.added_at);
    // is_tv is nullable and unreliable (see watchmode_resolve v21/v22), so a
    // saved title is excluded under BOTH media types rather than guessing.
    excluded.add(`movie:${id}`);
    excluded.add(`tv:${id}`);
  }
  for (const r of (likes.data ?? []) as any[]) {
    note(r.created_at);
    const id = r.tmdb_id ?? asTmdbId(r.title_id);
    add(id, asMediaType(r.media_type), 5, r.created_at);
  }
  for (const r of (watched.data ?? []) as any[]) {
    note(r.created_at);
    const id = r.tmdb_id ?? asTmdbId(r.title_id);
    const mt = asMediaType(r.media_type);
    add(id, mt, 4, r.created_at);
    if (id) excluded.add(`${mt}:${id}`);
  }
  for (const r of (reminders.data ?? []) as any[]) {
    note(r.created_at);
    add(r.tmdb_id ?? asTmdbId(r.title_id), asMediaType(r.media_type), 4, r.created_at);
  }
  for (const r of (teams.data ?? []) as any[]) note(r.created_at);
  for (const r of (events.data ?? []) as any[]) {
    note(r.created_at);
    const w = EVENT_WEIGHTS[r.event_type] ?? 0;
    if (!w) continue;
    const id = asTmdbId(r.title_id) ?? asTmdbId(r.metadata?.tmdb_id);
    add(id, asMediaType(r.metadata?.media_type), w, r.created_at);
  }

  const seeds = [...weights.values()].sort((a, b) => b.weight - a.weight);
  return {
    seeds,
    excluded,
    creatorIds,
    teamCount: (teams.data ?? []).length,
    fingerprint: `${rows}|${latest}|${seeds.length}`,
  };
}

// ---- Genre affinity ----------------------------------------------------------
// Documentary is 99 on both the tv and movie endpoints; most other ids differ
// between them, which is why the histogram is only ever a nudge, never a filter.
const DOCUMENTARY = 99;

const CREATOR_CATEGORY_GENRES: Array<[RegExp, number[]]> = [
  [/comedy|humor/i, [35]],
  [/sport|fitness/i, [DOCUMENTARY]],
  [/news|politic/i, [DOCUMENTARY, 10768]],
  [/tech|science|educat/i, [DOCUMENTARY, 878]],
  [/game|gaming/i, [878, 28]],
  [/music/i, [10402]],
  [/food|cook|travel/i, [DOCUMENTARY]],
  [/crime|mystery/i, [80, 9648]],
  [/horror|paranormal/i, [27]],
  [/film|movie|cinema|review/i, [18]],
];

async function genreNudges(creatorIds: string[], teamCount: number): Promise<Map<number, number>> {
  const nudges = new Map<number, number>();
  const bump = (g: number, by: number) => nudges.set(g, (nudges.get(g) ?? 0) + by);

  if (teamCount > 0) bump(DOCUMENTARY, Math.min(teamCount, 5) * 0.4);

  if (creatorIds.length) {
    const { data } = await supabase
      .from("content_sources")
      .select("title_id, category")
      .in("title_id", creatorIds.slice(0, 60));
    for (const row of (data ?? []) as any[]) {
      const cat = String(row.category ?? "");
      for (const [re, genres] of CREATOR_CATEGORY_GENRES) {
        if (re.test(cat)) for (const g of genres) bump(g, 0.5);
      }
    }
  }
  return nudges;
}

// ---- Candidate pools ---------------------------------------------------------

function absorb(pool: Map<string, Candidate>, raw: any, mt: MediaType, taste: number, fromDiscover: boolean) {
  const id = Number(raw?.id);
  if (!Number.isSafeInteger(id) || id <= 0) return;
  const title = String(raw?.name ?? raw?.title ?? "").trim();
  if (!title) return;
  const key = `${mt}:${id}`;
  const existing = pool.get(key);
  if (existing) {
    existing.taste += taste;
    if (taste > 0) existing.seedHits += 1;
    existing.fromDiscover = existing.fromDiscover || fromDiscover;
    return;
  }
  pool.set(key, {
    tmdb_id: id,
    media_type: mt,
    title,
    poster_path: raw?.poster_path ?? null,
    backdrop_path: raw?.backdrop_path ?? null,
    genre_ids: Array.isArray(raw?.genre_ids) ? raw.genre_ids.map(Number) : [],
    vote_average: Number(raw?.vote_average ?? 0),
    popularity: Number(raw?.popularity ?? 0),
    taste,
    fromDiscover,
    seedHits: taste > 0 ? 1 : 0,
  });
}

async function mapLimit<T, R>(items: T[], limit: number, fn: (t: T) => Promise<R>): Promise<R[]> {
  const out: R[] = new Array(items.length);
  let i = 0;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (i < items.length) {
      const idx = i++;
      out[idx] = await fn(items[idx]);
    }
  });
  await Promise.all(workers);
  return out;
}

async function streamsOnSubscribed(c: Candidate, providerIds: Set<number>): Promise<boolean> {
  const body = await tmdb(`/${c.media_type}/${c.tmdb_id}/watch/providers`);
  const us = body?.results?.[HOME_REGION];
  if (!us) return false;
  for (const bucket of ["flatrate", "ads", "free"]) {
    for (const p of (us[bucket] ?? []) as any[]) {
      if (providerIds.has(Number(p?.provider_id))) return true;
    }
  }
  return false;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const body = await req.json().catch(() => ({}));
    const userId: string | null = body.userId ? String(body.userId) : null;
    const deviceId: string | null = body.deviceId ? String(body.deviceId) : null;
    const services: string[] = Array.isArray(body.subscribedServices)
      ? body.subscribedServices.map(String) : [];
    const limit = clamp(Number(body.limit ?? DEFAULT_LIMIT) || DEFAULT_LIMIT, 1, MAX_LIMIT);
    const force = body.force === true;

    const owner = userId ?? deviceId;
    if (!owner) return json({ error: "userId or deviceId required" }, 400);

    // No services means nothing can pass the subscribed-only filter, and an
    // empty rail is the honest answer — not a rail of things they cannot watch.
    if (!services.length) {
      return json({ items: [], cached: false, seed_count: 0, reason: "no_services" });
    }

    const servicesKey = [...services].map(norm).sort().join(",");
    const signals = await gatherSignals(userId, deviceId);

    // ---- Cache probe -------------------------------------------------------
    const { data: cachedRow } = await supabase
      .from("title_recommendations").select("*").eq("owner", owner).maybeSingle();
    if (!force && cachedRow) {
      const fresh = Date.now() - new Date(cachedRow.computed_at).getTime() < TTL_MS;
      const sameSignals = cachedRow.signal_fingerprint === signals.fingerprint;
      const sameServices = (cachedRow.services ?? []).join(",") === servicesKey;
      if (fresh && sameSignals && sameServices) {
        return json({
          items: (cachedRow.items ?? []).slice(0, limit),
          cached: true,
          seed_count: cachedRow.seed_count ?? 0,
          signal_fingerprint: cachedRow.signal_fingerprint,
          computed_at: cachedRow.computed_at,
        });
      }
    }

    const { ids: providerIdList } = await providerIdsFor(services);
    const providerIds = new Set(providerIdList);
    if (!providerIds.size) {
      return json({ items: [], cached: false, seed_count: signals.seeds.length, reason: "no_provider_mapping" });
    }

    const nudges = await genreNudges(signals.creatorIds, signals.teamCount);
    const pool = new Map<string, Candidate>();

    // Pool 1 — taste. Top seeds' TMDB recommendations, concurrently.
    const topSeeds = signals.seeds.slice(0, MAX_SEEDS);
    await Promise.all(topSeeds.map(async (seed) => {
      const res = await tmdb(`/${seed.mediaType}/${seed.tmdbId}/recommendations`, { page: "1" });
      for (const raw of (res?.results ?? []).slice(0, 20)) {
        absorb(pool, raw, seed.mediaType, seed.weight, false);
      }
    }));

    // Seed genre histogram, taken from the taste pool so it costs no extra call.
    const genreScore = new Map<number, number>();
    for (const c of pool.values()) {
      for (const g of c.genre_ids) genreScore.set(g, (genreScore.get(g) ?? 0) + c.taste);
    }
    for (const [g, v] of nudges) genreScore.set(g, (genreScore.get(g) ?? 0) + v);
    const topGenres = [...genreScore.entries()]
      .sort((a, b) => b[1] - a[1]).slice(0, 3).map(([g]) => g);

    // Pool 2 — availability. Subscribed-only, shaped by the top genres.
    const discoverParams: Record<string, string> = {
      watch_region: HOME_REGION,
      with_watch_providers: providerIdList.join("|"),
      sort_by: "popularity.desc",
      "vote_count.gte": "50",
      page: "1",
    };
    if (topGenres.length) discoverParams.with_genres = topGenres.join("|");
    await Promise.all((["tv", "movie"] as MediaType[]).map(async (mt) => {
      const res = await tmdb(`/discover/${mt}`, discoverParams);
      for (const raw of (res?.results ?? []).slice(0, 20)) absorb(pool, raw, mt, 0, true);
    }));

    // ---- Score -------------------------------------------------------------
    const maxTaste = Math.max(1, ...[...pool.values()].map((c) => c.taste));
    const maxGenre = Math.max(1, ...[...genreScore.values()]);

    const scored = [...pool.values()]
      .filter((c) => !signals.excluded.has(`${c.media_type}:${c.tmdb_id}`))
      .filter((c) => !!c.poster_path)
      .map((c) => {
        const taste = (c.taste / maxTaste) * 60;
        const genre = c.genre_ids.length
          ? (c.genre_ids.reduce((s, g) => s + (genreScore.get(g) ?? 0), 0) / (c.genre_ids.length * maxGenre)) * 25
          : 0;
        const quality = clamp(c.vote_average / 10, 0, 1) * 10;
        const breadth = Math.min(c.seedHits, 3) * 1.5;
        return { c, score: taste + genre + quality + breadth };
      })
      .sort((a, b) => b.score - a.score);

    // ---- Availability check on the taste pool ------------------------------
    // Discover rows are subscribed by construction. Recommendation rows are
    // not, so the highest-scoring ones are checked until the rail is full —
    // bounded so a cold owner can never fan out into hundreds of TMDB calls.
    const confirmed: Array<{ c: Candidate; score: number }> = [];
    const needsCheck: Array<{ c: Candidate; score: number }> = [];
    for (const s of scored) (s.c.fromDiscover ? confirmed : needsCheck).push(s);

    const checkList = needsCheck.slice(0, PROVIDER_CHECKS);
    const verdicts = await mapLimit(checkList, PROVIDER_CONCURRENCY,
      (s) => streamsOnSubscribed(s.c, providerIds));
    checkList.forEach((s, i) => { if (verdicts[i]) confirmed.push(s); });

    const items = confirmed
      .sort((a, b) => b.score - a.score)
      .slice(0, MAX_LIMIT)
      .map(({ c, score }) => ({
        tmdb_id: c.tmdb_id,
        media_type: c.media_type,
        title: c.title,
        poster_path: c.poster_path,
        backdrop_path: c.backdrop_path,
        genre_ids: c.genre_ids,
        vote_average: c.vote_average,
        match_percentage: clamp(Math.round(55 + score / 2), 55, 98),
      }));

    const computedAt = new Date().toISOString();
    try {
      await supabase.from("title_recommendations").upsert({
        owner,
        items,
        signal_fingerprint: signals.fingerprint,
        seed_count: signals.seeds.length,
        services: servicesKey ? servicesKey.split(",") : [],
        computed_at: computedAt,
      }, { onConflict: "owner" });
    } catch { /* best-effort: a cache write must never fail the rail */ }

    return json({
      items: items.slice(0, limit),
      cached: false,
      seed_count: signals.seeds.length,
      signal_fingerprint: signals.fingerprint,
      computed_at: computedAt,
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

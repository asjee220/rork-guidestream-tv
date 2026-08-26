// recommend_creators
// Server-side port of iOS ContentSourcesService.fetchRecommendedCreators.
// Moves the "Creators/Podcasts for You" recommender out of the clients so iOS
// and Android score identically and the algorithm never drifts between
// platforms. Reads public.content_sources with the service role.
//
// Body: { followedIds: string[], limit?: number }
// Returns: { items: [{ title_id, display_name, image_url, source_type, category, match_percentage }] }
// Sorted by match_percentage desc then display_name asc.
//
// v9 (GUI-5): `limit` is optional and defaults to 12, which is what the home
// rail asks for and what every existing caller gets unchanged. The Android
// "Creators/Podcasts for You" See-all screen passes a larger value so the full
// list is deeper than the rail it came from — iOS's See-all already fetched 50
// via its own client-side recommender, and without this the Android screen
// could only ever repeat the rail's 12. Clamped to MAX_RESULT_LIMIT so a
// client cannot ask for the whole candidate set.
//
// Scoring tiers (identical to the iOS implementation):
//   1. Jaccard similarity over comma/slash/pipe-split categories -> clamped [65,98]
//   2. Description keyword overlap (only when no followed categories) -> clamped [60,92]
//   3. Source-type fallback: same type 70, different 55
//
// Note: the iOS version also calls an "enrich/creators" endpoint to backfill
// missing YouTube categories before scoring. Every row in content_sources
// currently carries a category, so tier 1 always fires and that step is omitted
// here. If uncategorised rows appear later, run discover_creators.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const env = (k: string): string => Deno.env.get(k) ?? "";
const SUPABASE_URL = env("SUPABASE_URL");
const SERVICE_KEY = env("SUPABASE_SERVICE_ROLE_KEY");

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...CORS, "content-type": "application/json" } });

const CANDIDATE_LIMIT = 200;
const DEFAULT_RESULT_LIMIT = 12;
const MAX_RESULT_LIMIT = 50;

const STOP_WORDS = new Set([
  "the", "and", "for", "are", "but", "not", "you", "all", "can",
  "had", "her", "was", "one", "our", "out", "has", "have", "from",
  "they", "will", "with", "your", "that", "this", "than", "then",
  "them", "what", "when", "were", "which", "their", "there", "about",
  "also", "into", "just", "like", "make", "more", "most", "over",
  "some", "such", "take", "very", "well", "much", "each", "been",
  "would", "could", "should", "after", "before", "between", "through",
  "subscribe", "channel", "video", "videos", "watch", "follow",
  "please", "click", "link", "links", "here", "check", "new",
  "content", "get", "see", "don", "does", "did", "made",
]);

type Source = {
  title_id: string;
  source_type: string;
  display_name: string;
  image_url: string | null;
  category: string | null;
  description: string | null;
};

function splitTags(cat: string | null | undefined): Set<string> {
  if (!cat) return new Set();
  return new Set(
    cat.split(/[,/|]/).map((t) => t.trim().toLowerCase()).filter((t) => t.length > 0)
  );
}

function extractKeywords(text: string): Set<string> {
  const words = (text || "")
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .map((w) => w.replace(/^['"\-*#]+|['"\-*#]+$/g, ""))
    .filter((w) => w.length >= 4 && !STOP_WORDS.has(w) && /[a-z]/.test(w));
  return new Set(words);
}

function jaccard(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 && b.size === 0) return 0;
  let inter = 0;
  for (const x of a) if (b.has(x)) inter++;
  const union = a.size + b.size - inter;
  return union > 0 ? inter / union : 0;
}

const clamp = (v: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, v));

// Mirrors SourceKind.from(titleId:) prefix parsing on both clients.
function sourceTypeFromTitleId(id: string): string | null {
  if (id.startsWith("yt:")) return "youtube";
  if (id.startsWith("pod:")) return "podcast";
  if (id.startsWith("tw:")) return "twitch";
  if (id.startsWith("kick:")) return "kick";
  return null;
}

// An absent, non-numeric or out-of-range `limit` falls back to the rail's 12,
// so every pre-v9 caller behaves exactly as before.
function resolveLimit(raw: unknown): number {
  const n = typeof raw === "number" ? raw : Number(raw);
  if (!Number.isFinite(n)) return DEFAULT_RESULT_LIMIT;
  return clamp(Math.trunc(n), 1, MAX_RESULT_LIMIT);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const body = await req.json().catch(() => ({}));
    const followedIds: string[] = Array.isArray(body.followedIds)
      ? body.followedIds.map(String).filter((s: string) => s.length > 0)
      : [];
    if (followedIds.length === 0) return json({ items: [] });

    const resultLimit = resolveLimit(body.limit);

    const supabase = createClient(SUPABASE_URL, SERVICE_KEY);

    const { data: followed, error: fErr } = await supabase
      .from("content_sources")
      .select("title_id, source_type, display_name, image_url, category, description")
      .in("title_id", followedIds);
    if (fErr) return json({ error: fErr.message }, 500);

    const followedSources = (followed ?? []) as Source[];

    const followedTags = new Set<string>();
    for (const s of followedSources) for (const t of splitTags(s.category)) followedTags.add(t);

    const hasCategories = followedTags.size > 0;

    const descriptionKeywords = hasCategories
      ? new Set<string>()
      : extractKeywords(followedSources.map((s) => s.description ?? "").join(" "));
    const hasKeywords = descriptionKeywords.size > 0;

    const followedSourceTypes = new Set(followedSources.map((s) => s.source_type));
    if (followedSourceTypes.size === 0) {
      for (const id of followedIds) {
        const t = sourceTypeFromTitleId(id);
        if (t) followedSourceTypes.add(t);
      }
    }

    const { data: all, error: aErr } = await supabase
      .from("content_sources")
      .select("title_id, source_type, display_name, image_url, category, description")
      .neq("source_type", "tmdb")
      .order("created_at", { ascending: false })
      .limit(CANDIDATE_LIMIT);
    if (aErr) return json({ error: aErr.message }, 500);

    const followedSet = new Set(followedIds);
    const items = ((all ?? []) as Source[])
      .filter((s) => !followedSet.has(s.title_id))
      .map((s) => {
        let pct: number;
        if (hasCategories) {
          pct = clamp(Math.trunc(jaccard(splitTags(s.category), followedTags) * 100), 65, 98);
        } else if (hasKeywords) {
          const candidate = extractKeywords(`${s.description ?? ""} ${s.category ?? ""}`);
          pct = clamp(Math.trunc(jaccard(candidate, descriptionKeywords) * 100), 60, 92);
        } else {
          pct = followedSourceTypes.has(s.source_type) ? 70 : 55;
        }
        return {
          title_id: s.title_id,
          display_name: s.display_name,
          image_url: s.image_url,
          source_type: s.source_type,
          category: s.category,
          match_percentage: pct,
        };
      })
      .sort((a, b) =>
        b.match_percentage !== a.match_percentage
          ? b.match_percentage - a.match_percentage
          : a.display_name.localeCompare(b.display_name, undefined, { sensitivity: "base", numeric: true })
      )
      .slice(0, resultLimit);

    return json({ items, tier: hasCategories ? "category" : hasKeywords ? "keyword" : "source_type" });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

/**
 * GuideStreamTV Push Notification Worker
 *
 * Cron endpoint:  POST /cron/send-push
 * Manual test:   GET  /cron/send-push
 * Health check:  GET  /ping
 *
 * The cron job polls `new_episodes` for fresh (is_new = true) entries,
 * finds users who follow those titles in their watch list, fetches their
 * APNs device tokens, and dispatches push notifications through Apple.
 */

import {
  fetchUnscheduledEpisodes,
  fetchFollowerUserIds,
  fetchPushTokensForUsers,
  deleteInvalidTokens,
  markEpisodeNotified,
  logPushBatch,
  type NewEpisode,
  debugStatus,
} from "./_lib/supabase";
import { sendBatchPush } from "./_lib/apns";
import {
  searchCreators,
  type CreatorSearchType,
} from "./_lib/creators";

interface Env {
  APPLE_APNS_PRIVATE_KEY: string;
  APPLE_BUNDLE_ID: string;
  APPLE_KEY_ID: string;
  APPLE_TEAM_ID: string;
  YOUTUBE_API_KEY?: string;
  TWITCH_CLIENT_ID?: string;
  TWITCH_CLIENT_SECRET?: string;
}

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS });
    }

    // Health check
    if (url.pathname === "/ping") {
      return Response.json(
        { ok: true, now: new Date().toISOString() },
        { headers: CORS },
      );
    }

    // Debug: check push state for a specific user
    if (url.pathname === "/debug/status") {
      const userId = url.searchParams.get("user_id");
      if (!userId) {
        return Response.json(
          { ok: false, error: "?user_id= required" },
          { status: 400, headers: CORS },
        );
      }
      try {
        const status = await debugStatus(userId);
        return Response.json({ ok: true, ...status }, { headers: CORS });
      } catch (err) {
        return Response.json(
          { ok: false, error: (err as Error).message },
          { status: 500, headers: CORS },
        );
      }
    }

    // Live creator search across YouTube + Twitch
    if (url.pathname === "/search/creators") {
      const q = url.searchParams.get("q")?.trim() ?? "";
      const typeParam = (url.searchParams.get("type") ?? "all").toLowerCase();
      const type: CreatorSearchType =
        typeParam === "youtube" || typeParam === "twitch"
          ? (typeParam as CreatorSearchType)
          : "all";
      if (!q) {
        return Response.json(
          { ok: true, results: [] },
          { headers: CORS },
        );
      }
      try {
        const results = await searchCreators(q, type, env);
        return Response.json({ ok: true, results }, { headers: CORS });
      } catch (err) {
        console.error("[search/creators] error:", (err as Error).message);
        return Response.json(
          { ok: false, error: (err as Error).message, results: [] },
          { status: 500, headers: CORS },
        );
      }
    }

    // Push dispatch — both GET (manual) and POST (cron) supported
    if (url.pathname === "/cron/send-push") {
      try {
        const result = await runPushDispatch(env);
        return Response.json(result, { headers: CORS });
      } catch (err) {
        console.error("[cron/send-push] fatal error:", (err as Error).message);
        return Response.json(
          {
            ok: false,
            error: (err as Error).message,
            stack:
              env.APPLE_BUNDLE_ID === "dev"
                ? (err as Error).stack
                : undefined,
          },
          { status: 500, headers: CORS },
        );
      }
    }

    return new Response("not found", { status: 404, headers: CORS });
  },
} satisfies { fetch: (request: Request, env: Env) => Promise<Response> };

// ── Push dispatch logic ────────────────────────────────────────────────

interface DispatchResult {
  ok: boolean;
  episodesProcessed: number;
  pushesSent: number;
  pushesFailed: number;
  invalidTokensRemoved: number;
  details: Array<{
    episodeId: string;
    title: string;
    followers: number;
    sent: number;
  }>;
}

async function runPushDispatch(env: Env): Promise<DispatchResult> {
  const episodes = await fetchUnscheduledEpisodes();
  console.log(
    `[push] found ${episodes.length} unscheduled episodes in the last 7d`,
  );

  let totalSent = 0;
  let totalFailed = 0;
  let totalInvalid = 0;
  const details: DispatchResult["details"] = [];

  for (const ep of episodes) {
    console.log(
      `[push] processing: "${ep.title ?? ep.title_id}" S${ep.season}E${ep.episode}`,
    );

    // 1. Find users who follow this title
    const userIds = await fetchFollowerUserIds(ep.title_id);
    if (userIds.length === 0) {
      console.log(`[push]   → no followers, skipping`);
      await markEpisodeNotified(ep.id);
      continue;
    }
    console.log(`[push]   → ${userIds.length} followers`);

    // 2. Get their push tokens
    const tokens = await fetchPushTokensForUsers(userIds);
    const tokenStrings = tokens.map((t) => t.apns_token);
    console.log(`[push]   → ${tokenStrings.length} push tokens`);

    if (tokenStrings.length === 0) {
      console.log(`[push]   → no push tokens, marking notified`);
      await markEpisodeNotified(ep.id);
      continue;
    }

    // 3. Build push payload
    const title = ep.title ?? "New Episode";
    const epLabel =
      ep.season != null && ep.episode != null
        ? `S${ep.season} E${ep.episode}`
        : "New episode";
    const platform = ep.platform ? ` on ${ep.platform}` : "";

    const platformId = ep.platform?.toLowerCase() ?? "";
    const encodedPlatform = encodeURIComponent(ep.platform ?? "");
    const encodedTitle = encodeURIComponent(ep.title ?? "");

    const deepLinkParams = [
      `platform=${encodedPlatform}`,
      `platform_id=${encodeURIComponent(platformId)}`,
      `title=${encodedTitle}`,
    ].join("&");

    const payload = {
      aps: {
        alert: {
          title: `${title} — ${epLabel}`,
          body: `A new episode is now available${platform}. Tap to watch.`,
        },
        sound: "default",
        badge: 1,
        "mutable-content": 1,
      },
      title_id: ep.title_id,
      platform_id: platformId,
      notification_type: "new_episode",
      deep_link: `guidestream://show/${ep.title_id}?${deepLinkParams}`,
    };

    // 4. Send pushes
    const { sent, failed, invalid } = await sendBatchPush(
      env,
      tokenStrings,
      payload,
    );
    totalSent += sent;
    totalFailed += failed;
    totalInvalid += invalid.length;

    details.push({
      episodeId: ep.id,
      title: title,
      followers: userIds.length,
      sent,
    });

    console.log(
      `[push]   → sent=${sent} failed=${failed} invalid=${invalid.length}`,
    );

    // 5. Clean up invalid tokens
    if (invalid.length > 0) {
      await deleteInvalidTokens(invalid);
    }

    // 6. Mark episode as notified
    await markEpisodeNotified(ep.id);

    // 7. Log the batch
    await logPushBatch({
      push_sent_at: new Date().toISOString(),
      new_episode_id: ep.id,
      title_id: ep.title_id,
      title: ep.title,
      season: ep.season,
      episode: ep.episode,
      user_count: userIds.length,
    });
  }

  console.log(
    `[push] done: episodes=${episodes.length} sent=${totalSent} failed=${totalFailed} invalid=${totalInvalid}`,
  );

  return {
    ok: true,
    episodesProcessed: episodes.length,
    pushesSent: totalSent,
    pushesFailed: totalFailed,
    invalidTokensRemoved: totalInvalid,
    details,
  };
}

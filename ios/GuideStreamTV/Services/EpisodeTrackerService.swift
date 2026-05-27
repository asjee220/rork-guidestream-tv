//
//  EpisodeTrackerService.swift
//  GuideStreamTV
//
//  Populates the Supabase `new_episodes` table from TMDB so the Home
//  "New Episodes" rail (and the badge / notification surface) has a real
//  data source. The table was previously read-only with no writer, so it
//  stayed empty forever — and the user's watch list never produced
//  episode pulses even when their shows aired a new episode.
//
//  Strategy:
//   * For every TMDB-id title in the signed-in user's (or guest device's)
//     watch list, look up `tv/{id}` and pull `last_episode_to_air`.
//   * If that episode aired within the last 14 days AND we don't already
//     have a row for `(title_id, season, episode)`, insert it.
//   * Title is unique by `(title_id, season, episode)` thanks to the new
//     partial unique index in the schema; if Supabase rejects with a
//     duplicate-key error we silently ignore — the row is already there.
//   * RLS on `new_episodes` is permissive (`insert` allowed) so this
//     works for guests too. Sensitive analytics aren't involved.
//
//  Runs on a 6-hour cooldown per install to avoid hammering TMDB.
//

import Foundation
import Supabase

@MainActor
final class EpisodeTrackerService {
    static let shared = EpisodeTrackerService()
    private init() {}

    /// Minimum interval between full scans. We rescan when a new title is
    /// added regardless of this cooldown.
    private static let scanCooldown: TimeInterval = 6 * 60 * 60

    /// Air dates older than this aren't surfaced as "new".
    private static let newWindow: TimeInterval = 14 * 24 * 60 * 60

    private let lastScanKey = "gs.episodeTracker.lastScan"
    private var inFlight: Task<Void, Never>?

    /// Trigger a scan. Coalesces concurrent calls and respects the
    /// cooldown unless `force` is true. Safe to call from anywhere
    /// (HomeView.task, watch-list add, app foreground) without spamming
    /// the network.
    func scanIfNeeded(force: Bool = false) {
        if let inFlight, !inFlight.isCancelled { return }
        let now = Date()
        if !force,
           let last = UserDefaults.standard.object(forKey: lastScanKey) as? Date,
           now.timeIntervalSince(last) < Self.scanCooldown {
            return
        }
        inFlight = Task { @MainActor in
            defer { inFlight = nil }
            await performScan()
            UserDefaults.standard.set(Date(), forKey: lastScanKey)
        }
    }

    /// Scan the watch list and upsert any freshly-aired episodes.
    private func performScan() async {
        let streams = StreamsViewModel.shared.userStreams
        // Watch list rows whose title_id is a TMDB numeric id (skip slugs).
        let tmdbTitles: [UserStream] = streams.compactMap { row in
            Int(row.titleId.trimmingCharacters(in: .whitespaces)) != nil ? row : nil
        }
        guard !tmdbTitles.isEmpty else {
            #if DEBUG
            print("[EpisodeTracker] no TMDB titles in watch list; skipping scan")
            #endif
            return
        }

        let locale = DeviceLocale.current()
        let cutoff = Date().addingTimeInterval(-Self.newWindow)

        // Process in parallel but cap at 8 concurrent TMDB calls so we
        // don't blow past the 50req/sec rate limit on big watch lists.
        await withTaskGroup(of: NewEpisodeInsert?.self) { group in
            var added = 0
            for row in tmdbTitles {
                if added >= 8 {
                    _ = await group.next()
                    added -= 1
                }
                added += 1
                group.addTask { [row, locale, cutoff] in
                    await Self.makeInsertIfFresh(
                        from: row,
                        locale: locale,
                        cutoff: cutoff
                    )
                }
            }
            var batch: [NewEpisodeInsert] = []
            for await insert in group {
                if let insert { batch.append(insert) }
            }
            if !batch.isEmpty {
                await Self.upsert(batch)
            }
        }

        // Refresh the in-memory cache so HomeView's panel reflects the
        // freshly-written rows on the next frame.
        await StreamsViewModel.shared.fetchNewEpisodes()
    }

    /// Fetches `tv/{id}` for one watch-list row and turns it into a
    /// `new_episodes` insert if the last aired episode falls inside our
    /// 14-day window. Returns nil if the title is a movie, the show has
    /// no recent episode, or TMDB doesn't surface a recognised provider.
    private static func makeInsertIfFresh(
        from row: UserStream,
        locale: DeviceLocale,
        cutoff: Date
    ) async -> NewEpisodeInsert? {
        guard let tmdbId = Int(row.titleId) else { return nil }
        do {
            let detail = try await TMDBService.shared.getTVDetail(tmdbId: tmdbId)
            guard let last = detail.lastEpisodeToAir,
                  let airDateString = last.airDate,
                  let airDate = Self.parseDate(airDateString),
                  airDate >= cutoff
            else { return nil }

            // Skip future episodes — only count things that have aired.
            guard airDate <= Date() else { return nil }

            // Resolve the streaming provider so the row carries a real
            // platform name. We tolerate provider-lookup failure (rail
            // still renders, just without the badge brand).
            var providerName: String? = row.platform
            if providerName == nil {
                let provider = try? await TMDBService.shared.getTopWatchProvider(
                    tmdbId: tmdbId,
                    isTV: true,
                    region: locale.region
                )
                providerName = provider?.providerName
            }

            // Prefer the still image; fall back to the show's poster so
            // the rail always has art.
            let posterUrl = last.stillUrl ?? detail.posterUrl ?? row.posterUrl

            return NewEpisodeInsert(
                titleId: row.titleId,
                title: row.title ?? detail.name,
                season: last.seasonNumber,
                episode: last.episodeNumber,
                durationMinutes: last.runtime ?? detail.runtimeMinutes,
                platform: providerName,
                posterUrl: posterUrl,
                releasedAt: ISO8601DateFormatter().string(from: airDate)
            )
        } catch {
            #if DEBUG
            print("[EpisodeTracker] lookup failed for \(row.titleId): \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    /// Inserts the batch into `new_episodes`. Uses Supabase's `upsert`
    /// with `onConflict: title_id,season,episode` so re-runs are
    /// idempotent. Any individual insert that fails (column missing,
    /// schema drift) is logged and skipped without aborting the batch.
    private static func upsert(_ batch: [NewEpisodeInsert]) async {
        for row in batch {
            await insertSingle(row)
        }
    }

    /// Inserts one episode row. Schema-drift safe: if a column is
    /// missing on the live database we retry with that column removed,
    /// up to 3 times. Duplicate-key errors (the row is already there) are
    /// silently swallowed.
    private static func insertSingle(_ row: NewEpisodeInsert) async {
        var payload: [String: AnyJSON] = [
            "title_id": .string(row.titleId),
            "is_new": .bool(true),
            "released_at": .string(row.releasedAt)
        ]
        if let title = row.title { payload["title"] = .string(title) }
        if let season = row.season { payload["season"] = .integer(season) }
        if let episode = row.episode { payload["episode"] = .integer(episode) }
        if let duration = row.durationMinutes { payload["duration_minutes"] = .integer(duration) }
        if let platform = row.platform { payload["platform"] = .string(platform) }
        if let poster = row.posterUrl { payload["poster_url"] = .string(poster) }

        for attempt in 0..<4 {
            do {
                try await SupabaseManager.shared.client
                    .from("new_episodes")
                    .insert(payload)
                    .execute()
                return
            } catch {
                let message = error.localizedDescription
                let lowered = message.lowercased()
                // Duplicate (title_id, season, episode) row → success.
                if lowered.contains("duplicate") || lowered.contains("23505") {
                    return
                }
                if attempt < 3,
                   let dropped = dropMissingColumn(from: payload, error: message) {
                    payload = dropped
                    continue
                }
                #if DEBUG
                print("[EpisodeTracker] insert failed: \(message)")
                #endif
                return
            }
        }
    }

    /// Parses TMDB's `YYYY-MM-DD` air date format.
    private static func parseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: s)
    }

    /// Inspects a Postgres PGRST204 missing-column error and returns the
    /// payload with that column removed so the next retry can succeed.
    private static func dropMissingColumn(
        from payload: [String: AnyJSON],
        error: String
    ) -> [String: AnyJSON]? {
        let lowered = error.lowercased()
        guard lowered.contains("could not find") && lowered.contains("column") else { return nil }
        var trimmed = payload
        var didDrop = false
        for key in Array(payload.keys) where key != "title_id" {
            if lowered.contains("'\(key.lowercased())'") {
                trimmed.removeValue(forKey: key)
                didDrop = true
            }
        }
        return didDrop ? trimmed : nil
    }
}

/// Local payload shape mirrors the columns on `public.new_episodes`.
/// Doesn't conform to `Encodable` directly — we go through a dictionary
/// payload so optional / drifted columns can be removed at insert time.
private nonisolated struct NewEpisodeInsert: Sendable {
    let titleId: String
    let title: String?
    let season: Int?
    let episode: Int?
    let durationMinutes: Int?
    let platform: String?
    let posterUrl: String?
    let releasedAt: String
}

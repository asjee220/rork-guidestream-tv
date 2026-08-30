//
//  TVStreamsViewModel.swift
//  GuideStreamTVTV
//
//  Watch list store for the Apple TV app. Mirrors the phone app's
//  `StreamsViewModel`:
//
//   1. Local cache in UserDefaults so the watch list renders instantly
//      on cold launch and survives offline restarts.
//   2. Supabase `user_streams` is the durable source of truth — every
//      change is written through with the same ownership rules
//      (signed-in users own rows via `user_id`, guests via `device_id`).
//   3. Failures never undo the local optimistic update; we just log
//      and keep the device-local copy.
//

import Foundation
import Supabase

@MainActor
@Observable
final class TVStreamsViewModel {
    static let shared = TVStreamsViewModel()

    var userStreams: [TVUserStream] = []
    /// Maps title_id → most-recent content timestamp from `title_recency`.
    /// Populated by `fetchLatestContentDates()` so sorters can rank by recency.
    var latestContentAt: [String: Date] = [:]
    /// Maps title_id → content_kind from `title_recency` ('tv','movie','youtube',
    /// 'podcast','twitch','kick'). Populated alongside `latestContentAt` so
    /// the watch-list new-content badge can distinguish shows from uploads.
    var latestContentKind: [String: String] = [:]
    /// Maps title_id → last-seen timestamp from `watchlist_seen`. Populated by
    /// `fetchWatchlistSeen()` and updated optimistically by `markWatchlistSeen`.
    var seenContentAt: [String: Date] = [:]
    /// Session cache of freshly-resolved poster URLs for saved titles whose
    /// stored snapshot is null or stale. Populated by `backfillPosters()`.
    var resolvedPosters: [String: String] = [:]
    var isLoading: Bool = false
    var lastError: String?

    // MARK: - iOS-compat stub state

    /// Stub: episode-tracker rows are only populated on iOS. tvOS surfaces
    /// trending fallback content instead so this stays empty.
    var newEpisodes: [NewEpisodeRow] = []
    var isLoadingEpisodes: Bool = false
    /// Mirror of `isLoading` for iOS-shared call sites that expect this name.
    var isLoadingStreams: Bool { isLoading }

    private let localCacheKey = "gs.tv.watchList.localCache.v1"
    private static let guestUserId = "guest"

    private var currentUserId: UUID? {
        TVAuthViewModel.shared.currentUser?.id
    }

    private init() {
        self.userStreams = loadLocalCache()
    }

    /// Pulls the canonical list. Falls back to the local cache on any
    /// network/RLS failure so the watch list never appears to vanish.
    func fetchUserStreams() async {
        isLoading = true
        defer { isLoading = false }
        let deviceId = TVDeviceIdentity.shared.deviceId
        do {
            var query = TVSupabaseManager.shared.client
                .from("user_streams")
                .select()
            if let uid = currentUserId?.uuidString {
                query = query.eq("user_id", value: uid)
            } else {
                query = query.eq("device_id", value: deviceId).filter("user_id", operator: "is", value: "null")
            }
            let rows: [TVUserStream] = try await query
                .order("added_at", ascending: false)
                .execute()
                .value
            let merged = mergeRemoteWithLocal(remote: rows)
            self.userStreams = merged
            saveLocalCache(merged)
        } catch {
            self.lastError = error.localizedDescription
            print("[TVStreams] fetchUserStreams failed: \(error.localizedDescription)")
            self.userStreams = loadLocalCache()
        }
    }

    /// Returns true when the given titleId is currently in the watch list.
    func contains(titleId: String) -> Bool {
        userStreams.contains { $0.titleId == titleId }
    }

    /// Toggle a title in/out of the watch list. Used by the focus
    /// poster cards on Home — one click is the whole interaction.
    func toggle(
        titleId: String,
        title: String?,
        posterUrl: String?,
        platform: String?
    ) async {
        if contains(titleId: titleId) {
            await remove(titleId: titleId)
        } else {
            await add(titleId: titleId, title: title, posterUrl: posterUrl, platform: platform)
        }
    }

    func add(titleId: String, title: String?, posterUrl: String?, platform: String?) async {
        let trimmed = titleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if !userStreams.contains(where: { $0.titleId == trimmed }) {
            let optimistic = TVUserStream(
                id: UUID().uuidString,
                userId: currentUserId?.uuidString ?? Self.guestUserId,
                titleId: trimmed,
                title: title,
                posterUrl: posterUrl,
                platform: platform,
                addedAt: Date(),
                isTv: nil
            )
            self.userStreams.insert(optimistic, at: 0)
            saveLocalCache(self.userStreams)
        }

        let didInsert = await insertUserStream(
            userId: currentUserId?.uuidString,
            deviceId: TVDeviceIdentity.shared.deviceId,
            titleId: trimmed,
            title: title,
            posterUrl: posterUrl,
            platform: platform
        )
        if didInsert {
            await fetchUserStreams()
        }
    }

    func remove(titleId: String) async {
        let trimmed = titleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        self.userStreams.removeAll { $0.titleId == trimmed }
        saveLocalCache(self.userStreams)

        let deviceId = TVDeviceIdentity.shared.deviceId
        do {
            var query = TVSupabaseManager.shared.client
                .from("user_streams")
                .delete()
                .eq("title_id", value: trimmed)
            if let uid = currentUserId?.uuidString {
                query = query.eq("user_id", value: uid)
            } else {
                query = query.eq("device_id", value: deviceId).filter("user_id", operator: "is", value: "null")
            }
            try await query.execute()
        } catch {
            self.lastError = error.localizedDescription
            print("[TVStreams] remove failed: \(error.localizedDescription)")
        }
    }

    @discardableResult
    private func insertUserStream(
        userId: String?,
        deviceId: String,
        titleId: String,
        title: String?,
        posterUrl: String?,
        platform: String?
    ) async -> Bool {
        let safeTitle = title ?? titleId
        var payload: [String: AnyJSON] = [
            "device_id": .string(deviceId),
            "title_id": .string(titleId),
            "title_name": .string(safeTitle)
        ]
        if let userId { payload["user_id"] = .string(userId) }
        if let title { payload["title"] = .string(title) }
        if let posterUrl { payload["poster_url"] = .string(posterUrl) }
        if let platform { payload["platform"] = .string(platform) }

        for attempt in 0..<5 {
            do {
                try await TVSupabaseManager.shared.client
                    .from("user_streams")
                    .insert(payload)
                    .execute()
                self.lastError = nil
                return true
            } catch {
                let message = error.localizedDescription
                let lowered = message.lowercased()
                if lowered.contains("duplicate") || lowered.contains("23505") {
                    return true
                }
                if attempt < 4, let dropped = Self.dropMissingColumn(from: payload, error: message) {
                    payload = dropped
                    continue
                }
                if attempt < 4,
                   let filled = Self.fillNotNullViolation(in: payload, error: message, fallback: safeTitle) {
                    payload = filled
                    continue
                }
                self.lastError = message
                print("[TVStreams] add failed: \(message)")
                return false
            }
        }
        return false
    }

    // MARK: - iOS-compat stub methods

    /// Refreshes both watch list + new-episodes feed. The episode feed is a
    /// no-op on tvOS so this just delegates to `fetchUserStreams`.
    func refreshAll() async {
        await fetchUserStreams()
        await fetchLatestContentDates()
    }

    /// Fetches the most-recent content timestamp and content_kind for each
    /// saved title from the `title_recency` table so sorters can promote
    /// freshly updated titles and the watch-list badge can distinguish shows
    /// from uploads. Titles without a row keep their existing date-added position.
    func fetchLatestContentDates() async {
        let titleIds = self.userStreams.map { $0.titleId }
        guard !titleIds.isEmpty else {
            latestContentAt = [:]
            latestContentKind = [:]
            return
        }
        do {
            let rows: [TVTitleRecencyRow] = try await TVSupabaseManager.shared.client
                .from("title_recency")
                .select("title_id,last_content_at,content_kind")
                .in("title_id", values: titleIds)
                .execute()
                .value
            var dateMap: [String: Date] = [:]
            var kindMap: [String: String] = [:]
            for row in rows {
                if let date = row.lastContentAt {
                    dateMap[row.titleId] = date
                }
                if let kind = row.contentKind {
                    kindMap[row.titleId] = kind
                }
            }
            self.latestContentAt = dateMap
            self.latestContentKind = kindMap
        } catch {
            print("[TVStreams] fetchLatestContentDates failed: \(error.localizedDescription)")
        }
    }

    /// Fetches `watchlist_seen` rows for the current owner and saved title_ids
    /// so the watch-list badge can tell whether new content has arrived since
    /// the user last opened a title. Owner is the signed-in user id when
    /// authenticated, otherwise the device id — the same identity used for
    /// `user_streams`.
    func fetchWatchlistSeen() async {
        let titleIds = self.userStreams.map { $0.titleId }
        guard !titleIds.isEmpty else {
            seenContentAt = [:]
            return
        }
        let owner = currentUserId?.uuidString ?? TVDeviceIdentity.shared.deviceId
        do {
            let rows: [TVWatchlistSeenRow] = try await TVSupabaseManager.shared.client
                .from("watchlist_seen")
                .select("title_id,seen_content_at")
                .eq("owner", value: owner)
                .in("title_id", values: titleIds)
                .execute()
                .value
            var map: [String: Date] = [:]
            for row in rows {
                if let date = row.seenContentAt {
                    map[row.titleId] = date
                }
            }
            self.seenContentAt = map
        } catch {
            print("[TVStreams] fetchWatchlistSeen failed: \(error.localizedDescription)")
        }
    }

    /// Whether a `new_episodes` row should show the NEW chip for *this*
    /// viewer. `new_episodes.is_new` is a shared, server-owned column, so on
    /// its own it can never reflect one person having already watched
    /// (GUI-74). Three conditions, all required:
    ///  * the server still considers the row new,
    ///  * the episode has actually landed — a future `released_at` is a
    ///    scheduled drop, not a new episode,
    ///  * this viewer has not opened the title since it landed.
    func isNewForViewer(_ row: NewEpisodeRow, now: Date = Date()) -> Bool {
        guard row.isNew ?? true else { return false }
        guard let released = row.releasedAt else { return true }
        guard released <= now else { return false }
        let seen = seenContentAt[row.titleId] ?? .distantPast
        return seen < released
    }

    /// Upserts a `watchlist_seen` row marking the title as seen now, and
    /// optimistically updates `seenContentAt` so the badge disappears
    /// immediately. Owner is the signed-in user id when authenticated,
    /// otherwise the device id.
    func markWatchlistSeen(titleId: String) async {
        let owner = currentUserId?.uuidString ?? TVDeviceIdentity.shared.deviceId
        // Stamp at the latest known content date whenever that is ahead of now.
        // `title_recency.last_content_at` is frequently a date-only air date
        // stored at midnight UTC, so a show whose next episode lands later
        // today already carries a `last_content_at` in the future. Stamping a
        // plain `Date()` would leave `seen < last_content`, and `newBadgeText`
        // would keep the chip alive through the very selection meant to clear it.
        let now = max(Date(), latestContentAt[titleId] ?? .distantPast)
        // Optimistic clear so the badge vanishes before the server responds.
        seenContentAt[titleId] = now
        let payload: [String: AnyJSON] = [
            "owner": .string(owner),
            "title_id": .string(titleId),
            "seen_content_at": .string(ISO8601DateFormatter().string(from: now))
        ]
        do {
            try await TVSupabaseManager.shared.client
                .from("watchlist_seen")
                .upsert(payload)
                .execute()
        } catch {
            print("[TVStreams] markWatchlistSeen failed: \(error.localizedDescription)")
        }
    }

    /// Returns the watch-list new-content badge text for a saved title, or
    /// nil when no badge should show.
    ///
    /// A badge shows when `last_content_at` is non-null AND `content_kind` is
    /// not "movie" AND `last_content_at` is strictly greater than the baseline,
    /// where baseline = `seen_content_at` for that title if present, otherwise
    /// that user_stream's `added_at` (so a freshly-saved old title never
    /// badges, only content arriving after it was saved does).
    ///
    /// Returns "NEW EPISODE" when content_kind == "tv" and "NEW UPLOAD" for
    /// every other non-movie kind (youtube, podcast, twitch, kick).
    func newBadgeText(for stream: TVUserStream) -> String? {
        guard let lastContent = latestContentAt[stream.titleId] else { return nil }
        let kind = latestContentKind[stream.titleId] ?? "tv"
        guard kind != "movie" else { return nil }
        guard lastContent >= Date().addingTimeInterval(-7 * 24 * 60 * 60) else { return nil }
        if let seen = seenContentAt[stream.titleId], seen >= lastContent { return nil }
        return kind == "tv" ? "NEW EPISODE" : "NEW UPLOAD"
    }

    /// No-op stub: tvOS does not run the iOS episode tracker. Kept so views
    /// shared with the iOS target compile cleanly.
    func fetchNewEpisodes() async {}

    /// No-op stub matching the iOS API. The episode rail is empty on tvOS
    /// so there is nothing to mark.
    func markStaleEpisodesSeen() async {}

    /// iOS-style alias for `add(...)`. Keeps shared sheets compiling.
    func addToMyStreams(
        titleId: String,
        title: String?,
        posterUrl: String?,
        platform: String?
    ) async {
        await add(titleId: titleId, title: title, posterUrl: posterUrl, platform: platform)
    }

    /// iOS-style alias for `remove(titleId:)`.
    func removeFromMyStreams(titleId: String) async {
        await remove(titleId: titleId)
    }

    /// Returns the best poster URL for a watch-list row: the freshly
    /// resolved poster when available, otherwise the stored snapshot.
    func displayPosterUrl(for row: TVUserStream) -> String? {
        resolvedPosters[row.titleId] ?? row.posterUrl
    }

    /// Back-fills fresh poster paths for saved TMDB titles whose stored
    /// snapshot is null or stale. Lookups run concurrently in a TaskGroup;
    /// rows already present in `resolvedPosters` are skipped. Non-TMDB rows
    /// (yt: creators, tt- sports slugs) keep their stored poster untouched.
    func backfillPosters() async {
        let toResolve = userStreams.filter { row in
            if resolvedPosters[row.titleId] != nil { return false }
            return TVTitleID.tmdbId(from: row.titleId) != nil
        }
        guard !toResolve.isEmpty else { return }
        let results = await withTaskGroup(of: (String, String?).self) { group in
            for row in toResolve {
                guard let tid = TVTitleID.tmdbId(from: row.titleId) else { continue }
                let isTV = row.isTv
                group.addTask {
                    var path: String? = nil
                    if isTV == nil || isTV == true {
                        let fresh = await TVTMDBService.shared.getTVFreshness(tmdbId: tid)
                        path = fresh.posterPath
                    }
                    if path == nil, isTV == false {
                        path = await TVTMDBService.shared.getMoviePosterPath(tmdbId: tid)
                    }
                    if path == nil, isTV == nil {
                        path = await TVTMDBService.shared.getMoviePosterPath(tmdbId: tid)
                    }
                    return (row.titleId, path)
                }
            }
            var collected: [(String, String?)] = []
            for await item in group { collected.append(item) }
            return collected
        }
        var map = resolvedPosters
        for (titleId, path) in results {
            if let path, let url = TVTMDBImage.url(path, size: .poster500) {
                map[titleId] = url
            }
        }
        resolvedPosters = map
    }

    // MARK: - Local cache helpers

    private func loadLocalCache() -> [TVUserStream] {
        guard let data = UserDefaults.standard.data(forKey: localCacheKey) else { return [] }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([TVUserStream].self, from: data)
        } catch {
            return []
        }
    }

    private func saveLocalCache(_ streams: [TVUserStream]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(streams)
            UserDefaults.standard.set(data, forKey: localCacheKey)
        } catch {
            // best effort
        }
    }

    private func mergeRemoteWithLocal(remote: [TVUserStream]) -> [TVUserStream] {
        let remoteTitleIds = Set(remote.map { $0.titleId })
        let pendingLocal = loadLocalCache().filter { !remoteTitleIds.contains($0.titleId) }
        return remote + pendingLocal
    }

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

    private static func fillNotNullViolation(
        in payload: [String: AnyJSON],
        error: String,
        fallback: String
    ) -> [String: AnyJSON]? {
        let lowered = error.lowercased()
        guard lowered.contains("23502") || lowered.contains("not-null constraint") else { return nil }
        guard let range = error.range(of: "column \"", options: .caseInsensitive) else { return nil }
        let after = error[range.upperBound...]
        guard let end = after.firstIndex(of: "\"") else { return nil }
        let column = String(after[..<end])
        guard !column.isEmpty, payload[column] == nil else { return nil }
        var filled = payload
        filled[column] = .string(fallback)
        return filled
    }
}

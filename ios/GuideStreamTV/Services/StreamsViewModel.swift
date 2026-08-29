//
//  StreamsViewModel.swift
//  GuideStreamTV
//
//  Watch list store with a **local-first** persistence strategy:
//
//  1. Every add/remove updates the in-memory `userStreams` array immediately
//     and writes through to a UserDefaults cache, so the UI feels instant and
//     works for guests, offline users, and signed-in users alike.
//  2. When a Supabase session exists, the change is also pushed to the
//     `user_streams` table; failures are logged but never undo the local
//     change (the user still sees the title saved on their device).
//  3. After sign-in, `syncLocalToSupabase()` pushes any guest-era rows up to
//     the server so the user's list doesn't get reset.
//

import Foundation
import Supabase

@MainActor
@Observable
final class StreamsViewModel {
    static let shared = StreamsViewModel()

    var userStreams: [UserStream] = []
    var newEpisodes: [NewEpisodeRow] = []
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
    var isLoadingStreams: Bool = false
    var isLoadingEpisodes: Bool = false
    var lastError: String?

    /// Timestamp of the last full `refreshAll()` pass. Used by
    /// `refreshIfStale(minimumInterval:)` to skip redundant refreshes when
    /// the app returns to the foreground within `minimumInterval` seconds.
    private var lastFullRefreshAt: Date?

    /// UserDefaults key for the local cache of watch list rows. Encoded as
    /// JSON `[UserStream]`. Survives sign-out so a returning user doesn't
    /// lose their guest list.
    private let localCacheKey = "gs.watchList.localCache.v1"

    private var currentUserId: UUID? {
        AuthViewModel.shared.currentUser?.id
    }

    /// Sentinel value stored in `UserStream.userId` for rows added before the
    /// user signed in. Used by `syncLocalToSupabase()` to find rows that
    /// still need to be pushed up to the server.
    private static let guestUserId = "guest"

    private init() {
        // Hydrate immediately so the watchlist surfaces (Home panel, sheets)
        // render their saved state on first frame without waiting on Supabase.
        self.userStreams = loadLocalCache()
    }

    // MARK: - Read

    func refreshAll() async {
        await fetchUserStreams()
        await fetchNewEpisodes()
        await fetchLatestContentDates()
        // Hydrate the seen baseline on the home path too, not just when the
        // watch-list sheet opens, so the Home rail badge matches the sheet's
        // badge after a cold launch. Mirrors Android's refreshAll().
        await fetchWatchlistSeen()
        // After we have a fresh watch list, kick off the episode tracker
        // so any titles that aired a new episode show up in the rail on
        // the next fetch. The tracker has its own 6h cooldown so calling
        // it on every refresh is safe.
        EpisodeTrackerService.shared.scanIfNeeded()
        // Also scan followed YouTube creators for recent uploads so their
        // videos populate the New Episodes rail.
        EpisodeTrackerService.shared.scanYouTubeIfNeeded()
        // Keep the widget in sync with the latest counts.
        WidgetDataService.shared.pushCounts(
            watchlistCount: userStreams.count,
            newEpisodeCount: newEpisodes.count
        )
        lastFullRefreshAt = Date()
    }

    /// Re-runs `refreshAll()` only when the previous full refresh is older
    /// than `minimumInterval` seconds. Used by the Home screen's scenePhase
    /// observer so backgrounding the app and returning after >60s re-sorts
    /// the My Watch List rail without a manual pull-to-refresh.
    func refreshIfStale(minimumInterval: TimeInterval = 60) async {
        if let lastFullRefreshAt, Date().timeIntervalSince(lastFullRefreshAt) < minimumInterval {
            return
        }
        lastFullRefreshAt = Date()
        await refreshAll()
    }

    /// Loads the canonical list. Fetches by user_id (signed-in) OR
    /// device_id (guests + cross-device sync) so the watch list works for
    /// every user state. On failure we keep showing the local cache.
    func fetchUserStreams() async {
        isLoadingStreams = true
        defer { isLoadingStreams = false }
        let deviceId = DeviceIdentity.shared.deviceId
        do {
            // Single-ownership scoping: signed-in users read strictly by
            // user_id; guests read by device_id AND user_id IS NULL so two
            // accounts on one install never see each other's rows.
            var query = SupabaseManager.shared.client
                .from("user_streams")
                .select()
            if let uid = currentUserId?.uuidString {
                query = query.eq("user_id", value: uid)
            } else {
                query = query.eq("device_id", value: deviceId)
                    .filter("user_id", operator: "is", value: "null")
            }
            let rows: [UserStream] = try await query
                .order("added_at", ascending: false)
                .execute()
                .value
            let merged = mergeRemoteWithLocal(remote: rows)
            self.userStreams = merged
            saveLocalCache(merged)
        } catch {
            self.lastError = error.localizedDescription
            print("[Streams] fetchUserStreams failed: \(error.localizedDescription)")
            // Network/RLS failure — keep showing the local cache so the user
            // never sees their list mysteriously disappear.
            self.userStreams = loadLocalCache()
        }
    }

    func fetchNewEpisodes() async {
        isLoadingEpisodes = true
        defer { isLoadingEpisodes = false }
        let deviceId = DeviceIdentity.shared.deviceId
        do {
            // Single-ownership scoping: signed-in users read strictly by
            // user_id; guests read by device_id AND user_id IS NULL.
            var query = SupabaseManager.shared.client
                .from("user_streams")
                .select()
            if let uid = currentUserId?.uuidString {
                query = query.eq("user_id", value: uid)
            } else {
                query = query.eq("device_id", value: deviceId)
                    .filter("user_id", operator: "is", value: "null")
            }
            let mine: [UserStream] = try await query.execute().value
            let titleIds = mine.map { $0.titleId }
            guard !titleIds.isEmpty else {
                newEpisodes = []
                return
            }

            // Split title IDs: TMDB (numeric) vs non-TMDB (prefixed like yt:, tw:, kick:, pod:).
            // TMDB titles only surface episodes marked is_new = true (freshly aired),
            // while non-TMDB creators surface all recent uploads regardless of push state
            // because YouTube/Twitch uploads are not gated by an is_new lifecycle.
            let tmdbIds = titleIds.filter { Int($0.trimmingCharacters(in: .whitespaces)) != nil }
            let nonTmdbIds = titleIds.filter { !tmdbIds.contains($0) }

            var allRows: [NewEpisodeRow] = []

            // TMDB: only fresh (is_new = true) episodes.
            if !tmdbIds.isEmpty {
                let tmdbRows: [NewEpisodeRow] = try await SupabaseManager.shared.client
                    .from("new_episodes")
                    .select()
                    .in("title_id", values: tmdbIds)
                    .eq("is_new", value: true)
                    .order("released_at", ascending: false)
                    .limit(20)
                    .execute()
                    .value
                allRows.append(contentsOf: tmdbRows)
            }

            // Non-TMDB creators: all recent uploads, regardless of is_new.
            // The push-notification cron flips is_new → false for TMDB episodes,
            // but YouTube/Twitch creator uploads live outside that lifecycle.
            if !nonTmdbIds.isEmpty {
                let nonTmdbRows: [NewEpisodeRow] = try await SupabaseManager.shared.client
                    .from("new_episodes")
                    .select()
                    .in("title_id", values: nonTmdbIds)
                    .order("released_at", ascending: false)
                    .limit(20)
                    .execute()
                    .value
                allRows.append(contentsOf: nonTmdbRows)
            }

            // Sort merged rows by released_at descending, then cap.
            let sorted = allRows.sorted { a, b in
                let da = a.releasedAt ?? Date.distantPast
                let db = b.releasedAt ?? Date.distantPast
                return da > db
            }
            self.newEpisodes = Array(sorted.prefix(20))
        } catch {
            self.lastError = error.localizedDescription
            print("[Streams] fetchNewEpisodes failed: \(error.localizedDescription)")
        }
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
            let rows: [TitleRecencyRow] = try await SupabaseManager.shared.client
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
            print("[Streams] fetchLatestContentDates failed: \(error.localizedDescription)")
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
        let owner = currentUserId?.uuidString ?? DeviceIdentity.shared.deviceId
        do {
            let rows: [WatchlistSeenRow] = try await SupabaseManager.shared.client
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
            print("[Streams] fetchWatchlistSeen failed: \(error.localizedDescription)")
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
        let owner = currentUserId?.uuidString ?? DeviceIdentity.shared.deviceId
        let now = Date()
        // Optimistic clear so the badge vanishes before the server responds.
        seenContentAt[titleId] = now
        let payload: [String: AnyJSON] = [
            "owner": .string(owner),
            "title_id": .string(titleId),
            "seen_content_at": .string(ISO8601DateFormatter().string(from: now))
        ]
        do {
            try await SupabaseManager.shared.client
                .from("watchlist_seen")
                .upsert(payload)
                .execute()
        } catch {
            print("[Streams] markWatchlistSeen failed: \(error.localizedDescription)")
        }
    }

    /// Clears the watch-list badge only when the title is actually saved in
    /// the user's watch list. No-ops otherwise — e.g. for a deep-link id that
    /// isn't a watch-list row, or a title slug that doesn't match any row.
    func markWatchlistSeenIfSaved(titleId: String) async {
        let trimmed = titleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard userStreams.contains(where: { $0.titleId == trimmed }) else { return }
        await markWatchlistSeen(titleId: trimmed)
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
    func newBadgeText(for stream: UserStream) -> String? {
        newBadgeText(titleId: stream.titleId)
    }

    /// Same rules as `newBadgeText(for:)`, keyed by `title_id` for callers that
    /// only hold an id — e.g. the Home watch-list rail, which renders `Episode`
    /// values rather than `UserStream` rows.
    func newBadgeText(titleId: String) -> String? {
        guard let lastContent = latestContentAt[titleId] else { return nil }
        let kind = latestContentKind[titleId] ?? "tv"
        guard kind != "movie" else { return nil }
        guard lastContent >= Date().addingTimeInterval(-7 * 24 * 60 * 60) else { return nil }
        if let seen = seenContentAt[titleId], seen >= lastContent { return nil }
        return kind == "tv" ? "NEW EPISODE" : "NEW UPLOAD"
    }

    // MARK: - Write

    /// Add a title to the user's watch list. Optimistic — the local state
    /// (and persisted cache) updates immediately so every consumer sees the
    /// change on the next frame, regardless of whether Supabase eventually
    /// succeeds. Writes through to Supabase for BOTH guests and signed-in
    /// users so the row is recoverable across reinstalls/devices.
    func addToMyStreams(titleId: String, title: String?, posterUrl: String? = nil, platform: String? = nil, isTV: Bool? = nil) async {
        let trimmedId = titleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else { return }

        // 1. Update local state immediately (optimistic UI).
        let alreadySaved = userStreams.contains { $0.titleId == trimmedId }
        if !alreadySaved {
            let optimistic = UserStream(
                id: UUID().uuidString,
                userId: currentUserId?.uuidString ?? Self.guestUserId,
                titleId: trimmedId,
                title: title,
                posterUrl: posterUrl,
                platform: platform,
                addedAt: Date(),
                isTV: isTV
            )
            self.userStreams.insert(optimistic, at: 0)
            saveLocalCache(self.userStreams)
        }

        WatchIntentLogger.shared.log(
            eventType: .streamAdded,
            titleId: trimmedId,
            platformId: platform?.lowercased()
        )

        // 2. Push to Supabase for everyone — guests included. The row is
        // owned by `device_id` (always set) and, for signed-in users, also
        // by `user_id` so the list survives sign-in/out and reinstalls.
        let didInsert = await insertUserStream(
            userId: currentUserId?.uuidString,
            deviceId: DeviceIdentity.shared.deviceId,
            titleId: trimmedId,
            title: title,
            posterUrl: posterUrl,
            platform: platform,
            isTV: isTV
        )
        if didInsert {
            // Refresh to pick up the canonical id/timestamp from the server.
            await fetchUserStreams()
        }
        // Local optimistic row stays even on failure — user still has it on
        // this device.
        // Adding a new title is the most likely moment we'll discover a
        // fresh episode for it, so trigger an immediate tracker scan
        // (bypassing the 6h cooldown) without blocking the caller.
        EpisodeTrackerService.shared.scanIfNeeded(force: true)
        // Keep the widget in sync after add.
        WidgetDataService.shared.pushCounts(
            watchlistCount: userStreams.count,
            newEpisodeCount: newEpisodes.count
        )
    }

    /// Inserts a row into `user_streams` using a dictionary payload so we can
    /// drop optional columns (`title`, `poster_url`, `platform`) if the live
    /// schema is missing them. Returns `true` on success.
    ///
    /// We surface RLS errors with a friendly message so the user knows to
    /// open the diagnostics screen and run the schema setup SQL.
    @discardableResult
    private func insertUserStream(
        userId: String?,
        deviceId: String,
        titleId: String,
        title: String?,
        posterUrl: String?,
        platform: String?,
        isTV: Bool? = nil
    ) async -> Bool {
        // Always populate `title_name` (legacy schemas declared it NOT NULL).
        // Fall back to titleId if we don't have a display title so the
        // constraint is satisfied. `dropMissingColumn` retries below drop
        // any of these keys if the live schema doesn't have them.
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
        if let isTV { payload["is_tv"] = .bool(isTV) }

        // Up to four retries: legacy schemas may still have other NOT NULL
        // columns or missing columns we have to work around.
        for attempt in 0..<5 {
            do {
                try await SupabaseManager.shared.client
                    .from("user_streams")
                    .insert(payload)
                    .execute()
                self.lastError = nil
                return true
            } catch {
                let message = error.localizedDescription
                let lowered = message.lowercased()
                // Duplicate row → not really an error (saved on another device).
                if lowered.contains("duplicate") || lowered.contains("23505") {
                    return true
                }
                // Missing-column → drop that column and retry.
                if attempt < 4, let dropped = Self.dropMissingColumn(from: payload, error: message) {
                    payload = dropped
                    continue
                }
                // NOT NULL violation on a column we don't yet send → backfill
                // with the safe title and retry.
                if attempt < 4,
                   let filled = Self.fillNotNullViolation(in: payload, error: message, fallback: safeTitle) {
                    payload = filled
                    continue
                }
                if lowered.contains("42501") || lowered.contains("row-level security") {
                    self.lastError = "Supabase blocked the write. Open Profile → Help & Feedback → App Diagnostics and run the schema setup SQL."
                } else {
                    self.lastError = message
                }
                print("[Streams] add failed: \(message)")
                return false
            }
        }
        return false
    }

    /// Remove a title from the watch list. Mirrors `addToMyStreams`:
    /// local state is updated immediately, Supabase is best-effort.
    /// Deletes by user_id (when signed in) OR device_id so guest rows are
    /// also removed.
    func removeFromMyStreams(titleId: String) async {
        let trimmedId = titleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else { return }

        self.userStreams.removeAll { $0.titleId == trimmedId }
        saveLocalCache(self.userStreams)

        WatchIntentLogger.shared.log(
            eventType: .streamRemoved,
            titleId: trimmedId
        )

        let deviceId = DeviceIdentity.shared.deviceId
        do {
            var query = SupabaseManager.shared.client
                .from("user_streams")
                .delete()
                .eq("title_id", value: trimmedId)
            if let uid = currentUserId?.uuidString {
                query = query.eq("user_id", value: uid)
            } else {
                query = query.eq("device_id", value: deviceId)
                    .filter("user_id", operator: "is", value: "null")
            }
            try await query.execute()
        } catch {
            self.lastError = error.localizedDescription
            print("[Streams] remove failed: \(error.localizedDescription)")
        }
        // Keep the widget in sync after remove.
        WidgetDataService.shared.pushCounts(
            watchlistCount: userStreams.count,
            newEpisodeCount: newEpisodes.count
        )
    }

    /// Persists a corrected media type onto an existing `user_streams` row.
    /// Called when the detail screen's legacy heal determines a saved title
    /// was actually a movie (or show) so the row self-corrects permanently.
    func updateStreamMediaType(titleId: String, isTV: Bool) async {
        let trimmedId = titleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else { return }
        let deviceId = DeviceIdentity.shared.deviceId
        do {
            var query = try SupabaseManager.shared.client
                .from("user_streams")
                .update(["is_tv": isTV])
                .eq("title_id", value: trimmedId)
            if let uid = currentUserId?.uuidString {
                query = query.eq("user_id", value: uid)
            } else {
                query = query.eq("device_id", value: deviceId)
                    .filter("user_id", operator: "is", value: "null")
            }
            try await query.execute()
        } catch {
            print("[Streams] updateStreamMediaType failed: \(error.localizedDescription)")
        }
    }

    /// Mark any `new_episodes` rows older than 24h as no longer new for the current user's titles.
    func markStaleEpisodesSeen() async {
        let deviceId = DeviceIdentity.shared.deviceId
        do {
            var query = SupabaseManager.shared.client
                .from("user_streams")
                .select("title_id")
            if let uid = currentUserId?.uuidString {
                query = query.eq("user_id", value: uid)
            } else {
                query = query.eq("device_id", value: deviceId)
                    .filter("user_id", operator: "is", value: "null")
            }
            let mine: [UserStream] = try await query.execute().value
            let titleIds = mine.map { $0.titleId }
            guard !titleIds.isEmpty else { return }
            let cutoff = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-24 * 60 * 60))
            try await SupabaseManager.shared.client
                .from("new_episodes")
                .update(["is_new": false])
                .in("title_id", values: titleIds)
                .lt("released_at", value: cutoff)
                .execute()
        } catch {
            print("[Streams] markStaleEpisodesSeen failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Guest → authenticated sync

    /// Pushes any locally-saved (guest era) rows up to Supabase after the
    /// user signs in. Idempotent — uses Supabase `insert` and tolerates
    /// duplicate-key errors when a row already exists on the server.
    /// Should be called from each auth path (Apple/Google/email).
    func syncLocalToSupabase() async {
        guard let uid = currentUserId else { return }
        let local = loadLocalCache()
        let pending = local.filter { $0.userId == Self.guestUserId }
        guard !pending.isEmpty else {
            // Even when there's nothing to push, kick off a fetch so the
            // canonical signed-in list replaces the guest-era cache.
            await fetchUserStreams()
            return
        }

        let deviceId = DeviceIdentity.shared.deviceId
        for row in pending {
            _ = await insertUserStream(
                userId: uid.uuidString,
                deviceId: deviceId,
                titleId: row.titleId,
                title: row.title,
                posterUrl: row.posterUrl,
                platform: row.platform,
                isTV: row.isTV
            )
        }

        // Strip the now-synced guest rows from the local cache; the next
        // fetch will repopulate with the canonical server records.
        let remaining = local.filter { $0.userId != Self.guestUserId }
        saveLocalCache(remaining)

        await fetchUserStreams()
    }

    // MARK: - Sign-out cleanup

    /// Clears all in-memory watch list state and removes the local UserDefaults
    /// cache. Called from `AuthViewModel.signOut()` so the next user starts
    /// with a clean slate instead of inheriting the previous user's saved titles.
    func clearLocalCache() {
        self.userStreams = []
        self.newEpisodes = []
        self.seenContentAt = [:]
        self.latestContentAt = [:]
        self.latestContentKind = [:]
        UserDefaults.standard.removeObject(forKey: localCacheKey)
    }

    // MARK: - Ownership claiming

    /// Promotes any guest-era rows on this device (user_id IS NULL,
    /// device_id matches) to the signed-in user via the `claim_device_rows`
    /// SECURITY DEFINER RPC. Called from `AuthViewModel` at every authenticated
    /// entry point **before** `syncLocalToSupabase()` so guest rows are
    /// attributed to the new account before the first fetch. Silently swallows
    /// errors (no session, network failure, zero guest rows) so it never blocks
    /// or delays the subsequent fetch.
    func claimDeviceRows() async {
        do {
            _ = try await SupabaseManager.shared.client
                .rpc("claim_device_rows", params: ["p_device_id": DeviceIdentity.shared.deviceId])
                .execute()
        } catch {
            print("[Streams] claimDeviceRows failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Local cache helpers

    private func loadLocalCache() -> [UserStream] {
        guard let data = UserDefaults.standard.data(forKey: localCacheKey) else { return [] }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([UserStream].self, from: data)
        } catch {
            print("[Streams] local cache decode failed: \(error.localizedDescription)")
            return []
        }
    }

    private func saveLocalCache(_ streams: [UserStream]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(streams)
            UserDefaults.standard.set(data, forKey: localCacheKey)
        } catch {
            print("[Streams] local cache encode failed: \(error.localizedDescription)")
        }
    }

    /// When the remote list includes a title we already have locally, the
    /// remote row (canonical id, timestamps) wins. Local rows whose titleIds
    /// aren't yet in the remote list are kept so a pending sync never makes
    /// the watchlist appear to "lose" items mid-flight.
    private func mergeRemoteWithLocal(remote: [UserStream]) -> [UserStream] {
        let remoteTitleIds = Set(remote.map { $0.titleId })
        let pendingLocal = loadLocalCache().filter { !remoteTitleIds.contains($0.titleId) }
        return remote + pendingLocal
    }

    /// Inspect a Postgres error message for `PGRST204 / could not find ... column`
    /// and return the payload with that column removed. `user_id` and `title_id`
    /// are required and never dropped.
    private static func dropMissingColumn(
        from payload: [String: AnyJSON],
        error: String
    ) -> [String: AnyJSON]? {
        let lowered = error.lowercased()
        guard lowered.contains("could not find") && lowered.contains("column") else {
            return nil
        }
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

    /// Inspect a Postgres `23502` (not-null violation) error and backfill
    /// the referenced column with the provided fallback so the next retry
    /// can succeed. Returns `nil` if the column can't be parsed or is
    /// already present.
    private static func fillNotNullViolation(
        in payload: [String: AnyJSON],
        error: String,
        fallback: String
    ) -> [String: AnyJSON]? {
        let lowered = error.lowercased()
        guard lowered.contains("23502") || lowered.contains("not-null constraint") else {
            return nil
        }
        // Postgres formats as: `null value in column "colname" of relation ...`
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

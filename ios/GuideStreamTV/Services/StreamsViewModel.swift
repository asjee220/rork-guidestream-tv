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
    var isLoadingStreams: Bool = false
    var isLoadingEpisodes: Bool = false
    var lastError: String?

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
        async let a: () = fetchUserStreams()
        async let b: () = fetchNewEpisodes()
        _ = await (a, b)
        // After we have a fresh watch list, kick off the episode tracker
        // so any titles that aired a new episode show up in the rail on
        // the next fetch. The tracker has its own 6h cooldown so calling
        // it on every refresh is safe.
        EpisodeTrackerService.shared.scanIfNeeded()
        // Keep the widget in sync with the latest counts.
        WidgetDataService.shared.pushCounts(
            watchlistCount: userStreams.count,
            newEpisodeCount: newEpisodes.count
        )
    }

    /// Loads the canonical list. Fetches by user_id (signed-in) OR
    /// device_id (guests + cross-device sync) so the watch list works for
    /// every user state. On failure we keep showing the local cache.
    func fetchUserStreams() async {
        isLoadingStreams = true
        defer { isLoadingStreams = false }
        let deviceId = DeviceIdentity.shared.deviceId
        do {
            // Use a PostgREST `or=(user_id.eq.<uid>,device_id.eq.<did>)` filter
            // so signed-in users see rows tied to either their account or this
            // install, and guests see their device-owned rows.
            var query = SupabaseManager.shared.client
                .from("user_streams")
                .select()
            if let uid = currentUserId?.uuidString {
                query = query.or("user_id.eq.\(uid),device_id.eq.\(deviceId)")
            } else {
                query = query.eq("device_id", value: deviceId)
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
            // Get this user's title_ids by user_id (signed-in) OR device_id
            // (guests + cross-device), so the New Episodes panel works for
            // every session state.
            var query = SupabaseManager.shared.client
                .from("user_streams")
                .select()
            if let uid = currentUserId?.uuidString {
                query = query.or("user_id.eq.\(uid),device_id.eq.\(deviceId)")
            } else {
                query = query.eq("device_id", value: deviceId)
            }
            let mine: [UserStream] = try await query.execute().value
            let titleIds = mine.map { $0.titleId }
            guard !titleIds.isEmpty else {
                newEpisodes = []
                return
            }
            let rows: [NewEpisodeRow] = try await SupabaseManager.shared.client
                .from("new_episodes")
                .select()
                .in("title_id", values: titleIds)
                .eq("is_new", value: true)
                .order("released_at", ascending: false)
                .limit(20)
                .execute()
                .value
            self.newEpisodes = rows
        } catch {
            self.lastError = error.localizedDescription
            print("[Streams] fetchNewEpisodes failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Write

    /// Add a title to the user's watch list. Optimistic — the local state
    /// (and persisted cache) updates immediately so every consumer sees the
    /// change on the next frame, regardless of whether Supabase eventually
    /// succeeds. Writes through to Supabase for BOTH guests and signed-in
    /// users so the row is recoverable across reinstalls/devices.
    func addToMyStreams(titleId: String, title: String?, posterUrl: String? = nil, platform: String? = nil) async {
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
                addedAt: Date()
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
            platform: platform
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
        platform: String?
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
                query = query.or("user_id.eq.\(uid),device_id.eq.\(deviceId)")
            } else {
                query = query.eq("device_id", value: deviceId)
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

    /// Mark any `new_episodes` rows older than 24h as no longer new for the current user's titles.
    func markStaleEpisodesSeen() async {
        let deviceId = DeviceIdentity.shared.deviceId
        do {
            var query = SupabaseManager.shared.client
                .from("user_streams")
                .select("title_id")
            if let uid = currentUserId?.uuidString {
                query = query.or("user_id.eq.\(uid),device_id.eq.\(deviceId)")
            } else {
                query = query.eq("device_id", value: deviceId)
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
                platform: row.platform
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
        UserDefaults.standard.removeObject(forKey: localCacheKey)
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

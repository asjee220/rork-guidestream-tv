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
    }

    /// Loads the canonical list. For signed-in users we hit Supabase and
    /// merge any unsynced local rows on top; for guests we just use the
    /// local cache. On network failure we keep showing whatever was cached.
    func fetchUserStreams() async {
        guard let uid = currentUserId else {
            self.userStreams = loadLocalCache()
            return
        }
        isLoadingStreams = true
        defer { isLoadingStreams = false }
        do {
            let rows: [UserStream] = try await SupabaseManager.shared.client
                .from("user_streams")
                .select()
                .eq("user_id", value: uid)
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
        guard let uid = currentUserId else {
            newEpisodes = []
            return
        }
        isLoadingEpisodes = true
        defer { isLoadingEpisodes = false }
        do {
            // First get the user's title_ids
            let mine: [UserStream] = try await SupabaseManager.shared.client
                .from("user_streams")
                .select("title_id")
                .eq("user_id", value: uid)
                .execute()
                .value
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
    /// succeeds.
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

        // 2. Push to Supabase if we have a session; tolerate failure.
        guard let uid = currentUserId else { return }
        let payload = UserStreamInsert(
            user_id: uid.uuidString,
            title_id: trimmedId,
            title: title,
            poster_url: posterUrl,
            platform: platform
        )
        do {
            try await SupabaseManager.shared.client
                .from("user_streams")
                .insert(payload)
                .execute()
            // Refresh to pick up the canonical id/timestamp from the server.
            await fetchUserStreams()
        } catch {
            self.lastError = error.localizedDescription
            print("[Streams] add failed: \(error.localizedDescription)")
            // Local optimistic row stays — user still has it on this device.
        }
    }

    /// Remove a title from the watch list. Mirrors `addToMyStreams`:
    /// local state is updated immediately, Supabase is best-effort.
    func removeFromMyStreams(titleId: String) async {
        let trimmedId = titleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else { return }

        self.userStreams.removeAll { $0.titleId == trimmedId }
        saveLocalCache(self.userStreams)

        WatchIntentLogger.shared.log(
            eventType: .streamRemoved,
            titleId: trimmedId
        )

        guard let uid = currentUserId else { return }
        do {
            try await SupabaseManager.shared.client
                .from("user_streams")
                .delete()
                .eq("user_id", value: uid)
                .eq("title_id", value: trimmedId)
                .execute()
        } catch {
            self.lastError = error.localizedDescription
            print("[Streams] remove failed: \(error.localizedDescription)")
        }
    }

    /// Mark any `new_episodes` rows older than 24h as no longer new for the current user's titles.
    func markStaleEpisodesSeen() async {
        guard let uid = currentUserId else { return }
        do {
            let mine: [UserStream] = try await SupabaseManager.shared.client
                .from("user_streams")
                .select("title_id")
                .eq("user_id", value: uid)
                .execute()
                .value
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

        for row in pending {
            let payload = UserStreamInsert(
                user_id: uid.uuidString,
                title_id: row.titleId,
                title: row.title,
                poster_url: row.posterUrl,
                platform: row.platform
            )
            do {
                try await SupabaseManager.shared.client
                    .from("user_streams")
                    .insert(payload)
                    .execute()
            } catch {
                let msg = error.localizedDescription
                // Duplicate-key violations are fine — the row already exists
                // on the server (e.g. same title saved on another device).
                if !msg.localizedCaseInsensitiveContains("duplicate")
                    && !msg.localizedCaseInsensitiveContains("23505") {
                    print("[Streams] sync local→remote failed for \(row.titleId): \(msg)")
                }
            }
        }

        // Strip the now-synced guest rows from the local cache; the next
        // fetch will repopulate with the canonical server records.
        let remaining = local.filter { $0.userId != Self.guestUserId }
        saveLocalCache(remaining)

        await fetchUserStreams()
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
}

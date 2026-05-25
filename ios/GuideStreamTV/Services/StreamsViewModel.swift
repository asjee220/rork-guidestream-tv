//
//  StreamsViewModel.swift
//  GuideStreamTV
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

    private var currentUserId: UUID? {
        AuthViewModel.shared.currentUser?.id
    }

    func refreshAll() async {
        async let a: () = fetchUserStreams()
        async let b: () = fetchNewEpisodes()
        _ = await (a, b)
    }

    func fetchUserStreams() async {
        guard let uid = currentUserId else {
            userStreams = []
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
            self.userStreams = rows
        } catch {
            self.lastError = error.localizedDescription
            print("[Streams] fetchUserStreams failed: \(error.localizedDescription)")
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

    func addToMyStreams(titleId: String, title: String?, posterUrl: String? = nil, platform: String? = nil) async {
        guard let uid = currentUserId else { return }
        let payload = UserStreamInsert(
            user_id: uid.uuidString,
            title_id: titleId,
            title: title,
            poster_url: posterUrl,
            platform: platform
        )
        WatchIntentLogger.shared.log(
            eventType: .streamAdded,
            titleId: titleId,
            platformId: platform?.lowercased()
        )
        do {
            try await SupabaseManager.shared.client
                .from("user_streams")
                .insert(payload)
                .execute()
            await fetchUserStreams()
        } catch {
            self.lastError = error.localizedDescription
            print("[Streams] add failed: \(error.localizedDescription)")
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

    func removeFromMyStreams(titleId: String) async {
        guard let uid = currentUserId else { return }
        WatchIntentLogger.shared.log(
            eventType: .streamRemoved,
            titleId: titleId
        )
        do {
            try await SupabaseManager.shared.client
                .from("user_streams")
                .delete()
                .eq("user_id", value: uid)
                .eq("title_id", value: titleId)
                .execute()
            await fetchUserStreams()
        } catch {
            self.lastError = error.localizedDescription
            print("[Streams] remove failed: \(error.localizedDescription)")
        }
    }
}

//
//  TVSocialService.swift
//  GuideStreamTVTV
//
//  Likes and watched marks for the tvOS target. The iPhone app has
//  `SocialViewModel`, which also carries comments, follows and profile
//  social state; none of that has a tvOS surface, so this is deliberately
//  the narrow half: the two toggles Reels needs, against the same two
//  tables, with the same ownership rule.
//
//  Ownership mirrors `TVStreamsViewModel`: a signed-in viewer is keyed by
//  `user_id`, a guest by `device_id`. Reads filter on whichever applies, so
//  a guest never sees a signed-in viewer's marks on a shared Apple TV.
//

import Foundation
import Supabase

private nonisolated struct TVTitleMarkRow: Decodable, Sendable {
    let titleId: String
    enum CodingKeys: String, CodingKey { case titleId = "title_id" }
}

@MainActor
@Observable
final class TVSocialService {
    static let shared = TVSocialService()
    private init() {}

    private(set) var likedTitleIds: Set<String> = []
    private(set) var watchedTitleIds: Set<String> = []
    /// Like totals across all viewers, for the count on the Like button.
    private(set) var likeCounts: [String: Int] = [:]

    private var userId: UUID? { TVAuthViewModel.shared.currentUser?.id }
    private var deviceId: String { TVDeviceIdentity.shared.deviceId }

    func isLiked(_ titleId: String) -> Bool { likedTitleIds.contains(titleId) }
    func isWatched(_ titleId: String) -> Bool { watchedTitleIds.contains(titleId) }
    func likeCount(_ titleId: String) -> Int { likeCounts[titleId] ?? 0 }

    // MARK: - Load

    /// Loads this viewer's marks, and the public like totals, for a batch of
    /// titles. Called once per feed page rather than per reel.
    func loadState(for titleIds: [String]) async {
        let ids = Array(Set(titleIds)).filter { !$0.isEmpty }
        guard !ids.isEmpty else { return }

        async let mine: Void = loadMine(ids)
        async let totals: Void = loadLikeTotals(ids)
        _ = await (mine, totals)
    }

    private func loadMine(_ ids: [String]) async {
        for table in ["title_likes", "title_watched"] {
            do {
                var query = SupabaseManager.shared.client
                    .from(table)
                    .select("title_id")
                    .in("title_id", values: ids)
                if let userId {
                    query = query.eq("user_id", value: userId.uuidString)
                } else {
                    query = query.eq("device_id", value: deviceId)
                }
                let rows: [TVTitleMarkRow] = try await query.execute().value
                let set = Set(rows.map { $0.titleId })
                if table == "title_likes" {
                    likedTitleIds.formUnion(set)
                } else {
                    watchedTitleIds.formUnion(set)
                }
            } catch {
                // A failed read leaves the buttons in their unmarked state,
                // which is recoverable; a toggle still writes.
                continue
            }
        }
    }

    private func loadLikeTotals(_ ids: [String]) async {
        do {
            let rows: [TVTitleMarkRow] = try await SupabaseManager.shared.client
                .from("title_likes")
                .select("title_id")
                .in("title_id", values: ids)
                .execute()
                .value
            var counts: [String: Int] = [:]
            for row in rows { counts[row.titleId, default: 0] += 1 }
            for id in ids { likeCounts[id] = counts[id] ?? 0 }
        } catch {
            for id in ids where likeCounts[id] == nil { likeCounts[id] = 0 }
        }
    }

    // MARK: - Toggles

    /// Optimistic: the button flips immediately and the row is written
    /// behind it. A failed write rolls the local state back, so the button
    /// never claims something the database does not hold.
    func toggleLike(titleId: String, mediaType: String, tmdbId: Int) async {
        let wasLiked = likedTitleIds.contains(titleId)
        if wasLiked {
            likedTitleIds.remove(titleId)
            likeCounts[titleId] = max(0, likeCount(titleId) - 1)
        } else {
            likedTitleIds.insert(titleId)
            likeCounts[titleId] = likeCount(titleId) + 1
            WatchIntentLogger.shared.log(
                eventType: .trailerLiked,
                titleId: titleId,
                metadata: ["surface": "tv_reels"]
            )
        }

        let ok = wasLiked
            ? await deleteMark(table: "title_likes", titleId: titleId)
            : await insertMark(table: "title_likes", titleId: titleId,
                               mediaType: mediaType, tmdbId: tmdbId, titleName: nil)
        guard !ok else { return }
        if wasLiked {
            likedTitleIds.insert(titleId)
            likeCounts[titleId] = likeCount(titleId) + 1
        } else {
            likedTitleIds.remove(titleId)
            likeCounts[titleId] = max(0, likeCount(titleId) - 1)
        }
    }

    func toggleWatched(titleId: String, titleName: String, mediaType: String, tmdbId: Int) async {
        let wasWatched = watchedTitleIds.contains(titleId)
        if wasWatched { watchedTitleIds.remove(titleId) } else { watchedTitleIds.insert(titleId) }

        WatchIntentLogger.shared.log(
            eventType: .watchedToggled,
            titleId: titleId,
            metadata: ["watched": !wasWatched, "source": "tv_reels", "media_type": mediaType]
        )

        let ok = wasWatched
            ? await deleteMark(table: "title_watched", titleId: titleId)
            : await insertMark(table: "title_watched", titleId: titleId,
                               mediaType: mediaType, tmdbId: tmdbId, titleName: titleName)
        guard !ok else { return }
        if wasWatched { watchedTitleIds.insert(titleId) } else { watchedTitleIds.remove(titleId) }
    }

    // MARK: - Writes

    private func insertMark(
        table: String,
        titleId: String,
        mediaType: String,
        tmdbId: Int,
        titleName: String?
    ) async -> Bool {
        var payload: [String: AnyJSON] = [
            "title_id": .string(titleId),
            "media_type": .string(mediaType),
            "tmdb_id": .integer(tmdbId)
        ]
        if let userId {
            payload["user_id"] = .string(userId.uuidString)
        } else {
            payload["device_id"] = .string(deviceId)
        }
        if let titleName, table == "title_watched" {
            payload["title_name"] = .string(titleName)
        }
        do {
            try await SupabaseManager.shared.client.from(table).insert(payload).execute()
            return true
        } catch {
            return false
        }
    }

    private func deleteMark(table: String, titleId: String) async -> Bool {
        do {
            var query = SupabaseManager.shared.client
                .from(table)
                .delete()
                .eq("title_id", value: titleId)
            if let userId {
                query = query.eq("user_id", value: userId.uuidString)
            } else {
                query = query.eq("device_id", value: deviceId)
            }
            try await query.execute()
            return true
        } catch {
            return false
        }
    }
}

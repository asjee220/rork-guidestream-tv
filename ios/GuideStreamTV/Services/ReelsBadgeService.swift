//  ReelsBadgeService.swift
//  GuideStreamTV
//
//  Unseen-content badge for the Reels tab. Computes whether any streaming
//  upcoming titles appeared since the user last opened Reels. Guest users
//  never see a badge because RLS prevents them from reading their own users
//  row; cold-start users get reels_seen_at stamped on first refresh.
//

import Foundation
import Supabase

@MainActor
@Observable
final class ReelsBadgeService {
    static let shared = ReelsBadgeService()

    private init() {}

    var hasUnseen: Bool = false

    /// Refreshes the badge state. Safe to call repeatedly; never throws.
    func refresh() async {
        guard let user = AuthViewModel.shared.currentUser else {
            print("[ReelsBadge] no signed-in user, hiding badge")
            hasUnseen = false
            return
        }

        do {
            let userId = user.id.uuidString
            let rows: [ReelsSeenRow] = try await SupabaseManager.shared.client
                .from("users")
                .select("reels_seen_at")
                .eq("id", value: userId)
                .single()
                .execute()
                .value

            guard let seenAt = rows.first?.reelsSeenAt else {
                print("[ReelsBadge] first use — stamping reels_seen_at")
                await stampSeen(for: userId)
                hasUnseen = false
                return
            }

            let unseenCount = try await countUnseen(since: seenAt)
            hasUnseen = unseenCount > 0
            print("[ReelsBadge] unseen count = \(unseenCount), hasUnseen = \(hasUnseen)")
        } catch {
            print("[ReelsBadge] refresh failed: \(error.localizedDescription)")
            hasUnseen = false
        }
    }

    /// Marks Reels as seen. Optimistically clears the badge before the network call.
    func markSeen() async {
        guard let user = AuthViewModel.shared.currentUser else { return }
        hasUnseen = false
        await stampSeen(for: user.id.uuidString)
    }

    private func stampSeen(for userId: String) async {
        do {
            try await SupabaseManager.shared.client
                .from("users")
                .update(["reels_seen_at": Date().ISO8601Format()])
                .eq("id", value: userId)
                .execute()
            print("[ReelsBadge] stamped reels_seen_at for \(userId)")
        } catch {
            print("[ReelsBadge] stamp failed: \(error.localizedDescription)")
        }
    }

    private func countUnseen(since: String) async throws -> Int {
        let rows: [CreatedAtRow] = try await SupabaseManager.shared.client
            .from("streaming_upcoming")
            .select("created_at")
            .gt("created_at", value: since)
            .execute()
            .value
        return rows.count
    }
}

// MARK: - Decodable rows

nonisolated struct ReelsSeenRow: Decodable, Sendable {
    let reelsSeenAt: String?

    enum CodingKeys: String, CodingKey {
        case reelsSeenAt = "reels_seen_at"
    }
}

nonisolated struct CreatedAtRow: Decodable, Sendable {
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
    }
}

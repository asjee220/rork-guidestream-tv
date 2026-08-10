//
//  ReelsBadgeService.swift
//  GuideStreamTV
//
//  Unseen-content badge for the Reels tab. Fetches the current
//  streaming_upcoming titles and compares their tmdb_ids against a locally
//  stored "seen" set in UserDefaults. Works for both signed-in and guest
//  users — no database column or RLS dependency.
//

import Foundation
import Supabase

@MainActor
@Observable
final class ReelsBadgeService {
    static let shared = ReelsBadgeService()

    private init() {}

    var hasUnseen: Bool = false

    private let seenKey = "gs.reelsSeenIds"

    /// Refreshes the badge state. Fetches streaming_upcoming rows and
    /// compares against the locally stored seen-id set. Safe to call
    /// repeatedly; never throws.
    func refresh() async {
        let rows = await StreamingUpcomingService.shared.fetchUpcoming() ?? []
        let currentIds = Set(rows.map(\.tmdbId))
        let seenIds = loadSeenIds()

        // Unseen = ids in the current upcoming list that the user hasn't
        // acknowledged yet by opening the Reels tab.
        let unseen = currentIds.subtracting(seenIds)
        hasUnseen = !unseen.isEmpty
    }

    /// Marks all current upcoming titles as seen. Clears the badge
    /// optimistically before persisting the full id set.
    func markSeen() async {
        hasUnseen = false
        let rows = await StreamingUpcomingService.shared.fetchUpcoming() ?? []
        let currentIds = Set(rows.map(\.tmdbId))
        // Merge with existing seen ids so older rows that drop off the
        // upcoming list don't re-trigger the badge if they reappear.
        var merged = loadSeenIds()
        merged.formUnion(currentIds)
        saveSeenIds(merged)
    }

    // MARK: - Local persistence

    private func loadSeenIds() -> Set<Int> {
        let arr = UserDefaults.standard.array(forKey: seenKey) as? [Int] ?? []
        return Set(arr)
    }

    private func saveSeenIds(_ ids: Set<Int>) {
        UserDefaults.standard.set(Array(ids), forKey: seenKey)
    }
}

//
//  TVContentSourcesService.swift
//  GuideStreamTVTV
//
//  Recommends creators/podcasts the user might like based on the categories
//  of creators they already follow. Reads the public-readable `content_sources`
//  table through TVSupabaseManager — no RLS or backend change required.
//
//  Category-tier matcher only: every content_sources row is already
//  categorized, so the YouTube category-enrichment and description-keyword
//  tiers from the iOS app are not ported.
//

import Foundation
import Supabase

struct TVRecommendedCreator: Identifiable, Hashable, Sendable {
    let titleId: String
    let displayName: String
    let imageUrl: String?
    let sourceType: String
    let category: String?
    let matchPercentage: Int

    var id: String { titleId }
}

enum TVContentSourcesService {
    static let shared = TVContentSourcesService.self

    /// Returns up to 12 recommended creators/podcasts based on the categories
    /// of the user's followed non-TMDB content. Uses Jaccard similarity over
    /// category tags and clamps the match percentage to 65–98.
    static func fetchRecommendedCreators(forFollowedIds followedIds: [String]) async -> [TVRecommendedCreator] {
        guard !followedIds.isEmpty else { return [] }
        let client = TVSupabaseManager.shared.client

        // Fetch the followed rows to build the user's category tag set.
        let followedRows: [TVContentSource]
        do {
            followedRows = try await client
                .from("content_sources")
                .select()
                .in("title_id", values: followedIds)
                .execute()
                .value
        } catch {
            return []
        }

        let followedTags = buildTagSet(from: followedRows)
        guard !followedTags.isEmpty else { return [] }

        // Fetch candidate rows (non-TMDB sources, most recent first).
        let candidates: [TVContentSource]
        do {
            candidates = try await client
                .from("content_sources")
                .select()
                .neq("source_type", value: "tmdb")
                .order("created_at", ascending: false)
                .range(0..<200)
                .execute()
                .value
        } catch {
            return []
        }

        let followedSet = Set(followedIds)
        var scored: [TVRecommendedCreator] = []
        for candidate in candidates {
            if followedSet.contains(candidate.titleId) { continue }
            let candidateTags = splitTags(candidate.category)
            if candidateTags.isEmpty { continue }
            let intersection = followedTags.intersection(candidateTags).count
            let union = followedTags.union(candidateTags).count
            guard union > 0 else { continue }
            let jaccard = Double(intersection) / Double(union)
            let pct = max(65, min(98, Int(jaccard * 100)))
            scored.append(TVRecommendedCreator(
                titleId: candidate.titleId,
                displayName: candidate.displayName,
                imageUrl: candidate.imageUrl,
                sourceType: candidate.sourceType,
                category: candidate.category,
                matchPercentage: pct
            ))
        }

        scored.sort { a, b in
            if a.matchPercentage != b.matchPercentage {
                return a.matchPercentage > b.matchPercentage
            }
            return a.displayName < b.displayName
        }
        return Array(scored.prefix(12))
    }

    // MARK: - Helpers

    /// Splits a category string on `,`, `/`, or `|`, trims each part, and
    /// lowercases it. Returns an empty set when the string is nil/empty.
    private static func splitTags(_ category: String?) -> Set<String> {
        guard let category, !category.isEmpty else { return [] }
        let parts = category.split { ch in
            ch == "," || ch == "/" || ch == "|"
        }
        var tags: Set<String> = []
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !trimmed.isEmpty { tags.insert(trimmed) }
        }
        return tags
    }

    /// Builds the union of all category tags from the followed rows.
    private static func buildTagSet(from rows: [TVContentSource]) -> Set<String> {
        var tags: Set<String> = []
        for row in rows {
            tags.formUnion(splitTags(row.category))
        }
        return tags
    }
}

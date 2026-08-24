//
//  TVFeaturetteService.swift
//  GuideStreamTVTV
//
//  Read-only access to the public.title_featurettes table — per-title
//  hosted featurette video for the full-screen Home hero. Rows are
//  matched back to the hero pool by tmdb id AND media type so a movie
//  and a show sharing a TMDB id never cross-pollinate. The app never
//  writes to this table (writes are service-role only, mirroring
//  trailer_cache and streaming_releases).
//
//  Modelled on TVStreamingReleasesService: one shared singleton, an
//  explicit selected-columns string, and exactly one batched query per
//  Home load — never one request per item.
//

import Foundation
import Supabase

@MainActor
@Observable
final class TVFeaturetteService {
    static let shared = TVFeaturetteService()

    private init() {}

    /// Columns verified on title_featurettes.
    private let selectedColumns = "tmdb_id,media_type,featurette_url"

    /// Resolves hosted featurette URLs for a hero pool in a single batched
    /// query filtered on the pool's tmdb ids. Returns a map keyed by
    /// canonicalTitleId ("tmdb:tv:123") with featurette_url as the value;
    /// a missing key means the item renders as a still. Any failure —
    /// network, decode, missing table — resolves to an empty dictionary so
    /// no error state ever reaches the UI. Never throws.
    func fetchFeaturettes(for pool: [(tmdbId: Int, isTV: Bool)]) async -> [String: String] {
        let ids = Array(Set(pool.map { $0.tmdbId }))
        guard !ids.isEmpty else { return [:] }

        do {
            let rows: [TVFeaturetteRow] = try await SupabaseManager.shared.client
                .from("title_featurettes")
                .select(selectedColumns)
                .in("tmdb_id", values: ids.map(String.init))
                .execute()
                .value

            var isTVById: [Int: Bool] = [:]
            for entry in pool {
                isTVById[entry.tmdbId] = entry.isTV
            }

            var map: [String: String] = [:]
            for row in rows {
                guard let isTV = isTVById[row.tmdbId] else { continue }
                guard row.mediaType == (isTV ? "tv" : "movie") else { continue }
                let key = "tmdb:\(row.mediaType):\(row.tmdbId)"
                map[key] = row.featuretteUrl
            }
            return map
        } catch {
            return [:]
        }
    }
}

// MARK: - Decodable row

nonisolated struct TVFeaturetteRow: Decodable, Sendable {
    let tmdbId: Int
    let mediaType: String
    let featuretteUrl: String

    enum CodingKeys: String, CodingKey {
        case tmdbId = "tmdb_id"
        case mediaType = "media_type"
        case featuretteUrl = "featurette_url"
    }
}

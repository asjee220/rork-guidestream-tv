//
//  TVStreamingReleasesService.swift
//  GuideStreamTVTV
//
//  Read-only access to the public.streaming_releases and
//  public.streaming_upcoming tables. Feeds the Home "Now & Next on
//  {service}" rail — rows from streaming_releases carry a NOW badge,
//  rows from streaming_upcoming carry a NEXT badge. The app never
//  writes to these tables.
//
//  Modelled on ios/GuideStreamTV/Services/StreamingReleasesService.swift
//  and StreamingUpcomingService.swift, but selects only the columns
//  verified live on both tables.
//

import Foundation
import Supabase

@MainActor
@Observable
final class TVStreamingReleasesService {
    static let shared = TVStreamingReleasesService()

    private init() {}

    /// Columns verified live on both streaming_releases and streaming_upcoming.
    private let selectedColumns = "tmdb_id,tmdb_type,title,poster_url,poster_path,source_id,source_name,is_original,source_release_date"

    /// Fetches all streaming releases ordered by source release date
    /// descending (most recent first). Returns nil on failure so callers
    /// can leave existing rail contents in place. Never throws.
    func fetchReleases() async -> [TVStreamingRelease]? {
        do {
            let rows: [TVStreamingRelease] = try await SupabaseManager.shared.client
                .from("streaming_releases")
                .select(selectedColumns)
                .order("source_release_date", ascending: false)
                .execute()
                .value
            return rows
        } catch {
            return nil
        }
    }

    /// Fetches all upcoming streaming releases ordered by source release
    /// date ascending (soonest first). Returns nil on failure. Never throws.
    func fetchUpcoming() async -> [TVStreamingRelease]? {
        do {
            let rows: [TVStreamingRelease] = try await SupabaseManager.shared.client
                .from("streaming_upcoming")
                .select(selectedColumns)
                .order("source_release_date", ascending: true)
                .execute()
                .value
            return rows
        } catch {
            return nil
        }
    }
}

// MARK: - Decodable row

nonisolated struct TVStreamingRelease: Decodable, Sendable, Identifiable {
    let tmdbId: Int
    let tmdbType: String
    let title: String
    let posterUrl: String?
    let posterPath: String?
    let sourceId: Int?
    let sourceName: String?
    let isOriginal: Bool?
    let sourceReleaseDate: String?

    var id: Int { tmdbId }
    var isTV: Bool { tmdbType == "tv" }

    enum CodingKeys: String, CodingKey {
        case tmdbId = "tmdb_id"
        case tmdbType = "tmdb_type"
        case title
        case posterUrl = "poster_url"
        case posterPath = "poster_path"
        case sourceId = "source_id"
        case sourceName = "source_name"
        case isOriginal = "is_original"
        case sourceReleaseDate = "source_release_date"
    }
}

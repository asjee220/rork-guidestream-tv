//
//  StreamingReleasesService.swift
//  GuideStreamTV
//
//  Read-only access to the public.streaming_releases table (refreshed daily by
//  the refresh_streaming_releases edge function). Feeds the Home "New This Week"
//  rail with titles that genuinely landed on a subscription streaming service in
//  the last seven days. The app never writes to this table.
//

import Foundation
import Supabase

@MainActor
@Observable
final class StreamingReleasesService {
    static let shared = StreamingReleasesService()

    private init() {}

    /// Fetches all streaming releases ordered by popularity (desc). Returns
    /// `nil` on failure so callers can leave the existing rail contents in place
    /// rather than clearing them. Never throws — mirrors how the other services
    /// in this folder swallow errors.
    func fetchReleases() async -> [StreamingRelease]? {
        do {
            let rows: [StreamingRelease] = try await SupabaseManager.shared.client
                .from("streaming_releases")
                .select()
                .order("popularity", ascending: false)
                .execute()
                .value
            return rows
        } catch {
            print("[StreamingReleases] fetch failed: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Decodable row for server reads

nonisolated struct StreamingRelease: Decodable, Sendable {
    let tmdbId: Int
    let tmdbType: String
    let title: String
    let posterUrl: String?
    let posterPath: String?
    let sourceName: String?
    let isOriginal: Bool?
    let sourceReleaseDate: String?
    let popularity: Double?
    let voteCount: Int?
    let voteAverage: Double?

    enum CodingKeys: String, CodingKey {
        case tmdbId = "tmdb_id"
        case tmdbType = "tmdb_type"
        case title
        case posterUrl = "poster_url"
        case posterPath = "poster_path"
        case sourceName = "source_name"
        case isOriginal = "is_original"
        case sourceReleaseDate = "source_release_date"
        case popularity
        case voteCount = "vote_count"
        case voteAverage = "vote_average"
    }
}

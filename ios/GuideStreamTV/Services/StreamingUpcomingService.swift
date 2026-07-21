//
//  StreamingUpcomingService.swift
//  GuideStreamTV
//
//  Read-only access to the public.streaming_upcoming table (refreshed daily at
//  04:00 UTC by the refresh_streaming_releases edge function on cron job 14).
//  Feeds the Reels "Coming Soon" tab with titles whose streaming release date
//  lands within the next thirty days. The server guarantees future dates and a
//  non-null poster on every row, so no client-side date or type filtering is
//  applied here. The app never writes to this table.
//

import Foundation
import Supabase

@MainActor
@Observable
final class StreamingUpcomingService {
    static let shared = StreamingUpcomingService()

    private init() {}

    /// Fetches all upcoming streaming releases ordered by source release date
    /// ascending so the soonest release appears first. Returns `nil` on failure
    /// so callers can leave the existing tab contents in place rather than
    /// clearing them. Never throws — mirrors how the other services in this
    /// folder swallow errors.
    func fetchUpcoming() async -> [StreamingUpcoming]? {
        do {
            let rows: [StreamingUpcoming] = try await SupabaseManager.shared.client
                .from("streaming_upcoming")
                .select()
                .order("source_release_date", ascending: true)
                .execute()
                .value
            return rows
        } catch {
            print("[StreamingUpcoming] fetch failed: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Decodable row for server reads

nonisolated struct StreamingUpcoming: Decodable, Sendable {
    let tmdbId: Int
    let tmdbType: String
    let watchmodeId: Int?
    let title: String
    let posterUrl: String?
    let posterPath: String?
    let sourceId: Int?
    let sourceName: String?
    let isOriginal: Bool?
    let sourceReleaseDate: String?
    let popularity: Double?
    let voteCount: Int?
    let voteAverage: Double?

    enum CodingKeys: String, CodingKey {
        case tmdbId = "tmdb_id"
        case tmdbType = "tmdb_type"
        case watchmodeId = "watchmode_id"
        case title
        case posterUrl = "poster_url"
        case posterPath = "poster_path"
        case sourceId = "source_id"
        case sourceName = "source_name"
        case isOriginal = "is_original"
        case sourceReleaseDate = "source_release_date"
        case popularity
        case voteCount = "vote_count"
        case voteAverage = "vote_average"
    }
}

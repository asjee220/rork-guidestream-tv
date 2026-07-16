//
//  ExpiringTitlesService.swift
//  GuideStreamTV
//
//  Read-only access to the public.expiring_titles table (refreshed daily by
//  the refresh_expiring_titles edge function). Feeds the Home "Leaving Soon"
//  rail with titles that are genuinely cycling off a streaming service soon.
//  The app never writes to this table.
//

import Foundation
import Supabase

@MainActor
@Observable
final class ExpiringTitlesService {
    static let shared = ExpiringTitlesService()

    private init() {}

    /// Fetches all expiring titles ordered by leaving date (soonest first).
    /// Returns `nil` on failure so callers can leave the existing rail contents
    /// in place rather than clearing them. Never throws — mirrors how the other
    /// services in this folder swallow errors.
    func fetchExpiring() async -> [ExpiringTitle]? {
        do {
            let rows: [ExpiringTitle] = try await SupabaseManager.shared.client
                .from("expiring_titles")
                .select()
                .order("leaving_date", ascending: true)
                .execute()
                .value
            return rows
        } catch {
            print("[ExpiringTitles] fetch failed: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Decodable row for server reads

nonisolated struct ExpiringTitle: Decodable, Sendable {
    let tmdbId: Int
    let tmdbType: String
    let title: String
    let posterUrl: String?
    let posterPath: String?
    let serviceName: String?
    let leavingDate: String?
    let isOriginal: Bool?
    let popularity: Double?
    let voteCount: Int?
    let voteAverage: Double?

    enum CodingKeys: String, CodingKey {
        case tmdbId = "tmdb_id"
        case tmdbType = "tmdb_type"
        case title
        case posterUrl = "poster_url"
        case posterPath = "poster_path"
        case serviceName = "service_name"
        case leavingDate = "leaving_date"
        case isOriginal = "is_original"
        case popularity
        case voteCount = "vote_count"
        case voteAverage = "vote_average"
    }
}

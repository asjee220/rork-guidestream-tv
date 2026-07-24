//
//  TVModels.swift
//  GuideStreamTVTV
//
//  Lightweight model shapes mirrored from the iOS app so the tvOS target
//  can decode the same Supabase/TMDB/ESPN responses without depending on
//  the iOS-specific source files. Keeping these standalone lets the tvOS
//  target compile in isolation while still hitting the same backend.
//

import Foundation

// MARK: - Watch list rows (Supabase `user_streams`)

nonisolated struct TVUserStream: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let userId: String
    let titleId: String
    let title: String?
    let posterUrl: String?
    let platform: String?
    let addedAt: Date?
    /// Mirrors the `is_tv` column on `public.user_streams`. Nullable — older
    /// rows and some edge-function writes omit it, so decoding must tolerate
    /// null (the optional handles both missing-key and null-value).
    let isTv: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case titleId = "title_id"
        case title
        case posterUrl = "poster_url"
        case platform
        case addedAt = "added_at"
        case isTv = "is_tv"
    }
}

nonisolated struct TVUserProfileNameRow: Decodable, Sendable {
    let display_name: String?
    let first_name: String?
    let last_name: String?
}

// MARK: - TMDB

nonisolated enum TVTMDBImageSize: String {
    case poster342 = "w342"
    case poster500 = "w500"
    case backdrop1280 = "w1280"
    case original = "original"
}

nonisolated enum TVTMDBImage {
    static let base = "https://image.tmdb.org/t/p/"
    static func url(_ path: String?, size: TVTMDBImageSize) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let clean = path.hasPrefix("/") ? path : "/\(path)"
        return base + size.rawValue + clean
    }
}

nonisolated struct TVTMDBResult: Identifiable, Hashable, Sendable, Decodable {
    let id: Int
    let mediaType: String?
    let name: String?
    let title: String?
    let posterPath: String?
    let backdropPath: String?
    let overview: String?
    let voteAverage: Double?
    let firstAirDate: String?
    let releaseDate: String?

    var displayName: String { name ?? title ?? "Untitled" }
    var isTV: Bool { (mediaType ?? "tv") == "tv" }
    var year: Int? {
        let date = firstAirDate ?? releaseDate
        guard let d = date, d.count >= 4 else { return nil }
        return Int(d.prefix(4))
    }
    var posterUrl: String? { TVTMDBImage.url(posterPath, size: .poster500) }
    var backdropUrl: String? { TVTMDBImage.url(backdropPath, size: .original) }
    /// Canonical title_id string we persist in `user_streams`. Includes the
    /// media type so a movie with the same TMDB id as a show doesn't collide.
    var canonicalTitleId: String {
        let kind = isTV ? "tv" : "movie"
        return "tmdb:\(kind):\(id)"
    }

    enum CodingKeys: String, CodingKey {
        case id, name, title, overview
        case mediaType = "media_type"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
        case firstAirDate = "first_air_date"
        case releaseDate = "release_date"
    }
}

nonisolated struct TVTMDBWatchProvider: Decodable, Sendable, Hashable {
    let providerId: Int
    let providerName: String
    let logoPath: String?
    let displayPriority: Int?

    enum CodingKeys: String, CodingKey {
        case providerId = "provider_id"
        case providerName = "provider_name"
        case logoPath = "logo_path"
        case displayPriority = "display_priority"
    }
}

// MARK: - Sports (ESPN)

struct TVSportsGame: Identifiable, Hashable {
    let id: String
    let sport: String
    let leagueShort: String
    let state: TVGameState
    let statusDetail: String
    let startDate: Date
    let home: TVGameTeam
    let away: TVGameTeam
    let broadcasts: [String]
}

enum TVGameState: String {
    case pre, live, post
    var isLive: Bool { self == .live }
}

struct TVGameTeam: Hashable {
    let abbreviation: String
    let displayName: String
    let shortName: String
    let score: String
    let primaryHex: String?
    let isWinner: Bool
}

// MARK: - Title recency (Supabase `title_recency`)

nonisolated struct TVTitleRecencyRow: Decodable, Sendable {
    let titleId: String
    let lastContentAt: Date?

    enum CodingKeys: String, CodingKey {
        case titleId = "title_id"
        case lastContentAt = "last_content_at"
    }
}

// MARK: - Content sources (Supabase `content_sources`)

/// Decodable row from the public-readable `content_sources` table. Used by
/// `TVContentSourcesService` to recommend creators/podcasts based on the
/// categories the user already follows.
nonisolated struct TVContentSource: Decodable, Sendable {
    let titleId: String
    let sourceType: String
    let displayName: String
    let imageUrl: String?
    let category: String?

    enum CodingKeys: String, CodingKey {
        case titleId = "title_id"
        case sourceType = "source_type"
        case displayName = "display_name"
        case imageUrl = "image_url"
        case category
    }
}

// MARK: - Type aliases for iOS-compatible naming

typealias SportsGame = TVSportsGame
typealias GameTeam = TVGameTeam
typealias GameState = TVGameState
typealias TMDBResult = TVTMDBResult
typealias UserStream = TVUserStream

// MARK: - Title ID parsing

/// Parses stored title identifiers into TMDB integer ids.
///
/// Mirrors `ios/GuideStreamTV/Models/TitleID.swift` for the tvOS target.
/// Duplicated deliberately per the project convention of copying shared
/// types into the tvOS target rather than sharing file membership, so the
/// tvOS target compiles in isolation.
enum TitleID {
    /// Returns the TMDB integer id encoded in `raw`, or `nil` when `raw` is
    /// nil/empty, not a TMDB identifier, or does not parse as an integer.
    /// Strips a leading `tmdb:tv:` or `tmdb:movie:` prefix case-insensitively
    /// before parsing. Identifiers for other content kinds (`yt:`, `tw:`,
    /// `pod:`, sports ids such as `tt-chw-phi-mlb`, etc.) return `nil` so they
    /// keep routing through their existing non-TMDB code paths.
    static func tmdbId(from raw: String?) -> Int? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let direct = Int(trimmed) { return direct }
        let lower = trimmed.lowercased()
        for prefix in ["tmdb:tv:", "tmdb:movie:"] {
            if lower.hasPrefix(prefix) {
                let remainder = String(trimmed.dropFirst(prefix.count))
                return Int(remainder.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return nil
    }
}

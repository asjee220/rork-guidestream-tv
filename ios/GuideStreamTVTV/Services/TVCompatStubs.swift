//
//  TVCompatStubs.swift
//  GuideStreamTVTV
//
//  Compatibility shims so views shared with the iOS target compile cleanly
//  on tvOS. The tvOS surface area is narrower (no Watchmode lookup, no
//  episode tracker, no streaming-app deeplinking) so these stubs return
//  empty/no-op results while preserving the iOS API signatures.
//

import Foundation
import SwiftUI

// MARK: - StreamsViewModel typealias

typealias StreamsViewModel = TVStreamsViewModel

// MARK: - NewEpisodeRow

/// Stub row shape mirrored from the iOS `EpisodeTrackerService`. The tvOS
/// target never populates `StreamsViewModel.newEpisodes`, so this only
/// needs the field surface area used by shared views.
struct NewEpisodeRow: Identifiable, Hashable {
    let id: String
    let titleId: String
    let title: String?
    let season: Int?
    let episode: Int?
    let platform: String?
    let posterUrl: String?
    let releasedAt: Date?
    let durationMinutes: Int?
    let isNew: Bool?
}

// MARK: - SocialViewModel stub

/// No-op social store. Likes and comments require the Supabase social
/// tables, which we don't wire up on tvOS — views read zero counts and
/// never display the "you liked this" state.
@MainActor
@Observable
final class SocialViewModel {
    static let shared = SocialViewModel()

    private(set) var likeCounts: [String: Int] = [:]
    private(set) var likedByMe: Set<String> = []
    private(set) var commentCounts: [String: Int] = [:]

    private init() {}

    func likes(_ titleId: String) -> Int { likeCounts[titleId] ?? 0 }
    func isLiked(_ titleId: String) -> Bool { likedByMe.contains(titleId) }
    func commentTotal(_ titleId: String) -> Int { commentCounts[titleId] ?? 0 }

    func refreshCounts(titleId: String) async {}
    func toggleLike(titleId: String) async {}

    static func initials(displayName: String?, firstName: String?, lastName: String?) -> String {
        if let first = firstName?.first, let last = lastName?.first {
            return "\(first)\(last)".uppercased()
        }
        if let name = displayName, !name.isEmpty {
            let parts = name.split(separator: " ").prefix(2)
            return parts.compactMap { $0.first }.map { String($0) }.joined().uppercased()
        }
        return "?"
    }
}

// MARK: - Watchmode stubs

/// Stub of the iOS `WatchmodeSource`. Real streaming-source lookups are
/// disabled on tvOS so this only exists to satisfy types in shared views.
nonisolated struct WatchmodeSource: Hashable, Sendable, Identifiable {
    let sourceId: Int
    let name: String
    let type: String
    let region: String?
    let iosUrl: String?
    let androidUrl: String?
    let webUrl: String?
    let format: String?
    let endDate: String?

    var id: String { "\(sourceId)-\(format ?? "")-\(region ?? "")" }
}

nonisolated struct WatchmodeTitleDetail: Sendable {
    let id: Int
    let title: String
    let plotOverview: String?
    let sources: [WatchmodeSource]?
}

/// No-op Watchmode service. Always returns nil so shared views fall back
/// to TMDB-provided overviews and the "Streaming services" placeholder.
nonisolated struct WatchmodeService {
    static let shared = WatchmodeService()

    func watchmodeId(forTMDBId tmdbId: Int, isTV: Bool) async throws -> Int? { nil }
    func titleDetail(titleId: Int) async throws -> WatchmodeTitleDetail {
        WatchmodeTitleDetail(id: titleId, title: "", plotOverview: nil, sources: nil)
    }
}

// MARK: - Streaming helpers

/// No-op deeplinker. tvOS apps can't open another device's streaming app,
/// so this is a quiet stub for shared sheets.
enum StreamingDeepLinker {
    static func open(platform: String, title: String, tmdbId: Int?, isTV: Bool) {}
}

/// Stub streaming-service catalog used by onboarding + the home services
/// pill. Provides a static list so shared views render without crashing.
struct StreamingService: Identifiable, Hashable {
    let id: String
    let name: String
    let color: Color
}

enum StreamingCatalog {
    static let all: [StreamingService] = [
        StreamingService(id: "netflix",     name: "Netflix",     color: Color(red: 0xE5/255, green: 0x09/255, blue: 0x14/255)),
        StreamingService(id: "max",         name: "Max",         color: Color(red: 0x5A/255, green: 0x1F/255, blue: 0xCB/255)),
        StreamingService(id: "appletv",     name: "Apple TV+",   color: Color(white: 0.10)),
        StreamingService(id: "hulu",        name: "Hulu",        color: Color(red: 0x1C/255, green: 0xE7/255, blue: 0x83/255)),
        StreamingService(id: "prime",       name: "Prime Video", color: Color(red: 0x00/255, green: 0xA8/255, blue: 0xE1/255)),
        StreamingService(id: "disney",      name: "Disney+",     color: Color(red: 0x11/255, green: 0x3C/255, blue: 0xCF/255)),
        StreamingService(id: "paramount",   name: "Paramount+",  color: Color(red: 0x00/255, green: 0x64/255, blue: 0xFF/255)),
        StreamingService(id: "peacock",     name: "Peacock",     color: .black),
        StreamingService(id: "starz",       name: "Starz",       color: .black),
        StreamingService(id: "showtime",    name: "Showtime",    color: Color(red: 0xD8/255, green: 0x00/255, blue: 0x00/255)),
        StreamingService(id: "crunchyroll", name: "Crunchyroll", color: Color(red: 0xF4/255, green: 0x7B/255, blue: 0x20/255)),
        StreamingService(id: "youtube",     name: "YouTube",     color: Color(red: 0xFF/255, green: 0x00/255, blue: 0x00/255))
    ]

    /// Returns the catalog filtered + ordered by `selectedIds`. Matches the
    /// iOS API so shared views compile.
    static func ordered(from selectedIds: Set<String>) -> [StreamingService] {
        all.filter { selectedIds.contains($0.id) }
    }
}

// MARK: - Service typealiases

typealias TMDBService = TVTMDBService
typealias SportsService = TVSportsService
typealias NewsService = TVNewsService

// MARK: - TMDBService stub extensions

/// Methods used by shared views that aren't part of the lean tvOS
/// `TVTMDBService` surface. They all fall back gracefully.
extension TVTMDBService {
    /// No-op for tvOS — returns an empty list so the "What's new today" rail
    /// is hidden when the data isn't available.
    func getNewToday() async throws -> [TVTMDBResult] { [] }

    /// Same fallback as `getOnTheAir()` so the "Binge worthy" rail still
    /// has something to render on tvOS.
    func getDiscoverEnded() async throws -> [TVTMDBResult] {
        try await getOnTheAir()
    }

    /// Show detail lookup not wired up on tvOS — shared views render with
    /// the data they already have.
    func getTVDetail(tmdbId: Int) async throws -> TMDBTVDetail? { nil }

    /// Season lookup stub — returns nil so episode rails just stay empty
    /// on tvOS.
    func getSeason(tmdbId: Int, seasonNumber: Int) async throws -> TMDBSeason? { nil }
}

// MARK: - Minimal TMDB detail / season stubs

/// Slim mirror of the iOS `TMDBTVDetail` — only the fields touched by
/// shared views need to exist for compilation.
nonisolated struct TMDBTVDetail: Sendable, Decodable {
    let id: Int
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let numberOfSeasons: Int?
    let firstAirDate: String?
    let voteAverage: Double?
    let status: String?
    let genres: [TMDBGenre]?
    let seasons: [TMDBSeasonSummary]?

    var displayName: String { name ?? "" }
    var posterUrl: String? { TVTMDBImage.url(posterPath, size: .poster500) }
    var backdropUrl: String? { TVTMDBImage.url(backdropPath, size: .original) }

    enum CodingKeys: String, CodingKey {
        case id, name, overview, status, genres, seasons
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case numberOfSeasons = "number_of_seasons"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
    }
}

nonisolated struct TMDBGenre: Sendable, Decodable, Hashable {
    let id: Int
    let name: String
}

nonisolated struct TMDBSeasonSummary: Sendable, Decodable, Hashable {
    let id: Int
    let name: String?
    let seasonNumber: Int?
    let episodeCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, name
        case seasonNumber = "season_number"
        case episodeCount = "episode_count"
    }
}

nonisolated struct TMDBSeason: Sendable, Decodable {
    let id: Int
    let name: String?
    let seasonNumber: Int?
    let episodes: [TMDBEpisode]?

    enum CodingKeys: String, CodingKey {
        case id, name, episodes
        case seasonNumber = "season_number"
    }
}

nonisolated struct TMDBEpisode: Sendable, Decodable, Hashable, Identifiable {
    let id: Int
    let name: String?
    let overview: String?
    let stillPath: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let airDate: String?
    let runtime: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, overview, runtime
        case stillPath = "still_path"
        case seasonNumber = "season_number"
        case episodeNumber = "episode_number"
        case airDate = "air_date"
    }
}

// MARK: - RemoteImage wrapper

/// iOS-named wrapper around `TVRemoteImage` that accepts the full iOS init
/// surface (`url:`, `urlString:`, optional `fallbackColors`). Shared views
/// pass `fallbackColors` for branded gradients — we use those as the
/// placeholder background on tvOS.
struct RemoteImage: View {
    private let url: URL?
    private let contentMode: ContentMode
    private let fallbackColors: [Color]

    init(url: URL?, contentMode: ContentMode = .fill, fallbackColors: [Color] = []) {
        self.url = url
        self.contentMode = contentMode
        self.fallbackColors = fallbackColors
    }

    init(urlString: String?, contentMode: ContentMode = .fill, fallbackColors: [Color] = []) {
        self.url = urlString.flatMap { URL(string: $0) }
        self.contentMode = contentMode
        self.fallbackColors = fallbackColors
    }

    var body: some View {
        ZStack {
            if !fallbackColors.isEmpty {
                LinearGradient(
                    colors: fallbackColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            TVRemoteImage(url: url, contentMode: contentMode)
        }
    }
}

// MARK: - Color extras

extension Color {
    static let textPrimary = Color.white
    static let newsGreen = Color(red: 0x00 / 255, green: 0x9E / 255, blue: 0x8A / 255)
}

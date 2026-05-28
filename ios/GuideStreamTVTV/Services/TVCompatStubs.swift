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

// MARK: - WatchListView typealias

/// The shared `ProfileView` references `WatchListView()` to push the user's
/// saved titles screen. tvOS has its own native implementation under
/// `TVWatchListView`, so we bridge the iOS name to it.
typealias WatchListView = TVWatchListView

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

/// Slim mirror of the iOS `TitleComment` row. Powered by Supabase on iOS
/// but the tvOS target intentionally short-circuits the social tier so all
/// methods return empty data. Marked `nonisolated` so it is usable across
/// every actor context (mirrors the iOS `TitleComment` declaration).
nonisolated struct TitleComment: Identifiable, Hashable, Sendable {
    let id: String
    let titleId: String
    let userId: String?
    let deviceId: String?
    let displayName: String?
    let initials: String?
    let body: String
    let createdAt: Date?
}

/// No-op social store. Likes and comments require the Supabase social
/// tables, which we don't wire up on tvOS — views read zero counts and
/// never display the "you liked this" state. The mutable fields exposed
/// here mirror the iOS API surface so shared views compile cleanly.
@MainActor
@Observable
final class SocialViewModel {
    static let shared = SocialViewModel()

    private(set) var likeCounts: [String: Int] = [:]
    private(set) var likedByMe: Set<String> = []
    private(set) var commentCounts: [String: Int] = [:]
    private(set) var commentThreads: [String: [TitleComment]] = [:]
    var loadingComments: Set<String> = []
    var postingComment: Set<String> = []

    private init() {}

    func likes(_ titleId: String) -> Int { likeCounts[titleId] ?? 0 }
    func isLiked(_ titleId: String) -> Bool { likedByMe.contains(titleId) }
    func commentTotal(_ titleId: String) -> Int { commentCounts[titleId] ?? 0 }
    func thread(_ titleId: String) -> [TitleComment] { commentThreads[titleId] ?? [] }

    /// True while the comment thread for `titleId` is being fetched. Method
    /// wrapper around `loadingComments` so views can read the state without
    /// directly touching the `@Observable`-synthesized stored property
    /// (which trips up Swift's key-path resolution in some build contexts).
    func isLoadingComments(_ titleId: String) -> Bool {
        loadingComments.contains(titleId)
    }

    /// True while a comment post for `titleId` is in flight.
    func isPostingComment(_ titleId: String) -> Bool {
        postingComment.contains(titleId)
    }

    func refreshCounts(titleId: String) async {}
    func toggleLike(titleId: String) async {}
    func loadComments(titleId: String) async {}
    func postComment(titleId: String, body: String) async -> Bool { false }

    static func initials(firstName: String?, lastName: String?, displayName: String?) -> String {
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
    let id: String
    let title: String
    let plotOverview: String?
    let sources: [WatchmodeSource]?
    let genreNames: [String]
    let userRating: Double?
    let year: Int?

    init(
        id: String,
        title: String,
        plotOverview: String? = nil,
        sources: [WatchmodeSource]? = nil,
        genreNames: [String] = [],
        userRating: Double? = nil,
        year: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.plotOverview = plotOverview
        self.sources = sources
        self.genreNames = genreNames
        self.userRating = userRating
        self.year = year
    }
}

/// No-op Watchmode service. Always returns nil so shared views fall back
/// to TMDB-provided overviews and the "Streaming services" placeholder.
nonisolated struct WatchmodeService {
    static let shared = WatchmodeService()

    func watchmodeId(forTMDBId tmdbId: Int, isTV: Bool) async throws -> String? { nil }
    func titleDetail(titleId: String) async throws -> WatchmodeTitleDetail {
        WatchmodeTitleDetail(id: titleId, title: "")
    }
}

// MARK: - Streaming helpers

/// No-op deeplinker. tvOS apps can't open another device's streaming app,
/// so this is a quiet stub for shared sheets. Overloads cover every call
/// shape the iOS source uses (`platform/title`, plus optional `tmdbId`,
/// `isTV`, and/or `titleSlug`).
enum StreamingDeepLinker {
    static func open(platform: String, title: String, tmdbId: Int?, isTV: Bool) {}
    static func open(platform: String, title: String, tmdbId: Int?, isTV: Bool, titleSlug: String) {}
    static func open(platform: String, title: String, titleSlug: String) {}
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
    var genreNames: [String] { (genres ?? []).map { $0.name } }
    var year: Int? {
        guard let firstAirDate, firstAirDate.count >= 4 else { return nil }
        return Int(firstAirDate.prefix(4))
    }

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
    let episodeNumber: Int
    let airDate: String?
    let runtime: Int?

    /// Full TMDB still image URL, or nil if no still path. Mirrors the iOS
    /// `TMDBEpisode.stillUrl` convenience used by ShowDetailScreen cards.
    var stillUrl: String? { TVTMDBImage.url(stillPath, size: .original) }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int.self, forKey: .id)
        self.name = try c.decodeIfPresent(String.self, forKey: .name)
        self.overview = try c.decodeIfPresent(String.self, forKey: .overview)
        self.stillPath = try c.decodeIfPresent(String.self, forKey: .stillPath)
        self.seasonNumber = try c.decodeIfPresent(Int.self, forKey: .seasonNumber)
        self.episodeNumber = (try c.decodeIfPresent(Int.self, forKey: .episodeNumber)) ?? 0
        self.airDate = try c.decodeIfPresent(String.self, forKey: .airDate)
        self.runtime = try c.decodeIfPresent(Int.self, forKey: .runtime)
    }

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

// MARK: - Glass card modifier

extension View {
    /// Same glassy rounded-rectangle background the iOS app uses. Mirrors
    /// the iOS `.glassCard()` helper so shared views compile cleanly on
    /// tvOS without having to know which platform they're running on.
    func glassCard(cornerRadius: CGFloat = 18) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .clipShape(.rect(cornerRadius: cornerRadius))
    }
}

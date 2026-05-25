//
//  TMDBService.swift
//  GuideStreamTV
//

import Foundation

// MARK: - Image Helpers

nonisolated enum TMDBImageSize: String {
    case poster342 = "w342"
    case poster500 = "w500"
    case backdrop1280 = "w1280"
    case still300 = "w300"
    case thumb185 = "w185"
}

nonisolated enum TMDBImage {
    static let base = "https://image.tmdb.org/t/p/"
    static func url(_ path: String?, size: TMDBImageSize) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let clean = path.hasPrefix("/") ? path : "/\(path)"
        return base + size.rawValue + clean
    }
}

// MARK: - Models

nonisolated struct TMDBResult: Identifiable, Hashable, Sendable, Decodable {
    let id: Int
    let mediaType: String?       // "tv" or "movie" (multi-search); nil for trending tv
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
    var posterUrl: String? { TMDBImage.url(posterPath, size: .poster342) }
    var backdropUrl: String? { TMDBImage.url(backdropPath, size: .backdrop1280) }

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

nonisolated struct TMDBGenre: Decodable, Hashable, Sendable {
    let id: Int
    let name: String
}

nonisolated struct TMDBNetwork: Decodable, Hashable, Sendable {
    let id: Int
    let name: String
    let logoPath: String?
    enum CodingKeys: String, CodingKey {
        case id, name
        case logoPath = "logo_path"
    }
}

nonisolated struct TMDBTVDetail: Decodable, Sendable {
    let id: Int
    let name: String
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let genres: [TMDBGenre]?
    let numberOfSeasons: Int?
    let episodeRunTime: [Int]?
    let status: String?
    let networks: [TMDBNetwork]?
    let firstAirDate: String?

    var posterUrl: String? { TMDBImage.url(posterPath, size: .poster500) }
    var backdropUrl: String? { TMDBImage.url(backdropPath, size: .backdrop1280) }
    var year: Int? {
        guard let d = firstAirDate, d.count >= 4 else { return nil }
        return Int(d.prefix(4))
    }
    var genreNames: [String] { genres?.map { $0.name } ?? [] }
    var runtimeMinutes: Int? { episodeRunTime?.first }

    enum CodingKeys: String, CodingKey {
        case id, name, overview, genres, status, networks
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
        case numberOfSeasons = "number_of_seasons"
        case episodeRunTime = "episode_run_time"
        case firstAirDate = "first_air_date"
    }
}

nonisolated struct TMDBEpisode: Decodable, Hashable, Sendable, Identifiable {
    let id: Int
    let episodeNumber: Int
    let seasonNumber: Int?
    let name: String?
    let overview: String?
    let stillPath: String?
    let airDate: String?
    let runtime: Int?

    var stillUrl: String? { TMDBImage.url(stillPath, size: .still300) }

    enum CodingKeys: String, CodingKey {
        case id, name, overview, runtime
        case episodeNumber = "episode_number"
        case seasonNumber = "season_number"
        case stillPath = "still_path"
        case airDate = "air_date"
    }
}

nonisolated struct TMDBSeason: Decodable, Sendable {
    let id: Int
    let name: String?
    let seasonNumber: Int?
    let episodes: [TMDBEpisode]

    enum CodingKeys: String, CodingKey {
        case id, name, episodes
        case seasonNumber = "season_number"
    }
}

private nonisolated struct TMDBSearchEnvelope: Decodable, Sendable {
    let results: [TMDBResult]
}

private nonisolated struct TMDBTrendingEnvelope: Decodable, Sendable {
    let results: [TMDBResult]
}

nonisolated struct TMDBVideo: Decodable, Sendable {
    let key: String
    let name: String?
    let site: String?
    let type: String?
}

private nonisolated struct TMDBVideosEnvelope: Decodable, Sendable {
    let results: [TMDBVideo]
}

// MARK: - Watch Providers

nonisolated struct TMDBWatchProvider: Decodable, Sendable, Hashable {
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

private nonisolated struct TMDBProviderRegion: Decodable, Sendable {
    let flatrate: [TMDBWatchProvider]?
    let ads: [TMDBWatchProvider]?
    let free: [TMDBWatchProvider]?
    let buy: [TMDBWatchProvider]?
    let rent: [TMDBWatchProvider]?
}

private nonisolated struct TMDBProvidersEnvelope: Decodable, Sendable {
    let results: [String: TMDBProviderRegion]
}

// MARK: - Service

nonisolated struct TMDBService {
    static let shared = TMDBService()

    private let apiKey = "233f8054219ef58bc928549b4b5bab50"
    private let base = "https://api.themoviedb.org/3"

    func searchContent(query: String) async throws -> [TMDBResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return [] }

        let urlString = "\(base)/search/multi?query=\(encoded)&api_key=\(apiKey)&language=en-US&page=1&include_adult=false"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TMDBSearchEnvelope.self, from: data)
        return env.results.filter { ($0.mediaType ?? "") == "tv" || ($0.mediaType ?? "") == "movie" }
    }

    func getTVDetail(tmdbId: Int) async throws -> TMDBTVDetail {
        let urlString = "\(base)/tv/\(tmdbId)?api_key=\(apiKey)&language=en-US"
        let data = try await get(urlString)
        return try JSONDecoder().decode(TMDBTVDetail.self, from: data)
    }

    func getSeason(tmdbId: Int, seasonNumber: Int) async throws -> TMDBSeason {
        let urlString = "\(base)/tv/\(tmdbId)/season/\(seasonNumber)?api_key=\(apiKey)&language=en-US"
        let data = try await get(urlString)
        return try JSONDecoder().decode(TMDBSeason.self, from: data)
    }

    func getEpisode(tmdbId: Int, season: Int, episode: Int) async throws -> TMDBEpisode {
        let urlString = "\(base)/tv/\(tmdbId)/season/\(season)/episode/\(episode)?api_key=\(apiKey)&language=en-US"
        let data = try await get(urlString)
        return try JSONDecoder().decode(TMDBEpisode.self, from: data)
    }

    /// Currently-airing TV shows (used as the "New Episodes" fallback when Supabase is empty).
    func getOnTheAir() async throws -> [TMDBResult] {
        let urlString = "\(base)/tv/on_the_air?api_key=\(apiKey)&language=en-US&page=1"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TMDBTrendingEnvelope.self, from: data)
        return env.results.map { stamp($0, mediaType: "tv") }
    }

    /// Popular ended TV shows for the "Binge Ready" fallback.
    func getDiscoverEnded() async throws -> [TMDBResult] {
        let urlString = "\(base)/discover/tv?api_key=\(apiKey)&language=en-US&sort_by=popularity.desc&with_status=Ended&page=1"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TMDBTrendingEnvelope.self, from: data)
        return env.results.map { stamp($0, mediaType: "tv") }
    }

    /// Popular TV shows for a single TMDB genre id (Drama 18, Crime 80, Comedy 35, Sci-Fi 10765, Documentary 99, Reality 10764).
    func getDiscoverByGenre(_ genreId: Int) async throws -> [TMDBResult] {
        let urlString = "\(base)/discover/tv?api_key=\(apiKey)&language=en-US&sort_by=popularity.desc&with_genres=\(genreId)&page=1"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TMDBTrendingEnvelope.self, from: data)
        return env.results.map { stamp($0, mediaType: "tv") }
    }

    /// Returns the top US streaming provider for a title (prefers subscription/flatrate,
    /// then ad-supported, then free). Returns `nil` if no real streaming service is
    /// associated with the title — caller should hide the item rather than show a fake label.
    func getTopWatchProvider(tmdbId: Int, isTV: Bool) async throws -> TMDBWatchProvider? {
        let kind = isTV ? "tv" : "movie"
        let urlString = "\(base)/\(kind)/\(tmdbId)/watch/providers?api_key=\(apiKey)"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TMDBProvidersEnvelope.self, from: data)
        guard let us = env.results["US"] else { return nil }
        // Prefer subscription, then ad-supported, then free. Skip buy/rent — those
        // aren't "available to stream" in the sense users expect.
        let pool = (us.flatrate ?? []) + (us.ads ?? []) + (us.free ?? [])
        guard !pool.isEmpty else { return nil }
        return pool.min(by: { ($0.displayPriority ?? 999) < ($1.displayPriority ?? 999) })
    }

    /// Trailers / teasers attached to a TV show. Returns a YouTube key for the best match, or nil.
    func getTrailerKey(tmdbId: Int) async throws -> String? {
        let urlString = "\(base)/tv/\(tmdbId)/videos?api_key=\(apiKey)&language=en-US"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TMDBVideosEnvelope.self, from: data)
        let yt = env.results.filter { $0.site == "YouTube" && ($0.type == "Trailer" || $0.type == "Teaser") }
        return yt.first?.key ?? env.results.first?.key
    }

    private func stamp(_ r: TMDBResult, mediaType: String) -> TMDBResult {
        TMDBResult(
            id: r.id,
            mediaType: r.mediaType ?? mediaType,
            name: r.name,
            title: r.title,
            posterPath: r.posterPath,
            backdropPath: r.backdropPath,
            overview: r.overview,
            voteAverage: r.voteAverage,
            firstAirDate: r.firstAirDate,
            releaseDate: r.releaseDate
        )
    }

    func getTrending() async throws -> [TMDBResult] {
        let urlString = "\(base)/trending/tv/week?api_key=\(apiKey)&language=en-US"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TMDBTrendingEnvelope.self, from: data)
        // Trending endpoint doesn't always include media_type; default to tv.
        return env.results.map { r in
            TMDBResult(
                id: r.id,
                mediaType: r.mediaType ?? "tv",
                name: r.name,
                title: r.title,
                posterPath: r.posterPath,
                backdropPath: r.backdropPath,
                overview: r.overview,
                voteAverage: r.voteAverage,
                firstAirDate: r.firstAirDate,
                releaseDate: r.releaseDate
            )
        }
    }

    private func get(_ urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

// MARK: - Watchmode lookup by TMDB id

nonisolated extension WatchmodeService {
    /// Finds a Watchmode title id from a TMDB id. Watchmode supports `search_field=tmdb_id`.
    func watchmodeId(forTMDBId tmdbId: Int, isTV: Bool) async throws -> String? {
        let urlString = "https://api.watchmode.com/v1/search/?apiKey=wqlepJq2xhEfyAVWpMOhVGmoUKBJFzHj3mlE3Lcw&search_field=tmdb_id&search_value=\(tmdbId)"
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        let env = try JSONDecoder().decode(WatchmodeSearchEnvelope.self, from: data)
        let preferred = env.titleResults.first { isTV ? $0.type.contains("tv") : $0.type.contains("movie") }
        let chosen = preferred ?? env.titleResults.first
        return chosen.map { String($0.id) }
    }
}

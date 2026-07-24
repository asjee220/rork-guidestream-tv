//
//  TVTMDBService.swift
//  GuideStreamTVTV
//
//  Read-only TMDB client used by the tvOS Home. We only need a handful
//  of endpoints (trending, on-the-air, top provider lookup) so this
//  service is intentionally a leaner subset of the phone app's full TMDB
//  surface.
//

import Foundation

private nonisolated struct TVTMDBSearchEnvelope: Decodable, Sendable {
    let results: [TVTMDBResult]
}

private nonisolated struct TVTMDBProviderRegion: Decodable, Sendable {
    let flatrate: [TVTMDBWatchProvider]?
    let ads: [TVTMDBWatchProvider]?
    let free: [TVTMDBWatchProvider]?
}

private nonisolated struct TVTMDBProvidersEnvelope: Decodable, Sendable {
    let results: [String: TVTMDBProviderRegion]
}

private nonisolated struct TVTMDBVideo: Decodable, Sendable {
    let key: String?
    let site: String?
    let type: String?
    let official: Bool?
}

private nonisolated struct TVTMDBVideosEnvelope: Decodable, Sendable {
    let results: [TVTMDBVideo]
}

private nonisolated struct TVTMDBGenre: Decodable, Sendable {
    let name: String
}

private nonisolated struct TVTMDBTVDetailEnvelope: Decodable, Sendable {
    let genres: [TVTMDBGenre]?
}

private nonisolated struct TVTMDBFreshness: Decodable, Sendable {
    let posterPath: String?
    let lastEpisodeToAir: TVTMDBFreshnessEpisode?
}

private nonisolated struct TVTMDBFreshnessEpisode: Decodable, Sendable {
    let seasonNumber: Int?
    let episodeNumber: Int?

    enum CodingKeys: String, CodingKey {
        case seasonNumber = "season_number"
        case episodeNumber = "episode_number"
    }
}

private nonisolated struct TVTMDBMoviePoster: Decodable, Sendable {
    let posterPath: String?

    enum CodingKeys: String, CodingKey {
        case posterPath = "poster_path"
    }
}

nonisolated struct TVTMDBService {
    static let shared = TVTMDBService()

    private let apiKey = "233f8054219ef58bc928549b4b5bab50"
    private let base = "https://api.themoviedb.org/3"

    /// Mixed trending feed (TV + movies) for the hero carousel + rail.
    func getTrending() async throws -> [TVTMDBResult] {
        let urlString = "\(base)/trending/all/week?api_key=\(apiKey)&language=en-US"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TVTMDBSearchEnvelope.self, from: data)
        return env.results
            .filter { ($0.mediaType ?? "") == "tv" || ($0.mediaType ?? "") == "movie" }
            .map { stamp($0, mediaType: $0.mediaType ?? "tv") }
    }

    /// Currently-airing TV — used for the "New Episodes" rail.
    func getOnTheAir() async throws -> [TVTMDBResult] {
        let urlString = "\(base)/tv/on_the_air?api_key=\(apiKey)&language=en-US&page=1"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TVTMDBSearchEnvelope.self, from: data)
        return env.results.map { stamp($0, mediaType: "tv") }
    }

    /// Returns the first genre name for a TV show, or nil.
    func getTVGenre(tmdbId: Int) async throws -> String? {
        let urlString = "\(base)/tv/\(tmdbId)?api_key=\(apiKey)&language=en-US"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TVTMDBTVDetailEnvelope.self, from: data)
        return env.genres?.first?.name
    }

    /// Popular TV — used as a secondary feed source for For You.
    func getPopularTV() async throws -> [TVTMDBResult] {
        let urlString = "\(base)/tv/popular?api_key=\(apiKey)&language=en-US&page=1"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TVTMDBSearchEnvelope.self, from: data)
        return env.results.map { stamp($0, mediaType: "tv") }
    }

    /// Returns the YouTube key of the best available trailer for a title, or
    /// nil if none exists. Prefers official trailers, then any trailer, then
    /// any teaser/clip so we still surface motion art when possible.
    func getTrailerKey(tmdbId: Int, isTV: Bool) async throws -> String? {
        let kind = isTV ? "tv" : "movie"
        let urlString = "\(base)/\(kind)/\(tmdbId)/videos?api_key=\(apiKey)&language=en-US"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TVTMDBVideosEnvelope.self, from: data)
        let youtube = env.results.filter { ($0.site ?? "").lowercased() == "youtube" && !($0.key ?? "").isEmpty }
        if let official = youtube.first(where: { ($0.type ?? "") == "Trailer" && ($0.official ?? false) }) {
            return official.key
        }
        if let trailer = youtube.first(where: { ($0.type ?? "") == "Trailer" }) {
            return trailer.key
        }
        if let teaser = youtube.first(where: { ($0.type ?? "") == "Teaser" }) {
            return teaser.key
        }
        return youtube.first?.key
    }

    /// Returns the top US streaming provider for a title, or nil if no
    /// real streaming service is associated with it.
    func getTopWatchProvider(tmdbId: Int, isTV: Bool) async throws -> TVTMDBWatchProvider? {
        let kind = isTV ? "tv" : "movie"
        let urlString = "\(base)/\(kind)/\(tmdbId)/watch/providers?api_key=\(apiKey)"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TVTMDBProvidersEnvelope.self, from: data)
        guard let us = env.results["US"] else { return nil }
        let pool = (us.flatrate ?? []) + (us.ads ?? []) + (us.free ?? [])
        guard !pool.isEmpty else { return nil }
        return pool.min(by: { ($0.displayPriority ?? 999) < ($1.displayPriority ?? 999) })
    }

    /// Fetches a fresh poster path and the latest aired episode for a TV
    /// title. Returns nil poster/season/episode on any error so callers
    /// can fall back to the stored snapshot. Used by the watch-list poster
    /// back-fill and the season/episode pre-selection in TVTitleSheet.
    func getTVFreshness(tmdbId: Int) async -> (posterPath: String?, latestSeason: Int?, latestEpisode: Int?) {
        let urlString = "\(base)/tv/\(tmdbId)?api_key=\(apiKey)&language=en-US"
        guard let data = try? await get(urlString) else { return (nil, nil, nil) }
        guard let env = try? JSONDecoder().decode(TVTMDBFreshness.self, from: data) else { return (nil, nil, nil) }
        return (env.posterPath, env.lastEpisodeToAir?.seasonNumber, env.lastEpisodeToAir?.episodeNumber)
    }

    /// Fetches a fresh poster path for a movie title. Returns nil on any
    /// error so callers can fall back to the stored snapshot.
    func getMoviePosterPath(tmdbId: Int) async -> String? {
        let urlString = "\(base)/movie/\(tmdbId)?api_key=\(apiKey)&language=en-US"
        guard let data = try? await get(urlString) else { return nil }
        guard let env = try? JSONDecoder().decode(TVTMDBMoviePoster.self, from: data) else { return nil }
        return env.posterPath
    }

    private func stamp(_ r: TVTMDBResult, mediaType: String) -> TVTMDBResult {
        TVTMDBResult(
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

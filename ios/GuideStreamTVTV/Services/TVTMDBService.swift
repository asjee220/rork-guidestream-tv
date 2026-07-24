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

private nonisolated struct TVTMDBReleaseDateEntry: Decodable, Sendable {
    let releaseDate: String?
    let type: Int?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case releaseDate = "release_date"
        case type
        case note
    }
}

private nonisolated struct TVTMDBReleaseDateCountry: Decodable, Sendable {
    let iso31661: String
    let releaseDates: [TVTMDBReleaseDateEntry]?

    enum CodingKeys: String, CodingKey {
        case iso31661 = "iso_3166_1"
        case releaseDates = "release_dates"
    }
}

private nonisolated struct TVTMDBReleaseDatesEnvelope: Decodable, Sendable {
    let results: [TVTMDBReleaseDateCountry]
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

    /// Now-playing movies in the US — mirrors the iOS `getNowPlayingMovies`.
    func getNowPlayingMovies() async -> [TVTMDBResult] {
        let urlString = "\(base)/movie/now_playing?api_key=\(apiKey)&language=en-US&region=US&page=1"
        guard let data = try? await get(urlString) else { return [] }
        guard let env = try? JSONDecoder().decode(TVTMDBSearchEnvelope.self, from: data) else { return [] }
        return env.results.map { stamp($0, mediaType: "movie") }
    }

    /// Returns the earliest future US digital release date (type == 4) for a
    /// movie, or nil when none exists. Mirrors the iOS `getUSDigitalReleaseDate`.
    func getUSDigitalReleaseDate(movieId: Int) async -> (date: Date, note: String?)? {
        let urlString = "\(base)/movie/\(movieId)/release_dates?api_key=\(apiKey)"
        guard let data = try? await get(urlString) else { return nil }
        guard let env = try? JSONDecoder().decode(TVTMDBReleaseDatesEnvelope.self, from: data) else { return nil }
        guard let us = env.results.first(where: { $0.iso31661 == "US" }) else { return nil }
        let digital = (us.releaseDates ?? []).filter { $0.type == 4 }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = DateFormatter()
        fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        fallbackFormatter.locale = Locale(identifier: "en_US_POSIX")
        fallbackFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        let now = Date()
        var best: (date: Date, note: String?)? = nil
        for entry in digital {
            guard let raw = entry.releaseDate else { continue }
            let parsed = isoFormatter.date(from: raw) ?? fallbackFormatter.date(from: raw)
            guard let date = parsed, date > now else { continue }
            if best == nil || date < best!.date {
                best = (date, entry.note)
            }
        }
        return best
    }

    /// Popular TV shows on a specific Watchmode provider — mirrors the iOS
    /// `getPopularOnService`. Returns [] on any error so the rail hides.
    func getPopularOnService(tmdbProviderId: Int) async -> [TVTMDBResult] {
        let urlString = "\(base)/discover/tv?api_key=\(apiKey)&language=en-US&sort_by=popularity.desc&watch_region=US&with_watch_providers=\(tmdbProviderId)&with_watch_monetization_types=flatrate%7Cads&page=1"
        guard let data = try? await get(urlString) else { return [] }
        guard let env = try? JSONDecoder().decode(TVTMDBSearchEnvelope.self, from: data) else { return [] }
        return env.results.map { stamp($0, mediaType: "tv") }
    }

    /// Popular movies on a specific Watchmode provider — mirrors the iOS
    /// `getPopularMoviesOnService`. Returns [] on any error so the rail hides.
    func getPopularMoviesOnService(tmdbProviderId: Int) async -> [TVTMDBResult] {
        let urlString = "\(base)/discover/movie?api_key=\(apiKey)&language=en-US&sort_by=popularity.desc&watch_region=US&with_watch_providers=\(tmdbProviderId)&page=1"
        guard let data = try? await get(urlString) else { return [] }
        guard let env = try? JSONDecoder().decode(TVTMDBSearchEnvelope.self, from: data) else { return [] }
        return env.results.map { stamp($0, mediaType: "movie") }
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

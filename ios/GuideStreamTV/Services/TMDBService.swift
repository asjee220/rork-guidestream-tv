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

/// Compact episode summary returned inline on `/tv/{id}` via the
/// `last_episode_to_air` / `next_episode_to_air` fields. Lets the
/// `EpisodeTrackerService` figure out the latest aired episode without a
/// second round-trip to `/tv/{id}/season/{n}`.
nonisolated struct TMDBEpisodeSummary: Decodable, Sendable, Hashable {
    let id: Int
    let name: String?
    let overview: String?
    let airDate: String?
    let episodeNumber: Int?
    let seasonNumber: Int?
    let runtime: Int?
    let stillPath: String?

    var stillUrl: String? { TMDBImage.url(stillPath, size: .still300) }

    enum CodingKeys: String, CodingKey {
        case id, name, overview, runtime
        case airDate = "air_date"
        case episodeNumber = "episode_number"
        case seasonNumber = "season_number"
        case stillPath = "still_path"
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
    /// The most recently aired episode (or the current week's, when the
    /// show is in mid-season). Used by the new-episode tracker.
    let lastEpisodeToAir: TMDBEpisodeSummary?
    /// The next scheduled episode, when TMDB has one queued. Useful for
    /// "premieres tomorrow" cards.
    let nextEpisodeToAir: TMDBEpisodeSummary?

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
        case lastEpisodeToAir = "last_episode_to_air"
        case nextEpisodeToAir = "next_episode_to_air"
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

// MARK: - Release Dates

nonisolated struct TMDBReleaseDatesEnvelope: Decodable, Sendable {
    let id: Int
    let results: [TMDBReleaseDateCountry]
}

nonisolated struct TMDBReleaseDateCountry: Decodable, Sendable {
    let iso31661: String
    let releaseDates: [TMDBReleaseDateEntry]

    enum CodingKeys: String, CodingKey {
        case iso31661 = "iso_3166_1"
        case releaseDates = "release_dates"
    }
}

nonisolated struct TMDBReleaseDateEntry: Decodable, Sendable {
    let releaseDate: String?
    let type: Int?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case releaseDate = "release_date"
        case type
        case note
    }
}

nonisolated struct TMDBVideo: Decodable, Sendable {
    let key: String
    let name: String?
    let site: String?
    let type: String?
    let publishedAt: String?
    let official: Bool?

    enum CodingKeys: String, CodingKey {
        case key, name, site, type, official
        case publishedAt = "published_at"
    }
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

    /// Wraps `searchContent` so SearchView callers can use the shorter name.
    func search(query: String) async throws -> [TMDBResult] {
        try await searchContent(query: query)
    }

    func searchContent(query: String) async throws -> [TMDBResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return [] }

        let locale = DeviceLocale.current()
        let urlString = "\(base)/search/multi?query=\(encoded)&api_key=\(apiKey)&language=\(locale.tmdbLanguage)&region=\(locale.region)&page=1&include_adult=false"
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

    /// Movies currently in theaters (US).
    func getNowPlayingMovies() async throws -> [TMDBResult] {
        let urlString = "\(base)/movie/now_playing?api_key=\(apiKey)&language=en-US&region=US&page=1"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TMDBTrendingEnvelope.self, from: data)
        return env.results.map { stamp($0, mediaType: "movie") }
    }

    /// Returns the earliest future US digital release date (type 4) for a movie,
    /// along with its note (e.g. "Netflix"). Returns nil when no future digital
    /// release is scheduled.
    func getUSDigitalReleaseDate(movieId: Int) async throws -> (date: Date, note: String?)? {
        let urlString = "\(base)/movie/\(movieId)/release_dates?api_key=\(apiKey)"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TMDBReleaseDatesEnvelope.self, from: data)
        guard let us = env.results.first(where: { $0.iso31661 == "US" }) else { return nil }

        let now = Date()
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFmt: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
            return f
        }()

        func parseDate(_ raw: String) -> Date? {
            isoFmt.date(from: raw) ?? fallbackFmt.date(from: raw)
        }

        let digitalEntries = us.releaseDates.filter { $0.type == 4 }
        let futureEntries = digitalEntries.compactMap { entry -> (date: Date, note: String?)? in
            guard let raw = entry.releaseDate, let date = parseDate(raw), date > now else { return nil }
            return (date, entry.note)
        }

        // Earliest future digital release wins
        return futureEntries.min(by: { $0.date < $1.date })
    }

    /// Popular TV shows trending globally.
    func getPopularTV() async throws -> [TMDBResult] {
        let urlString = "\(base)/tv/popular?api_key=\(apiKey)&language=en-US&page=1"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TMDBTrendingEnvelope.self, from: data)
        return env.results.map { stamp($0, mediaType: "tv") }
    }

    /// Upcoming movies with known release dates, sorted by popularity.
    func getUpcomingMovies() async throws -> [TMDBResult] {
        let urlString = "\(base)/movie/upcoming?api_key=\(apiKey)&language=en-US&page=1"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TMDBTrendingEnvelope.self, from: data)
        return env.results.map { stamp($0, mediaType: "movie") }
    }

    /// Popular ended TV shows for the "Binge Ready" fallback.
    func getDiscoverEnded() async throws -> [TMDBResult] {
        let urlString = "\(base)/discover/tv?api_key=\(apiKey)&language=en-US&sort_by=popularity.desc&with_status=Ended&page=1"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TMDBTrendingEnvelope.self, from: data)
        return env.results.map { stamp($0, mediaType: "tv") }
    }

    /// Popular shows for a single TMDB genre id. Defaults to TV; pass "movie" for movie-only genres like Romance (10749).
    func getDiscoverByGenre(_ genreId: Int, mediaType: String = "tv") async throws -> [TMDBResult] {
        let urlString = "\(base)/discover/\(mediaType)?api_key=\(apiKey)&language=en-US&sort_by=popularity.desc&with_genres=\(genreId)&page=1"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TMDBTrendingEnvelope.self, from: data)
        return env.results.map { stamp($0, mediaType: mediaType) }
    }

    /// International / foreign-language TV — surfaces popular non-English shows across
    /// major language markets so the "International" genre tile has real content.
    func getDiscoverInternational() async throws -> [TMDBResult] {
        let languages = "ko|ja|fr|de|es|it|pt|hi|ar|tr|sv|no|da|fi|nl|pl|th|zh"
        let urlString = "\(base)/discover/tv?api_key=\(apiKey)&language=en-US&sort_by=popularity.desc&with_original_language=\(languages)&page=1"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TMDBTrendingEnvelope.self, from: data)
        return env.results.map { stamp($0, mediaType: "tv") }
    }

    func discoverByProvider(providerId: Int, limit: Int = 15) async throws -> [TMDBResult] {
        let urlString = "\(base)/discover/tv?api_key=\(apiKey)&language=en-US&sort_by=popularity.desc&watch_region=US&with_watch_providers=\(providerId)&with_type=0&page=1"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TMDBTrendingEnvelope.self, from: data)
        return Array(env.results.map { stamp($0, mediaType: "tv") }.prefix(limit))
    }

    func getTopRated() async throws -> [TMDBResult] {
        let urlString = "\(base)/tv/top_rated?api_key=\(apiKey)&language=en-US&page=1"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TMDBTrendingEnvelope.self, from: data)
        return env.results.map { stamp($0, mediaType: "tv") }
    }

    /// Returns the top streaming provider for a title in the requested
    /// region (defaults to the device's resolved region). Prefers
    /// subscription/flatrate, then ad-supported, then free. Returns `nil` if
    /// no real streaming service is associated with the title — caller
    /// should hide the item rather than show a fake label.
    ///
    /// If the user's region returns nothing, we fall back to US so the rail
    /// still has something to open (most TMDB providers carry a US entry
    /// even when they're not active in the user's market).
    func getTopWatchProvider(
        tmdbId: Int,
        isTV: Bool,
        region: String? = nil
    ) async throws -> TMDBWatchProvider? {
        let kind = isTV ? "tv" : "movie"
        let urlString = "\(base)/\(kind)/\(tmdbId)/watch/providers?api_key=\(apiKey)"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TMDBProvidersEnvelope.self, from: data)
        let resolvedRegion = (region ?? DeviceLocale.current().region).uppercased()
        if let provider = Self.bestProvider(in: env.results[resolvedRegion]) {
            return provider
        }
        // Fallback to US — TMDB's most complete region — so callers always
        // get a deeplink target when one exists somewhere in the world.
        if resolvedRegion != "US", let provider = Self.bestProvider(in: env.results["US"]) {
            return provider
        }
        return nil
    }

    private static func bestProvider(in region: TMDBProviderRegion?) -> TMDBWatchProvider? {
        guard let region else { return nil }
        // Prefer subscription, then ad-supported, then free. Skip buy/rent — those
        // aren't "available to stream" in the sense users expect.
        let pool = (region.flatrate ?? []) + (region.ads ?? []) + (region.free ?? [])
        guard !pool.isEmpty else { return nil }
        return pool.min(by: { ($0.displayPriority ?? 999) < ($1.displayPriority ?? 999) })
    }

    /// Trailers / teasers attached to a TV show. Returns a YouTube key for the best match, or nil.
    /// For ongoing shows, also checks season-specific video endpoints (latest 3 seasons)
    /// because TMDB's main `/tv/{id}/videos` often only carries the original pilot trailer.
    func getTrailerKey(tmdbId: Int) async throws -> String? {
        // 1. Grab the main video list.
        let mainUrl = "\(base)/tv/\(tmdbId)/videos?api_key=\(apiKey)&language=en-US"
        let mainData = try await get(mainUrl)
        let mainEnv = try JSONDecoder().decode(TMDBVideosEnvelope.self, from: mainData)
        var allVideos = mainEnv.results

        // 2. Try to discover newer trailers via season-specific endpoints.
        if let detail = try? await getTVDetail(tmdbId: tmdbId),
           let seasons = detail.numberOfSeasons, seasons > 1 {
            let startSeason = seasons
            let endSeason = max(1, seasons - 2)
            for season in stride(from: startSeason, through: endSeason, by: -1) {
                guard let seasonData = try? await get("\(base)/tv/\(tmdbId)/season/\(season)/videos?api_key=\(apiKey)&language=en-US"),
                      let seasonEnv = try? JSONDecoder().decode(TMDBVideosEnvelope.self, from: seasonData)
                else { continue }
                allVideos.append(contentsOf: seasonEnv.results)
            }
        }

        // 3. Deduplicate by key — season endpoints may return the same videos as the main list.
        var seen = Set<String>()
        let unique = allVideos.filter { seen.insert($0.key).inserted }

        // 4. Filter to YouTube Trailers/Teasers and sort: official → newest → Trailer over Teaser.
        let yt = unique.filter { $0.site == "YouTube" && ($0.type == "Trailer" || $0.type == "Teaser") }
        if yt.isEmpty { return unique.first?.key }
        let sorted = yt.sorted { a, b in
            let aOfficial = a.official == true ? 1 : 0
            let bOfficial = b.official == true ? 1 : 0
            if aOfficial != bOfficial { return aOfficial > bOfficial }
            let aDate = a.publishedAt ?? ""
            let bDate = b.publishedAt ?? ""
            if aDate != bDate { return aDate > bDate }
            let aIsTrailer = a.type == "Trailer" ? 1 : 0
            let bIsTrailer = b.type == "Trailer" ? 1 : 0
            return aIsTrailer > bIsTrailer
        }
        return sorted.first?.key
    }

    func getMovieTrailerKey(tmdbId: Int) async throws -> String? {
        let urlString = "\(base)/movie/\(tmdbId)/videos?api_key=\(apiKey)&language=en-US"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TMDBVideosEnvelope.self, from: data)
        let yt = env.results.filter { $0.site == "YouTube" && ($0.type == "Trailer" || $0.type == "Teaser") }
        if yt.isEmpty { return env.results.first?.key }
        let sorted = yt.sorted { a, b in
            let aOfficial = a.official == true ? 1 : 0
            let bOfficial = b.official == true ? 1 : 0
            if aOfficial != bOfficial { return aOfficial > bOfficial }
            let aDate = a.publishedAt ?? ""
            let bDate = b.publishedAt ?? ""
            if aDate != bDate { return aDate > bDate }
            let aIsTrailer = a.type == "Trailer" ? 1 : 0
            let bIsTrailer = b.type == "Trailer" ? 1 : 0
            return aIsTrailer > bIsTrailer
        }
        return sorted.first?.key
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

    /// Parameterized trending fetch — lets SearchView pull TV and movies separately.
    func getTrending(mediaType: String, timeWindow: String) async throws -> [TMDBResult] {
        let urlString = "\(base)/trending/\(mediaType)/\(timeWindow)?api_key=\(apiKey)&language=en-US"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TMDBTrendingEnvelope.self, from: data)
        return env.results
            .filter { ($0.mediaType ?? mediaType) == "tv" || ($0.mediaType ?? mediaType) == "movie" }
            .map { r in
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
    }

    func getTrending() async throws -> [TMDBResult] {
        // Use the mixed `all/week` endpoint so the trending pool contains
        // both popular shows AND movies — the hero carousel needs variety.
        let urlString = "\(base)/trending/all/week?api_key=\(apiKey)&language=en-US"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TMDBTrendingEnvelope.self, from: data)
        // Filter to tv + movie only (the `all` endpoint can also return people).
        return env.results
            .filter { ($0.mediaType ?? "") == "tv" || ($0.mediaType ?? "") == "movie" }
            .map { r in
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

    /// Popular TV shows for a specific streaming provider using TMDB's discover
    /// endpoint. Filters to free + ad-supported content available in the US.
    func getPopularOnService(tmdbProviderId: Int) async throws -> [TMDBResult] {
        let urlString = "\(base)/discover/tv?api_key=\(apiKey)&language=en-US&sort_by=popularity.desc&watch_region=US&with_watch_providers=\(tmdbProviderId)&with_watch_monetization_types=flatrate%7Cads&page=1"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TMDBTrendingEnvelope.self, from: data)
        return env.results.map { stamp($0, mediaType: "tv") }
    }

    /// Popular movies currently available on a specific streaming service,
    /// using TMDB's discover endpoint filtered to flat-rate + ad-supported
    /// titles available in the US. Mirrors `getPopularOnService` but for movies.
    func getPopularMoviesOnService(tmdbProviderId: Int) async throws -> [TMDBResult] {
        let urlString = "\(base)/discover/movie?api_key=\(apiKey)&language=en-US&sort_by=popularity.desc&watch_region=US&with_watch_providers=\(tmdbProviderId)&with_watch_monetization_types=flatrate%7Cads&page=1"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TMDBTrendingEnvelope.self, from: data)
        return env.results.map { stamp($0, mediaType: "movie") }
    }

    /// "What's New Today" — trending TV + movies for the current day, capturing
    /// the daily zeitgeist of titles freshly hitting streaming services. Uses
    /// TMDB's `trending/all/day` endpoint and filters out people results.
    func getNewToday() async throws -> [TMDBResult] {
        let urlString = "\(base)/trending/all/day?api_key=\(apiKey)&language=en-US"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TMDBTrendingEnvelope.self, from: data)
        return env.results
            .filter { ($0.mediaType ?? "") == "tv" || ($0.mediaType ?? "") == "movie" }
            .map { r in
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
        // Watchmode requires the typed search field — tmdb_tv_id for shows, tmdb_movie_id for movies.
        let field = isTV ? "tmdb_tv_id" : "tmdb_movie_id"
        let urlString = "https://api.watchmode.com/v1/search/?apiKey=wqlepJq2xhEfyAVWpMOhVGmoUKBJFzHj3mlE3Lcw&search_field=\(field)&search_value=\(tmdbId)"
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

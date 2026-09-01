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

private nonisolated struct TVTMDBSeasonsEnvelope: Decodable, Sendable {
    let seasons: [TMDBSeasonSummary]?
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

    enum CodingKeys: String, CodingKey {
        case posterPath = "poster_path"
        case lastEpisodeToAir = "last_episode_to_air"
    }
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

private nonisolated struct TVTMDBDiscoverEnvelope: Decodable, Sendable {
    let page: Int?
    let results: [TVTMDBResult]
    let totalPages: Int?
    let totalResults: Int?

    enum CodingKeys: String, CodingKey {
        case page, results
        case totalPages = "total_pages"
        case totalResults = "total_results"
    }
}

/// tvOS counterpart of the phone app's BrowsePage. The filter model itself
/// lives in Shared/BrowseFilters.swift and is identical across targets; only
/// the result element type differs.
nonisolated struct TVBrowsePage: Hashable, Sendable {
    let results: [TVTMDBResult]
    let page: Int
    let totalPages: Int
    let totalResults: Int

    static let empty = TVBrowsePage(results: [], page: 1, totalPages: 1, totalResults: 0)
}

nonisolated struct TVTMDBService {
    static let shared = TVTMDBService()

    private let apiKey = "233f8054219ef58bc928549b4b5bab50"
    private let base = "https://api.themoviedb.org/3"

    /// Mixed trending feed (TV + movies) for the hero carousel + rail.
    func getTrending() async throws -> [TVTMDBResult] {
        let locale = DeviceLocale.current()
        let urlString = "\(base)/trending/all/week?api_key=\(apiKey)&language=\(locale.tmdbLanguage)"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TVTMDBSearchEnvelope.self, from: data)
        return env.results
            .filter { ($0.mediaType ?? "") == "tv" || ($0.mediaType ?? "") == "movie" }
            .map { stamp($0, mediaType: $0.mediaType ?? "tv") }
    }

    /// Currently-airing TV — used for the "New Episodes" rail.
    func getOnTheAir() async throws -> [TVTMDBResult] {
        let locale = DeviceLocale.current()
        let urlString = "\(base)/tv/on_the_air?api_key=\(apiKey)&language=\(locale.tmdbLanguage)&page=1"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TVTMDBSearchEnvelope.self, from: data)
        return env.results.map { stamp($0, mediaType: "tv") }
    }

    /// Returns the first genre name for a TV show, or nil.
    func getTVGenre(tmdbId: Int) async throws -> String? {
        let locale = DeviceLocale.current()
        let urlString = "\(base)/tv/\(tmdbId)?api_key=\(apiKey)&language=\(locale.tmdbLanguage)"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TVTMDBTVDetailEnvelope.self, from: data)
        return env.genres?.first?.name
    }

    /// Popular TV — used as a secondary feed source for For You.
    func getPopularTV() async throws -> [TVTMDBResult] {
        let locale = DeviceLocale.current()
        let urlString = "\(base)/tv/popular?api_key=\(apiKey)&language=\(locale.tmdbLanguage)&page=1"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TVTMDBSearchEnvelope.self, from: data)
        return env.results.map { stamp($0, mediaType: "tv") }
    }

    /// Returns the YouTube key of the best available trailer for a title, or
    /// nil if none exists. Prefers official trailers, then any trailer, then
    /// any teaser/clip so we still surface motion art when possible.
    func getTrailerKey(tmdbId: Int, isTV: Bool) async throws -> String? {
        let locale = DeviceLocale.current()
        let kind = isTV ? "tv" : "movie"
        let urlString = "\(base)/\(kind)/\(tmdbId)/videos?api_key=\(apiKey)&language=\(locale.tmdbLanguage)"
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

    /// Every YouTube key TMDB carries for a title, ranked: official
    /// trailers, then any trailer, then teasers, then whatever is left.
    /// The hero walks this list when a stream refuses to play, so a title
    /// with one dead trailer still gets a video.
    func getTrailerKeys(tmdbId: Int, isTV: Bool) async -> [String] {
        let locale = DeviceLocale.current()
        let kind = isTV ? "tv" : "movie"
        let urlString = "\(base)/\(kind)/\(tmdbId)/videos?api_key=\(apiKey)&language=\(locale.tmdbLanguage)"
        guard let data = try? await get(urlString),
              let env = try? JSONDecoder().decode(TVTMDBVideosEnvelope.self, from: data) else {
            return []
        }
        let youtube = env.results.filter {
            ($0.site ?? "").lowercased() == "youtube" && !($0.key ?? "").isEmpty
        }
        func rank(_ video: TVTMDBVideo) -> Int {
            let type = video.type ?? ""
            if type == "Trailer" && (video.official ?? false) { return 0 }
            if type == "Trailer" { return 1 }
            if type == "Teaser" { return 2 }
            return 3
        }
        var seen = Set<String>()
        return youtube
            .sorted { rank($0) < rank($1) }
            .compactMap { $0.key }
            .filter { seen.insert($0).inserted }
    }

    /// Returns the top US streaming provider for a title, or nil if no
    /// real streaming service is associated with it.
    func getTopWatchProvider(tmdbId: Int, isTV: Bool) async throws -> TVTMDBWatchProvider? {
        let locale = DeviceLocale.current()
        let kind = isTV ? "tv" : "movie"
        let urlString = "\(base)/\(kind)/\(tmdbId)/watch/providers?api_key=\(apiKey)"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TVTMDBProvidersEnvelope.self, from: data)
        let regionEntry = env.results[locale.region] ?? env.results["US"]
        guard let entry = regionEntry else { return nil }
        let pool = (entry.flatrate ?? []) + (entry.ads ?? []) + (entry.free ?? [])
        guard !pool.isEmpty else { return nil }
        return pool.min(by: { ($0.displayPriority ?? 999) < ($1.displayPriority ?? 999) })
    }

    /// Fetches a fresh poster path and the latest aired episode for a TV
    /// title. Returns nil poster/season/episode on any error so callers
    /// can fall back to the stored snapshot. Used by the watch-list poster
    /// back-fill and the season/episode pre-selection in TVTitleSheet.
    func getTVFreshness(tmdbId: Int) async -> (posterPath: String?, latestSeason: Int?, latestEpisode: Int?) {
        let locale = DeviceLocale.current()
        let urlString = "\(base)/tv/\(tmdbId)?api_key=\(apiKey)&language=\(locale.tmdbLanguage)"
        guard let data = try? await get(urlString) else { return (nil, nil, nil) }
        guard let env = try? JSONDecoder().decode(TVTMDBFreshness.self, from: data) else { return (nil, nil, nil) }
        return (env.posterPath, env.lastEpisodeToAir?.seasonNumber, env.lastEpisodeToAir?.episodeNumber)
    }

    /// Fetches a fresh poster path for a movie title. Returns nil on any
    /// error so callers can fall back to the stored snapshot.
    func getMoviePosterPath(tmdbId: Int) async -> String? {
        let locale = DeviceLocale.current()
        let urlString = "\(base)/movie/\(tmdbId)?api_key=\(apiKey)&language=\(locale.tmdbLanguage)"
        guard let data = try? await get(urlString) else { return nil }
        guard let env = try? JSONDecoder().decode(TVTMDBMoviePoster.self, from: data) else { return nil }
        return env.posterPath
    }

    /// Full season with its episode list — titles, stills, air dates,
    /// overviews and runtimes. This is the only source for that data:
    /// `watchmode_title_cache.episodes` carries season/episode numbers and
    /// per-episode deep links but no descriptive fields at all.
    ///
    /// Replaces the stub that used to live in TVCompatStubs and return nil,
    /// which is why the tvOS episode rails were always empty.
    func getSeason(tmdbId: Int, seasonNumber: Int) async throws -> TMDBSeason? {
        let locale = DeviceLocale.current()
        let urlString = "\(base)/tv/\(tmdbId)/season/\(seasonNumber)?api_key=\(apiKey)&language=\(locale.tmdbLanguage)"
        guard let data = try? await get(urlString) else { return nil }
        return try? JSONDecoder().decode(TMDBSeason.self, from: data)
    }

    /// Season summaries for a series, so the detail screen knows how many
    /// seasons exist before it fetches one. Returns an empty array on any
    /// failure so the season picker simply does not render.
    func getSeasonSummaries(tmdbId: Int) async -> [TMDBSeasonSummary] {
        let locale = DeviceLocale.current()
        let urlString = "\(base)/tv/\(tmdbId)?api_key=\(apiKey)&language=\(locale.tmdbLanguage)"
        guard let data = try? await get(urlString) else { return [] }
        guard let env = try? JSONDecoder().decode(TVTMDBSeasonsEnvelope.self, from: data) else { return [] }
        // Season 0 is TMDB's "Specials" bucket; the detail screen shows
        // numbered seasons only, matching Apple TV.
        return (env.seasons ?? []).filter { ($0.seasonNumber ?? 0) > 0 }
    }

    /// TMDB recommendations for a title, stamped with a media type so the
    /// cards route correctly. Feeds the "More Like This" rail. Never throws.
    func getRecommendations(tmdbId: Int, isTV: Bool) async -> [TVTMDBResult] {
        let locale = DeviceLocale.current()
        let path = isTV ? "tv" : "movie"
        let urlString = "\(base)/\(path)/\(tmdbId)/recommendations?api_key=\(apiKey)&language=\(locale.tmdbLanguage)"
        guard let data = try? await get(urlString) else { return [] }
        guard let env = try? JSONDecoder().decode(TVTMDBSearchEnvelope.self, from: data) else { return [] }
        return env.results.map { stamp($0, mediaType: $0.mediaType ?? path) }
    }

    /// Now-playing movies in the US — mirrors the iOS `getNowPlayingMovies`.
    func getNowPlayingMovies() async -> [TVTMDBResult] {
        let locale = DeviceLocale.current()
        let urlString = "\(base)/movie/now_playing?api_key=\(apiKey)&language=\(locale.tmdbLanguage)&region=\(locale.region)&page=1"
        guard let data = try? await get(urlString) else { return [] }
        guard let env = try? JSONDecoder().decode(TVTMDBSearchEnvelope.self, from: data) else { return [] }
        return env.results.map { stamp($0, mediaType: "movie") }
    }

    /// Returns the earliest future US digital release date (type == 4) for a
    /// movie, or nil when none exists. Mirrors the iOS `getUSDigitalReleaseDate`.
    func getUSDigitalReleaseDate(movieId: Int) async -> (date: Date, note: String?)? {
        let locale = DeviceLocale.current()
        let urlString = "\(base)/movie/\(movieId)/release_dates?api_key=\(apiKey)"
        guard let data = try? await get(urlString) else { return nil }
        guard let env = try? JSONDecoder().decode(TVTMDBReleaseDatesEnvelope.self, from: data) else { return nil }
        guard let regionEntry = env.results.first(where: { $0.iso31661 == locale.region }) ?? env.results.first(where: { $0.iso31661 == "US" }) else { return nil }
        let digital = (regionEntry.releaseDates ?? []).filter { $0.type == 4 }
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
        let locale = DeviceLocale.current()
        let urlString = "\(base)/discover/tv?api_key=\(apiKey)&language=\(locale.tmdbLanguage)&sort_by=popularity.desc&watch_region=\(locale.region)&with_watch_providers=\(tmdbProviderId)&with_watch_monetization_types=flatrate%7Cads&page=1"
        guard let data = try? await get(urlString) else { return [] }
        guard let env = try? JSONDecoder().decode(TVTMDBSearchEnvelope.self, from: data) else { return [] }
        return env.results.map { stamp($0, mediaType: "tv") }
    }

    /// Popular movies on a specific Watchmode provider — mirrors the iOS
    /// `getPopularMoviesOnService`. Returns [] on any error so the rail hides.
    func getPopularMoviesOnService(tmdbProviderId: Int) async -> [TVTMDBResult] {
        let locale = DeviceLocale.current()
        let urlString = "\(base)/discover/movie?api_key=\(apiKey)&language=\(locale.tmdbLanguage)&sort_by=popularity.desc&watch_region=\(locale.region)&with_watch_providers=\(tmdbProviderId)&page=1"
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

    // MARK: - Search

    /// Multi-search across shows and movies. Person results and anything
    /// without a poster are dropped — a grid cell with no artwork reads as a
    /// loading failure on a ten-foot screen.
    func searchContent(query: String) async throws -> [TVTMDBResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return [] }

        let locale = DeviceLocale.current()
        let urlString = "\(base)/search/multi?api_key=\(apiKey)&language=\(locale.tmdbLanguage)&include_adult=false&query=\(encoded)"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TVTMDBSearchEnvelope.self, from: data)
        return env.results.filter { result in
            let kind = result.mediaType ?? ""
            return (kind == "tv" || kind == "movie") && result.posterPath != nil
        }
    }

    // MARK: - Browse

    /// One page of browse results for the current filter set. `.all` runs the
    /// tv and movie paths concurrently and interleaves them; if one path fails
    /// the other still returns. Mirrors the phone app's discoverBrowse.
    func discoverBrowse(_ filters: BrowseFilters, page: Int = 1) async throws -> TVBrowsePage {
        let f = filters.resolved()

        if let path = f.resolvedMediaType.discoverPath {
            return try await discoverBrowsePage(f, path: path, page: page)
        }

        async let tvPage = try? await discoverBrowsePage(f, path: "tv", page: page)
        async let moviePage = try? await discoverBrowsePage(f, path: "movie", page: page)
        let (tv, movie) = await (tvPage, moviePage)

        guard tv != nil || movie != nil else { throw URLError(.badServerResponse) }
        let t = tv ?? .empty
        let m = movie ?? .empty
        return TVBrowsePage(
            results: Self.interleaveBrowse(t.results, m.results),
            page: page,
            totalPages: max(t.totalPages, m.totalPages),
            totalResults: t.totalResults + m.totalResults
        )
    }

    private func discoverBrowsePage(_ f: BrowseFilters, path: String, page: Int) async throws -> TVBrowsePage {
        let locale = DeviceLocale.current()
        var url = "\(base)/discover/\(path)?api_key=\(apiKey)&language=\(locale.tmdbLanguage)&page=\(page)"
        url += "&sort_by=\(f.sort.tmdbValue(for: path))"

        let genres = f.selectedGenres
        let genreIds = genres.compactMap { $0.genreId(for: path) }
        if !genreIds.isEmpty {
            url += "&with_genres=\(genreIds.map(String.init).joined(separator: "%2C"))"
        }

        if let language = genres.compactMap({ $0.originalLanguage ?? $0.languagePool }).first {
            let encoded = language.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? language
            url += "&with_original_language=\(encoded)"
        }

        let providers = f.effectiveProviderIds
        if !providers.isEmpty {
            url += "&watch_region=\(locale.region)"
            url += "&with_watch_providers=\(providers.map(String.init).joined(separator: "%7C"))"
            url += "&with_watch_monetization_types=\(f.includeFreeWithAds ? "flatrate%7Cads" : "flatrate")"
        }

        if let years = f.yearRange {
            let lower = "\(years.lowerBound)-01-01"
            let upper = "\(years.upperBound)-12-31"
            if path == "movie" {
                url += "&primary_release_date.gte=\(lower)&primary_release_date.lte=\(upper)"
            } else {
                url += "&first_air_date.gte=\(lower)&first_air_date.lte=\(upper)"
            }
        }

        if let rating = f.minRating {
            url += "&vote_average.gte=\(rating)"
        }
        // Mirrors the phone app: the higher of the sort-driven floor and the
        // genre's own, so neither can weaken the other. Anime's floor is a
        // content filter, not a quality preference — see BrowseCatalog.
        let sortFloor = (f.minRating != nil || f.sort.needsVoteFloor) ? 50 : nil
        let genreFloor = genres.compactMap { $0.voteFloor }.max()
        if let floor = [sortFloor, genreFloor].compactMap({ $0 }).max() {
            url += "&vote_count.gte=\(floor)"
        }
        if let keywords = genres.compactMap({ $0.excludedKeywordIds }).first {
            url += "&without_keywords=\(keywords)"
        }

        let data = try await get(url)
        let env = try JSONDecoder().decode(TVTMDBDiscoverEnvelope.self, from: data)
        // TMDB has no `without_ids`, so the blocklist is applied here rather
        // than in the query. It only ever has entries for Anime.
        let blocked = genres.reduce(into: Set<Int>()) { $0.formUnion($1.blockedTmdbIds) }
        return TVBrowsePage(
            results: env.results
                .map { stamp($0, mediaType: path) }
                .filter { blocked.isEmpty || !blocked.contains($0.id) },
            page: env.page ?? page,
            totalPages: env.totalPages ?? 1,
            totalResults: env.totalResults ?? env.results.count
        )
    }

    private static func interleaveBrowse(_ a: [TVTMDBResult], _ b: [TVTMDBResult]) -> [TVTMDBResult] {
        var out: [TVTMDBResult] = []
        out.reserveCapacity(a.count + b.count)
        var seen = Set<Int>()
        for i in 0..<max(a.count, b.count) {
            if i < a.count, seen.insert(a[i].id).inserted { out.append(a[i]) }
            if i < b.count, seen.insert(b[i].id).inserted { out.append(b[i]) }
        }
        return out
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

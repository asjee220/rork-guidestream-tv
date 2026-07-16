//
//  WatchmodeService.swift
//  GuideStreamTV
//

import Foundation

nonisolated struct WatchmodeResult: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let type: String        // "tv_series", "movie", etc.
    let year: Int?
    let imageUrl: String?

    var titleId: String { String(id) }
    var isTV: Bool { type.contains("tv") }
    var typeLabel: String { isTV ? "TV" : "Movie" }
}

nonisolated struct WatchmodeSource: Decodable, Hashable, Sendable, Identifiable {
    let sourceId: Int
    let name: String
    let type: String
    let region: String?
    let iosUrl: String?
    let androidUrl: String?
    let webUrl: String?
    let format: String?
    let endDate: String?
    let rokuUrl: String?
    let tvosUrl: String?
    let androidTvUrl: String?
    let price: Double?

    var id: String { "\(sourceId)-\(format ?? "")-\(region ?? "")" }

    enum CodingKeys: String, CodingKey {
        case sourceId = "source_id"
        case name, type, region, format
        case iosUrl = "ios_url"
        case androidUrl = "android_url"
        case webUrl = "web_url"
        case endDate = "end_date"
        case rokuUrl = "roku_url"
        case tvosUrl = "tvos_url"
        case androidTvUrl = "android_tv_url"
        case price = "price"
    }
}

nonisolated struct WatchmodeTitleDetail: Decodable, Sendable {
    let id: Int
    let title: String
    let year: Int?
    let userRating: Double?
    let plotOverview: String?
    let genreNames: [String]?
    let trailer: String?
    let posterUrl: String?
    let backdrop: String?
    let releaseDate: String?
    let endYear: Int?
    let runtimeMinutes: Int?
    let usRating: String?
    let type: String?
    let sources: [WatchmodeSource]?

    enum CodingKeys: String, CodingKey {
        case id, title, year, trailer, type, sources
        case userRating = "user_rating"
        case plotOverview = "plot_overview"
        case genreNames = "genre_names"
        case posterUrl = "poster"
        case backdrop
        case releaseDate = "release_date"
        case endYear = "end_year"
        case runtimeMinutes = "runtime_minutes"
        case usRating = "us_rating"
    }
}

nonisolated struct WatchmodeService {
    static let shared = WatchmodeService()

    private let apiKey = "wqlepJq2xhEfyAVWpMOhVGmoUKBJFzHj3mlE3Lcw"

    /// Fetches a title's metadata + all per-source watch links.
    ///
    /// Watchmode's title details live at `/v1/title/{id}/details/`. The bare
    /// `/v1/title/{id}/` path returns `400 Invalid method.`, which silently
    /// killed every "Watch on …" deeplink resolution. `append_to_response=sources`
    /// inlines the per-streaming-service URLs we need to open the right title
    /// inside Netflix / Max / Prime / etc.
    func titleDetail(titleId: String) async throws -> WatchmodeTitleDetail {
        let urlString = "https://api.watchmode.com/v1/title/\(titleId)/details/?apiKey=\(apiKey)&append_to_response=sources&include_links=true"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            #if DEBUG
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            print("[Watchmode] titleDetail HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1) for id=\(titleId): \(body.prefix(200))")
            #endif
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(WatchmodeTitleDetail.self, from: data)
    }

    /// Fetches the top TV series for a given Watchmode source ID.
    func fetchTopTitles(sourceId: Int, limit: Int = 12) async throws -> [WatchmodeResult] {
        let urlString = "https://api.watchmode.com/v1/list-titles/?apiKey=\(apiKey)&source_ids=\(sourceId)&types=tv_series&sort_by=popularity_desc&limit=\(limit)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let envelope = try JSONDecoder().decode(WatchmodeListTitlesEnvelope.self, from: data)
        return envelope.titles.map {
            WatchmodeResult(
                id: $0.id,
                name: $0.title,
                type: $0.type,
                year: $0.year,
                imageUrl: $0.poster
            )
        }
    }

    func search(query: String) async throws -> [WatchmodeResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }

        let urlString = "https://api.watchmode.com/v1/search/?apiKey=\(apiKey)&search_field=name&search_value=\(encoded)&types=tv,movie"
        guard let url = URL(string: urlString) else { return [] }

        var req = URLRequest(url: url)
        req.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(WatchmodeSearchEnvelope.self, from: data)
        return decoded.titleResults.map {
            WatchmodeResult(
                id: $0.id,
                name: $0.name,
                type: $0.type,
                year: $0.year,
                imageUrl: $0.imageUrl
            )
        }
    }
}

// MARK: - Releases (upcoming-to-streaming)

nonisolated struct WatchmodeRelease: Decodable, Sendable {
    let id: Int?
    let title: String?
    let type: String?
    let tmdbId: Int?
    let tmdbType: String?
    let posterUrl: String?
    let sourceReleaseDate: String?
    let sourceId: Int?
    let sourceName: String?
    let isOriginal: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, type
        case tmdbId = "tmdb_id"
        case tmdbType = "tmdb_type"
        case posterUrl = "poster_url"
        case sourceReleaseDate = "source_release_date"
        case sourceId = "source_id"
        case sourceName = "source_name"
        case isOriginal = "is_original"
    }
}

nonisolated struct WatchmodeReleasesEnvelope: Decodable, Sendable {
    let releases: [WatchmodeRelease]?
}

nonisolated extension WatchmodeService {
    /// Fetches upcoming streaming releases from Watchmode's releases endpoint.
    /// Returns movies with a known TMDB id and a streaming release date on or
    /// after today, up to `daysAhead` in the future.
    func upcomingStreamingReleases(daysAhead: Int = 30, limit: Int = 250) async throws -> [WatchmodeRelease] {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd"
        df.locale = Locale(identifier: "en_US_POSIX")
        let start = df.string(from: Date())
        let endDate = Calendar.current.date(byAdding: .day, value: daysAhead, to: Date()) ?? Date()
        let end = df.string(from: endDate)

        let urlString = "https://api.watchmode.com/v1/releases/?apiKey=\(apiKey)&start_date=\(start)&end_date=\(end)&limit=\(limit)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: req)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(statusCode) else {
            #if DEBUG
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            print("[Watchmode] upcomingStreamingReleases HTTP \(statusCode): \(body.prefix(200))")
            #endif
            throw URLError(.badServerResponse)
        }
        let envelope = try JSONDecoder().decode(WatchmodeReleasesEnvelope.self, from: data)
        return envelope.releases ?? []
    }
}

// MARK: - Episode-level sources

nonisolated struct WatchmodeEpisode: Decodable, Sendable {
    let seasonNumber: Int?
    let episodeNumber: Int?
    let sources: [WatchmodeSource]?

    enum CodingKeys: String, CodingKey {
        case seasonNumber = "season_number"
        case episodeNumber = "episode_number"
        case sources
    }
}

nonisolated struct WatchmodeEpisodesEnvelope: Decodable, Sendable {
    let episodes: [WatchmodeEpisode]?
}

nonisolated extension WatchmodeService {
    /// In-memory cache for episode-level sources so reopening the same
    /// title spends no additional Watchmode credits.
    private static let episodeSourcesCache = NSCache<NSString, NSArray>()

    /// Fetches per-episode streaming sources from Watchmode for a specific
    /// season/episode of a show. Uses the paid-plan endpoint that returns
    /// real deep-link URLs capable of opening the exact episode in the
    /// streaming app (not just the show home page).
    ///
    /// - Returns: The sources array for the matching episode, or `nil` if
    ///   Watchmode doesn't know the show, the episode, or returns only
    ///   free-tier placeholder data.
    func episodeSources(
        tmdbId: Int,
        isTV: Bool,
        season: Int,
        episode: Int,
        region: String = "US"
    ) async -> [WatchmodeSource]? {
        guard let wmId = try? await watchmodeId(forTMDBId: tmdbId, isTV: isTV),
              !wmId.isEmpty
        else { return nil }

        let cacheKey = "\(tmdbId)-\(season)-\(episode)" as NSString
        if let cached = Self.episodeSourcesCache.object(forKey: cacheKey) as? [WatchmodeSource] {
            return cached
        }

        let urlString = "https://api.watchmode.com/v1/title/\(wmId)/episodes/?apiKey=\(apiKey)&regions=\(region)&include_links=true"
        guard let url = URL(string: urlString) else { return nil }

        var req = URLRequest(url: url)
        req.timeoutInterval = 12

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { return nil }

        let episodes: [WatchmodeEpisode]?
        // Defensive decode: the endpoint may return a bare array or an
        // object wrapping an "episodes" array.
        if let arr = try? JSONDecoder().decode([WatchmodeEpisode].self, from: data) {
            episodes = arr
        } else if let envelope = try? JSONDecoder().decode(WatchmodeEpisodesEnvelope.self, from: data) {
            episodes = envelope.episodes
        } else {
            return nil
        }

        guard let episodes else { return nil }

        let match = episodes.first { ep in
            ep.seasonNumber == season && ep.episodeNumber == episode
        }

        let result = match?.sources
        if let result {
            Self.episodeSourcesCache.setObject(result as NSArray, forKey: cacheKey)
        }
        return result
    }
}

// MARK: - Decoding

nonisolated struct WatchmodeSearchEnvelope: Decodable, Sendable {
    let titleResults: [WatchmodeTitleResult]

    enum CodingKeys: String, CodingKey {
        case titleResults = "title_results"
    }
}

nonisolated struct WatchmodeTitleResult: Decodable, Sendable {
    let id: Int
    let name: String
    let type: String
    let year: Int?
    let imageUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, name, type, year
        case imageUrl = "image_url"
    }
}

// MARK: - List titles (source-based)

nonisolated struct WatchmodeListTitlesEnvelope: Decodable, Sendable {
    let titles: [WatchmodeListTitle]

    enum CodingKeys: String, CodingKey {
        case titles
    }
}

nonisolated struct WatchmodeListTitle: Decodable, Sendable {
    let id: Int
    let title: String
    let type: String
    let year: Int?
    let poster: String?

    enum CodingKeys: String, CodingKey {
        case id, title, type, year, poster
    }
}

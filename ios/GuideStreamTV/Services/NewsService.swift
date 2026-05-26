//
//  NewsService.swift
//  GuideStreamTV
//
//  Aggregates the latest news streams/shows available across the major
//  streaming services. Mixes:
//    * TMDB News-genre TV shows (genre id 10763 — News) sorted by
//      airing date so the freshest CNN/BBC/MSNBC/Fox News updates land at
//      the top.
//    * TMDB News-genre movies (documentaries / newsmagazines), so the rail
//      isn't just cable news redux.
//
//  The result set is deduped, capped to the top 10 most-recent items, and
//  every item is keyed to its top US streaming provider so the rail never
//  advertises a service we can't deeplink to.
//

import Foundation

/// Single news item rendered by the Home news panel. Mirrors the shape of
/// `TMDBResult` but carries an already-resolved streaming `provider` so the
/// rendering layer doesn't need a follow-up call to populate badges.
nonisolated struct NewsStream: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let outlet: String
    let posterUrl: String?
    let backdropUrl: String?
    let overview: String?
    let isTV: Bool
    let publishedAt: Date?
    let providerName: String?
}

@MainActor
final class NewsService {
    static let shared = NewsService()
    private init() {}

    /// TMDB genre id for News content (TV + movie). The same id works for
    /// both `discover/tv` and `discover/movie`.
    private static let newsGenreId = 10763

    /// Returns up to 10 of the freshest news items spread across streaming
    /// services. Items are sorted descending by air/release date so the
    /// top-of-the-feed slot is always today's headlines. Items that can't
    /// be paired with a recognised streaming provider are skipped — we
    /// only show things users can actually open.
    func fetchTopNewsStreams(limit: Int = 10) async -> [NewsStream] {
        async let tvCall = try? fetchNewsTV()
        async let movieCall = try? fetchNewsMovies()
        let (tv, movies) = await (tvCall, movieCall)

        let combined: [TMDBResult] = (tv ?? []) + (movies ?? [])
        // Dedupe by tmdb id; the same outlet sometimes appears in both
        // endpoints (e.g. PBS News).
        var seen: Set<Int> = []
        let unique = combined.filter { seen.insert($0.id).inserted }

        // Resolve top US streaming provider in parallel. Skip items with no
        // recognised provider — those have no deeplink behind them, so
        // showing the card would be misleading.
        let resolved: [(TMDBResult, String?)] = await withTaskGroup(of: (TMDBResult, String?)?.self) { group in
            for item in unique {
                group.addTask {
                    let provider = try? await TMDBService.shared.getTopWatchProvider(tmdbId: item.id, isTV: item.isTV)
                    return (item, provider?.providerName)
                }
            }
            var out: [(TMDBResult, String?)] = []
            for await pair in group {
                if let pair { out.append(pair) }
            }
            return out
        }

        // Build NewsStream models and sort by air date (newest first).
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate]
        let news: [NewsStream] = resolved.compactMap { (r, providerName) in
            let outlet = Self.outlet(from: r.displayName)
            let dateString = r.firstAirDate ?? r.releaseDate
            let date = dateString.flatMap { isoFormatter.date(from: $0) }
            return NewsStream(
                id: r.id,
                title: r.displayName,
                outlet: outlet,
                posterUrl: r.posterUrl,
                backdropUrl: r.backdropUrl,
                overview: r.overview,
                isTV: r.isTV,
                publishedAt: date,
                providerName: providerName
            )
        }

        let sorted = news.sorted { a, b in
            switch (a.publishedAt, b.publishedAt) {
            case let (l?, r?): return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.title < b.title
            }
        }
        return Array(sorted.prefix(limit))
    }

    // MARK: - TMDB News endpoints

    private func fetchNewsTV() async throws -> [TMDBResult] {
        // Discover TV with News genre, sorted by most recent first-air-date.
        let urlString = "https://api.themoviedb.org/3/discover/tv?api_key=\(apiKey)&language=en-US&sort_by=first_air_date.desc&with_genres=\(Self.newsGenreId)&air_date.lte=\(todayString())&page=1"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TMDBDiscoverEnvelope.self, from: data)
        return env.results.map { Self.stamp($0, mediaType: "tv") }
    }

    private func fetchNewsMovies() async throws -> [TMDBResult] {
        let urlString = "https://api.themoviedb.org/3/discover/movie?api_key=\(apiKey)&language=en-US&sort_by=release_date.desc&with_genres=\(Self.newsGenreId)&release_date.lte=\(todayString())&page=1"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TMDBDiscoverEnvelope.self, from: data)
        return env.results.map { Self.stamp($0, mediaType: "movie") }
    }

    private func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date())
    }

    /// Best-effort outlet extraction so the rail can label cards with a
    /// short brand name (e.g. "CNN", "BBC News", "MSNBC") instead of the
    /// long episode title. Falls back to the first word of the title when
    /// no known network is mentioned.
    private static func outlet(from title: String) -> String {
        let key = title.lowercased()
        if key.contains("cnn") { return "CNN" }
        if key.contains("bbc") { return "BBC News" }
        if key.contains("msnbc") { return "MSNBC" }
        if key.contains("fox news") || key.contains("fox business") { return "Fox News" }
        if key.contains("abc news") || key.contains("nightline") || key.contains("good morning america") { return "ABC News" }
        if key.contains("nbc nightly") || key.contains("today show") || key.contains("nbc news") { return "NBC News" }
        if key.contains("cbs news") || key.contains("60 minutes") || key.contains("cbs evening") { return "CBS News" }
        if key.contains("pbs news") || key.contains("newshour") { return "PBS NewsHour" }
        if key.contains("al jazeera") { return "Al Jazeera" }
        if key.contains("vice news") || key.contains("vice") { return "VICE News" }
        if key.contains("reuters") { return "Reuters" }
        if key.contains("bloomberg") { return "Bloomberg" }
        if key.contains("cnbc") { return "CNBC" }
        if key.contains("sky news") { return "Sky News" }
        if key.contains("dw news") || key.contains("deutsche welle") { return "DW News" }
        // No known outlet — use the first two words of the title.
        let words = title.split(separator: " ").prefix(2).joined(separator: " ")
        return words.isEmpty ? title : words
    }

    private static func stamp(_ r: TMDBResult, mediaType: String) -> TMDBResult {
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

    // MARK: - Networking

    private let apiKey = "233f8054219ef58bc928549b4b5bab50"

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

/// TMDB's `discover` envelope — identical shape to `trending` but kept
/// separate for clarity in this file.
private nonisolated struct TMDBDiscoverEnvelope: Decodable, Sendable {
    let results: [TMDBResult]
}

//
//  TVNewsService.swift
//  GuideStreamTVTV
//
//  Latest news streams across major streaming services. Mirrors the
//  phone app's `NewsService`: pulls the TMDB News genre for TV + movies,
//  dedupes, and caps to the freshest 10 items.
//

import Foundation

private nonisolated struct TVTMDBDiscoverEnvelope: Decodable, Sendable {
    let results: [TVTMDBResult]
}

@MainActor
final class TVNewsService {
    static let shared = TVNewsService()
    private init() {}

    private static let newsGenreId = 10763

    func fetchTopNewsStreams(limit: Int = 10) async -> [TVNewsStream] {
        async let tvCall = try? fetchNewsTV()
        async let movieCall = try? fetchNewsMovies()
        let (tv, movies) = await (tvCall, movieCall)

        let combined: [TVTMDBResult] = (tv ?? []) + (movies ?? [])
        var seen: Set<Int> = []
        let unique = combined.filter { seen.insert($0.id).inserted }

        let resolved: [(TVTMDBResult, String?)] = await withTaskGroup(of: (TVTMDBResult, String?)?.self) { group in
            for item in unique {
                group.addTask {
                    let provider = try? await TVTMDBService.shared.getTopWatchProvider(
                        tmdbId: item.id,
                        isTV: item.isTV
                    )
                    return (item, provider?.providerName)
                }
            }
            var out: [(TVTMDBResult, String?)] = []
            for await pair in group {
                if let pair { out.append(pair) }
            }
            return out
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate]
        let news: [TVNewsStream] = resolved.map { (r, providerName) in
            let outlet = Self.outlet(from: r.displayName)
            let dateString = r.firstAirDate ?? r.releaseDate
            let date = dateString.flatMap { isoFormatter.date(from: $0) }
            return TVNewsStream(
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

    private func fetchNewsTV() async throws -> [TVTMDBResult] {
        let urlString = "https://api.themoviedb.org/3/discover/tv?api_key=\(apiKey)&language=en-US&sort_by=first_air_date.desc&with_genres=\(Self.newsGenreId)&air_date.lte=\(todayString())&page=1"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TVTMDBDiscoverEnvelope.self, from: data)
        return env.results.map { Self.stamp($0, mediaType: "tv") }
    }

    private func fetchNewsMovies() async throws -> [TVTMDBResult] {
        let urlString = "https://api.themoviedb.org/3/discover/movie?api_key=\(apiKey)&language=en-US&sort_by=release_date.desc&with_genres=\(Self.newsGenreId)&release_date.lte=\(todayString())&page=1"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TVTMDBDiscoverEnvelope.self, from: data)
        return env.results.map { Self.stamp($0, mediaType: "movie") }
    }

    private func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date())
    }

    private static func outlet(from title: String) -> String {
        let key = title.lowercased()
        if key.contains("cnn") { return "CNN" }
        if key.contains("bbc") { return "BBC News" }
        if key.contains("msnbc") { return "MSNBC" }
        if key.contains("fox news") || key.contains("fox business") { return "Fox News" }
        if key.contains("abc news") || key.contains("nightline") { return "ABC News" }
        if key.contains("nbc nightly") || key.contains("today show") { return "NBC News" }
        if key.contains("cbs news") || key.contains("60 minutes") { return "CBS News" }
        if key.contains("pbs news") || key.contains("newshour") { return "PBS NewsHour" }
        if key.contains("al jazeera") { return "Al Jazeera" }
        if key.contains("vice news") { return "VICE News" }
        if key.contains("reuters") { return "Reuters" }
        if key.contains("bloomberg") { return "Bloomberg" }
        if key.contains("cnbc") { return "CNBC" }
        if key.contains("sky news") { return "Sky News" }
        let words = title.split(separator: " ").prefix(2).joined(separator: " ")
        return words.isEmpty ? title : words
    }

    private static func stamp(_ r: TVTMDBResult, mediaType: String) -> TVTMDBResult {
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

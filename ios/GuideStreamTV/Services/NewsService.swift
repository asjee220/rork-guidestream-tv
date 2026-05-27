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
//  Now **device-localized**: the TMDB `language`, `region`, and
//  `watch_region` parameters are driven by `DeviceLocale` so a user in
//  the UK gets BBC / Sky News / ITV results, a user in Germany sees DW /
//  ARD, and so on. We always fall back to the top US streaming provider
//  for the deeplink layer when no localised provider is available, so
//  the rail still has something to open.
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

    /// When `providerName` is nil (common for broadcast networks like Fox,
    /// CBS, ABC, NBC that don't have SVOD providers in TMDB), fall back to
    /// the outlet's live-stream or news-homepage URL so the tile still has
    /// a deeplink target.
    var fallbackDeepLinkURL: String? {
        let key = outlet.lowercased()
        if key.contains("fox") { return "https://www.foxnews.com" }
        if key.contains("cbs") { return "https://www.cbsnews.com/live" }
        if key.contains("abc") { return "https://abcnews.go.com/Live" }
        if key.contains("nbc") { return "https://www.nbcnews.com/now" }
        if key.contains("pbs") { return "https://www.pbs.org/newshour/live" }
        if key.contains("cnn") { return "https://www.cnn.com/live-tv" }
        if key.contains("msnbc") { return "https://www.msnbc.com/live-video" }
        return nil
    }
}

@MainActor
final class NewsService {
    static let shared = NewsService()
    private init() {}

    /// TMDB genre id for News content (TV + movie). The same id works for
    /// both `discover/tv` and `discover/movie`.
    private static let newsGenreId = 10763

    /// Returns up to `limit` of the freshest news items spread across
    /// streaming services available in the device's region. Sorted by air
    /// date desc. Items without a recognised streaming provider in the
    /// device's region are skipped so the rail never advertises a service
    /// users can't open from where they live.
    func fetchTopNewsStreams(limit: Int = 10) async -> [NewsStream] {
        let locale = DeviceLocale.current()
        async let tvCall = try? fetchNewsTV(locale: locale)
        async let movieCall = try? fetchNewsMovies(locale: locale)
        let (tv, movies) = await (tvCall, movieCall)

        let combined: [TMDBResult] = (tv ?? []) + (movies ?? [])
        // Dedupe by tmdb id; the same outlet sometimes appears in both
        // endpoints (e.g. PBS News).
        var seen: Set<Int> = []
        let unique = combined.filter { seen.insert($0.id).inserted }

        // Resolve top regional streaming provider in parallel. Skip items
        // with no recognised provider — those have no deeplink behind them.
        let region = locale.region
        let resolved: [(TMDBResult, String?)] = await withTaskGroup(of: (TMDBResult, String?)?.self) { group in
            for item in unique {
                group.addTask {
                    let provider = try? await TMDBService.shared.getTopWatchProvider(
                        tmdbId: item.id,
                        isTV: item.isTV,
                        region: region
                    )
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
        let news: [NewsStream] = resolved.map { (r, providerName) in
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

    private func fetchNewsTV(locale: DeviceLocale) async throws -> [TMDBResult] {
        // Discover TV with News genre, scoped to the device's region/language
        // so a user in the UK gets BBC/Sky outlets, a user in Germany gets
        // DW/ARD, etc. `watch_region` filters out titles that aren't on a
        // streaming service in that country — the very thing we want.
        let urlString = "https://api.themoviedb.org/3/discover/tv?api_key=\(apiKey)&language=\(locale.tmdbLanguage)&region=\(locale.region)&watch_region=\(locale.region)&sort_by=first_air_date.desc&with_genres=\(Self.newsGenreId)&air_date.lte=\(todayString())&page=1"
        let data = try await get(urlString)
        let env = try JSONDecoder().decode(TMDBDiscoverEnvelope.self, from: data)
        return env.results.map { Self.stamp($0, mediaType: "tv") }
    }

    private func fetchNewsMovies(locale: DeviceLocale) async throws -> [TMDBResult] {
        let urlString = "https://api.themoviedb.org/3/discover/movie?api_key=\(apiKey)&language=\(locale.tmdbLanguage)&region=\(locale.region)&watch_region=\(locale.region)&sort_by=release_date.desc&with_genres=\(Self.newsGenreId)&release_date.lte=\(todayString())&page=1"
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

    /// Best-effort outlet extraction. Includes US, UK, EU, MENA, APAC, LatAm
    /// outlets so the localised feed never falls back to a generic two-word
    /// title slice when the rail lands in a non-US region.
    private static func outlet(from title: String) -> String {
        let key = title.lowercased()
        // North America
        if key.contains("cnn") { return "CNN" }
        if key.contains("msnbc") { return "MSNBC" }
        if key.contains("fox news") || key.contains("fox business") { return "Fox News" }
        if key.contains("abc news") || key.contains("nightline") || key.contains("good morning america") { return "ABC News" }
        if key.contains("nbc nightly") || key.contains("today show") || key.contains("nbc news") { return "NBC News" }
        if key.contains("cbs news") || key.contains("60 minutes") || key.contains("cbs evening") { return "CBS News" }
        if key.contains("pbs news") || key.contains("newshour") { return "PBS NewsHour" }
        if key.contains("vice news") || key.contains("vice") { return "VICE News" }
        if key.contains("cbc") { return "CBC News" }
        if key.contains("ctv") { return "CTV News" }
        if key.contains("global news") { return "Global News" }
        // UK / Ireland
        if key.contains("bbc") { return "BBC News" }
        if key.contains("sky news") { return "Sky News" }
        if key.contains("itv news") || key.contains("itn") { return "ITV News" }
        if key.contains("channel 4") { return "Channel 4 News" }
        if key.contains("rte") { return "RTÉ News" }
        // Continental Europe
        if key.contains("dw news") || key.contains("deutsche welle") { return "DW News" }
        if key.contains("zdf") { return "ZDF" }
        if key.contains("ard") { return "ARD" }
        if key.contains("euronews") { return "Euronews" }
        if key.contains("france 24") || key.contains("france24") { return "France 24" }
        if key.contains("tf1") { return "TF1" }
        if key.contains("rai") { return "Rai News" }
        if key.contains("rtve") { return "RTVE" }
        if key.contains("nos") { return "NOS Nieuws" }
        // Middle East / Africa
        if key.contains("al jazeera") { return "Al Jazeera" }
        if key.contains("al arabiya") { return "Al Arabiya" }
        if key.contains("sabc") { return "SABC News" }
        // APAC
        if key.contains("nhk") { return "NHK" }
        if key.contains("cctv") || key.contains("cgtn") { return "CGTN" }
        if key.contains("abc australia") || key.contains("abc news australia") { return "ABC Australia" }
        if key.contains("nine news") { return "9 News" }
        if key.contains("seven news") { return "7 News" }
        if key.contains("ndtv") { return "NDTV" }
        if key.contains("times now") { return "Times Now" }
        if key.contains("kbs") { return "KBS News" }
        if key.contains("sbs") { return "SBS News" }
        if key.contains("channel news asia") || key.contains("cna") { return "CNA" }
        // Latin America
        if key.contains("globo") { return "TV Globo" }
        if key.contains("telesur") || key.contains("telesur") { return "teleSUR" }
        if key.contains("televisa") { return "Televisa" }
        // Wire services / financial
        if key.contains("reuters") { return "Reuters" }
        if key.contains("bloomberg") { return "Bloomberg" }
        if key.contains("cnbc") { return "CNBC" }
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

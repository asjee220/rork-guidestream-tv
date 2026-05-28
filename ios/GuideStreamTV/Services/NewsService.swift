//
//  NewsService.swift
//  GuideStreamTV
//
//  Aggregates the latest news headlines from NewsAPI.org. Fetches two
//  endpoints in parallel:
//    * Top headlines by country (localised to the device region)
//    * Major US TV news sources (US users only — CNN, Fox, CBS, ABC, NBC, MSNBC)
//
//  Each article is mapped to the existing `NewsStream` model so HomeView
//  requires no changes. Outlet-based fallback web URLs provide deeplink
//  targets when no streaming provider is attached.
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
    /// Canonical article URL on the publisher's site. Used to open the
    /// original story in Safari when the user taps a news item — news
    /// articles aren't streaming titles, so we can't resolve them via
    /// Watchmode/TMDB.
    let articleUrl: String?

    /// When `providerName` is nil (common for broadcast networks like Fox,
    /// CBS, ABC, NBC that don't have SVOD providers), fall back to the
    /// outlet's live-stream URL so the tile still has a deeplink target.
    var fallbackWebURL: String? {
        let key = outlet.lowercased()
        if key.contains("fox news")    { return "https://www.foxnews.com/video/5614640629001" }
        if key.contains("cbs news")    { return "https://www.cbsnews.com/live" }
        if key.contains("abc news")    { return "https://abcnews.go.com/Live" }
        if key.contains("nbc news")    { return "https://www.nbcnews.com/now" }
        if key.contains("cnn")         { return "https://www.cnn.com/live-tv" }
        if key.contains("msnbc")       { return "https://www.msnbc.com/live-video" }
        if key.contains("bbc")         { return "https://www.bbc.co.uk/news/av/live" }
        if key.contains("reuters")     { return "https://www.reuters.com/video/live" }
        if key.contains("al jazeera")  { return "https://www.aljazeera.com/live" }
        if key.contains("bloomberg")   { return "https://www.bloomberg.com/live" }
        if key.contains("sky news")    { return "https://news.sky.com/watch-live" }
        if key.contains("cbc")         { return "https://www.cbc.ca/player/live/1" }
        return nil
    }
}

// MARK: - Decodable NewsAPI models

private nonisolated struct NewsAPIArticle: Decodable, Sendable {
    let source: NewsAPISource
    let title: String
    let description: String?
    let url: String
    let urlToImage: String?
    let publishedAt: String
}

private nonisolated struct NewsAPISource: Decodable, Sendable {
    let id: String?
    let name: String
}

private nonisolated struct NewsAPIResponse: Decodable, Sendable {
    let articles: [NewsAPIArticle]
}

// MARK: - Service

@MainActor
final class NewsService {
    static let shared = NewsService()
    private init() {}

    private let newsApiKey = "ee2ec473cbe7442ea03c53c505ef6b65"

    /// Returns up to `limit` of the freshest news headlines, localised to
    /// the device's country. US users also get a parallel fetch from the
    /// major cable/broadcast sources (CNN, Fox, CBS, ABC, NBC, MSNBC).
    func fetchTopNewsStreams(limit: Int = 10) async -> [NewsStream] {
        let regionCode = Locale.current.region?.identifier ?? "US"
        let countryParam = regionCode.lowercased()
        let isUS = regionCode == "US"

        // Build source list based on region.
        // US: major cable/broadcast networks.
        // International: BBC, Reuters, Al Jazeera, Bloomberg —
        // all available on NewsAPI free tier globally.
        let sourcesForRegion: String = {
            switch regionCode {
            case "US":
                return "cnn,fox-news,cbs-news,abc-news,nbc-news,msnbc"
            case "GB":
                return "bbc-news,sky-news,the-guardian-uk,independent"
            case "CA":
                return "cbc-news,global-news"
            case "AU":
                return "abc-news-au"
            default:
                // Universal fallback — works globally on free tier
                return "bbc-news,reuters,al-jazeera-english,bloomberg,cnn"
            }
        }()

        // Always use the sources endpoint (works on free tier globally).
        // Additionally fetch country headlines for US users as a supplement.
        async let sourcesCall = try? fetchHeadlines(sources: sourcesForRegion)
        async let countryCall: [NewsAPIArticle]? = isUS
            ? (try? fetchHeadlines(country: countryParam))
            : nil

        let (sourceArticles, countryArticles) = await (sourcesCall, countryCall)

        // Sources feed is primary; country feed supplements for US users.
        let combined = (sourceArticles ?? []) + (countryArticles ?? [])

        var seen: Set<String> = []
        let unique = combined.filter { seen.insert($0.url).inserted }

        let isoParser = ISO8601DateFormatter()
        isoParser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let news: [NewsStream] = unique.map { article in
            let date = isoParser.date(from: article.publishedAt)
                ?? ISO8601DateFormatter().date(from: article.publishedAt)
            return NewsStream(
                id: article.url.hashValue,
                title: article.title,
                outlet: article.source.name,
                posterUrl: article.urlToImage,
                backdropUrl: article.urlToImage,
                overview: article.description,
                isTV: false,
                publishedAt: date,
                providerName: Self.providerForOutlet(article.source.name),
                articleUrl: article.url
            )
        }

        return Array(
            news.sorted { a, b in
                switch (a.publishedAt, b.publishedAt) {
                case let (l?, r?): return l > r
                case (_?, nil):    return true
                case (nil, _?):    return false
                default:           return a.title < b.title
                }
            }.prefix(limit)
        )
    }

    // MARK: - Outlet mapping

    /// Maps a NewsAPI source name to a recognised outlet badge string.
    /// Returns `nil` for outlets that aren't a known broadcast/cable
    /// network so the UI shows the source name directly.
    private static func providerForOutlet(_ name: String) -> String? {
        let key = name.lowercased()
        if key.contains("fox news")   { return "Fox News" }
        if key.contains("cbs news")   { return "CBS News" }
        if key.contains("abc news")   { return "ABC News" }
        if key.contains("nbc news")   { return "NBC News" }
        if key.contains("cnn")        { return "CNN" }
        if key.contains("msnbc")      { return "MSNBC" }
        if key.contains("bloomberg")  { return "Bloomberg" }
        if key.contains("bbc")        { return "BBC News" }
        if key.contains("reuters")    { return "Reuters" }
        if key.contains("al jazeera") { return "Al Jazeera" }
        if key.contains("sky news")   { return "Sky News" }
        if key.contains("cbc")        { return "CBC News" }
        if key.contains("guardian")   { return "The Guardian" }
        return nil
    }

    // MARK: - Networking

    private func fetchHeadlines(country: String) async throws -> [NewsAPIArticle] {
        let urlString = "https://newsapi.org/v2/top-headlines"
            + "?country=\(country)"
            + "&category=general"
            + "&pageSize=10"
            + "&apiKey=\(newsApiKey)"
        return try await fetchArticles(urlString)
    }

    private func fetchHeadlines(sources: String) async throws -> [NewsAPIArticle] {
        let urlString = "https://newsapi.org/v2/top-headlines"
            + "?sources=\(sources)"
            + "&pageSize=10"
            + "&apiKey=\(newsApiKey)"
        return try await fetchArticles(urlString)
    }

    private func fetchArticles(_ urlString: String) async throws -> [NewsAPIArticle] {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let envelope = try JSONDecoder().decode(NewsAPIResponse.self, from: data)
        return envelope.articles
    }
}

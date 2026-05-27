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

    var id: String { "\(sourceId)-\(format ?? "")-\(region ?? "")" }

    enum CodingKeys: String, CodingKey {
        case sourceId = "source_id"
        case name, type, region, format
        case iosUrl = "ios_url"
        case androidUrl = "android_url"
        case webUrl = "web_url"
        case endDate = "end_date"
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

    /// Fetches source expiry dates for TMDB ids from the user's watch list and returns
    /// titles that expire within 30 days.
    func getExpiringTitles(
        tmdbIds: [Int]
    ) async -> [(tmdbId: Int, title: String, daysLeft: Int, sourceId: String)] {
        var results: [(Int, String, Int, String)] = []
        let calendar = Calendar.current
        let now = Date()

        await withTaskGroup(of: (Int, String, Int, String)?.self) { group in
            for tmdbId in tmdbIds.prefix(10) {
                group.addTask {
                    guard let wmId = try? await WatchmodeService.shared.watchmodeId(forTMDBId: tmdbId, isTV: true),
                          let detail = try? await WatchmodeService.shared.titleDetail(titleId: wmId),
                          let sources = detail.sources
                    else { return nil }

                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withFullDate]

                    for source in sources {
                        guard let endStr = source.endDate,
                              let endDate = formatter.date(from: endStr)
                        else { continue }
                        let days = calendar.dateComponents([.day], from: now, to: endDate).day ?? 999
                        if days >= 0 && days <= 30 {
                            return (tmdbId, detail.title ?? "Unknown", days, source.name)
                        }
                    }
                    return nil
                }
            }
            for await result in group {
                if let r = result { results.append(r) }
            }
        }
        return results.sorted { $0.2 < $1.2 }
    }

    /// Fetches a title's metadata + all per-source watch links.
    ///
    /// Watchmode's title details live at `/v1/title/{id}/details/`. The bare
    /// `/v1/title/{id}/` path returns `400 Invalid method.`, which silently
    /// killed every "Watch on …" deeplink resolution. `append_to_response=sources`
    /// inlines the per-streaming-service URLs we need to open the right title
    /// inside Netflix / Max / Prime / etc.
    func titleDetail(titleId: String) async throws -> WatchmodeTitleDetail {
        let urlString = "https://api.watchmode.com/v1/title/\(titleId)/details/?apiKey=\(apiKey)&append_to_response=sources"
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

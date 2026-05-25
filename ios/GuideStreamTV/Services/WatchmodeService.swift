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

    var id: String { "\(sourceId)-\(format ?? "")-\(region ?? "")" }

    enum CodingKeys: String, CodingKey {
        case sourceId = "source_id"
        case name, type, region, format
        case iosUrl = "ios_url"
        case androidUrl = "android_url"
        case webUrl = "web_url"
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

    func titleDetail(titleId: String) async throws -> WatchmodeTitleDetail {
        let urlString = "https://api.watchmode.com/v1/title/\(titleId)/?apiKey=\(apiKey)&append_to_response=sources"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
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

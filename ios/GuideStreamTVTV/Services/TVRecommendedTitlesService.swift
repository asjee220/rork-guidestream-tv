//
//  TVRecommendedTitlesService.swift
//  GuideStreamTVTV
//
//  tvOS client for the `recommend_titles` Supabase edge function, which backs
//  the "Recommended for You" home rail. Mirrors the iOS
//  RecommendedTitlesService exactly — same request, same decoding — so all
//  three clients get the same ranking from the same server-side scorer.
//
//  Uses a plain URLSession POST with the anon key rather than the Supabase
//  functions client, matching TVWatchmodeResolver's sibling pattern and the
//  edge function's verify_jwt=false deployment.
//

import Foundation

nonisolated struct TVRecommendedTitle: Decodable, Sendable, Identifiable {
    let tmdbId: Int
    let mediaType: String
    let title: String
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let matchPercentage: Int

    var id: String { "\(mediaType):\(tmdbId)" }
    var isTV: Bool { mediaType == "tv" }

    var posterUrl: String? {
        guard let posterPath, !posterPath.isEmpty else { return nil }
        return "https://image.tmdb.org/t/p/w500\(posterPath)"
    }

    var backdropUrl: String? {
        guard let backdropPath, !backdropPath.isEmpty else { return nil }
        return "https://image.tmdb.org/t/p/w1280\(backdropPath)"
    }

    enum CodingKeys: String, CodingKey {
        case tmdbId = "tmdb_id"
        case mediaType = "media_type"
        case title
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
        case matchPercentage = "match_percentage"
    }
}

nonisolated enum TVRecommendedTitlesService {

    private struct Response: Decodable {
        let items: [TVRecommendedTitle]
    }

    /// - Returns: the ranked titles, or an empty array on any failure. The rail
    ///   is additive and must never be able to break the Home screen.
    static func fetch(
        userId: String?,
        deviceId: String,
        subscribedServices: [String],
        limit: Int = 20
    ) async -> [TVRecommendedTitle] {
        guard !subscribedServices.isEmpty else { return [] }

        let base = TVSupabaseConfig.url.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: "\(base)/functions/v1/recommend_titles") else { return [] }

        var body: [String: Any] = [
            "subscribedServices": subscribedServices,
            "limit": limit
        ]
        if let userId, !userId.isEmpty {
            body["userId"] = userId
        } else {
            body["deviceId"] = deviceId
        }
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(TVSupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(TVSupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            return try JSONDecoder().decode(Response.self, from: data).items
        } catch {
            return []
        }
    }
}

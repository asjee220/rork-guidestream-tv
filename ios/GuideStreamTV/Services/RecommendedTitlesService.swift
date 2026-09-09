//
//  RecommendedTitlesService.swift
//  GuideStreamTV
//
//  Client for the `recommend_titles` Supabase edge function, which backs the
//  "Recommended for You" home rail. Companion to RecommendedCreatorsService —
//  same shape, same reasoning: the scorer lives on the server so iOS, tvOS and
//  Android rank identically and the algorithm cannot drift between platforms.
//
//  The server reads the signals directly (watchlist, likes, watched, release
//  reminders, trailer engagement, browse events, favourite teams, followed
//  creators), so this client sends only identity and the subscribed-service
//  set — it never assembles a taste profile itself.
//
//  Freshness is the server's job too. It keys a cache on a fingerprint of the
//  owner's signals, so calling this on every Home appearance is cheap: an
//  unchanged signal set returns the cached rail with no TMDB calls, and saving
//  a title or liking a trailer rebuilds it on the very next call. That is what
//  makes the rail "update when the signals change" without any client polling.
//

import Foundation

/// One recommended title as returned by `recommend_titles`.
nonisolated struct RecommendedTitle: Decodable, Sendable, Identifiable {
    let tmdbId: Int
    let mediaType: String
    let title: String
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let matchPercentage: Int

    var id: String { "\(mediaType):\(tmdbId)" }
    var isTV: Bool { mediaType == "tv" }

    /// Full TMDB poster URL at the same width the other home rails request.
    var posterUrl: String? {
        guard let posterPath, !posterPath.isEmpty else { return nil }
        return "https://image.tmdb.org/t/p/w500\(posterPath)"
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

nonisolated enum RecommendedTitlesService {

    private struct Response: Decodable {
        let items: [RecommendedTitle]
        let cached: Bool?
        let seedCount: Int?
        let reason: String?

        enum CodingKeys: String, CodingKey {
            case items, cached, reason
            case seedCount = "seed_count"
        }
    }

    /// Fetches the recommended rail for the current viewer.
    ///
    /// - Parameters:
    ///   - userId: Supabase auth uuid, or nil for a guest.
    ///   - deviceId: Device identifier, used as the owner when signed out.
    ///   - subscribedServices: The viewer's saved services. The server filters
    ///     every recommendation to these, so an empty set legitimately returns
    ///     an empty rail rather than titles the viewer cannot watch.
    ///   - limit: Maximum rail length.
    /// - Returns: The ranked titles, `[]` when the server genuinely has no
    ///   recommendations, and **`nil` when the call failed** — a non-200, a
    ///   decode error, or a cancelled request.
    ///
    ///   The two used to be the same value, and the caller assigned it either
    ///   way. A pull-to-refresh that got cancelled mid-flight therefore wiped
    ///   a rail that was already on screen (GUI-98 follow-up). Failure has to be
    ///   distinguishable from emptiness for the caller to keep what it has.
    static func fetch(
        userId: String?,
        deviceId: String,
        subscribedServices: [String],
        limit: Int = 20
    ) async -> [RecommendedTitle]? {
        guard !subscribedServices.isEmpty else { return [] }

        let base = SupabaseConfig.url.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: "\(base)/functions/v1/recommend_titles") else { return nil }

        var body: [String: Any] = [
            "subscribedServices": subscribedServices,
            "limit": limit
        ]
        if let userId, !userId.isEmpty {
            body["userId"] = userId
        } else {
            body["deviceId"] = deviceId
        }
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            return decoded.items
        } catch {
            return nil
        }
    }
}

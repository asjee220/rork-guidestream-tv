//
//  TheTVDBService.swift
//  GuideStreamTV
//

import Foundation

// MARK: - Models

nonisolated struct TVDBEpisode: Decodable, Sendable, Identifiable {
    let id: Int
    let seriesId: Int
    let name: String?
    let aired: String?
    let runtime: Int?
    let overview: String?
    let image: String?
    let seasonNumber: Int?
    let episodeNumber: Int?

    /// Parses the `aired` string ("YYYY-MM-DD") as UTC midnight.
    var airDate: Date? {
        guard let aired else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: aired)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, aired, runtime, overview, image
        case seriesId
        case seasonNumber
        case episodeNumber = "number"
    }
}

nonisolated struct TVDBSeriesExtended: Decodable, Sendable {
    let id: Int
    let name: String?
    let nextAired: String?
    let lastAired: String?
    let status: TVDBStatus?
}

nonisolated struct TVDBStatus: Decodable, Sendable {
    let name: String?
}

nonisolated struct TVDBRemoteIDLookup: Decodable, Sendable {
    let id: Int
    let type: String
}

nonisolated struct TVDBRemoteIDMatch: Decodable, Sendable {
    let series: TVDBRemoteIDLookup?
    let movie: TVDBRemoteIDLookup?
}

// MARK: - Errors

enum TVDBError: Error, LocalizedError, Sendable {
    case badURL
    case loginFailed
    case transport
    case http(statusCode: Int)
    case empty

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "Invalid TVDB URL."
        case .loginFailed:
            return "TVDB authentication failed. Check the API key."
        case .transport:
            return "Network error contacting TVDB."
        case .http(let code):
            return "TVDB returned HTTP \(code)."
        case .empty:
            return "TVDB returned an empty response."
        }
    }
}

// MARK: - Private Models

private nonisolated struct TVDBEnvelope<T: Decodable>: Decodable, Sendable {
    let status: String?
    let data: T?
}

private nonisolated struct TVDBLoginEnvelope: Decodable, Sendable {
    struct LoginData: Decodable, Sendable {
        let token: String
    }
    let status: String?
    let data: LoginData?
}

private nonisolated struct TVDBEpisodesPage: Decodable, Sendable {
    let episodes: [TVDBEpisode]
}

private struct CachedToken: Sendable {
    let jwt: String
    let expiresAt: Date
}

// MARK: - Service

/// Higher-fidelity episode air-date data from TheTVDB.
/// Drives the new-episode push notification pipeline.
@MainActor
final class TheTVDBService {
    static let shared = TheTVDBService()

    private let apiKey = "REPLACE_WITH_TVDB_V4_API_KEY"
    private let base = "https://api4.thetvdb.com/v4"

    private init() {}

    // MARK: Token Cache

    /// Reads or writes both the JWT and its expiry atomically.
    /// Returns nil when no token is cached or the cached token has expired.
    private var cached: CachedToken? {
        get {
            guard let jwt = UserDefaults.standard.string(forKey: "gs.tvdb.jwt"),
                  let expiresAt = UserDefaults.standard.object(forKey: "gs.tvdb.jwt.expiresAt") as? Date
            else { return nil }
            guard expiresAt > Date() else {
                UserDefaults.standard.removeObject(forKey: "gs.tvdb.jwt")
                UserDefaults.standard.removeObject(forKey: "gs.tvdb.jwt.expiresAt")
                return nil
            }
            return CachedToken(jwt: jwt, expiresAt: expiresAt)
        }
        set {
            if let token = newValue {
                UserDefaults.standard.set(token.jwt, forKey: "gs.tvdb.jwt")
                UserDefaults.standard.set(token.expiresAt, forKey: "gs.tvdb.jwt.expiresAt")
            } else {
                UserDefaults.standard.removeObject(forKey: "gs.tvdb.jwt")
                UserDefaults.standard.removeObject(forKey: "gs.tvdb.jwt.expiresAt")
            }
        }
    }

    /// Returns a valid JWT token — either from cache or by performing a fresh login.
    private func validToken() async throws -> String {
        if let jwt = cached?.jwt { return jwt }
        return try await login()
    }

    /// POST /login with the API key. Stores the JWT with a 25-day expiry.
    private func login() async throws -> String {
        let urlString = "\(base)/login"
        guard let url = URL(string: urlString) else { throw TVDBError.badURL }

        let body: [String: String] = ["apikey": apiKey]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = try JSONEncoder().encode(body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw TVDBError.transport }
        guard (200..<300).contains(http.statusCode) else {
            throw TVDBError.loginFailed
        }

        let envelope = try JSONDecoder().decode(TVDBLoginEnvelope.self, from: data)
        guard let token = envelope.data?.token else { throw TVDBError.loginFailed }

        let expiresAt = Calendar.current.date(byAdding: .day, value: 25, to: Date())
            ?? Date().addingTimeInterval(25 * 86_400)
        cached = CachedToken(jwt: token, expiresAt: expiresAt)
        return token
    }

    // MARK: HTTP Plumbing

    /// Generic GET request with Bearer auth. Automatically retries once on 401
    /// by clearing the cached token and re-authenticating.
    private func get<T: Decodable>(path: String) async throws -> T {
        let token = try await validToken()
        let urlString = "\(base)\(path)"
        guard let url = URL(string: urlString) else { throw TVDBError.badURL }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw TVDBError.transport }

        if http.statusCode == 401 {
            // Token expired or invalid — clear cache and retry once.
            cached = nil
            let newToken = try await login()
            var retryReq = URLRequest(url: url)
            retryReq.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            retryReq.setValue("application/json", forHTTPHeaderField: "Accept")
            retryReq.timeoutInterval = 12
            let (retryData, retryResponse) = try await URLSession.shared.data(for: retryReq)
            guard let retryHttp = retryResponse as? HTTPURLResponse else { throw TVDBError.transport }
            guard (200..<300).contains(retryHttp.statusCode) else {
                throw TVDBError.http(statusCode: retryHttp.statusCode)
            }
            return try decodeEnvelope(retryData)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw TVDBError.http(statusCode: http.statusCode)
        }

        return try decodeEnvelope(data)
    }

    /// Unwraps the TVDB response envelope and returns the `data` payload.
    private func decodeEnvelope<T: Decodable>(_ data: Data) throws -> T {
        let envelope = try JSONDecoder().decode(TVDBEnvelope<T>.self, from: data)
        guard let result = envelope.data else { throw TVDBError.empty }
        return result
    }

    // MARK: Public API

    /// Maps a TMDB id to the corresponding TVDB series id.
    /// Uses the `/search/remoteid` endpoint. Returns nil when no TV series match exists.
    func tvdbSeriesId(forTMDBId tmdbId: Int) async throws -> Int? {
        let matches: [TVDBRemoteIDMatch] = try await get(path: "/search/remoteid/\(tmdbId)")
        return matches.first?.series?.id
    }

    /// Fetches the extended series record, including `nextAired` / `lastAired` / `status`.
    func seriesExtended(_ seriesId: Int) async throws -> TVDBSeriesExtended {
        try await get(path: "/series/\(seriesId)/extended")
    }

    /// Returns the next upcoming episode whose air date is today or later (UTC).
    func nextEpisode(seriesId: Int) async throws -> TVDBEpisode? {
        let page: TVDBEpisodesPage = try await get(path: "/series/\(seriesId)/episodes/default?page=0")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let todayStart = calendar.startOfDay(for: Date())
        return page.episodes
            .filter { episode in
                guard let date = episode.airDate else { return false }
                return date >= todayStart
            }
            .sorted { ($0.airDate ?? .distantFuture) < ($1.airDate ?? .distantFuture) }
            .first
    }

    /// Looks up a specific episode by season and episode number.
    func episode(seriesId: Int, season: Int, episode: Int) async throws -> TVDBEpisode? {
        let page: TVDBEpisodesPage = try await get(path: "/series/\(seriesId)/episodes/default?season=\(season)")
        return page.episodes.first { $0.episodeNumber == episode }
    }
}

//
//  WatchmodeResolveService.swift
//  GuideStreamTV
//
//  Client for the `watchmode_resolve` Supabase edge function (deployed at
//  version 7 with verify_jwt=false, so the anon key is sufficient and no user
//  session is needed). Routes every Watchmode call through the server so the
//  hardcoded Watchmode API key never ships in the app binary — mirrors the
//  pattern already used by tvOS (TVWatchmodeResolver) and Android.
//
//  The edge function mirrors the old client-side pipeline (Watchmode id lookup,
//  title detail, TMDB provider tiebreaker, network signals, subscribed-first
//  priority, US filter, dedupe, rank) and returns the resolved primary source,
//  ranked US source list, overview, provider-name fallback, and — for episode
//  queries — a single episode source narrowed to the hinted or primary service.
//
//  Source objects use the same snake_case wire shape as Watchmode's direct
//  API, so `WatchmodeSource` is reused for decoding rather than inventing a
//  parallel model.
//

import Foundation

nonisolated enum WatchmodeResolveService {

    /// Response envelope from the `watchmode_resolve` edge function.
    struct Response: Decodable, Sendable {
        let primarySource: WatchmodeSource?
        let usSources: [WatchmodeSource]
        let overview: String?
        let providerNameFallback: String?
        let episodeSource: WatchmodeSource?
        let resolvedMediaType: String?

        enum CodingKeys: String, CodingKey {
            case primarySource = "primary_source"
            case usSources = "us_sources"
            case overview
            case providerNameFallback = "provider_name_fallback"
            case episodeSource = "episode_source"
            case resolvedMediaType = "resolved_media_type"
        }
    }

    /// NSCache wrapper so a struct value can be stored in NSCache.
    private final class ResponseBox: NSObject {
        let response: Response
        init(_ response: Response) { self.response = response }
    }

    /// In-memory cache for episode-level lookups so reopening the same
    /// episode spends no additional paid Watchmode call. The edge function
    /// has no server-side cache. Keyed by tmdbId, season, episode, and hint.
    private static let episodeCache = NSCache<NSString, ResponseBox>()

    /// Resolves streaming sources for a title via the `watchmode_resolve`
    /// edge function.
    ///
    /// - Parameters:
    ///   - tmdbId: The TMDB id of the title.
    ///   - isTV: Whether the id is a TV series. When nil the server probes
    ///     TV then movie and reports what it found in `resolvedMediaType`.
    ///   - season: Season number for episode-level lookups.
    ///   - episode: Episode number for episode-level lookups.
    ///   - episodePlatformHint: A service name to prioritise for episode
    ///     source resolution. The server narrows `episodeSource` to this
    ///     service when present.
    ///   - subscribedServices: Service names for subscribed-first priority.
    /// - Returns: The decoded `Response` on any HTTP 200 (including a
    ///   response with empty `usSources`), or `nil` only on transport
    ///   failure, non-200 status, or decode failure so callers can
    ///   distinguish a Supabase outage from an empty result.
    static func resolve(
        tmdbId: Int,
        isTV: Bool? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        episodePlatformHint: String? = nil,
        sourceId: Int? = nil,
        subscribedServices: [String] = []
    ) async -> Response? {
        // Episode-level cache check — only for episode lookups (both
        // season and episode provided). sourceId is included in the key
        // so a pinned lookup never reads back a cached unpinned response.
        let isEpisodeLookup = season != nil && episode != nil
        let cacheKey = "\(tmdbId)-\(season ?? -1)-\(episode ?? -1)-\(episodePlatformHint ?? "")-\(sourceId ?? -1)" as NSString
        if isEpisodeLookup,
           let cached = episodeCache.object(forKey: cacheKey) {
            return cached.response
        }

        let base = SupabaseConfig.url.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: "\(base)/functions/v1/watchmode_resolve") else { return nil }

        // Build body, omitting nil parameters rather than sending nulls.
        var body: [String: Any] = ["tmdbId": tmdbId]
        if let isTV { body["isTV"] = isTV }
        if let season { body["season"] = season }
        if let episode { body["episode"] = episode }
        if let episodePlatformHint { body["episodePlatformHint"] = episodePlatformHint }
        if let sourceId { body["sourceId"] = sourceId }
        if !subscribedServices.isEmpty { body["subscribedServices"] = subscribedServices }

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = httpBody

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            return nil
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return nil }

        // Cache episode-level responses.
        if isEpisodeLookup {
            episodeCache.setObject(ResponseBox(decoded), forKey: cacheKey)
        }

        return decoded
    }
}

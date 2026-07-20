//
//  TVWatchmodeResolver.swift
//  GuideStreamTVTV
//
//  Calls the "watchmode_resolve" Supabase edge function to look up streaming
//  sources, overviews, and per-episode deep links. Results are cached in
//  memory for the session so re-opening the same title doesn't re-hit the
//  function.
//

import Foundation
import Supabase

@MainActor
@Observable
final class TVWatchmodeResolver {
    static let shared = TVWatchmodeResolver()

    // MARK: - Decodable response shapes

    nonisolated struct TVResolvedSource: Decodable {
        let sourceId: Int
        let name: String
        let type: String
        let region: String?
        let webUrl: String?
        let iosUrl: String?
        let tvosUrl: String?
        let format: String?
        let price: Double?

        enum CodingKeys: String, CodingKey {
            case sourceId = "source_id"
            case name, type, region
            case webUrl = "web_url"
            case iosUrl = "ios_url"
            case tvosUrl = "tvos_url"
            case format
            case price = "price"
        }
    }

    nonisolated struct TVResolvedStreaming: Decodable {
        let primarySource: TVResolvedSource?
        let usSources: [TVResolvedSource]
        let overview: String?
        let providerNameFallback: String?
        let episodeSource: TVResolvedSource?
        /// "tv" or "movie" — returned by the watchmode_resolve edge function
        /// (v7+) on every response path. Present when the backend probed the
        /// media type; nil if an older cached response lacked the field.
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

    // MARK: - Cache

    private var cache: [String: TVResolvedStreaming] = [:]

    private init() {}

    // MARK: - Resolve

    func resolve(
        tmdbId: Int,
        isTV: Bool?,
        season: Int?,
        episode: Int?,
        subscribedServices: [String] = [],
        episodePlatformHint: String? = nil
    ) async -> TVResolvedStreaming? {
        // Include the media-type token and the platform hint in the cache key
        // so an unknown-type resolve cannot collide with a later known-type
        // resolve for the same tmdbId, season and episode, and a
        // selected-service resolve doesn't collide with the default resolve.
        let isTVToken: String = {
            guard let isTV else { return "unknown" }
            return isTV ? "tv" : "movie"
        }()
        let cacheKey = "\(tmdbId)-\(isTVToken)-\(season ?? 0)-\(episode ?? 0)-\(episodePlatformHint ?? "")"
        if let cached = cache[cacheKey] { return cached }

        let body = ResolveBody(
            tmdbId: tmdbId,
            isTV: isTV,
            season: season,
            episode: episode,
            subscribedServices: subscribedServices,
            episodePlatformHint: episodePlatformHint
        )

        do {
            let result: TVResolvedStreaming = try await TVSupabaseManager.shared.client.functions.invoke(
                "watchmode_resolve",
                options: FunctionInvokeOptions(body: body)
            )
            cache[cacheKey] = result
            return result
        } catch {
            return nil
        }
    }
}

// MARK: - Request body

// Swift's synthesized Encodable omits nil optionals, so a nil `isTV` is
// dropped from the JSON body entirely and the edge function (v7+) treats
// the request as an unknown media type, probing Watchmode by tmdb_tv_id
// then tmdb_movie_id with strict type matching.
private struct ResolveBody: Encodable {
    let tmdbId: Int
    let isTV: Bool?
    let season: Int?
    let episode: Int?
    let subscribedServices: [String]
    let episodePlatformHint: String?

    enum CodingKeys: String, CodingKey {
        case tmdbId, isTV, season, episode, subscribedServices, episodePlatformHint
    }
}

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

        enum CodingKeys: String, CodingKey {
            case primarySource = "primary_source"
            case usSources = "us_sources"
            case overview
            case providerNameFallback = "provider_name_fallback"
            case episodeSource = "episode_source"
        }
    }

    // MARK: - Cache

    private var cache: [String: TVResolvedStreaming] = [:]

    private init() {}

    // MARK: - Resolve

    func resolve(
        tmdbId: Int,
        isTV: Bool,
        season: Int?,
        episode: Int?,
        subscribedServices: [String] = [],
        episodePlatformHint: String? = nil
    ) async -> TVResolvedStreaming? {
        // Include the platform hint in the cache key so a selected-service
        // resolve doesn't collide with the default resolve for the same episode.
        let cacheKey = "\(tmdbId)-\(season ?? 0)-\(episode ?? 0)-\(episodePlatformHint ?? "")"
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

private struct ResolveBody: Encodable {
    let tmdbId: Int
    let isTV: Bool
    let season: Int?
    let episode: Int?
    let subscribedServices: [String]
    let episodePlatformHint: String?

    enum CodingKeys: String, CodingKey {
        case tmdbId, isTV, season, episode, subscribedServices, episodePlatformHint
    }
}

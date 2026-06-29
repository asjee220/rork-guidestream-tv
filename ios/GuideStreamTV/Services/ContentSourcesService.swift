//
//  ContentSourcesService.swift
//  GuideStreamTV
//
//  Fetches from public.content_sources and public.live_status tables.
//  Mirrors the existing SupabaseManager fetch patterns.
//

import Foundation
import Supabase

@MainActor
final class ContentSourcesService {
    static let shared = ContentSourcesService()

    private var client: SupabaseClient { SupabaseManager.shared.client }

    private init() {}

    // MARK: - Fetch all content sources

    /// Returns all content_sources rows, optionally filtered by source_type.
    func fetchSources(sourceType: String? = nil) async throws -> [ContentSource] {
        var query = client.from("content_sources").select()
        if let type = sourceType {
            query = query.eq("source_type", value: type)
        }
        let rows: [ContentSource] = try await query
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows
    }

    /// Returns content_sources rows matching a search term against display_name.
    func searchSources(query: String, sourceType: String? = nil) async throws -> [ContentSource] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var dbQuery = client.from("content_sources")
            .select()
            .ilike("display_name", value: "%\(trimmed)%")
        if let type = sourceType {
            dbQuery = dbQuery.eq("source_type", value: type)
        }
        let rows: [ContentSource] = try await dbQuery
            .order("created_at", ascending: false)
            .limit(30)
            .execute()
            .value
        return rows
    }

    // MARK: - Live creator search (YouTube + Twitch via Functions worker)

    /// Response wrapper from the `/search/creators` worker endpoint.
    private struct CreatorSearchResponse: Decodable {
        let ok: Bool
        let results: [ContentSource]
    }

    /// Searches YouTube and/or Twitch live via the backend worker, which also
    /// persists discovered creators into content_sources. Returns normalized
    /// ContentSource rows. Returns [] (never throws) when the functions URL is
    /// unconfigured or the request fails, so the UI degrades to local results.
    /// - Parameter type: "all", "youtube", or "twitch".
    func searchCreatorsLive(query: String, type: String = "all") async -> [ContentSource] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let base = Config.EXPO_PUBLIC_RORK_FUNCTIONS_URL.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty,
              var components = URLComponents(string: base.hasSuffix("/") ? base + "search/creators" : base + "/search/creators")
        else { return [] }
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "type", value: type)
        ]
        guard let url = components.url else { return [] }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            let decoded = try JSONDecoder().decode(CreatorSearchResponse.self, from: data)
            return decoded.results
        } catch {
            print("[ContentSources] live search failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Fetch live status

    /// Returns live_status rows for the given title_ids.
    func fetchLiveStatus(for titleIds: [String]) async throws -> [LiveStatus] {
        guard !titleIds.isEmpty else { return [] }
        let rows: [LiveStatus] = try await client
            .from("live_status")
            .select()
            .in("title_id", values: titleIds)
            .execute()
            .value
        return rows
    }

    /// Returns live_status rows where is_live is true (all currently live channels).
    func fetchCurrentlyLive() async throws -> [LiveStatus] {
        let rows: [LiveStatus] = try await client
            .from("live_status")
            .select()
            .eq("is_live", value: true)
            .execute()
            .value
        return rows
    }

    // MARK: - Combined: discoverable creators

    /// Builds a merged list of content sources + live status for discovery/search.
    /// Live streamers are sorted to the top.
    func fetchDiscoverable(sourceType: String? = nil) async throws -> [DiscoverableCreator] {
        let s = try await fetchSources(sourceType: sourceType)

        // Fetch live status only for streamer types (twitch, kick)
        let liveIds = s.filter { SourceKind.from(titleId: $0.titleId).isLivestream }.map { $0.titleId }
        var liveMap: [String: LiveStatus] = [:]
        if !liveIds.isEmpty {
            let statuses = (try? await fetchLiveStatus(for: liveIds)) ?? []
            for status in statuses {
                liveMap[status.titleId] = status
            }
        }

        let results: [DiscoverableCreator] = s.map { source in
            let status = liveMap[source.titleId]
            return DiscoverableCreator(
                titleId: source.titleId,
                sourceType: source.sourceType,
                displayName: source.displayName,
                handle: source.handle,
                imageUrl: source.imageUrl,
                category: source.category,
                description: source.description,
                isLive: status?.isLive ?? false,
                streamTitle: status?.streamTitle,
                liveCategory: status?.category,
                viewerCount: status?.viewerCount,
                startedAt: status?.startedAt
            )
        }
        // Sort: live streamers first, then the rest by name
        return results.sorted { a, b in
            if a.isLive != b.isLive { return a.isLive }
            return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
        }
    }

    // MARK: - Source image URLs by title_id

    /// Returns a dictionary mapping title_id → image_url for the given ids.
    /// Used as a poster fallback so non-TMDB creators always show an image
    /// even when new_episodes or user_streams rows lack a poster_url.
    func fetchSourceImages(for titleIds: [String]) async throws -> [String: String] {
        guard !titleIds.isEmpty else { return [:] }
        let rows: [ContentSource] = try await client
            .from("content_sources")
            .select()
            .in("title_id", values: titleIds)
            .execute()
            .value
        var map: [String: String] = [:]
        for row in rows {
            if let url = row.imageUrl, !url.isEmpty {
                map[row.titleId] = url
            }
        }
        return map
    }

    // MARK: - Follow-scoped upload fetch

    /// Returns recent uploads from new_episodes for the given followed creator
    /// title_ids, ordered by released_at descending. Returns [] when titleIds
    /// is empty. Used by the hero carousel to surface only content from creators
    /// the signed-in customer follows.
    func fetchRecentUploads(forTitleIds titleIds: [String], limit: Int = 12) async throws -> [NewEpisodeRow] {
        guard !titleIds.isEmpty else { return [] }
        let rows: [NewEpisodeRow] = try await client
            .from("new_episodes")
            .select()
            .in("title_id", values: titleIds)
            .order("released_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        return rows
    }

    // MARK: - Per-title episode fetch

    /// Returns new_episodes rows for a single creator title_id, ordered by
    /// released_at descending, limited to 30 rows. Used by CreatorDetailView
    /// to populate the "Recent uploads" / "Recent episodes" list.
    func fetchEpisodes(forTitleId titleId: String) async throws -> [NewEpisodeRow] {
        let rows: [NewEpisodeRow] = try await client
            .from("new_episodes")
            .select()
            .eq("title_id", value: titleId)
            .order("released_at", ascending: false)
            .limit(30)
            .execute()
            .value
        return rows
    }

    // MARK: - Recommended creators based on follows

    /// Returns creators (YouTube, podcasts, Twitch, Kick) recommended for the
    /// current user based on category overlap with their followed creators.
    ///
    /// Algorithm mirrors Top Picks for You: a match-percentage is computed from
    /// category similarity, clamped to 72–98%, and sorted highest-first.
    /// Already-followed creators are excluded. Returns at most 12 results.
    func fetchRecommendedCreators(forFollowedIds followedIds: [String]) async throws -> [(titleId: String, displayName: String, imageUrl: String?, sourceType: String, category: String?, matchPercentage: Int)] {
        guard !followedIds.isEmpty else { return [] }

        // Get followed creators' categories from content_sources.
        let followedSources: [ContentSource] = try await client
            .from("content_sources")
            .select()
            .in("title_id", values: followedIds)
            .execute()
            .value

        let followedCategories = Set(followedSources.compactMap { $0.category }.filter { !$0.isEmpty })
        // Normalise: split on commas/slashes/pipes so "Gaming, Tech" → ["Gaming", "Tech"]
        let followedTags: Set<String> = Set(followedCategories.flatMap { cat in
            cat.components(separatedBy: CharacterSet(charactersIn: ",/|")).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        })

        guard !followedTags.isEmpty else { return [] }

        // Fetch all creators (all source types — YouTube, podcast, Twitch, Kick).
        let allSources: [ContentSource] = try await client
            .from("content_sources")
            .select()
            .neq("source_type", value: "tmdb")
            .order("created_at", ascending: false)
            .limit(200)
            .execute()
            .value

        let followedSet = Set(followedIds)

        // Score each non-followed creator by category overlap.
        var scored: [(titleId: String, displayName: String, imageUrl: String?, sourceType: String, category: String?, matchPercentage: Int)] = []
        for source in allSources {
            guard !followedSet.contains(source.titleId) else { continue }
            let cat = source.category ?? ""
            let tags = cat.components(separatedBy: CharacterSet(charactersIn: ",/|")).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
            let overlap = tags.filter { followedTags.contains($0) }.count
            // Base score: how many followed categories does this creator share?
            // Map to 72–98% range using the same clamping as Top Picks.
            let overlapRatio = Double(overlap) / Double(max(1, followedTags.count))
            let rawScore = Int(overlapRatio * 100)
            let clamped = max(72, min(98, rawScore))
            scored.append((
                titleId: source.titleId,
                displayName: source.displayName,
                imageUrl: source.imageUrl,
                sourceType: source.sourceType,
                category: source.category,
                matchPercentage: clamped
            ))
        }

        // Sort by match percentage descending, then by display name for ties.
        scored.sort { a, b in
            if a.matchPercentage != b.matchPercentage { return a.matchPercentage > b.matchPercentage }
            return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
        }
        return Array(scored.prefix(12))
    }

    // MARK: - Realtime subscription for live_status

    /// Subscribe to live_status changes via Supabase Realtime using AnyAction.
    /// Calls `onChange` with the full list of currently-live rows whenever
    /// any live_status row is inserted, updated, or deleted.
    func subscribeToLiveStatus(onChange: @escaping @Sendable ([LiveStatus]) -> Void) {
        Task {
            let ch = client.channel("live-status-svc")
            let changes = ch.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "live_status"
            )
            await ch.subscribe()
            for await _ in changes {
                guard let live = try? await fetchCurrentlyLive() else { continue }
                onChange(live)
            }
        }
    }
}

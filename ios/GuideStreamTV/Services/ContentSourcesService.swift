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
                viewerCount: status?.viewerCount
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

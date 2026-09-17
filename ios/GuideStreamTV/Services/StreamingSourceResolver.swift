//
//  StreamingSourceResolver.swift
//
//  Centralized resolver that turns a TMDB id into the correct streaming
//  source. Previously combined Watchmode sources (US-filtered, ranked,
//  deduped) with a TMDB primary-provider tiebreaker entirely client-side,
//  shipping the Watchmode API key in the binary. Now delegates the entire
//  pipeline to the `watchmode_resolve` Supabase edge function, which mirrors
//  the old client logic server-side (Watchmode id lookup, title detail, TMDB
//  provider + network signals, subscribed-first priority, US filter, dedupe,
//  rank) and returns the resolved primary source, ranked US source list,
//  overview, and provider-name fallback.
//
//  Network-call architecture: the single edge function call executes inside a
//  Task.detached so it is immune to cancellation by the caller's lifecycle.
//  Selection, ranking, and filtering happen server-side.

import Foundation

// MARK: - Result type

nonisolated struct ResolvedStreaming: Sendable {
    /// The single best source chosen for the title (Watchmode source
    /// selected by the priority logic, or nil when Watchmode has no data).
    let primarySource: WatchmodeSource?

    /// The full US-region-filtered, deduped-by-name, ranked list — for
    /// surfaces that render a "Where to Watch" row of every service.
    let usSources: [WatchmodeSource]

    /// Set only when Watchmode returns no usable sources but TMDB has a
    /// watch-provider name. Callers use this as a label fallback.
    let providerNameFallback: String?

    /// Region codes where the title streams even though it has no US
    /// sources — drives the "Not available in the …" state.
    let availabilityRegions: [String]

    /// Watchmode plot overview, captured regardless of source resolution.
    let overview: String?

    static let empty = ResolvedStreaming(
        primarySource: nil,
        usSources: [],
        providerNameFallback: nil,
        availabilityRegions: [],
        overview: nil
    )
}

// MARK: - Resolver

nonisolated struct StreamingSourceResolver {
    static let shared = StreamingSourceResolver()

    // MARK: - Cache

    /// NSCache wrapper so the Sendable `ResolvedStreaming` value can be
    /// stored in NSCache (mirrors WatchmodeResolveService.ResponseBox).
    private final class ResolvedBox: NSObject {
        let value: ResolvedStreaming
        init(_ value: ResolvedStreaming) { self.value = value }
    }

    /// In-memory cache of resolved streaming data so reopening a title is
    /// instant — a hit returns immediately with no network call.
    ///
    /// Keyed by tmdbId, isTV, episodePlatformHint, region AND the user's
    /// subscribed services. The server's `selectPrimary` ranks subscribed
    /// services first, so the same title resolves to a different primary
    /// chip once the user changes their services in Profile. Leaving
    /// services out of the key (the pre-Sep-17 behaviour) served the stale
    /// chip until the app was relaunched.
    private static let resolveCache = NSCache<NSString, ResolvedBox>()

    /// Drops every cached resolve. Called when the subscribed-services set
    /// changes so no surface can hand back a primary chosen for the old
    /// set; the services-aware key below already prevents that on its own,
    /// this just keeps the cache from filling with dead entries.
    static func clearCache() {
        resolveCache.removeAllObjects()
    }

    // MARK: Public API

    /// Resolves streaming information for a title identified by TMDB id.
    ///
    /// All network calls execute inside a `Task.detached` so they cannot
    /// be cancelled by the caller's task lifecycle (fixes the -999
    /// "cancelled" error). The edge function handles US filtering, dedupe,
    /// ranking, and priority selection server-side.
    ///
    /// - Parameters:
    ///   - tmdbId: The TMDB id (tv or movie).
    ///   - isTV: Whether the id refers to a TV series.
    ///   - episodePlatformHint: An optional platform name for an episode,
    ///     used as the highest-priority match in the server's selection.
    /// - Returns: A `ResolvedStreaming` with the best available data.
    func resolve(
        tmdbId: Int,
        isTV: Bool,
        episodePlatformHint: String? = nil
    ) async -> ResolvedStreaming {
        // Snapshot the user's subscribed services on the main actor BEFORE
        // the cache lookup — they are part of the key. The resolver is a
        // nonisolated struct, so we hop to the main actor to read
        // AuthViewModel.shared.selectedServices. Set<String> is Sendable,
        // so this is safe to pass into the detached task.
        let subscribedServices = await MainActor.run { AuthViewModel.shared.selectedServices }
        let servicesKey = subscribedServices.sorted().joined(separator: ",")
        let region = DeviceLocale.current().region

        // Cache hit — return immediately without any network call.
        let cacheKey = "\(tmdbId)-\(isTV)-\(episodePlatformHint ?? "")-\(region)-[\(servicesKey)]" as NSString
        if let cached = Self.resolveCache.object(forKey: cacheKey) {
            return cached.value
        }

        // ── Single edge function call inside a detached task ──────────
        // This task has NO parent — it cannot be cancelled by view
        // re-renders, .task teardown, superseding startLoad, or sibling
        // async-let cancellation.
        let response = await Task.detached(priority: .userInitiated) { () -> WatchmodeResolveService.Response? in
            await WatchmodeResolveService.resolve(
                tmdbId: tmdbId,
                isTV: isTV,
                episodePlatformHint: episodePlatformHint,
                subscribedServices: Array(subscribedServices)
            )
        }.value

        // Transport failure / non-200 / decode failure → empty result so
        // callers degrade gracefully (same as the old Watchmode outage path).
        guard let response else { return .empty }

        // Map the server response into the unchanged ResolvedStreaming
        // contract. The server already applied US filter, dedupe, rank,
        // and priority selection — including the subscribed-first step and
        // the TMDB provider/network tiebreakers. providerNameFallback
        // preserves the old TMDB-only fallback when Watchmode had no
        // usable sources but TMDB knew a provider name.
        let resolved = ResolvedStreaming(
            primarySource: response.primarySource,
            usSources: response.usSources,
            providerNameFallback: response.providerNameFallback,
            availabilityRegions: response.availabilityRegions ?? [],
            overview: response.overview
        )

        // Write through on every successful resolve. The `.empty` transport-
        // failure return above stays uncached so a later call can retry.
        Self.resolveCache.setObject(ResolvedBox(resolved), forKey: cacheKey)
        return resolved
    }
}

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

    /// Watchmode plot overview, captured regardless of source resolution.
    let overview: String?

    static let empty = ResolvedStreaming(
        primarySource: nil,
        usSources: [],
        providerNameFallback: nil,
        overview: nil
    )
}

// MARK: - Resolver

nonisolated struct StreamingSourceResolver {
    static let shared = StreamingSourceResolver()

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
        // Snapshot the user's subscribed services on the main actor. The
        // resolver is a nonisolated struct, so we hop to the main actor to
        // read AuthViewModel.shared.selectedServices. Set<String> is Sendable,
        // so this is safe to pass into the detached task.
        let subscribedServices = await MainActor.run { AuthViewModel.shared.selectedServices }

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
        return ResolvedStreaming(
            primarySource: response.primarySource,
            usSources: response.usSources,
            providerNameFallback: response.providerNameFallback,
            overview: response.overview
        )
    }
}

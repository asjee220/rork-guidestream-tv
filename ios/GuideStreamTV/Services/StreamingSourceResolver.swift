//
//  StreamingSourceResolver.swift
//  GuideStreamTV
//
//  Centralized resolver that turns a TMDB id into the correct streaming
//  source — combining Watchmode sources (US-filtered, ranked, deduped)
//  with a TMDB primary-provider tiebreaker. Shared by all surfaces that
//  need to show a "Where to Watch" label or open a deeplink.
//
//  Network-call architecture: all four external fetches (Watchmode ID,
//  Watchmode detail, TMDB provider, TMDB network) execute inside a single
//  Task.detached so they are immune to cancellation by the caller's
//  lifecycle. Selection, ranking, and filtering are pure computation
//  that runs after the detached task returns.

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
    /// "cancelled" error). Selection, ranking, and filtering are pure
    /// computation that runs after the detached task returns.
    ///
    /// - Parameters:
    ///   - tmdbId: The TMDB id (tv or movie).
    ///   - isTV: Whether the id refers to a TV series.
    ///   - episodePlatformHint: An optional platform name for an episode,
    ///     used as the highest-priority match in step (1).
    /// - Returns: A `ResolvedStreaming` with the best available data.
    func resolve(
        tmdbId: Int,
        isTV: Bool,
        episodePlatformHint: String? = nil
    ) async -> ResolvedStreaming {
        // ── All network calls inside a single detached task ──────────
        // This task has NO parent — it cannot be cancelled by view
        // re-renders, .task teardown, superseding startLoad, or sibling
        // async-let cancellation.
        let fetched = await Task.detached(priority: .userInitiated) { () -> FetchBundle in
            var bundle = FetchBundle()

            // Watchmode ID
            do {
                if let id = try await WatchmodeService.shared.watchmodeId(forTMDBId: tmdbId, isTV: isTV) {
                    bundle.wmId = id
                }
            } catch {
            }

            // Watchmode title detail (only if we have an ID)
            if let wmId = bundle.wmId {
                do {
                    bundle.detail = try await WatchmodeService.shared.titleDetail(titleId: wmId)
                } catch {
                }
            }

            // TMDB primary watch provider (lower-priority tiebreaker)
            do {
                let provider = try await TMDBService.shared.getTopWatchProvider(tmdbId: tmdbId, isTV: isTV)
                if let name = provider?.providerName {
                    bundle.providerName = name
                }
            } catch {
            }

            // TMDB network (TV only — the originating network is the
            // strongest signal for a show's true home service)
            if isTV {
                do {
                    let tvDetail = try await TMDBService.shared.getTVDetail(tmdbId: tmdbId)
                    if let name = tvDetail.networks?.first?.name {
                        bundle.networkName = name
                    }
                } catch {
                }
            }

            return bundle
        }.value

        // ── Pure logic below — no more network calls ──────────────────

        // wmId failed or nil → TMDB-only fallback
        guard let _ = fetched.wmId else {
            return buildFallback(
                providerName: fetched.providerName,
                overview: nil,
                tmdbId: tmdbId,
                networkName: fetched.networkName,
                tmdbProviderName: fetched.providerName
            )
        }

        // titleDetail failed → TMDB-only fallback
        guard let detail = fetched.detail else {
            return buildFallback(
                providerName: fetched.providerName,
                overview: nil,
                tmdbId: tmdbId,
                networkName: fetched.networkName,
                tmdbProviderName: fetched.providerName
            )
        }

        let overview = detail.plotOverview
        let sources = detail.sources ?? []

        // Snapshot the user's subscribed services on the main actor. The
        // resolver is a nonisolated struct, so we hop to the main actor to
        // read AuthViewModel.shared.selectedServices. Set<String> is Sendable,
        // so this is safe to pass into the pure selection logic below.
        let subscribedServices = await MainActor.run { AuthViewModel.shared.selectedServices }

        if !sources.isEmpty {
            return selectFromSources(
                sources: sources,
                networkName: fetched.networkName,
                providerName: fetched.providerName,
                episodePlatformHint: episodePlatformHint,
                overview: overview,
                tmdbId: tmdbId,
                subscribedServices: subscribedServices
            )
        }

        return buildFallback(
            providerName: fetched.providerName,
            overview: overview,
            tmdbId: tmdbId,
            networkName: fetched.networkName,
            tmdbProviderName: fetched.providerName
        )
    }

    // MARK: - Helpers (internal, fileprivate)

    private func sourceRank(_ s: WatchmodeSource) -> Int {
        switch s.type.lowercased() {
        case "sub": return 0
        case "free": return 1
        case "tve": return 2          // requires cable login
        case "rent": return 3
        case "purchase", "buy": return 4
        default: return 5
        }
    }

    private func isResellerSource(_ s: WatchmodeSource) -> Bool {
        s.name.lowercased().contains("(via ")
    }

    /// Fuzzy-match a Watchmode source name against a platform display name.
    private func matches(sourceName: String, platform: String) -> Bool {
        let s = sourceName.lowercased()
        let p = platform.lowercased()
        if p.isEmpty { return true }
        if p.contains("netflix") { return s.contains("netflix") }
        if p.contains("hbo") || p.contains("max") { return s.contains("max") || s.contains("hbo") }
        if p.contains("hulu") { return s.contains("hulu") }
        if p.contains("disney") { return s.contains("disney") }
        if p.contains("apple") { return s.contains("apple tv") }
        if p.contains("prime") || p.contains("amazon") { return s.contains("amazon") || s.contains("prime") }
        if p.contains("paramount") { return s.contains("paramount") }
        if p.contains("peacock") { return s.contains("peacock") }
        if p.contains("youtube") { return s.contains("youtube") }
        if p.contains("showtime") { return s.contains("showtime") || s.contains("sho ") }
        if p.contains("starz") { return s.contains("starz") }
        if p.contains("crunchyroll") { return s.contains("crunchyroll") }
        return s.contains(p) || p.contains(s)
    }

    // MARK: - Pure selection logic (no network calls)

    /// Watchmode has sources — filter to US, dedupe, rank, and pick the
    /// best source using the network/provider signals captured earlier.
    private func selectFromSources(
        sources: [WatchmodeSource],
        networkName: String?,
        providerName: String?,
        episodePlatformHint: String?,
        overview: String?,
        tmdbId: Int,
        subscribedServices: Set<String>
    ) -> ResolvedStreaming {
        // Step 2 — US filter
        let usFiltered = sources.filter { ($0.region ?? "").uppercased() == "US" }
        let pool = usFiltered.isEmpty ? sources : usFiltered

        // Dedupe by name (keep first occurrence, preserving order)
        var seen: Set<String> = []
        let deduped = pool.filter { seen.insert($0.name.lowercased()).inserted }

        // Step 3 — Rank: first by sourceRank, then non-reseller before reseller
        let ranked = deduped.sorted { a, b in
            let ra = sourceRank(a)
            let rb = sourceRank(b)
            if ra != rb { return ra < rb }
            let aReseller = isResellerSource(a)
            let bReseller = isResellerSource(b)
            if aReseller != bReseller { return !aReseller }
            return false
        }

        // Priority selection, first match wins:
        // (0) A watchable-tier source (sub/free/tve only — never rent or
        //     purchase, even if the brand name matches) that the user is
        //     subscribed to. Reuses `matches(sourceName:platform:)` against
        //     the snapshot of `AuthViewModel.shared.selectedServices`. The
        //     ranked list already orders sub > free > tve and non-reseller
        //     before reseller, so among multiple subscribed matches the
        //     best-ranked one wins deterministically. Falls through unchanged
        //     when the user subscribes to none of the title's watchable sources.
        // (1) Episode platform hint match
        // (2) Network match among non-resellers — strongest TV signal.
        //     Broadcast nets (ABC, NBC, FOX, CBS) won't match streaming
        //     source names, so selection correctly falls through.
        // (3) TMDB primary-provider match among non-resellers
        // (4) First non-reseller
        // (5) First of any kind
        let chosen: WatchmodeSource?
        if let subscribed = ranked.first(where: { source in
            let rank = sourceRank(source)
            guard rank <= 2 else { return false } // sub/free/tve only
            return subscribedServices.contains(where: { matches(sourceName: source.name, platform: $0) })
        }) {
            chosen = subscribed
        } else if let hint = episodePlatformHint, !hint.isEmpty {
            chosen = ranked.first { matches(sourceName: $0.name, platform: hint) }
        } else if let net = networkName, !net.isEmpty {
            chosen = ranked.first {
                !isResellerSource($0) && matches(sourceName: $0.name, platform: net)
            }
        } else if let providerName, !providerName.isEmpty {
            chosen = ranked.first {
                !isResellerSource($0) && matches(sourceName: $0.name, platform: providerName)
            }
        } else {
            chosen = nil
        }

        let primary = chosen
            ?? ranked.first(where: { !isResellerSource($0) })
            ?? ranked.first

        var result = ResolvedStreaming(
            primarySource: primary,
            usSources: ranked,
            providerNameFallback: nil,
            overview: overview
        )
        return result
    }

    /// TMDB-only fallback when Watchmode returned no usable sources.
    private func buildFallback(
        providerName: String?,
        overview: String?,
        tmdbId: Int,
        networkName: String?,
        tmdbProviderName: String?
    ) -> ResolvedStreaming {
        var result: ResolvedStreaming
        if let name = providerName, !name.isEmpty {
            result = ResolvedStreaming(
                primarySource: nil,
                usSources: [],
                providerNameFallback: name,
                overview: overview
            )
        } else {
            result = ResolvedStreaming(
                primarySource: nil,
                usSources: [],
                providerNameFallback: nil,
                overview: overview
            )
        }

        return result
    }
}

// MARK: - Fetch bundle (detached-task return value)

private struct FetchBundle: Sendable {
    var wmId: String?
    var detail: WatchmodeTitleDetail?
    var providerName: String?
    var networkName: String?
}

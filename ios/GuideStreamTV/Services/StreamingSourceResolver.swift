//
//  StreamingSourceResolver.swift
//  GuideStreamTV
//
//  Centralized resolver that turns a TMDB id into the correct streaming
//  source — combining Watchmode sources (US-filtered, ranked, deduped)
//  with a TMDB primary-provider tiebreaker. Shared by all surfaces that
//  need to show a "Where to Watch" label or open a deeplink.

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

    /// Human-readable trace of what happened during resolution — each
    /// checkpoint appends a short token. Diagnostic only; never shown
    /// in production UI.
    var debugTrace: String = ""

    static let empty = ResolvedStreaming(
        primarySource: nil,
        usSources: [],
        providerNameFallback: nil,
        overview: nil,
        debugTrace: ""
    )
}

// MARK: - Resolver

nonisolated struct StreamingSourceResolver {
    static let shared = StreamingSourceResolver()

    // MARK: Public API

    /// Resolves streaming information for a title identified by TMDB id.
    ///
    /// All network calls are tolerant of failure — a thrown error never
    /// propagates out of this method. The result degrades gracefully
    /// through every fallback until `ResolvedStreaming.empty`.
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
        #if DEBUG
        print("[Resolver] tmdb=\(tmdbId) resolving…")
        #endif

        var traceParts: [String] = []

        // Step 1 — Watchmode lookup
        let wmId: String
        do {
            guard let id = try await WatchmodeService.shared.watchmodeId(forTMDBId: tmdbId, isTV: isTV) else {
                traceParts.append("wmId:nil")
                var result = await tmdbOnlyFallback(tmdbId: tmdbId, isTV: isTV, overview: nil)
                result.debugTrace = traceParts.joined(separator: " | ")
                return result
            }
            traceParts.append("wmId:ok")
            wmId = id
        } catch {
            traceParts.append("wmId:THREW(\(error))")
            var result = await tmdbOnlyFallback(tmdbId: tmdbId, isTV: isTV, overview: nil)
            result.debugTrace = traceParts.joined(separator: " | ")
            return result
        }

        let detail: WatchmodeTitleDetail
        do {
            detail = try await WatchmodeService.shared.titleDetail(titleId: wmId)
            traceParts.append("titleDetail:ok(sources=\(detail.sources?.count ?? 0))")
        } catch {
            traceParts.append("titleDetail:THREW(\(error))")
            var result = await tmdbOnlyFallback(tmdbId: tmdbId, isTV: isTV, overview: nil)
            result.debugTrace = traceParts.joined(separator: " | ")
            return result
        }

        let overview = detail.plotOverview
        let sources = detail.sources ?? []
        let parentTrace = traceParts.joined(separator: " | ")

        // Step 2 — If sources is non-empty, filter to US, dedupe, rank, and pick
        if !sources.isEmpty {
            return await resolveFromSources(
                sources: sources,
                tmdbId: tmdbId,
                isTV: isTV,
                episodePlatformHint: episodePlatformHint,
                overview: overview,
                parentTrace: parentTrace
            )
        }

        // No Watchmode sources — fall back to TMDB-only
        return await tmdbOnlyFallback(tmdbId: tmdbId, isTV: isTV, overview: overview, parentTrace: parentTrace)
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

    // MARK: - Resolution steps

    /// Step 2–4: Watchmode returned sources — filter, dedupe, rank, pick.
    private func resolveFromSources(
        sources: [WatchmodeSource],
        tmdbId: Int,
        isTV: Bool,
        episodePlatformHint: String?,
        overview: String?,
        parentTrace: String
    ) async -> ResolvedStreaming {
        var traceParts: [String] = []
        if !parentTrace.isEmpty { traceParts.append(parentTrace) }

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
            // Same rank — non-reseller sorts first
            let aReseller = isResellerSource(a)
            let bReseller = isResellerSource(b)
            if aReseller != bReseller { return !aReseller }
            return false
        }

        traceParts.append("usFiltered=\(deduped.count)")

        // Step 4a — TMDB network (for TV shows, the originating network is the
        // most reliable signal of the true home service). Works well when the
        // network is itself a streamer (Starz, HBO/Max, Showtime, Paramount+,
        // Peacock, Apple TV+, Netflix, Disney+). For broadcast networks (ABC,
        // NBC, FOX, CBS) the name won't match any streaming source, so the
        // selection correctly falls through to the watch-provider signal below.
        var networkName: String?
        if isTV {
            do {
                let tvDetail = try await TMDBService.shared.getTVDetail(tmdbId: tmdbId)
                if let name = tvDetail.networks?.first?.name {
                    networkName = name
                    traceParts.append("network:\(name)")
                } else {
                    traceParts.append("network:nil")
                }
            } catch {
                traceParts.append("tvDetail:THREW(\(error))")
            }
        }

        // Step 4b — TMDB primary watch provider (lower-priority tiebreaker; may
        // be unreliable for shows where a reseller channel inflates the ranking).
        var tmdbName: String?
        do {
            let tmdbProvider = try await TMDBService.shared.getTopWatchProvider(tmdbId: tmdbId, isTV: isTV)
            if let name = tmdbProvider?.providerName {
                tmdbName = name
                traceParts.append("provider:\(name)")
            } else {
                traceParts.append("provider:nil")
            }
        } catch {
            traceParts.append("provider:THREW(\(error))")
        }

        // Priority selection, first match wins:
        // (1) Episode platform hint match
        // (2) Network match among non-resellers (new — highest signal for TV)
        // (3) TMDB primary-provider match among non-resellers
        // (4) First non-reseller
        // (5) First of any kind
        let chosen: WatchmodeSource?
        if let hint = episodePlatformHint, !hint.isEmpty {
            chosen = ranked.first { matches(sourceName: $0.name, platform: hint) }
        } else if let net = networkName, !net.isEmpty {
            chosen = ranked.first {
                !isResellerSource($0) && matches(sourceName: $0.name, platform: net)
            }
        } else if let tmdbName, !tmdbName.isEmpty {
            chosen = ranked.first {
                !isResellerSource($0) && matches(sourceName: $0.name, platform: tmdbName)
            }
        } else {
            chosen = nil
        }

        let primary = chosen
            ?? ranked.first(where: { !isResellerSource($0) })
            ?? ranked.first

        let selectedName = primary?.name ?? "none"
        traceParts.append("chose:\(selectedName)")

        var result = ResolvedStreaming(
            primarySource: primary,
            usSources: ranked,
            providerNameFallback: nil,
            overview: overview
        )
        result.debugTrace = traceParts.joined(separator: " | ")

        #if DEBUG
        print("[Resolver] tmdb=\(tmdbId) network=\(networkName ?? "nil") provider=\(tmdbName ?? "nil") chose=\(result.primarySource?.name ?? result.providerNameFallback ?? "none")")
        #endif

        return result
    }

    /// Step 5: TMDB-only fallback when Watchmode returned no usable sources.
    private func tmdbOnlyFallback(
        tmdbId: Int,
        isTV: Bool,
        overview: String?,
        parentTrace: String = ""
    ) async -> ResolvedStreaming {
        var traceParts: [String] = []
        if !parentTrace.isEmpty { traceParts.append(parentTrace) }

        var fallbackName: String?
        do {
            let provider = try await TMDBService.shared.getTopWatchProvider(tmdbId: tmdbId, isTV: isTV)
            if let name = provider?.providerName {
                fallbackName = name
                traceParts.append("provider:\(name)")
            } else {
                traceParts.append("provider:nil")
            }
        } catch {
            traceParts.append("provider:THREW(\(error))")
        }

        var result: ResolvedStreaming
        if let name = fallbackName, !name.isEmpty {
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

        let selectedName = result.primarySource?.name ?? result.providerNameFallback ?? "none"
        traceParts.append("chose:\(selectedName)")
        result.debugTrace = traceParts.joined(separator: " | ")

        #if DEBUG
        print("[Resolver] tmdb=\(tmdbId) chose=\(result.primarySource?.name ?? result.providerNameFallback ?? "none")")
        #endif

        return result
    }
}

//
//  TVReelsViewModel.swift
//  GuideStreamTVTV
//
//  Feed for the tvOS Reels screen, built to the same depth as the phone's
//  `ReelsViewModel`: the same four sources woven into one vertical feed,
//  the same sponsored full-page reel after every third content reel, and
//  the same pagination that keeps loading until each source is exhausted.
//
//  Two things differ, both forced by the platform. Keys come from
//  `TVTrailerResolveService` and then have to be turned into a direct
//  stream by `TVTrailerStreamService`, because tvOS has no WebKit and so no
//  IFrame embed to hand a key to. And resolution is chunked rather than
//  fired at the whole batch at once — the extractor runs YouTube's
//  descrambler through JavaScriptCore, and a real Apple TV will kill the
//  app for it.
//

import Foundation

// MARK: - Model

nonisolated struct TVReelItem: Identifiable, Hashable, Sendable {
    /// canonicalTitleId for content, "sponsored-<advertiser>-<slot>" for ads.
    let id: String
    let tmdbId: Int
    let isTV: Bool
    let title: String
    let synopsis: String
    let backdropUrl: String?
    let posterUrl: String?
    let year: Int?
    let genre: String?
    /// Display name of the service this title streams on, when known.
    let platformName: String?
    let platformId: String?
    /// Verified playable keys in rank order. The first is tried first and
    /// the rest are the fallback walk.
    let trailerKeys: [String]
    let isSponsored: Bool
    let advertiserKey: String?

    var canonicalTitleId: String { isSponsored ? id : "tmdb:\(isTV ? "tv" : "movie"):\(tmdbId)" }
    var mediaType: String { isTV ? "tv" : "movie" }

    static func == (lhs: TVReelItem, rhs: TVReelItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - View model

@MainActor
@Observable
final class TVReelsViewModel {
    private(set) var reels: [TVReelItem] = []
    private(set) var isLoading: Bool = false
    private(set) var isLoadingMore: Bool = false
    /// canonicalTitleId -> direct stream URL, filled as reels come into view.
    private(set) var streams: [String: String] = [:]

    /// A sponsored full-page reel is injected after every third content reel,
    /// matching the phone. Ad slots alternate so the same service never leads
    /// twice running.
    private static let sponsoredEvery = 3
    /// How many reels from the end before the next page is fetched.
    private static let loadMoreThreshold = 6

    private enum Source: CaseIterable { case popularTV, trending, onTheAir, comingSoon }
    private var exhausted: Set<Source> = []
    private var seenIds: Set<String> = []
    private var adSlot = 0

    // MARK: - Injected feed

    /// Seeds the feed with a title-scoped list instead of the browse feed,
    /// so the detail screen's Trailers & Clips row can open Reels on the
    /// title the viewer is looking at. Mirrors the iPhone, where
    /// `ReelsScreen(injectedReels:injectedStartIndex:)` does the same.
    ///
    /// `load()` guards on `reels.isEmpty`, so seeding here means the browse
    /// feed never replaces what was injected. Pagination is deliberately
    /// left off: an injected feed is a closed set, not an endless one.
    func inject(_ items: [TVReelItem]) {
        guard !items.isEmpty else { return }
        reels = items
        seenIds = Set(items.map(\.canonicalTitleId))
        isInjected = true
    }

    /// True when the feed was seeded by a caller. Suppresses pagination.
    private(set) var isInjected = false

    /// Builds a one-title feed from a TMDB result, resolving its trailer
    /// keys the same way the browse feed does. Returns nil when the title
    /// has no playable trailer, so callers can hide the row rather than
    /// open an empty player.
    func reelItem(for result: TVTMDBResult, platformName: String?) async -> TVReelItem? {
        let keys: [String]
        if let verified = await TVTrailerResolveService.resolve(tmdbId: result.id, isTV: result.isTV) {
            keys = verified
        } else {
            keys = await TVTMDBService.shared.getTrailerKeys(tmdbId: result.id, isTV: result.isTV)
        }
        guard !keys.isEmpty else { return nil }
        return TVReelItem(
            id: result.canonicalTitleId,
            tmdbId: result.id,
            isTV: result.isTV,
            title: result.displayName,
            synopsis: result.overview ?? "",
            backdropUrl: result.backdropUrl,
            posterUrl: result.posterUrl,
            year: result.year,
            genre: nil,
            platformName: platformName,
            platformId: nil,
            trailerKeys: keys,
            isSponsored: false,
            advertiserKey: nil
        )
    }

    // MARK: - Load

    func load() async {
        guard reels.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        await TVAffiliateService.shared.fetchIfNeeded()

        // For You leads, same as the phone: what the viewer already saves,
        // then popular, then what is on the air.
        let mine = await forYouResults()
        let trending = (try? await TVTMDBService.shared.getTrending()) ?? []
        let firstBatch = interleave(mine, trending)

        var built = await buildReels(from: firstBatch)
        if built.count < 8 {
            let onAir = (try? await TVTMDBService.shared.getOnTheAir()) ?? []
            built += await buildReels(from: onAir)
        }
        reels = weaveSponsored(into: built)
        await TVSocialService.shared.loadState(for: reels.map(\.canonicalTitleId))
    }

    /// Called as the viewer nears the end of the feed.
    func loadMoreIfNeeded(currentIndex: Int) async {
        guard !isInjected else { return }
        guard !isLoadingMore, !isLoading else { return }
        guard currentIndex >= reels.count - Self.loadMoreThreshold else { return }
        guard exhausted.count < Source.allCases.count else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        for source in Source.allCases where !exhausted.contains(source) {
            let batch = await fetch(source)
            if batch.isEmpty { exhausted.insert(source); continue }
            let built = await buildReels(from: batch)
            if built.isEmpty { exhausted.insert(source); continue }
            reels += weaveSponsored(into: built)
            await TVSocialService.shared.loadState(for: built.map(\.canonicalTitleId))
            return
        }
    }

    private func fetch(_ source: Source) async -> [TVTMDBResult] {
        switch source {
        case .popularTV:   return (try? await TVTMDBService.shared.getPopularTV()) ?? []
        case .trending:    return (try? await TVTMDBService.shared.getTrending()) ?? []
        case .onTheAir:    return (try? await TVTMDBService.shared.getOnTheAir()) ?? []
        case .comingSoon:  return await comingSoonResults()
        }
    }

    /// The viewer's own watch list, plus popular movies on the services they
    /// actually subscribe to — the phone's For You shape.
    private func forYouResults() async -> [TVTMDBResult] {
        var out = (try? await TVTMDBService.shared.getPopularTV()) ?? []
        let owned = AuthViewModel.shared.selectedServices
        if !owned.isEmpty {
            for providerId in owned.compactMap({ Self.tmdbProviderId[$0] }).prefix(2) {
                out += await TVTMDBService.shared.getPopularMoviesOnService(tmdbProviderId: providerId)
            }
        }
        return out
    }

    private func comingSoonResults() async -> [TVTMDBResult] {
        guard let rows = await TVStreamingReleasesService.shared.fetchUpcoming() else { return [] }
        return rows.prefix(20).map { row in
            TVTMDBResult(
                id: row.tmdbId,
                mediaType: row.tmdbType,
                name: row.isTV ? row.title : nil,
                title: row.isTV ? nil : row.title,
                posterPath: row.posterPath,
                backdropPath: nil,
                overview: nil,
                voteAverage: nil,
                firstAirDate: row.isTV ? row.sourceReleaseDate : nil,
                releaseDate: row.isTV ? nil : row.sourceReleaseDate
            )
        }
    }

    private func interleave(_ a: [TVTMDBResult], _ b: [TVTMDBResult]) -> [TVTMDBResult] {
        var out: [TVTMDBResult] = []
        var i = 0
        while i < max(a.count, b.count) {
            if i < a.count { out.append(a[i]) }
            if i < b.count { out.append(b[i]) }
            i += 1
        }
        return out
    }

    // MARK: - Build

    /// Resolves verified keys for a batch and drops anything with no playable
    /// trailer — a reel with nothing to play is not a reel.
    private func buildReels(from results: [TVTMDBResult]) async -> [TVReelItem] {
        var fresh: [TVTMDBResult] = []
        for r in results {
            let id = r.canonicalTitleId
            guard !seenIds.contains(id) else { continue }
            seenIds.insert(id)
            fresh.append(r)
        }
        guard !fresh.isEmpty else { return [] }

        var keysById: [String: [String]] = [:]
        // Two at a time, same reason the hero resolves in chunks.
        for chunk in stride(from: 0, to: fresh.count, by: 2).map({
            Array(fresh[$0..<min($0 + 2, fresh.count)])
        }) {
            await withTaskGroup(of: (String, [String]).self) { group in
                for r in chunk {
                    group.addTask {
                        // `??` takes an autoclosure, which cannot carry an
                        // await — the fallback has to be spelled out.
                        if let verified = await TVTrailerResolveService.resolve(
                            tmdbId: r.id, isTV: r.isTV
                        ) {
                            return (r.canonicalTitleId, verified)
                        }
                        let unverified = await TVTMDBService.shared.getTrailerKeys(
                            tmdbId: r.id, isTV: r.isTV
                        )
                        return (r.canonicalTitleId, unverified)
                    }
                }
                for await (id, keys) in group where !keys.isEmpty {
                    keysById[id] = keys
                }
            }
        }

        return fresh.compactMap { r in
            guard let keys = keysById[r.canonicalTitleId] else { return nil }
            return TVReelItem(
                id: r.canonicalTitleId,
                tmdbId: r.id,
                isTV: r.isTV,
                title: r.displayName,
                synopsis: r.overview ?? "",
                backdropUrl: r.backdropUrl,
                posterUrl: r.posterUrl,
                year: r.year,
                genre: nil,
                platformName: nil,
                platformId: nil,
                trailerKeys: keys,
                isSponsored: false,
                advertiserKey: nil
            )
        }
    }

    /// One sponsored full-page reel after every third content reel, drawn
    /// from the gap services only — the same filter the inline chip uses.
    private func weaveSponsored(into items: [TVReelItem]) -> [TVReelItem] {
        let gaps = TVAffiliateService.shared.gapAdvertisers()
        guard !gaps.isEmpty else { return items }

        var out: [TVReelItem] = []
        for (offset, item) in items.enumerated() {
            out.append(item)
            guard (offset + 1) % Self.sponsoredEvery == 0 else { continue }
            let advertiser = gaps[adSlot % gaps.count]
            adSlot += 1
            out.append(TVReelItem(
                id: "sponsored-\(advertiser.key)-\(adSlot)",
                tmdbId: 0,
                isTV: false,
                title: advertiser.displayName,
                synopsis: "Thousands of movies and shows, on your Apple TV.",
                backdropUrl: item.backdropUrl,
                posterUrl: nil,
                year: nil,
                genre: nil,
                platformName: advertiser.displayName,
                platformId: advertiser.key,
                trailerKeys: [],
                isSponsored: true,
                advertiserKey: advertiser.key
            ))
        }
        return out
    }

    // MARK: - Streams

    /// Resolves the direct stream for one reel, walking its keys. Cached, so
    /// stepping back to a reel is instant.
    func stream(for item: TVReelItem) async -> String? {
        if let cached = streams[item.canonicalTitleId] { return cached }
        guard !item.isSponsored else { return nil }
        let map = await TVTrailerStreamService.shared.fetchTrailerStreams(
            for: [(tmdbId: item.tmdbId, isTV: item.isTV)]
        )
        if let url = map[item.canonicalTitleId] {
            streams[item.canonicalTitleId] = url
            return url
        }
        return nil
    }

    /// Maps tvOS StreamingCatalog ids to TMDB watch-provider ids. Same table
    /// TVHomeView uses.
    private static let tmdbProviderId: [String: Int] = [
        "netflix": 8, "prime": 9, "disney": 337, "max": 1899, "hulu": 15,
        "appletv": 350, "paramount": 2303, "peacock": 386, "starz": 43,
        "showtime": 37, "crunchyroll": 283, "youtube": 192
    ]
}

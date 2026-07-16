//
//  ReelsScreen.swift
//  GuideStreamTV
//
//  TikTok-style vertical trailer feed. Pulls trailers from TMDB (For You from
//  user_streams, Trending from /trending/tv/week, New from /tv/on_the_air),
//  inserts a Rakuten sponsored reel at slot 4, fires an AdMob interstitial
//  every 5 swipes, and logs every interaction through WatchIntentLogger.
//

import SwiftUI
import UIKit
import YouTubeiOSPlayerHelper
import Supabase

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Model

enum ReelTab: String, CaseIterable, Hashable {
    case forYou = "for-you"
    case trending = "trending"
    case new = "new"
    case comingSoon = "coming-soon"

    var label: String {
        switch self {
        case .forYou: return "For You"
        case .trending: return "Trending"
        case .new: return "New"
        case .comingSoon: return "Coming Soon"
        }
    }
}

struct TrailerItem: Identifiable, Hashable {
    let id: String          // YouTube video ID (or "sponsored-<n>")
    let tmdbId: Int
    let showName: String
    let synopsis: String
    let genre: String
    let runtime: String
    let platformId: String
    let platformName: String
    let platformColor: Color
    let platformTextColor: Color
    let backdropURL: URL?
    let posterURL: URL?
    let trailerKey: String
    /// Ordered fallback YouTube video ids to try (in priority order) after the
    /// first candidate raises an embed error. Empty for single-candidate reels
    /// (injected title-scoped reels and sponsored reels), preserving today's
    /// collapse-to-poster behavior for those. Excluded from identity/dedupe.
    var fallbackKeys: [String] = []
    let thumbnailURL: URL?
    let youtubeURL: URL?
    let deepLinkURL: String?
    let voteAverage: Double
    let likes: Int
    let comments: Int
    let tab: ReelTab
    let identityCode: String
    let gradeColor: Color
    let isSponsored: Bool
    /// Whether the underlying TMDB title is a TV show (vs. a movie). Used to
    /// record `media_type` on `title_likes`. Defaults to `true` for entries
    /// without a TMDB identity (e.g. sponsored reels), which are never liked.
    var isTV: Bool = true
    /// For title-scoped Reels (Trailers & Clips), the TMDB video type
    /// ("Trailer", "Teaser", "Featurette", "Clip"). nil in the global feed.
    var videoType: String? = nil
    /// The TMDB video name for title-scoped reels. nil in the global feed.
    var videoName: String? = nil

    static func == (lhs: TrailerItem, rhs: TrailerItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Lazily-enriched TVDB data for a reel. Fetched when the reel becomes visible
/// (current or next in the feed) so API calls stay proportional to viewport.
struct TVDBReelInfo: Equatable, Sendable {
    let nextAirDate: Date?
    let episodeCode: String?      // "S3 E7"
    let episodeName: String?
    let seriesStatus: String?     // "Returning", "Ended", "Continuing"
}

// MARK: - Platform mapping

private enum ReelPlatform {
    /// Returns the canonical platform id when the raw provider name maps to one of the
    /// streaming services we can deep-link into. Returns `nil` for unrecognised providers
    /// so reels can be filtered out entirely.
    static func recognizedKey(for raw: String?) -> String? {
        let key = (raw ?? "").lowercased()
        if key.contains("netflix") { return "netflix" }
        if key.contains("max") || key.contains("hbo") { return "hbo" }
        if key.contains("apple tv") { return "apple" }
        if key.contains("disney") { return "disney" }
        if key.contains("hulu") { return "hulu" }
        if key.contains("peacock") { return "peacock" }
        if key.contains("paramount") { return "paramount" }
        if key.contains("amazon") || key.contains("prime video") { return "prime" }
        if key.contains("starz") { return "starz" }
        if key.contains("showtime") { return "showtime" }
        if key.contains("crunchyroll") { return "crunchyroll" }
        if key.contains("youtube") { return "youtube" }
        if key.contains("fubo") { return "fubo" }
        if key.contains("tubi") { return "tubi" }
        if key.contains("pluto") { return "pluto" }
        if key.contains("amc") { return "amc" }
        if key.contains("discovery") { return "discovery" }
        if key.contains("mubi") { return "mubi" }
        if key.contains("britbox") { return "britbox" }
        return nil
    }

    static func info(for raw: String?) -> (id: String, name: String, color: Color, grade: Color) {
        let key = (raw ?? "").lowercased()
        switch key {
        case let s where s.contains("netflix"):
            return ("netflix", "NETFLIX", Color(hex: "E50914"), Color.red.opacity(0.15))
        case let s where s.contains("max") || s.contains("hbo"):
            return ("hbo", "HBO MAX", Color(hex: "5A1FCB"), Color.purple.opacity(0.15))
        case let s where s.contains("apple tv"):
            return ("apple", "APPLE TV+", Color(hex: "101010"), Color.gray.opacity(0.15))
        case let s where s.contains("disney"):
            return ("disney", "DISNEY+", Color(hex: "113CCF"), Color.blue.opacity(0.15))
        case let s where s.contains("hulu"):
            return ("hulu", "HULU", Color(hex: "1CE783"), Color.green.opacity(0.15))
        case let s where s.contains("peacock"):
            return ("peacock", "PEACOCK", Color(hex: "000000"), Color.indigo.opacity(0.15))
        case let s where s.contains("paramount"):
            return ("paramount", "PARAMOUNT+", Color(hex: "0064FF"), Color.blue.opacity(0.15))
        case let s where s.contains("amazon") || s.contains("prime video"):
            return ("prime", "PRIME VIDEO", Color(hex: "00A8E1"), Color.cyan.opacity(0.15))
        case let s where s.contains("starz"):
            return ("starz", "STARZ", Color(hex: "000000"), Color.gray.opacity(0.15))
        case let s where s.contains("showtime"):
            return ("showtime", "SHOWTIME", Color(hex: "D80000"), Color.red.opacity(0.15))
        case let s where s.contains("crunchyroll"):
            return ("crunchyroll", "CRUNCHYROLL", Color(hex: "F47B20"), Color.orange.opacity(0.15))
        case let s where s.contains("youtube"):
            return ("youtube", "YOUTUBE", Color(hex: "FF0000"), Color.red.opacity(0.15))
        case let s where s.contains("fubo"):
            return ("fubo", "FUBO", Color(hex: "FF5500"), Color.orange.opacity(0.15))
        case let s where s.contains("tubi"):
            return ("tubi", "TUBI", Color(hex: "4B0896"), Color.purple.opacity(0.15))
        case let s where s.contains("pluto"):
            return ("pluto", "PLUTO TV", Color(hex: "1D1D1D"), Color.gray.opacity(0.15))
        case let s where s.contains("amc"):
            return ("amc", "AMC+", Color(hex: "000000"), Color.gray.opacity(0.15))
        case let s where s.contains("discovery"):
            return ("discovery", "DISCOVERY+", Color(hex: "0066FF"), Color.blue.opacity(0.15))
        case let s where s.contains("mubi"):
            return ("mubi", "MUBI", Color(hex: "000000"), Color.gray.opacity(0.15))
        case let s where s.contains("britbox"):
            return ("britbox", "BRITBOX", Color(hex: "003366"), Color.teal.opacity(0.15))
        default:
            return ("tmdb", "STREAMING", Color(hex: "F5821F"), Color.orange.opacity(0.12))
        }
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class ReelsViewModel {
    /// Shared instance so the feed can be preloaded at app launch and survive
    /// tab switches without re-fetching trailers every time the user opens Reels.
    static let shared = ReelsViewModel()

    var allTrailers: [TrailerItem] = []
    var currentIndex: Int = 0
    var isLoading: Bool = true
    var activeTab: ReelTab = .forYou
    var reelSwipeCount: Int = 0
    /// Lazily-populated TVDB next-episode data keyed by TMDB series id.
    var tvdbCache: [Int: TVDBReelInfo] = [:]

    private let tmdb = TMDBService.shared
    private var hasLoaded: Bool = false

    // MARK: Pagination state

    /// The four sources that support background pagination for the endless feed.
    private enum PagedSource: CaseIterable, Hashable {
        case popularTV, trending, onTheAir, streamingMovies
    }

    /// Next TMDB page to fetch for every paginated source. Page 1 is consumed
    /// by the initial `loadTrailers()` pass.
    private var nextPage: Int = 2
    /// Collapses concurrent load-more triggers into a single in-flight fetch.
    private var isLoadingMore: Bool = false
    /// Session-wide trailer-key dedup so no trailer ever appears twice.
    private var seenTrailerKeys: Set<String> = []
    /// Sources that returned a successful empty page — never fetched again.
    private var exhaustedSources: Set<PagedSource> = []
    /// Persistent ad-weaving counters so the Rakuten/AdMob cadence continues
    /// seamlessly across appended batches instead of restarting per batch.
    private var contentReelsSinceAd: Int = 0
    private var adSlotCount: Int = 0
    private var rakutenIndex: Int = 0

    /// True once every paginated source has returned an empty page — the feed
    /// can no longer grow, so the final reel is allowed to loop.
    var allSourcesExhausted: Bool {
        exhaustedSources.count == PagedSource.allCases.count
    }

    /// TMDB provider IDs for the user's subscribed services, used to surface
    /// movies that are currently streaming (not just theatrical / upcoming).
    private let tmdbProviderIdMap: [String: Int] = [
        "netflix": 8, "prime": 9, "disney": 337, "hbo": 1899, "hulu": 15,
        "appletv": 350, "paramount": 531, "peacock": 386, "starz": 43,
        "showtime": 37, "crunchyroll": 283, "amc": 526, "discovery": 584,
        "mubi": 11, "britbox": 151, "fubo": 257, "tubi": 73, "pluto": 300,
        "youtube": 192
    ]

    /// Loads the feed once per app session. Subsequent calls are no-ops so the
    /// data is shared across reentries into the Reels tab.
    func loadIfNeeded() async {
        guard !hasLoaded, !isLoading || allTrailers.isEmpty else { return }
        if hasLoaded { return }
        await loadTrailers()
    }

    func loadTrailers() async {
        isLoading = true
        defer { isLoading = false }

        // Fresh feed — reset pagination and ad-weaving state so a reload
        // behaves exactly like a first launch.
        nextPage = 2
        seenTrailerKeys = []
        exhaustedSources = []
        contentReelsSinceAd = 0
        adSlotCount = 0
        rakutenIndex = 0

        // Fetch source lists in parallel — including movies currently on the
        // user's subscribed services so the feed includes streaming movies,
        // not just theatrical / upcoming titles.
        async let trendingTask: [TMDBResult] = (try? tmdb.getTrending()) ?? []
        async let onAirTask: [TMDBResult] = (try? tmdb.getOnTheAir()) ?? []
        async let myStreamsTask: [UserStream] = fetchMyStreams()
        async let popularTVTask: [TMDBResult] = (try? tmdb.getPopularTV()) ?? []
        async let streamingMoviesTask: [TMDBResult] = fetchStreamingMovies()

        let (trending, onAir, mine, popularTV, streamingMovies) = await (trendingTask, onAirTask, myStreamsTask, popularTVTask, streamingMoviesTask)

        let comingSoonReleases = (try? await WatchmodeService.shared.upcomingStreamingReleases()) ?? []

        print("[REELS] Fetched sources: trending=\(trending.count) onAir=\(onAir.count) mine=\(mine.count) popularTV=\(popularTV.count) streamingMovies=\(streamingMovies.count) comingSoonReleases=\(comingSoonReleases.count)")

        // For each show, fetch its YouTube trailer key + TMDB detail.
        // Keep the work parallel but capped to avoid hammering TMDB.
        let forYouItems = await buildItems(from: mineResults(mine), tab: .forYou)
        let trendingItems = await buildItems(from: Array(trending.prefix(50)), tab: .trending)
        let newItems = await buildItems(from: Array(onAir.prefix(50)), tab: .new)
        let popularTVItems = await buildItems(from: Array(popularTV.prefix(50)), tab: .forYou)
        let comingSoonItems = await buildComingSoonItems(from: comingSoonReleases)
        let streamingMovieItems = await buildItems(from: Array(streamingMovies.prefix(50)), tab: .forYou)

        print("[REELS] Built items: forYou=\(forYouItems.count) trending=\(trendingItems.count) new=\(newItems.count) popularTV=\(popularTVItems.count) comingSoon=\(comingSoonItems.count) streamingMovies=\(streamingMovieItems.count)")

        // Backfill For You feed with trending when the account has a light watchlist.
        var forYouCombined = forYouItems + popularTVItems
        if forYouCombined.count < 10 {
            let trendingFallback = (try? await tmdb.getTrending()) ?? []
            let needed = max(0, 10 - forYouCombined.count)
            if !trendingFallback.isEmpty {
                let extra = await buildItems(from: Array(trendingFallback.prefix(needed)), tab: .forYou)
                forYouCombined += extra
            }
        }

        // Intersperse streaming movies with For You content so movies appear
        // early in the feed rather than buried after 100+ TV reels.
        var combined: [TrailerItem] = []
        let interleaveCount = max(forYouCombined.count, streamingMovieItems.count)
        for i in 0..<interleaveCount {
            if i < forYouCombined.count { combined.append(forYouCombined[i]) }
            if i < streamingMovieItems.count { combined.append(streamingMovieItems[i]) }
        }
        combined += trendingItems + newItems + comingSoonItems

        // Deduplicate by trailer key so the same video doesn't appear twice.
        // The seen set persists in the view model so later paginated batches
        // keep deduplicating against everything already in the feed.
        combined = combined.filter { seenTrailerKeys.insert($0.trailerKey).inserted }

        let finalFeed = weaveAds(into: combined, isInitialLoad: true)

        self.allTrailers = finalFeed
        self.hasLoaded = !finalFeed.isEmpty

        // Saved state now lives in the shared StreamsViewModel store, which
        // hydrates itself from the local cache on init and refreshes from
        // Supabase whenever the user signs in. Nothing else to do here.


    }

    /// Weaves Rakuten reels into a batch of content reels using the persistent
    /// counters, preserving the cadence: an ad slot after every third content
    /// reel. On the initial load only, inserts one Rakuten reel near the top
    /// when none landed at all. (The even-slot AdMob reel was removed — real
    /// interstitials now fire on a swipe cadence instead.)
    private func weaveAds(into batch: [TrailerItem], isInitialLoad: Bool) -> [TrailerItem] {
        let rakutenReels = makeRakutenAdReels()
        var out: [TrailerItem] = []

        for item in batch {
            out.append(item)
            contentReelsSinceAd += 1

            if contentReelsSinceAd == 3 {
                contentReelsSinceAd = 0
                adSlotCount += 1
                if adSlotCount % 2 == 1 {
                    // Odd ad slots (after reels 3, 9, 15...) → Rakuten
                    if !rakutenReels.isEmpty {
                        out.append(
                            rakutenReels[rakutenIndex % rakutenReels.count]
                        )
                        rakutenIndex += 1
                    }
                }
            }
        }

        // Safety net (initial feed only): if the feed was too short to insert
        // any Rakuten reel at all, insert one now so it always appears.
        if isInitialLoad {
            let hasRakuten = out.contains { $0.isSponsored }
            if !hasRakuten, let first = rakutenReels.first {
                let insertAt = min(2, out.count)
                out.insert(first, at: insertAt)
            }
        }
        return out
    }

    /// Fetches the next page of the four paginated sources (popular TV,
    /// trending, on-the-air, big-five streaming movies), builds reels, drops
    /// session-wide duplicates, weaves ads with the persistent counters, and
    /// appends the batch to `allTrailers`. Concurrent triggers collapse into
    /// one in-flight load via `isLoadingMore`. A failed request never marks a
    /// source exhausted — only a successful empty result array does.
    func loadMoreTrailers() async {
        guard hasLoaded, !isLoadingMore, !allSourcesExhausted else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let page = nextPage
        let skipPopularTV = exhaustedSources.contains(.popularTV)
        let skipTrending = exhaustedSources.contains(.trending)
        let skipOnTheAir = exhaustedSources.contains(.onTheAir)
        let skipMovies = exhaustedSources.contains(.streamingMovies)

        // nil = fetch failed (or skipped); [] = successful empty page.
        async let popularTVFetch: [TMDBResult]? = skipPopularTV ? nil : (try? tmdb.getPopularTV(page: page))
        async let trendingFetch: [TMDBResult]? = skipTrending ? nil : (try? tmdb.getTrending(page: page))
        async let onAirFetch: [TMDBResult]? = skipOnTheAir ? nil : (try? tmdb.getOnTheAir(page: page))
        async let moviesFetch: ([TMDBResult], Bool)? = skipMovies ? nil : fetchMoreStreamingMovies(page: page)

        let (popularTV, trending, onAir, movies) = await (popularTVFetch, trendingFetch, onAirFetch, moviesFetch)

        var newItems: [TrailerItem] = []

        if !skipPopularTV, let results = popularTV {
            if results.isEmpty {
                exhaustedSources.insert(.popularTV)
            } else {
                newItems += await buildItems(from: results, tab: .forYou)
            }
        }
        if !skipTrending, let results = trending {
            if results.isEmpty {
                exhaustedSources.insert(.trending)
            } else {
                newItems += await buildItems(from: results, tab: .trending)
            }
        }
        if !skipOnTheAir, let results = onAir {
            if results.isEmpty {
                exhaustedSources.insert(.onTheAir)
            } else {
                newItems += await buildItems(from: results, tab: .new)
            }
        }
        if !skipMovies, let (movieResults, allSucceeded) = movies {
            if movieResults.isEmpty {
                if allSucceeded { exhaustedSources.insert(.streamingMovies) }
            } else {
                newItems += await buildItems(from: movieResults, tab: .forYou)
            }
        }

        // Session-wide dedup — drop anything already in the feed.
        let fresh = newItems.filter { seenTrailerKeys.insert($0.trailerKey).inserted }

        if !fresh.isEmpty {
            let woven = weaveAds(into: fresh, isInitialLoad: false)
            allTrailers.append(contentsOf: woven)
            print("[REELS] loadMore page=\(page): appended \(woven.count) reels (\(fresh.count) content, exhausted=\(exhaustedSources.count)/4)")
        } else {
            print("[REELS] loadMore page=\(page): appended 0 reels (exhausted=\(exhaustedSources.count)/4)")
        }
        nextPage += 1
    }

    /// Page-N popular movies for the big-five providers only (Netflix, Prime,
    /// Disney+, Max, Hulu), deduplicated by TMDB id. Returns nil when every
    /// provider request failed; the Bool reports whether all five succeeded
    /// (required before the source may be marked exhausted).
    private func fetchMoreStreamingMovies(page: Int) async -> ([TMDBResult], Bool)? {
        let bigFive = [8, 9, 337, 1899, 15]
        let fetched: [[TMDBResult]?] = await withTaskGroup(of: [TMDBResult]?.self) { group in
            for pid in bigFive {
                group.addTask { [tmdb] in
                    try? await tmdb.getPopularMoviesOnService(tmdbProviderId: pid, page: page)
                }
            }
            var all: [[TMDBResult]?] = []
            for await results in group { all.append(results) }
            return all
        }
        guard fetched.contains(where: { $0 != nil }) else { return nil }
        var seen = Set<Int>()
        let deduped = fetched.compactMap { $0 }.flatMap { $0 }.filter { seen.insert($0.id).inserted }
        return (deduped, fetched.allSatisfy { $0 != nil })
    }

    private func mineResults(_ streams: [UserStream]) -> [TMDBResult] {
        streams.prefix(50).compactMap { s -> TMDBResult? in
            // user_streams may store numeric tmdb id in title_id (tt-xxx slug for some).
            // Only build items for entries with a numeric tmdb id available.
            let trimmed = s.titleId.trimmingCharacters(in: .whitespaces)
            guard let id = Int(trimmed) else { return nil }
            return TMDBResult(
                id: id,
                mediaType: "tv",
                name: s.title,
                title: nil,
                posterPath: nil,
                backdropPath: nil,
                overview: nil,
                voteAverage: nil,
                firstAirDate: nil,
                releaseDate: nil
            )
        }
    }

    private func fetchMyStreams() async -> [UserStream] {
        guard let uid = AuthViewModel.shared.currentUser?.id.uuidString else { return [] }
        do {
            let rows: [UserStream] = try await SupabaseManager.shared.client
                .from("user_streams")
                .select()
                .eq("user_id", value: uid)
                .order("added_at", ascending: false)
                .limit(15)
                .execute()
                .value
            return rows
        } catch {
            return []
        }
    }

    /// Fetches popular movies currently streaming across ALL major services
    /// (not just the ones the user has chosen) so the reels feed always
    /// includes movies available to watch now. Uses async let for the 5 largest
    /// providers (Netflix, Prime, Disney+, HBO/Max, Hulu) plus a task group
    /// for the remaining 14 providers — all run concurrently.
    private func fetchStreamingMovies() async -> [TMDBResult] {
        // Fetch the "big five" directly with async let for reliability.
        async let netflix = (try? tmdb.getPopularMoviesOnService(tmdbProviderId: 8)) ?? []
        async let prime = (try? tmdb.getPopularMoviesOnService(tmdbProviderId: 9)) ?? []
        async let disney = (try? tmdb.getPopularMoviesOnService(tmdbProviderId: 337)) ?? []
        async let hbo = (try? tmdb.getPopularMoviesOnService(tmdbProviderId: 1899)) ?? []
        async let hulu = (try? tmdb.getPopularMoviesOnService(tmdbProviderId: 15)) ?? []

        // Remaining providers via task group.
        let secondaryProviderIds = [350, 531, 386, 43, 37, 283, 526, 584, 11, 151, 257, 73, 300, 192]
        async let secondary: [TMDBResult] = await withTaskGroup(of: [TMDBResult].self) { group in
            for pid in secondaryProviderIds {
                group.addTask { [tmdb] in
                    (try? await tmdb.getPopularMoviesOnService(tmdbProviderId: pid)) ?? []
                }
            }
            var all: [TMDBResult] = []
            for await results in group { all.append(contentsOf: results) }
            return all
        }

        let (n, p, d, hb, hu, sec) = await (netflix, prime, disney, hbo, hulu, secondary)
        let allSources = [[n, p, d, hb, hu].flatMap { $0 }, sec].flatMap { $0 }
        var seen = Set<Int>()
        let deduped = allSources.filter { seen.insert($0.id).inserted }
        NSLog("[REELS] fetchStreamingMovies: big5=\([n.count, p.count, d.count, hb.count, hu.count]) secondary=\(sec.count) deduped=\(deduped.count)")
        return deduped
    }

    private func buildItems(from results: [TMDBResult], tab: ReelTab) async -> [TrailerItem] {
        // Snapshot the user's subscribed services once before the task group so
        // every result in this batch sees a consistent view. Set<String> is
        // Sendable, so capturing it into the task closures needs no actor hop.
        let subscribedServiceIds = Set(AuthViewModel.shared.selectedServices.map { $0.lowercased() })
        return await withTaskGroup(of: TrailerItem?.self) { group in
            for r in results {
                group.addTask { [tmdb, subscribedServiceIds] in
                    // Only fetch the TV detail endpoint for TV shows — calling
                    // /tv/{movieId} for movies returns a slow 404 and blocks the
                    // task group for up to 12 seconds per movie result.
                    let detail: TMDBTVDetail? = r.isTV ? (try? await tmdb.getTVDetail(tmdbId: r.id)) : nil
                    // Server-verified playable trailer keys in rank order. The
                    // resolver only returns keys that are embeddable, public,
                    // processed, and not US-blocked, so the first key is trusted
                    // to play — no client-side ranking can replicate that.
                    async let resolveTask: [String]? = TrailerResolveService.resolve(tmdbId: r.id, isTV: r.isTV)
                    async let providerTask: [TMDBWatchProvider]? = try? tmdb.getWatchProviders(tmdbId: r.id, isTV: r.isTV)
                    let (resolved, poolOptional) = await (resolveTask, providerTask)
                    let pool = poolOptional ?? []

                    // Three-way handling of the resolver result:
                    //  * nil → the call failed; degrade to the unverified TMDB
                    //    key so a brief Supabase outage doesn't empty the feed.
                    //  * [] → the title has no playable trailer at all; drop it.
                    //  * [...] → verified keys; first is primary, rest fallback.
                    let candidates: [String]
                    if let resolved {
                        if resolved.isEmpty { return nil }
                        candidates = resolved
                    } else {
                        let single = (try? await (r.isTV ? tmdb.getTrailerKey(tmdbId: r.id) : tmdb.getMovieTrailerKey(tmdbId: r.id))) ?? nil
                        guard let single, !single.isEmpty else { return nil }
                        candidates = [single]
                    }
                    guard let key = candidates.first, !key.isEmpty, !pool.isEmpty else { return nil }
                    let fallbackKeys = Array(candidates.dropFirst())

                    // topProvider reproduces current behavior: the pool element
                    // with the lowest displayPriority (nil treated as large).
                    let topProvider = pool.min(by: {
                        ($0.displayPriority ?? Int.max) < ($1.displayPriority ?? Int.max)
                    })

                    // subscribedProvider: a recognized provider the user
                    // subscribes to. Apple is normalized so "apple" matches
                    // whether the stored id is "apple" or "appletv". When
                    // several qualify, the lowest displayPriority wins (which
                    // mirrors the existing flatrate > ads > free ranking).
                    let subscribedProvider: TMDBWatchProvider? = pool
                        .filter { ReelPlatform.recognizedKey(for: $0.providerName) != nil }
                        .filter { provider in
                            guard let recognized = ReelPlatform.recognizedKey(for: provider.providerName) else { return false }
                            if recognized == "apple" {
                                return subscribedServiceIds.contains("apple")
                                    || subscribedServiceIds.contains("appletv")
                            }
                            return subscribedServiceIds.contains(recognized)
                        }
                        .min(by: {
                            ($0.displayPriority ?? Int.max) < ($1.displayPriority ?? Int.max)
                        })

                    let chosen = subscribedProvider ?? topProvider
                    // Reels must point at an app users can actually open — skip titles
                    // with no verified US streaming provider.
                    guard let chosen, let _ = ReelPlatform.recognizedKey(for: chosen.providerName) else {
                        return nil
                    }

                    let name = detail?.name ?? r.displayName
                    let overview = (detail?.overview?.isEmpty == false ? detail?.overview : r.overview) ?? ""
                    let year = detail?.year ?? r.year
                    let genreName = detail?.genreNames.first ?? "DRAMA"
                    let plat = ReelPlatform.info(for: chosen.providerName)

                    let runtimeText: String = {
                        if let m = detail?.runtimeMinutes, let seasons = detail?.numberOfSeasons {
                            return "\(m)m avg · \(seasons) Season\(seasons == 1 ? "" : "s")"
                        } else if let m = detail?.runtimeMinutes {
                            return "\(m)m avg"
                        }
                        return "Trailer"
                    }()

                    let backdropPath = detail?.backdropPath ?? r.backdropPath
                    let posterPath = detail?.posterPath ?? r.posterPath
                    let backdrop = TMDBImage.url(backdropPath, size: .backdrop1280).flatMap { URL(string: $0) }
                    let poster = TMDBImage.url(posterPath, size: .poster342).flatMap { URL(string: $0) }
                    let thumb = URL(string: "https://img.youtube.com/vi/\(key)/maxresdefault.jpg")
                    // We no longer load a remote embed URL — YouTubePlayerView builds inline HTML
                    // from the trailerKey to avoid embed error 153 (referrer/origin restrictions).
                    let embed: URL? = URL(string: "https://www.youtube.com/watch?v=\(key)")
                    let identity = String(name.prefix(3)).uppercased()

                    return TrailerItem(
                        id: key,
                        tmdbId: r.id,
                        showName: name,
                        synopsis: overview,
                        genre: "\(genreName.uppercased())\(year.map { " · \($0)" } ?? "")",
                        runtime: runtimeText,
                        platformId: plat.id,
                        platformName: plat.name,
                        platformColor: plat.color,
                        platformTextColor: .white,
                        backdropURL: backdrop,
                        posterURL: poster,
                        trailerKey: key,
                        fallbackKeys: fallbackKeys,
                        thumbnailURL: thumb,
                        youtubeURL: embed,
                        deepLinkURL: nil,
                        voteAverage: detail?.voteAverage ?? (r.voteAverage ?? 0),
                        likes: 0,
                        comments: 0,
                        tab: tab,
                        identityCode: identity,
                        gradeColor: plat.grade,
                        isSponsored: false,
                        isTV: r.isTV
                    )
                }
            }
            var out: [TrailerItem] = []
            for await item in group {
                if let item { out.append(item) }
            }
            return out
        }
    }

    /// Builds Coming Soon reels from Watchmode's upcoming streaming releases.
    /// Filters to movie-type entries with a valid TMDB id and a source release
    /// date on or after today, deduplicates by tmdbId keeping the earliest
    /// date, fetches the YouTube trailer key, and assembles TrailerItems with
    /// a STREAMING <date> badge.
    private func buildComingSoonItems(from releases: [WatchmodeRelease]) async -> [TrailerItem] {
        // Parse and filter releases.
        let inDF = DateFormatter()
        inDF.dateFormat = "yyyy-MM-dd"
        inDF.locale = Locale(identifier: "en_US_POSIX")
        let today = Calendar.current.startOfDay(for: Date())

        let eligible: [(release: WatchmodeRelease, date: Date)] = releases.compactMap { r in
            guard r.type == "movie",
                  let tmdbId = r.tmdbId,
                  let dateStr = r.sourceReleaseDate,
                  let date = inDF.date(from: dateStr),
                  date >= today
            else { return nil }
            return (r, date)
        }

        // Deduplicate by tmdbId, keeping the earliest sourceReleaseDate.
        var bestByTmdb: [Int: (release: WatchmodeRelease, date: Date)] = [:]
        for entry in eligible {
            let tid = entry.release.tmdbId!
            if let existing = bestByTmdb[tid] {
                if entry.date < existing.date { bestByTmdb[tid] = entry }
            } else {
                bestByTmdb[tid] = entry
            }
        }
        let deduped = Array(bestByTmdb.values)

        let outDF = DateFormatter()
        outDF.dateFormat = "MMM d"
        outDF.locale = Locale(identifier: "en_US_POSIX")

        return await withTaskGroup(of: TrailerItem?.self) { group in
            for entry in deduped {
                let release = entry.release
                let releaseDate = entry.date
                let tmdbId = release.tmdbId!
                group.addTask { [tmdb] in
                    // Coming Soon is always movies — resolve server-verified
                    // playable keys, same three-way handling as buildItems.
                    let resolved = await TrailerResolveService.resolve(tmdbId: tmdbId, isTV: false)
                    let candidates: [String]
                    if let resolved {
                        if resolved.isEmpty { return nil }
                        candidates = resolved
                    } else {
                        let single = (try? await tmdb.getMovieTrailerKey(tmdbId: tmdbId)) ?? nil
                        guard let single, !single.isEmpty else { return nil }
                        candidates = [single]
                    }
                    guard let key = candidates.first, !key.isEmpty else { return nil }
                    let fallbackKeys = Array(candidates.dropFirst())

                    let name = release.title ?? ""
                    let badgeText = "STREAMING \(outDF.string(from: releaseDate).uppercased())"
                    let thumb = URL(string: "https://img.youtube.com/vi/\(key)/maxresdefault.jpg")
                    let embed: URL? = URL(string: "https://www.youtube.com/watch?v=\(key)")
                    let identity = String(name.prefix(3)).uppercased()

                    return TrailerItem(
                        id: key,
                        tmdbId: tmdbId,
                        showName: name,
                        synopsis: "",
                        genre: "MOVIE",
                        runtime: "Movie",
                        platformId: "coming_soon",
                        platformName: badgeText,
                        platformColor: Color.navy,
                        platformTextColor: .white,
                        backdropURL: thumb,
                        posterURL: thumb,
                        trailerKey: key,
                        fallbackKeys: fallbackKeys,
                        thumbnailURL: thumb,
                        youtubeURL: embed,
                        deepLinkURL: nil,
                        voteAverage: 0,
                        likes: 0,
                        comments: 0,
                        tab: .comingSoon,
                        identityCode: identity,
                        gradeColor: Color.navy.opacity(0.15),
                        isSponsored: false,
                        isTV: false
                    )
                }
            }
            var out: [TrailerItem] = []
            for await item in group {
                if let item { out.append(item) }
            }
            return out
        }
    }

private func makeRakutenAdReels() -> [TrailerItem] {
        let selected = AuthViewModel.shared.selectedServices
            .map { $0.lowercased() }
        let pool: [(id:String, name:String, color:String,
                     headline:String, synopsis:String,
                     backdrop:String, identity:String,
                     ytKey:String)] = [
            ("netflix","NETFLIX","E50914",
             "Stream the world's biggest hits",
             "Unlimited movies, TV and more. Cancel anytime.",
             "https://image.tmdb.org/t/p/w1280/56v2KjBlU4XaOv9rVYEQypROD7P.jpg",
             "NFX", "XEMwSdne6UE"),
            ("hbo","MAX","001EE0",
             "Home of HBO. Home of Max.",
             "The greatest shows, movies and Max Originals.",
             "https://image.tmdb.org/t/p/w1280/etj8E2o0Bud0HkONVQPjyCkIvpv.jpg",
             "MAX", "q9GfZtJOBFw"),
            ("hulu","HULU","1CE783",
             "Live TV + on-demand.",
             "Watch TV, movies, Hulu Originals and live sports.",
             "https://image.tmdb.org/t/p/w1280/3V4kLQg0kSqe6sqSlFBVPDZlTqf.jpg",
             "HLU", "aHjkaQ1K5_4"),
            ("disney","DISNEY+","113CCF",
             "Marvel, Star Wars and more.",
             "Infinite worlds of entertainment for the family.",
             "https://image.tmdb.org/t/p/w1280/9yBVqNruk6Ykrwc32qDbHTE0z5o.jpg",
             "D+", "JAOcxc96hxQ"),
            ("appletv","APPLE TV+","101010",
             "Award-winning originals.",
             "Critically acclaimed shows. New every month.",
             "https://image.tmdb.org/t/p/w1280/4MC3p4zRCGkpnJzSjkGIr3MUJPN.jpg",
             "ATV", "FiHOjQ0sCj8"),
            ("prime","PRIME VIDEO","00A8E1",
             "Included with Prime.",
             "Thursday Night Football and Amazon Originals.",
             "https://image.tmdb.org/t/p/w1280/kqjL17yufvn9OVLyXYpvtyrFfak.jpg",
             "PV", "q5w0mVONdT0"),
            ("paramount","PARAMOUNT+","0064FF",
             "NFL on CBS and live sports.",
             "Stream Paramount+ with Showtime available.",
             "https://image.tmdb.org/t/p/w1280/5UkzNSOK561c2QRy2Zr4AkADzLT.jpg",
             "P+", "rBP9QQVdp9o"),
            ("peacock","PEACOCK","333333",
             "Stream free. Or go Premium.",
             "NFL, Premier League, WWE and NBC hits.",
             "https://image.tmdb.org/t/p/w1280/1Rr5SrvHxMXHu5RjKpaMba8VTzi.jpg",
             "PCK", "RY8p_7KQNtE")
        ]
        let eligible = pool.filter { !selected.contains($0.id) }
        let source = eligible.isEmpty ? pool : eligible
        return source.map { e in
            TrailerItem(
                id: "rak-\(e.id)-\(Int.random(in:1000...9999))",
                tmdbId: -1,
                showName: e.headline,
                synopsis: e.synopsis,
                genre: "SPONSORED · \(e.name)",
                runtime: "Limited offer · Tap to start",
                platformId: e.id,
                platformName: e.name,
                platformColor: Color(hex: e.color),
                platformTextColor: .white,
                backdropURL: URL(string: e.backdrop),
                posterURL: URL(string: e.backdrop),
                trailerKey: e.ytKey,
                thumbnailURL: URL(string: e.backdrop),
                youtubeURL: nil,
                deepLinkURL: nil,
                voteAverage: 0,
                likes: 0,
                comments: 0,
                tab: .forYou,
                identityCode: e.identity,
                gradeColor: Color(hex: e.color).opacity(0.18),
                isSponsored: true
            )
        }
    }

    // MARK: - Mutations

    func isReminded(_ trailer: TrailerItem) -> Bool {
        guard trailer.tmdbId > 0, !trailer.isSponsored else { return false }
        return ReleaseReminderService.shared.isReminded(String(trailer.tmdbId))
    }

    func toggleReminder(_ trailer: TrailerItem) async {
        guard trailer.tmdbId > 0, !trailer.isSponsored else { return }
        await ReleaseReminderService.shared.toggleReminder(
            titleId: String(trailer.tmdbId),
            tmdbId: trailer.tmdbId
        )
    }

    func toggleLike(_ trailer: TrailerItem) {
        guard !trailer.isSponsored, trailer.tmdbId > 0 else { return }
        let titleId = String(trailer.tmdbId)
        let wasLiked = SocialViewModel.shared.isLiked(titleId)
        let mediaType = trailer.isTV ? "tv" : "movie"
        let likeTmdbId = trailer.tmdbId
        Task { await SocialViewModel.shared.toggleLike(titleId: titleId, mediaType: mediaType, tmdbId: likeTmdbId) }
        if !wasLiked {
            WatchIntentLogger.shared.log(
                eventType: .trailerLiked,
                titleId: titleId
            )
        }
    }

    func toggleSave(_ trailer: TrailerItem) async {
        let titleId = String(trailer.tmdbId)
        // Single source of truth — ask the shared streams store whether the
        // title is already saved instead of duplicating state in Reels.
        if StreamsViewModel.shared.userStreams.contains(where: { $0.titleId == titleId }) {
            await StreamsViewModel.shared.removeFromMyStreams(titleId: titleId)
        } else {
            await StreamsViewModel.shared.addToMyStreams(
                titleId: titleId,
                title: trailer.showName,
                posterUrl: trailer.posterURL?.absoluteString,
                platform: trailer.platformId,
                isTV: trailer.isTV
            )
        }
    }

    func likeCount(for trailer: TrailerItem) -> Int {
        SocialViewModel.shared.likes(String(trailer.tmdbId))
    }

    func isLiked(_ trailer: TrailerItem) -> Bool {
        SocialViewModel.shared.isLiked(String(trailer.tmdbId))
    }

    func toggleWatched(_ trailer: TrailerItem) {
        guard !trailer.isSponsored, trailer.tmdbId > 0 else { return }
        let titleId = String(trailer.tmdbId)
        let titleName = trailer.showName
        let mediaType = trailer.isTV ? "tv" : "movie"
        let watchedTmdbId = trailer.tmdbId
        Task { await SocialViewModel.shared.toggleWatched(titleId: titleId, titleName: titleName, mediaType: mediaType, tmdbId: watchedTmdbId) }
    }

    func isWatched(_ trailer: TrailerItem) -> Bool {
        SocialViewModel.shared.isWatched(String(trailer.tmdbId))
    }

    func commentCount(for trailer: TrailerItem) -> Int {
        SocialViewModel.shared.commentTotal(String(trailer.tmdbId))
    }
    /// Mirrors `StreamsViewModel.userStreams` so the Reels rail button stays
    /// in sync with every other save surface (Episode/Sports sheets, Home
    /// panel, Profile). Reading the shared store also automatically subscribes
    /// the surrounding view body to its updates via @Observable tracking.
    func isSaved(_ trailer: TrailerItem) -> Bool {
        let titleId = String(trailer.tmdbId)
        return StreamsViewModel.shared.userStreams.contains { $0.titleId == titleId }
    }

    func jumpToTab(_ tab: ReelTab) {
        guard let idx = allTrailers.firstIndex(where: { $0.tab == tab }) else { return }
        currentIndex = idx
    }

    // MARK: TVDB Enrichment

    /// Looks up the TVDB series id from the TMDB id, fetches the next upcoming
    /// episode and series status, and stores the result in `tvdbCache` so the
    /// reel card can display an air-date banner without blocking feed load.
    func enrichWithTVDB(tmdbId: Int) async {
        guard tvdbCache[tmdbId] == nil else { return }
        guard let tvdbId = try? await TheTVDBService.shared.tvdbSeriesId(forTMDBId: tmdbId)
        else {
            tvdbCache[tmdbId] = TVDBReelInfo(nextAirDate: nil, episodeCode: nil, episodeName: nil, seriesStatus: nil)
            return
        }
        async let nextEp = try? TheTVDBService.shared.nextEpisode(seriesId: tvdbId)
        async let series = try? TheTVDBService.shared.seriesExtended(tvdbId)
        let (ep, s) = await (nextEp, series)
        let code: String? = {
            guard let sn = ep?.seasonNumber, let en = ep?.episodeNumber else { return nil }
            return "S\(sn) E\(en)"
        }()
        tvdbCache[tmdbId] = TVDBReelInfo(
            nextAirDate: ep?.airDate,
            episodeCode: code,
            episodeName: ep?.name,
            seriesStatus: s?.status?.name
        )
    }
}

// MARK: - Reels Screen

struct ReelsScreen: View {
    @State private var vm = ReelsViewModel.shared
    @State private var social = SocialViewModel.shared
    @State private var isMuted: Bool = false
    @State private var isPlaying: Bool = true
    @State private var showComments: Bool = false
    @State private var showShare: Bool = false
    @State private var showDetail: Bool = false
    @State private var detailSubject: DetailSubject?
    @State private var scrolledID: Int? = 0
    @State private var pendingInterstitialAt: Int? = nil
    /// Timestamp of the last interstitial presentation; used with the swipe
    /// count to enforce the 6-swipe / 90-second cadence.
    @State private var lastInterstitialDate: Date = .distantPast
    /// Timestamp when the current reel became active. Used to compute
    /// actual watch duration for the stats engine.
    @State private var reelStartTime: Date = Date()
    /// Live translation while the user drags down to dismiss. Used to slide
    /// the whole feed down for visual feedback before commit.
    @State private var dismissDragOffset: CGFloat = 0
    @Environment(\.tabBarVisibility) private var tabBarVisibility

    /// Called when the user taps the dismiss chevron or completes a
    /// downward swipe-to-dismiss gesture. ContentView routes the user back
    /// to whichever tab they were on before opening Reels.
    let onDismiss: () -> Void

    /// When non-nil, the screen renders exactly these title-scoped reels
    /// (Trailers & Clips) instead of the global shared feed, starting at
    /// `injectedStartIndex`. In this mode the shared `ReelsViewModel` is never
    /// touched, the category pills are hidden, and each reel shows the
    /// embedded streaming-service switcher.
    var injectedReels: [TrailerItem]? = nil
    var injectedStartIndex: Int = 0
    /// Local paging position for the injected title-scoped feed.
    @State private var injectedScrolledID: Int?

    init(onDismiss: @escaping () -> Void, injectedReels: [TrailerItem]? = nil, injectedStartIndex: Int = 0) {
        self.onDismiss = onDismiss
        self.injectedReels = injectedReels
        self.injectedStartIndex = injectedStartIndex
        _injectedScrolledID = State(initialValue: injectedReels == nil ? nil : injectedStartIndex)
    }

    var body: some View {
        GeometryReader { geo in
            // Use the FULL screen size for each reel so paging height matches the
            // visible scrollable area exactly (otherwise neighbouring reels peek
            // above the floating nav and the screen looks "split in two").
            let fullSize = CGSize(
                width: geo.size.width,
                height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            )
            let topInset = geo.safeAreaInsets.top
            let bottomInset = geo.safeAreaInsets.bottom
            ZStack {
                Color(hex: "04090F").ignoresSafeArea()

                if let injected = injectedReels {
                    injectedScroll(injected, size: fullSize, topInset: topInset, bottomInset: bottomInset)
                } else if vm.isLoading && vm.allTrailers.isEmpty {
                    LoadingSpinner().frame(width: 36, height: 36)
                } else if vm.allTrailers.isEmpty {
                    EmptyReelsState()
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(vm.allTrailers.enumerated()), id: \.element.id) { idx, trailer in
                                reelCell(trailer: trailer, index: idx, size: fullSize, topInset: topInset, bottomInset: bottomInset)
                                    .frame(width: fullSize.width, height: fullSize.height)
                                    .id(idx)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $scrolledID)
                    .scrollIndicators(.hidden)
                    .ignoresSafeArea()
                    .onChange(of: scrolledID) { oldValue, newValue in
                        guard let newValue, newValue != vm.currentIndex else { return }
                        isPlaying = true
                        let prevIdx = vm.currentIndex
                        vm.currentIndex = newValue
                        vm.reelSwipeCount += 1
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        // Log the PREVIOUS reel with its actual watch duration.
                        let elapsed = Date().timeIntervalSince(reelStartTime)
                        if let prevTrailer = vm.allTrailers[safe: prevIdx] {
                            logTrailerViewed(prevTrailer, elapsedSeconds: elapsed)
                        }
                        // Log the NEW reel as started (no duration yet).
                        if let trailer = vm.allTrailers[safe: newValue] {
                            logTrailerViewed(trailer, elapsedSeconds: nil)
                        }
                        reelStartTime = Date()
                        prefetchNeighbors(around: newValue)
                        // Lazily enrich current + next reel with TVDB episode data.
                        if let trailer = vm.allTrailers[safe: newValue], trailer.tmdbId > 0, !trailer.isSponsored {
                            Task { await vm.enrichWithTVDB(tmdbId: trailer.tmdbId) }
                        }
                        if let nextTrailer = vm.allTrailers[safe: newValue + 1], nextTrailer.tmdbId > 0, !nextTrailer.isSponsored {
                            Task { await vm.enrichWithTVDB(tmdbId: nextTrailer.tmdbId) }
                        }
                        _ = prevIdx
                        refreshSocialCounts(around: newValue)
                        // Background pagination — top up the feed once the
                        // user is within six reels of the end.
                        if newValue >= vm.allTrailers.count - 6 {
                            Task { await vm.loadMoreTrailers() }
                        }
                        // Interstitial cadence: fire only after at least 8
                        // total swipes, 6 swipes since the last interstitial,
                        // and 90 seconds of wall-clock since the last one —
                        // and only when an ad is actually preloaded.
                        if vm.reelSwipeCount >= 8,
                           vm.reelSwipeCount - (pendingInterstitialAt ?? 0) >= 6,
                           Date().timeIntervalSince(lastInterstitialDate) >= 90,
                           AdManager.shared.hasInterstitial {
                            pendingInterstitialAt = vm.reelSwipeCount
                            lastInterstitialDate = Date()
                            showInterstitial { }
                        }
                    }
                }

                // Top-left dismiss chevron + tab pills. Sits above all reel
                // content with a glassy background so it stays legible.
                VStack(spacing: 0) {
                    HStack {
                        Button(action: handleDismiss) {
                            Image(systemName: "chevron.left")
                                .scaledFont(size: 17, weight: .bold)
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.45))
                                )
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                                .shadow(color: .black.opacity(0.35), radius: 10, y: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 14)

                        // Tab pills — tap to jump to the first reel of each section.
                        // Hidden in the injected title-scoped mode.
                        if injectedReels == nil {
                            HStack(spacing: 13) {
                                ForEach(ReelTab.allCases, id: \.self) { tab in
                                    TabPill(
                                        tab: tab,
                                        active: currentTrailer?.tab == tab,
                                        action: {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            if let idx = vm.allTrailers.firstIndex(where: { $0.tab == tab }) {
                                                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                                                    scrolledID = idx
                                                }
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.leading, 12)
                        }

                        Spacer()
                    }
                    .padding(.top, topInset)
                    Spacer()
                }
                .ignoresSafeArea()
            }
            .offset(y: dismissDragOffset)
            // Swipe-down-to-dismiss. Runs *simultaneously* with the inner
            // paging ScrollView, but we only react to drags that begin at the
            // first reel and pull downward — so neighbour reel paging is
            // untouched.
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onChanged { value in
                        guard canDismissSwipe, value.translation.height > 0 else { return }
                        // Resist a little so the drag feels weighty.
                        dismissDragOffset = value.translation.height * 0.55
                    }
                    .onEnded { value in
                        let translation = value.translation.height
                        let predicted = value.predictedEndTranslation.height
                        if canDismissSwipe && translation > 110 && predicted > 180 {
                            handleDismiss()
                        } else {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                dismissDragOffset = 0
                            }
                        }
                    }
            )
        }
        .task {
            // Initialise the ad SDK so interstitials and native ads begin
            // preloading. No-op on the cloud simulator.
            AdManager.shared.start()
            // Hide the floating tab bar so the reel fills the entire screen.
            tabBarVisibility.hide()
            // Injected title-scoped mode never touches the shared feed.
            guard injectedReels == nil else { return }
            await vm.loadIfNeeded()
            if scrolledID == nil { scrolledID = 0 }
            prefetchNeighbors(around: vm.currentIndex)
            // Refresh social counts for the first visible reel and its neighbours.
            refreshSocialCounts(around: vm.currentIndex)
        }
        .onAppear { tabBarVisibility.hide() }
        .onDisappear { tabBarVisibility.show() }
        .sheet(isPresented: $showComments) {
            if let trailer = currentTrailer, !trailer.isSponsored, trailer.tmdbId > 0 {
                TitleCommentsSheet(
                    titleId: String(trailer.tmdbId),
                    title: trailer.showName,
                    subtitle: trailer.genre,
                    posterUrl: trailer.posterURL?.absoluteString ?? trailer.backdropURL?.absoluteString,
                    posterColors: [trailer.platformColor.opacity(0.85), Color(hex: "04090F")],
                    accent: Color(hex: "F5821F")
                )
                .presentationDetents([.fraction(0.72)])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(red: 10/255, green: 16/255, blue: 26/255).opacity(0.96))
            }
        }
        .sheet(isPresented: $showShare) {
            if let trailer = currentTrailer {
                TrailerShareSheet(trailer: trailer)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Color(red: 10/255, green: 16/255, blue: 26/255).opacity(0.96))
            }
        }
        .sheet(item: $detailSubject) { subject in
            EpisodeDetailSheet(subject: subject)
        }
    }

    /// Builds a `PosterShow` from a reel so the detail sheet — which is
    /// designed around home-screen subjects — can resolve the title's
    /// Watchmode source, overview, and deeplink the same way it does
    /// everywhere else in the app.
    private func posterShow(from trailer: TrailerItem) -> PosterShow {
        PosterShow(
            title: trailer.showName,
            meta: trailer.genre.capitalized,
            posterColors: [trailer.platformColor.opacity(0.85), Color(hex: "04090F")],
            symbol: "play.rectangle",
            posterUrl: trailer.posterURL?.absoluteString ?? trailer.backdropURL?.absoluteString,
            tmdbId: trailer.tmdbId > 0 ? trailer.tmdbId : nil,
            isTV: trailer.isTV
        )
    }

    private var currentTrailer: TrailerItem? {
        if let injected = injectedReels {
            return injected[safe: injectedScrolledID ?? injectedStartIndex]
        }
        guard vm.allTrailers.indices.contains(vm.currentIndex) else { return nil }
        return vm.allTrailers[vm.currentIndex]
    }

    /// Only allow the swipe-down dismiss when the user is on the very first
    /// reel — otherwise downward swipes mean "previous reel" and we mustn't
    /// fight the paging ScrollView.
    private var canDismissSwipe: Bool {
        if injectedReels != nil {
            return (injectedScrolledID ?? injectedStartIndex) == 0
        }
        return vm.currentIndex == 0 && !vm.allTrailers.isEmpty
    }

    private func handleDismiss() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeOut(duration: 0.24)) {
            dismissDragOffset = 0
        }
        onDismiss()
    }

    @ViewBuilder
    private func reelCell(trailer: TrailerItem, index: Int, size: CGSize, topInset: CGFloat, bottomInset: CGFloat) -> some View {
        let isCurrent = index == vm.currentIndex
        ReelView(
                trailer: trailer,
                tvdbInfo: vm.tvdbCache[trailer.tmdbId],
                size: size,
                topInset: topInset,
                bottomInset: bottomInset,
                isPlaying: isCurrent && isPlaying,
                isMuted: isMuted,
                isCurrent: isCurrent,
                likeCount: vm.likeCount(for: trailer),
                isLiked: vm.isLiked(trailer),
                isWatched: vm.isWatched(trailer),
                isSaved: vm.isSaved(trailer),
                commentCount: vm.commentCount(for: trailer),
                activeTab: trailer.tab,
                currentIndex: vm.currentIndex,
                totalCount: vm.allTrailers.count,
                onEnded: (index == vm.allTrailers.count - 1 && vm.allSourcesExhausted)
                    ? nil
                    : {
                        guard index == vm.currentIndex else { return }
                        if vm.allTrailers.indices.contains(index + 1) {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                                scrolledID = index + 1
                            }
                        } else {
                            // Reached the true last reel before pagination
                            // caught up — load more, then advance only if the
                            // next reel now exists and the user hasn't moved.
                            Task {
                                await vm.loadMoreTrailers()
                                guard vm.currentIndex == index,
                                      vm.allTrailers.indices.contains(index + 1) else { return }
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                                    scrolledID = index + 1
                                }
                            }
                        }
                    },
                isReminded: vm.isReminded(trailer),
                onTogglePlay: { isPlaying.toggle() },
                onToggleMute: {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    isMuted.toggle()
                    WatchIntentLogger.shared.log(eventType: .muteToggled, titleId: String(trailer.tmdbId), metadata: ["muted": !isMuted, "trailer_key": trailer.trailerKey])
                },
                onLike: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    vm.toggleLike(trailer)
                },
                onComments: {
                    showComments = true
                    WatchIntentLogger.shared.log(
                        eventType: .commentsOpened,
                        titleId: String(trailer.tmdbId),
                        metadata: ["trailer_key": trailer.trailerKey]
                    )
                },
                onSave: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task { await vm.toggleSave(trailer) }
                },
                onWatched: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    vm.toggleWatched(trailer)
                },
                onShare: { showShare = true },
                onTabSelect: { tab in
                    guard let idx = vm.allTrailers.firstIndex(where: { $0.tab == tab }) else { return }
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                        scrolledID = idx
                    }
                },
                onSponsorCTA: {
                        RakutenManager.shared.openAffiliateLink(
                            serviceId: trailer.platformId,
                            metadata: [
                                "source": "sponsored_reel",
                                "position": index
                            ]
                        )
                        WatchIntentLogger.shared.log(
                            eventType: .sponsoredReelTapped,
                            platformId: trailer.platformId,
                            metadata: ["position": index]
                        )
                },
                onShowDetail: {
                    guard !trailer.isSponsored, trailer.tmdbId > 0 else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    detailSubject = .show(posterShow(from: trailer))
                    WatchIntentLogger.shared.log(
                        eventType: .episodeDetailViewed,
                        titleId: String(trailer.tmdbId),
                        platformId: trailer.platformId,
                        metadata: ["source": "reels_play_pill"]
                    )
                },
                onNotify: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    Task { await vm.toggleReminder(trailer) }
                }
            )
            .frame(width: size.width, height: size.height)
            .id(index)
    }

    // MARK: - Injected title-scoped feed

    /// Renders the fixed title-scoped reel list in the same paging ScrollView
    /// used by the global feed, starting at `injectedStartIndex`. Never touches
    /// the shared `ReelsViewModel`.
    @ViewBuilder
    private func injectedScroll(_ feed: [TrailerItem], size: CGSize, topInset: CGFloat, bottomInset: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(Array(feed.enumerated()), id: \.element.id) { idx, trailer in
                    injectedReelCell(trailer: trailer, index: idx, feed: feed, size: size, topInset: topInset, bottomInset: bottomInset)
                        .frame(width: size.width, height: size.height)
                        .id(idx)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $injectedScrolledID)
        .scrollIndicators(.hidden)
        .ignoresSafeArea()
        .onChange(of: injectedScrolledID) { _, newValue in
            guard let newValue else { return }
            isPlaying = true
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            if let t = feed[safe: newValue], t.tmdbId > 0 {
                Task { await SocialViewModel.shared.refreshCounts(titleId: String(t.tmdbId)) }
            }
        }
    }

    @ViewBuilder
    private func injectedReelCell(trailer: TrailerItem, index: Int, feed: [TrailerItem], size: CGSize, topInset: CGFloat, bottomInset: CGFloat) -> some View {
        let isCurrent = index == (injectedScrolledID ?? injectedStartIndex)
        ReelView(
            trailer: trailer,
            tvdbInfo: nil,
            size: size,
            topInset: topInset,
            bottomInset: bottomInset,
            isPlaying: isCurrent && isPlaying,
            isMuted: isMuted,
            isCurrent: isCurrent,
            likeCount: social.likes(String(trailer.tmdbId)),
            isLiked: social.isLiked(String(trailer.tmdbId)),
            isWatched: social.isWatched(String(trailer.tmdbId)),
            isSaved: StreamsViewModel.shared.userStreams.contains { $0.titleId == String(trailer.tmdbId) },
            commentCount: social.commentTotal(String(trailer.tmdbId)),
            activeTab: trailer.tab,
            currentIndex: index,
            totalCount: feed.count,
            onEnded: {
                guard index == (injectedScrolledID ?? injectedStartIndex) else { return }
                if feed.indices.contains(index + 1) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                        injectedScrolledID = index + 1
                    }
                }
            },
            isReminded: false,
            onTogglePlay: { isPlaying.toggle() },
            onToggleMute: {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                isMuted.toggle()
            },
            onLike: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                let tid = String(trailer.tmdbId)
                let mediaType = trailer.isTV ? "tv" : "movie"
                Task { await SocialViewModel.shared.toggleLike(titleId: tid, mediaType: mediaType, tmdbId: trailer.tmdbId) }
            },
            onComments: { showComments = true },
            onSave: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                let tid = String(trailer.tmdbId)
                Task {
                    if StreamsViewModel.shared.userStreams.contains(where: { $0.titleId == tid }) {
                        await StreamsViewModel.shared.removeFromMyStreams(titleId: tid)
                    } else {
                        await StreamsViewModel.shared.addToMyStreams(
                            titleId: tid,
                            title: trailer.showName,
                            posterUrl: trailer.posterURL?.absoluteString,
                            platform: trailer.platformId,
                            isTV: trailer.isTV
                        )
                    }
                }
            },
            onWatched: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                let tid = String(trailer.tmdbId)
                let mediaType = trailer.isTV ? "tv" : "movie"
                Task { await SocialViewModel.shared.toggleWatched(titleId: tid, titleName: trailer.showName, mediaType: mediaType, tmdbId: trailer.tmdbId) }
            },
            onShare: { showShare = true },
            onTabSelect: { _ in },
            onSponsorCTA: {},
            onShowDetail: {},
            onNotify: {},
            isInjected: true
        )
        .frame(width: size.width, height: size.height)
        .id(index)
    }

    private func prefetchNeighbors(around index: Int) {}

    /// Lazily fetch like + comment counts for the current reel and its
    /// immediate neighbours so the right-rail numbers are live by the time
    /// the user swipes. Sponsored reels and entries with non-positive
    /// tmdbId are skipped.
    private func refreshSocialCounts(around index: Int) {
        let neighbours = [index - 1, index, index + 1]
        for i in neighbours {
            guard let trailer = vm.allTrailers[safe: i],
                  !trailer.isSponsored,
                  trailer.tmdbId > 0 else { continue }
            let titleId = String(trailer.tmdbId)
            Task {
                await SocialViewModel.shared.refreshCounts(titleId: titleId)
            }
            Task {
                await ReleaseReminderService.shared.refreshReminded(titleId: titleId)
            }
        }
    }

    private func showInterstitial(_ completion: @escaping () -> Void) {
        guard let root = UIApplication.shared.topViewController() else {
            completion(); return
        }
        WatchIntentLogger.shared.log(
            eventType: .adImpression,
            metadata: ["ad_type": "interstitial", "position": vm.reelSwipeCount]
        )
        AdManager.shared.showInterstitial(from: root, completion: completion)
    }

    private func logTrailerViewed(_ trailer: TrailerItem, elapsedSeconds: Double?) {
        if trailer.isSponsored {
            WatchIntentLogger.shared.log(
                eventType: .sponsoredReelViewed,
                platformId: trailer.platformId,
                metadata: ["position": vm.currentIndex, "sponsor": trailer.platformName],
                watchDurationSeconds: elapsedSeconds
            )
        } else {
            WatchIntentLogger.shared.log(
                eventType: .trailerViewed,
                titleId: String(trailer.tmdbId),
                platformId: trailer.platformId,
                metadata: [
                    "trailer_key": trailer.trailerKey,
                    "tab": trailer.tab.rawValue
                ],
                watchDurationSeconds: elapsedSeconds
            )
        }
    }


}

// MARK: - Single Reel

private struct ReelView: View {
    let trailer: TrailerItem
    let tvdbInfo: TVDBReelInfo?
    let size: CGSize
    let topInset: CGFloat
    let bottomInset: CGFloat
    let isPlaying: Bool
    let isMuted: Bool
    let isCurrent: Bool
    let likeCount: Int
    let isLiked: Bool
    let isWatched: Bool
    let isSaved: Bool
    let commentCount: Int
    let activeTab: ReelTab
    let currentIndex: Int
    let totalCount: Int
    var onEnded: (() -> Void)? = nil

    let isReminded: Bool
    let onTogglePlay: () -> Void
    let onToggleMute: () -> Void
    let onLike: () -> Void
    let onComments: () -> Void
    let onSave: () -> Void
    let onWatched: () -> Void
    let onShare: () -> Void
    let onTabSelect: (ReelTab) -> Void
    let onSponsorCTA: () -> Void
    let onShowDetail: () -> Void
    let onNotify: () -> Void
    /// Title-scoped mode: replaces the Watch pill with the streaming-service
    /// switcher, shows the video-type chip, and suppresses the glass ad.
    var isInjected: Bool = false

    @State private var contentOpacity: Double = 0.4
    @State private var likeBounce: CGFloat = 1.0
    /// Index into the candidate list: 0 = `trailer.trailerKey`, N = `fallbackKeys[N-1]`.
    @State private var candidateIndex: Int = 0
    /// Terminal state once every candidate has raised an embed error — the reel
    /// then collapses to its backdrop, exactly like the old single-key path.
    @State private var allCandidatesFailed: Bool = false
    @State private var playbackProgress: Double = 0
    @State private var showControls: Bool = false
    @State private var controlsFadeTask: Task<Void, Never>?
    @State private var seekToFraction: Double = -1
    @State private var glassAdDismissed: Bool = false
    @State private var glassAdTargets: [(serviceId: String, name: String, color: Color, tagline: String)] = []
    @State private var adPage: Int = 0
    @State private var glassAdVisible: Bool = false
    @State private var glassAdFadeTask: Task<Void, Never>? = nil
    @State private var adAdvanceTask: Task<Void, Never>? = nil

    /// The YouTube video id currently loading: the primary key at index 0, or
    /// the corresponding fallback key thereafter.
    private var activeKey: String {
        candidateIndex == 0 ? trailer.trailerKey : (trailer.fallbackKeys[safe: candidateIndex - 1] ?? trailer.trailerKey)
    }

    private func resolveGlassAds(count: Int) -> [(serviceId: String, name: String, color: Color, tagline: String)] {
        let current = trailer.platformId.lowercased()
        let selected = AuthViewModel.shared.selectedServices
            .map { $0.lowercased() }
        let pool: [(String, String, Color, String)] = [
            ("netflix", "Netflix", Color(red:0xE5/255, green:0x09/255, blue:0x14/255), "Unlimited movies, TV and more. Cancel anytime."),
            ("hbo", "Max", Color(red:0x00/255, green:0x1E/255, blue:0xE0/255), "The greatest shows, movies and Max Originals."),
            ("hulu", "Hulu", Color(red:0x1C/255, green:0xE7/255, blue:0x83/255), "Watch TV, movies, Hulu Originals and live sports."),
            ("disney", "Disney+", Color(red:0x0E/255, green:0x29/255, blue:0x3F/255), "Infinite worlds of entertainment for the family."),
            ("appletv", "Apple TV+", Color.black, "Critically acclaimed shows. New every month."),
            ("prime", "Prime Video", Color(red:0x1A/255, green:0x20/255, blue:0x2C/255), "Thursday Night Football and Amazon Originals."),
            ("paramount","Paramount+", Color(red:0x00/255, green:0x64/255, blue:0xFF/255), "Stream Paramount+ with Showtime available."),
            ("peacock", "Peacock", Color.black, "NFL, Premier League, WWE and NBC hits.")
        ]
        // Prefer services the user doesn't already own AND aren't the
        // current platform. If everything is owned, drop the owned filter so
        // an ad still appears (only excluding the current platform). If even
        // that's empty, fall back to the full pool.
        let preferred = pool.filter { entry in
            entry.0 != current && !selected.contains(entry.0)
        }
        let secondary = pool.filter { $0.0 != current }
        let eligible: [(String, String, Color, String)]
        if !preferred.isEmpty { eligible = preferred }
        else if !secondary.isEmpty { eligible = secondary }
        else { eligible = pool }
        guard !eligible.isEmpty else { return [] }
        // Rotate so different shows lead with different services.
        let shift = abs(trailer.tmdbId) % eligible.count
        let rotated = Array(eligible[shift...] + eligible[..<shift])
        return Array(rotated.prefix(count))
    }



    var body: some View {
        ZStack {
            // Layer 1 — backdrop
            RemoteImage(url: trailer.backdropURL,
                        contentMode: .fill,
                        fallbackColors: [trailer.platformColor.opacity(0.6), Color(hex: "04090F")])
                .frame(width: size.width, height: size.height)
                .clipped()

            // Layer 2 — subject silhouette blur
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(width: size.width * 0.60, height: size.height * 0.35)
                .blur(radius: 28)
                .position(x: size.width * 0.45, y: size.height * 0.65)
                .allowsHitTesting(false)

            // Layer 3 — atmospheric depth
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: size.width * 1.30, height: size.height * 0.45)
                .blur(radius: 40)
                .position(x: size.width * 0.5, y: size.height * 0.375)
                .allowsHitTesting(false)

            // Layer 4 — colour grade
            trailer.gradeColor
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Layer 6 — motion blur hint
            LinearGradient(colors: [.clear, .white.opacity(0.06), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 40)
                .position(x: size.width / 2, y: size.height * 0.475)
                .allowsHitTesting(false)

            // Layer 7 — identity letterforms
            Text(trailer.identityCode)
                .scaledFont(size: 240, weight: .black)
                .foregroundStyle(Color.white.opacity(0.06))
                .tracking(-9.6)
                .offset(y: -80)
                .allowsHitTesting(false)

            // Layer 8 — YouTube embed inside the letterbox window.
            // The cloud iOS simulator cannot decode H.264 video inside WKWebView,
            // so we show the trailer thumbnail with a tap-to-open overlay there.
            // On real devices we render via inline HTML with baseURL = youtube.com
            // so the IFrame Player API treats it as same-origin and doesn't throw
            // error 150/153 for videos with embed restrictions.
            if !trailer.trailerKey.isEmpty, !allCandidatesFailed {
                #if targetEnvironment(simulator)
                SimulatorTrailerPoster(trailer: trailer, videoKey: activeKey)
                    .frame(width: size.height * 16 / 9, height: size.height)
                    .position(x: size.width / 2, y: size.height / 2)
                #else
                if isCurrent {
                    ZStack {
                        // Poster sits underneath so the reel is never blank
                        // while the IFrame embed loads.
                        SimulatorTrailerPoster(trailer: trailer, videoKey: activeKey)
                        YouTubePlayerView(
                            videoId: activeKey,
                            isMuted: isMuted,
                            isPlaying: isPlaying,
                            progress: $playbackProgress,
                            seekToFraction: $seekToFraction,
                            onEmbedError: {
                                // Advance to the next candidate; only collapse to
                                // the backdrop once every candidate has failed.
                                if candidateIndex < trailer.fallbackKeys.count {
                                    candidateIndex += 1
                                    playbackProgress = 0
                                } else {
                                    allCandidatesFailed = true
                                }
                            },
                            onEnded: onEnded
                        )
                        .allowsHitTesting(false)
                    }
                    .frame(width: size.height * 16 / 9, height: size.height)
                    .clipped()
                    .position(x: size.width / 2, y: size.height / 2)
                } else {
                    // Neighbors show poster only — avoids spinning up multiple players simultaneously.
                    SimulatorTrailerPoster(trailer: trailer, videoKey: activeKey)
                        .frame(width: size.height * 16 / 9, height: size.height)
                        .position(x: size.width / 2, y: size.height / 2)
                        .allowsHitTesting(false)
                }
                #endif
            }

            // Full-screen tap target for play/pause toggle.
            // Rendered beneath interactive overlays so the right rail,
            // glass ad chip, and scrubber always receive taps first.
            if isCurrent {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onTogglePlay()
                        flashControls()
                    }
                    .allowsHitTesting(!showControls && isPlaying)
            }

            // Layer 11 — top scrim
            VStack {
                LinearGradient(
                    colors: [Color.navy.opacity(0.75), Color.navy.opacity(0.30), .clear],
                    startPoint: .top, endPoint: .bottom)
                    .frame(height: 130)
                Spacer()
            }
            .allowsHitTesting(false)

            // Layer 16 — bottom scrim (extends to the very bottom now that the tab bar is hidden)
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.clear, Color.navy.opacity(0.55), Color.navy.opacity(0.92), Color.navy],
                    startPoint: .top, endPoint: .bottom)
                    .frame(height: 440)
            }
            .allowsHitTesting(false)

            // Layer 15 — right rail
            VStack {
                Spacer().frame(height: size.height * 0.27)
                HStack {
                    Spacer()
                    VStack(spacing: 28) {
                        if !trailer.isSponsored {
                            RailButton(
                                    icon: isLiked ? "heart.fill" : "heart",
                                    label: formatCount(likeCount),
                                    tint: isLiked ? Color(hex: "FF3B5C") : .white,
                                    action: {
                                        likeBounce = 1.4
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
                                            likeBounce = 1.0
                                        }
                                        onLike()
                                    }
                                )
                                .scaleEffect(likeBounce)

                            RailButton(icon: "message", label: formatCount(commentCount), tint: .white, action: onComments)
                        }

                        WatchListButton(saved: isSaved, sponsored: trailer.isSponsored, action: onSave)

                        if !trailer.isSponsored {
                            RailButton(
                                icon: isWatched ? "eye.fill" : "eye",
                                label: "Watched",
                                tint: isWatched ? Color(hex: "1A6FE8") : .white,
                                action: onWatched
                            )
                        }

                        RailButton(icon: "arrowshape.turn.up.right", label: "Share", tint: .white, action: onShare)
                    }
                    .padding(.trailing, 18)
                }
                Spacer()
            }

            // Sponsored tag
            if trailer.isSponsored {
                VStack {
                    HStack {
                        Text("Sponsored")
                            .scaledFont(size: 10, weight: .semibold)
                            .foregroundStyle(Color.white.opacity(0.50))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .clipShape(.rect(cornerRadius: 4))
                            .padding(.leading, 14)
                            .padding(.top, 90)
                        Spacer()
                    }
                    Spacer()
                }
            }

            // Layer 17 — bottom content
            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Text(trailer.platformName)
                            .scaledFont(size: 11, weight: .bold)
                            .foregroundStyle(trailer.platformTextColor)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(trailer.platformColor.opacity(trailer.isSponsored ? 0.25 : 1.0))
                            .clipShape(.rect(cornerRadius: 6))
                        Text(trailer.genre)
                            .scaledFont(size: 11, weight: .bold)
                            .foregroundStyle(.white.opacity(trailer.isSponsored ? 0.75 : 1.0))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background((trailer.isSponsored ? Color.white.opacity(0.06) : Color.white.opacity(0.12)))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(trailer.isSponsored ? 0.10 : 0.20)))
                            .clipShape(.rect(cornerRadius: 6))
                        if isInjected, let vtype = trailer.videoType, !vtype.isEmpty {
                            Text(vtype)
                                .scaledFont(size: 11, weight: .bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.white.opacity(0.12))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.20)))
                                .clipShape(.rect(cornerRadius: 6))
                        }
                    }
                    .padding(.trailing, 90)
                    .padding(.bottom, 8)

                    Text(trailer.showName)
                        .scaledFont(size: 28, weight: .bold)
                        .tracking(-0.8)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(.trailing, 90)
                        .padding(.bottom, 10)

                    if !trailer.synopsis.isEmpty {
                        Text(trailer.synopsis)
                            .scaledFont(size: 14)
                            .foregroundStyle(Color.white.opacity(0.80))
                            .lineLimit(2)
                            .padding(.trailing, 90)
                            .padding(.bottom, 8)
                    }

                    Text(trailer.runtime)
                        .scaledFont(size: 12, weight: .medium)
                        .foregroundStyle(Color.white.opacity(0.55))
                        .padding(.trailing, 90)
                        .padding(.bottom, 14)

                    // TVDB next-episode air-date banner
                    if let tvdb = tvdbInfo, let code = tvdb.episodeCode {
                        tvdbNextEpisodeRow(tvdb: tvdb)
                            .padding(.trailing, 90)
                            .padding(.bottom, 12)
                    }

                    HStack(alignment: .center, spacing: 6) {
                        if trailer.isSponsored {
                            // Make the whole bottom content area a tap target.
                            // The explicit button is removed — tapping anywhere
                            // on the lower half of the reel fires the CTA.
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: 120)
                                .contentShape(Rectangle())
                                .onTapGesture { onSponsorCTA() }
                                .overlay(alignment: .bottomLeading) {
                                    HStack(spacing: 6) {
                                        Text("Learn more")
                                            .scaledFont(size: 13, weight: .semibold)
                                            .foregroundStyle(.white)
                                        Image(systemName: "arrow.up.right")
                                            .scaledFont(size: 11, weight: .semibold)
                                            .foregroundStyle(Color.white.opacity(0.70))
                                    }
                                    .padding(.bottom, 2)
                                }
                        } else if trailer.tab == .comingSoon {
                            NotifyMePill(enrolled: isReminded, action: onNotify)
                            if !glassAdDismissed, !glassAdTargets.isEmpty {
                                adCarousel
                                    .opacity(glassAdVisible ? 1 : 0)
                                    .allowsHitTesting(glassAdVisible)
                            }
                        } else if isInjected {
                            WatchNowSwitcher(
                                tmdbId: trailer.tmdbId,
                                isTV: trailer.isTV,
                                showName: trailer.showName
                            )
                        } else {
                            PlayOnPill(action: onShowDetail)
                            if !glassAdDismissed, !glassAdTargets.isEmpty {
                                adCarousel
                                    .opacity(glassAdVisible ? 1 : 0)
                                    .allowsHitTesting(glassAdVisible)
                            }
                        }
                    }
                    .padding(.trailing, 16)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 22)
                .padding(.bottom, bottomInset + 38)
                .opacity(contentOpacity)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.6)) { contentOpacity = 1.0 }
                }
            }

            // Layer 19 — interactive video scrubber.
            VStack {
                Spacer()
                GeometryReader { barGeo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.18))
                            .frame(height: 6)
                        Capsule()
                            .fill(Color(hex: "F5821F"))
                            .frame(width: max(0, min(1, playbackProgress)) * barGeo.size.width, height: 6)
                        // Invisible wider hit target for dragging.
                        Color.clear
                            .frame(height: 32)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let fraction = max(0, min(1, value.location.x / max(barGeo.size.width, 1)))
                                        seekToFraction = fraction
                                    }
                            )
                    }
                }
                .frame(height: 6)
                .padding(.horizontal, 22)
                .padding(.bottom, bottomInset + 14)
            }

            // Layer 21 — media controls overlay (play/pause + mute).
            if isCurrent && (showControls || !isPlaying) {
                // Center play/pause button
                Button {
                    onTogglePlay()
                    flashControls()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.5))
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .scaledFont(size: 28, weight: .bold)
                            .foregroundStyle(.white)
                    }
                    .frame(width: 68, height: 68)
                    .shadow(color: .black.opacity(0.4), radius: 16)
                }
                .buttonStyle(.plain)
                .position(x: size.width / 2, y: size.height / 2)

                // Mute button — bottom-leading
                Button {
                    onToggleMute()
                    flashControls()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.45))
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .scaledFont(size: 16, weight: .semibold)
                            .foregroundStyle(.white)
                    }
                    .frame(width: 40, height: 40)
                    .shadow(color: .black.opacity(0.35), radius: 10)
                }
                .buttonStyle(.plain)
                .position(x: isPlaying ? 38 : size.width / 2,
                          y: isPlaying ? size.height - bottomInset - 64 : size.height / 2 - 34 - 16 - 20)
            }
        }
        .clipped()
        .onAppear { if !isInjected { armGlassAdFade() } }
        .onChange(of: isCurrent) { _, nowCurrent in
            if nowCurrent {
                if !isInjected { armGlassAdFade() }
            } else {
                glassAdFadeTask?.cancel()
                adAdvanceTask?.cancel()
                glassAdVisible = false
            }
        }
        .onChange(of: adPage) { _, page in
            guard page < glassAdTargets.count else { return }
            let ad = glassAdTargets[page]
            WatchIntentLogger.shared.log(
                eventType: .adImpression,
                platformId: ad.serviceId,
                metadata: ["source": "reel_ad_carousel", "position": page, "show_platform": trailer.platformId]
            )
        }
        .onDisappear {
            glassAdFadeTask?.cancel()
            adAdvanceTask?.cancel()
        }
    }

    @ViewBuilder
    private var adCarousel: some View {
        VStack(spacing: 0) {
            TabView(selection: $adPage) {
                ForEach(Array(glassAdTargets.enumerated()), id: \.offset) { idx, ad in
                    SponsoredAffiliateCard(
                        service: StreamingCatalog.all.first(where: { $0.id == ad.serviceId }),
                        fallbackName: ad.name,
                        fallbackColor: ad.color,
                        headline: "Stream on \(ad.name)",
                        subtitle: ad.tagline,
                        onTap: {
                            RakutenManager.shared.openAffiliateLink(
                                serviceId: ad.serviceId,
                                metadata: [
                                    "source": "reel_ad_carousel",
                                    "reel_platform": trailer.platformId,
                                    "show": trailer.showName
                                ]
                            )
                            WatchIntentLogger.shared.log(
                                eventType: .affiliateLinkTapped,
                                platformId: ad.serviceId,
                                metadata: [
                                    "source": "reel_ad_carousel",
                                    "show_platform": trailer.platformId
                                ]
                            )
                        },
                        onDismiss: { glassAdDismissed = true },
                        compact: true
                    )
                    .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 120)

            HStack(spacing: 6) {
                ForEach(0..<glassAdTargets.count, id: \.self) { dotIdx in
                    Circle()
                        .fill(dotIdx == adPage ? Color(hex: "F5821F") : Color.white.opacity(0.28))
                        .frame(width: 5, height: 5)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.25)) { adPage = dotIdx }
                        }
                }
            }
            .padding(.top, 8)
        }
    }

    private func armGlassAdFade() {
        glassAdFadeTask?.cancel()
        adAdvanceTask?.cancel()
        glassAdTargets = resolveGlassAds(count: 5)
        adPage = 0
        glassAdDismissed = false
        glassAdVisible = false
        glassAdFadeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, isCurrent, !glassAdDismissed else { return }
            withAnimation(.easeIn(duration: 0.45)) {
                glassAdVisible = true
            }
            // Log initial impression for the first ad in the carousel.
            if !glassAdTargets.isEmpty {
                let ad = glassAdTargets[0]
                WatchIntentLogger.shared.log(
                    eventType: .adImpression,
                    platformId: ad.serviceId,
                    metadata: ["source": "reel_ad_carousel", "position": 0, "show_platform": trailer.platformId]
                )
            }
            // Start auto-advance after the fade-in completes.
            if glassAdTargets.count > 1 {
                startAdAutoAdvance()
            }
        }
    }

    private func startAdAutoAdvance() {
        adAdvanceTask?.cancel()
        guard glassAdTargets.count > 1 else { return }
        adAdvanceTask = Task { @MainActor in
            while !Task.isCancelled, isCurrent, glassAdVisible, !glassAdDismissed {
                try? await Task.sleep(for: .seconds(5.5))
                guard !Task.isCancelled, isCurrent, glassAdVisible, !glassAdDismissed else { break }
                withAnimation(.easeInOut(duration: 0.3)) {
                    adPage = (adPage + 1) % glassAdTargets.count
                }
            }
        }
    }

    private func flashControls() {
        controlsFadeTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            showControls = true
        }
        controlsFadeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) {
                showControls = false
            }
        }
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    // MARK: TVDB Next-Episode Banner

    private var tvdbNextAirDateText: String? {
        guard let date = tvdbInfo?.nextAirDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return "Airs \(formatter.string(from: date))"
    }

    /// Compact next-episode air-date banner that mirrors the ShowDetailScreen
    /// TVDB banner but scaled for the reel bottom overlay.
    private func tvdbNextEpisodeRow(tvdb: TVDBReelInfo) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.orange.opacity(0.18))
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "sparkles")
                        .scaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(Color.orange)
                }

            VStack(alignment: .leading, spacing: 2) {
                if let name = tvdb.episodeName {
                    Text("\(tvdb.episodeCode ?? "") • \(name)")
                        .scaledFont(size: 11, weight: .semibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                } else if let code = tvdb.episodeCode {
                    Text(code)
                        .scaledFont(size: 11, weight: .semibold)
                        .foregroundStyle(Color.orange)
                }
                HStack(spacing: 4) {
                    if let airText = tvdbNextAirDateText {
                        Label(airText, systemImage: "calendar")
                            .scaledFont(size: 10)
                            .foregroundStyle(Color.white.opacity(0.50))
                    }
                    if let status = tvdb.seriesStatus, !status.isEmpty {
                        if tvdbNextAirDateText != nil {
                            Text("•")
                                .scaledFont(size: 10)
                                .foregroundStyle(Color.white.opacity(0.30))
                        }
                        Text(status)
                            .scaledFont(size: 10, weight: .medium)
                            .foregroundStyle(
                                status.lowercased().contains("returning")
                                    ? Color.green.opacity(0.85)
                                    : Color.white.opacity(0.50)
                            )
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Reusable bits

private struct TabPill: View {
    let tab: ReelTab
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(tab.label)
                    .scaledFont(size: 15, weight: active ? .bold : .medium)
                    .foregroundStyle(active ? .white : Color.white.opacity(0.40))
                Rectangle()
                    .fill(active ? Color.white : .clear)
                    .frame(width: 32, height: 3)
                    .clipShape(.rect(cornerRadius: 2))
            }
        }
        .buttonStyle(.plain)
    }
}

private struct RailButton: View {
    let icon: String
    let label: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.45))
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    Image(systemName: icon)
                        .scaledFont(size: 22, weight: .semibold)
                        .foregroundStyle(tint)
                }
                .frame(width: 52, height: 52)
                Text(label)
                    .scaledFont(size: 11, weight: .semibold)
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Rail save-affordance shown on every non-sponsored reel and reused as the
/// design template for the watchlist circles on `EpisodeDetailSheet` and
/// `SportsWatchSheet`. Two visual states:
///
/// * **Not saved** — solid orange circle with a `plus` glyph and a "Watch List"
///   label underneath.
/// * **Saved** — transparent circle with a white stroke (outlined), checkmark
///   glyph, and a "Saved" label underneath so users see at a glance that the
///   title is already on their list.
private struct WatchListButton: View {
    let saved: Bool
    let sponsored: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    if sponsored {
                        Circle().fill(Color.white.opacity(0.15))
                            .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    } else if saved {
                        // Outlined treatment — transparent fill, white stroke.
                        Circle()
                            .fill(Color.clear)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1.8))
                    } else {
                        Circle()
                            .fill(Color(hex: "F5821F"))
                            .shadow(color: Color(hex: "F5821F").opacity(0.6), radius: 10)
                    }
                    Image(systemName: sponsored ? "info.circle" : (saved ? "checkmark" : "plus"))
                        .scaledFont(size: 22, weight: .bold)
                        .foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)
                Text(sponsored ? "Learn" : (saved ? "Saved" : "Watch List"))
                    .scaledFont(size: 11, weight: .semibold)
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            sponsored
                ? "Learn more"
                : (saved ? "Saved to watch list. Tap to remove." : "Add to watch list")
        )
    }
}

/// Notify-me CTA shown on Coming Soon reels. Mirrors PlayOnPill styling
/// but toggles a title_likes enrollment (bell icon) instead of opening the
/// detail sheet. The enrollment is consumed by existing send_movie_releases
/// and check_watchlist_availability edge functions — no new backend wiring.
private struct NotifyMePill: View {
    let enrolled: Bool
    let action: () -> Void
    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: enrolled ? "bell.badge.fill" : "bell.fill")
                    .scaledFont(size: 14, weight: .bold)
                Text(enrolled ? "Reminder Set" : "Notify Me")
                    .scaledFont(size: 15, weight: .bold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(height: 52)
            .background(Capsule().fill(Color(hex: "F5821F")))
            .shadow(color: Color(hex: "F5821F").opacity(0.55), radius: 14, y: 6)
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

/// Brand color for a streaming service name. Mirrors the per-service brand
/// mapping used across the app's watch surfaces (PlayOnBottomSheet etc.).
private func reelBrandColor(for name: String) -> Color {
    let key = name.lowercased()
    if key.contains("netflix") { return Color(red: 0xE5/255, green: 0x09/255, blue: 0x14/255) }
    if key.contains("hbo") || key.contains("max") { return Color(red: 0x5B/255, green: 0x2D/255, blue: 0x8E/255) }
    if key.contains("hulu") { return Color(red: 0x1C/255, green: 0xE7/255, blue: 0x83/255) }
    if key.contains("disney") { return Color(red: 0.05, green: 0.10, blue: 0.42) }
    if key.contains("apple") { return Color(white: 0.12) }
    if key.contains("prime") || key.contains("amazon") { return Color(red: 0.0, green: 0.66, blue: 0.93) }
    if key.contains("paramount") { return Color(red: 0x00/255, green: 0x64/255, blue: 0xFF/255) }
    if key.contains("peacock") { return Color(red: 0.05, green: 0.05, blue: 0.10) }
    if key.contains("youtube") { return Color(red: 0.90, green: 0.10, blue: 0.10) }
    if key.contains("crunchyroll") { return Color(red: 0xF4/255, green: 0x7B/255, blue: 0x20/255) }
    if key.contains("showtime") { return Color(red: 0xD8/255, green: 0x00/255, blue: 0x00/255) }
    if key.contains("starz") { return Color(white: 0.08) }
    return Color(red: 0x6A/255, green: 0x3F/255, blue: 0xE0/255)
}

/// Title-scoped Reels bottom control. Starts as a compact "Watch now" pill;
/// tapping expands it inline into a horizontal row of streaming-service chips
/// resolved from Watchmode (subscribed-first). Chips open the service's web
/// URL. Shows a disabled "Not available to stream" state when nothing is
/// streamable, and never crashes.
private struct WatchNowSwitcher: View {
    let tmdbId: Int
    let isTV: Bool
    let showName: String

    @State private var expanded: Bool = false
    @State private var sources: [WatchmodeSource] = []
    @State private var loaded: Bool = false
    @State private var loading: Bool = false

    var body: some View {
        Group {
            if !expanded {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { expanded = true }
                } label: {
                    pill(text: "Watch now", icon: "play.fill", dimmed: false)
                }
                .buttonStyle(.plain)
            } else if loading && !loaded {
                pill(text: "Finding services…", icon: "hourglass", dimmed: true)
            } else if loaded && sources.isEmpty {
                pill(text: "Not available to stream", icon: "xmark.circle", dimmed: true)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(sources) { source in
                            Button {
                                openSource(source)
                            } label: {
                                HStack(spacing: 6) {
                                    Text(gsDisplayName(for: source.name))
                                        .scaledFont(size: 13, weight: .bold)
                                        .foregroundStyle(.white)
                                    if let tag = Self.pillTag(for: source) {
                                        Text(tag)
                                            .scaledFont(size: 9, weight: .heavy)
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Color.black.opacity(0.28)))
                                    }
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 44)
                                .background(Capsule().fill(reelBrandColor(for: source.name)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .task(id: expanded) {
            guard expanded, !loaded, !loading else { return }
            await loadSources()
        }
    }

    private func pill(text: String, icon: String, dimmed: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .scaledFont(size: 14, weight: .bold)
            Text(text)
                .scaledFont(size: 15, weight: .bold)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .frame(height: 52)
        .background(Capsule().fill(Color(hex: "F5821F")))
        .shadow(color: Color(hex: "F5821F").opacity(0.55), radius: 14, y: 6)
        .opacity(dimmed ? 0.6 : 1.0)
    }

    private func loadSources() async {
        guard tmdbId > 0 else { loaded = true; return }
        loading = true
        let resolved = await StreamingSourceResolver.shared.resolve(tmdbId: tmdbId, isTV: isTV)
        let subscribed = resolved.usSources.filter { AuthViewModel.shared.subscribesToService(named: $0.name) }
        let others = resolved.usSources.filter { !AuthViewModel.shared.subscribesToService(named: $0.name) }
        sources = subscribed + others
        loaded = true
        loading = false
    }

    private func openSource(_ source: WatchmodeSource) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // Prefer the native iOS deep link, then the web URL — filtering out
        // Watchmode free-tier placeholder strings and non-URLs.
        let candidate = [source.iosUrl, source.webUrl]
            .compactMap { $0 }
            .first { Self.isUsableStreamURL($0) }
        guard let s = candidate, let url = URL(string: s) else { return }
        StreamingDeepLinker.openResolvedURL(
            url,
            platform: source.name,
            title: showName,
            tmdbId: tmdbId > 0 ? tmdbId : nil,
            titleSlug: String(tmdbId)
        )
    }

    /// Compact monetization tag for a source pill — Rent/Buy with price,
    /// Free, TV; nothing for subscription tiers.
    private static func pillTag(for source: WatchmodeSource) -> String? {
        switch source.type.lowercased() {
        case "rent": return source.price.map { String(format: "Rent $%.2f", $0) } ?? "Rent"
        case "purchase", "buy": return source.price.map { String(format: "Buy $%.2f", $0) } ?? "Buy"
        case "free": return "Free"
        case "tve": return "TV"
        default: return nil
        }
    }

    /// Rejects candidates without a scheme separator or containing
    /// Watchmode's free-tier placeholder text.
    private static func isUsableStreamURL(_ s: String) -> Bool {
        let lower = s.lowercased()
        guard lower.contains("://") else { return false }
        if lower.contains("deeplinks available") || lower.contains("paid plan") { return false }
        return true
    }
}

/// Primary orange CTA in each reel's bottom content stack. Tapping it
/// opens the same `EpisodeDetailSheet` used everywhere else in the app —
/// full where-to-watch resolution, Send-to-TV, like, notify, and
/// deeplink-on-tap.
private struct PlayOnPill: View {
    let action: () -> Void
    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .scaledFont(size: 14, weight: .bold)
                Text("Watch")
                    .scaledFont(size: 15, weight: .bold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(height: 52)
            .background(Capsule().fill(Color(hex: "F5821F")))
            .shadow(color: Color(hex: "F5821F").opacity(0.55), radius: 14, y: 6)
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

private struct LoadingSpinner: View {
    @State private var rotation: Double = 0
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .background(Circle().stroke(Color.white.opacity(0.20), lineWidth: 2))
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

private struct EmptyReelsState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "play.rectangle.on.rectangle")
                .scaledFont(size: 44, weight: .light)
                .foregroundStyle(Color.orange)
            Text("Trailers loading…")
                .scaledFont(size: 16, weight: .bold)
                .foregroundStyle(.white)
            Text("Add shows to My Streams to personalise this feed.")
                .scaledFont(size: 13)
                .foregroundStyle(Color.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - Simulator fallback

/// The cloud iOS simulator can't decode video in WKWebView, so we show the
/// trailer's YouTube thumbnail with a tap-to-open overlay. On real devices the
/// real `YouTubePlayerView` is rendered instead.
private struct SimulatorTrailerPoster: View {
    let trailer: TrailerItem
    /// Which candidate's thumbnail to show — defaults to the reel's own primary
    /// key, but the Reels feed passes the currently-loading candidate so the
    /// poster underlay matches the video being attempted.
    var videoKey: String = ""

    var body: some View {
        let key = videoKey.isEmpty ? trailer.trailerKey : videoKey
        let thumb = URL(string: "https://img.youtube.com/vi/\(key)/maxresdefault.jpg")
        ZStack {
            RemoteImage(url: thumb,
                        contentMode: .fill,
                        fallbackColors: [trailer.platformColor.opacity(0.7), Color(hex: "04090F")])
            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.55)],
                           startPoint: .top, endPoint: .bottom)

        }
        .clipped()
        // Poster is purely decorative — taps must fall through to the reel's
        // mute-toggle gesture rather than opening YouTube in the browser.
        .allowsHitTesting(false)
    }
}

// MARK: - YouTube YTPlayerView (Official IFrame embed)

/// Official youtube.com/embed IFrame player via Google's youtube-ios-player-helper.
/// Progress events are fed back through YTPlayerViewDelegate so the scrubber
/// bar stays in sync.
private struct YouTubePlayerView: UIViewRepresentable {
    let videoId: String
    let isMuted: Bool
    let isPlaying: Bool
    var progress: Binding<Double>? = nil
    var seekToFraction: Binding<Double>
    var onEmbedError: (() -> Void)? = nil
    var onEnded: (() -> Void)? = nil

    func makeUIView(context: Context) -> YTPlayerView {
        let playerView = YTPlayerView()
        playerView.delegate = context.coordinator
        playerView.backgroundColor = .clear
        playerView.webView?.backgroundColor = .clear
        playerView.webView?.isOpaque = false
        playerView.webView?.scrollView.isScrollEnabled = false
        playerView.webView?.scrollView.contentInsetAdjustmentBehavior = .never
        playerView.isUserInteractionEnabled = false

        context.coordinator.onEmbedError = onEmbedError
        context.coordinator.progress = progress
        context.coordinator.onEnded = onEnded

        let playerVars: [String: Any] = [
            "playsinline": 1,
            "autoplay": 1,
            "controls": 0,
            "rel": 0,
            "modestbranding": 1,
            "fs": 0,
            "iv_load_policy": 3,
            "mute": isMuted ? 1 : 0
        ]
        playerView.load(withVideoId: videoId, playerVars: playerVars)
        context.coordinator.lastVideoId = videoId
        context.coordinator.lastMuted = isMuted
        context.coordinator.lastPlaying = isPlaying
        return playerView
    }

    func updateUIView(_ playerView: YTPlayerView, context: Context) {
        context.coordinator.onEmbedError = onEmbedError
        context.coordinator.progress = progress
        context.coordinator.onEnded = onEnded

        // Only reload the entire webview when the videoId itself changes.
        if context.coordinator.lastVideoId != videoId {
            let playerVars: [String: Any] = [
                "playsinline": 1,
                "autoplay": 1,
                "controls": 0,
                "rel": 0,
                "modestbranding": 1,
                "fs": 0,
                "iv_load_policy": 3,
                "mute": isMuted ? 1 : 0
            ]
            playerView.load(withVideoId: videoId, playerVars: playerVars)
            context.coordinator.lastVideoId = videoId
            context.coordinator.lastMuted = isMuted
            context.coordinator.lastPlaying = isPlaying
            context.coordinator.cachedDuration = 0
            progress?.wrappedValue = 0
            return
        }

        // Mute toggle via the YouTube IFrame API — no reload, no restart.
        if context.coordinator.lastMuted != isMuted {
            let js = isMuted ? "player.mute();" : "player.unMute();"
            playerView.webView?.evaluateJavaScript(js)
            context.coordinator.lastMuted = isMuted
        }

        // Toggle play/pause only when the state actually changed.
        if context.coordinator.lastPlaying != isPlaying {
            if isPlaying {
                playerView.playVideo()
            } else {
                playerView.pauseVideo()
            }
            context.coordinator.lastPlaying = isPlaying
        }

        // Seek to a fraction when the scrubber is dragged.
        let fraction = seekToFraction.wrappedValue
        if fraction >= 0,
           context.coordinator.cachedDuration > 0,
           fraction != context.coordinator.lastSeekFraction {
            context.coordinator.lastSeekFraction = fraction
            let seconds = Float(fraction * context.coordinator.cachedDuration)
            playerView.seek(toSeconds: seconds, allowSeekAhead: true)
            Task { @MainActor in
                seekToFraction.wrappedValue = -1
            }
        }
    }

    static func dismantleUIView(_ playerView: YTPlayerView, coordinator: Coordinator) {
        // Stop playback so no audio or video continues in the background.
        playerView.stopVideo()
        // Fully release the web view to stop leaking WebKit memory across swipes.
        if let web = playerView.webView {
            web.stopLoading()
            web.navigationDelegate = nil
            web.uiDelegate = nil
            web.configuration.userContentController.removeAllUserScripts()
            web.loadHTMLString("", baseURL: nil)
            web.removeFromSuperview()
        }
        playerView.delegate = nil
        playerView.removeFromSuperview()
        coordinator.onEmbedError = nil
        coordinator.onEnded = nil
        coordinator.progress = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, YTPlayerViewDelegate {
        var lastVideoId: String = ""
        var lastMuted: Bool = true
        var lastPlaying: Bool = true
        var onEmbedError: (() -> Void)?
        var onEnded: (() -> Void)?
        var progress: Binding<Double>?
        var lastSeekFraction: Double = -1
        var cachedDuration: Double = 0

        func playerViewDidBecomeReady(_ playerView: YTPlayerView) {
            // Re-assert contentInsetAdjustmentBehavior because the helper
            // may recreate its web view when the video loads.
            playerView.webView?.scrollView.contentInsetAdjustmentBehavior = .never
            // Kick off playback after the player is fully loaded.
            playerView.playVideo()
        }

        func playerView(_ playerView: YTPlayerView, didPlayTime playTime: Float) {
            // Lazily fetch duration once from the YouTube IFrame API.
            if cachedDuration <= 0 {
                playerView.duration { [weak self] result, error in
                    guard let self, error == nil, result > 0 else { return }
                    self.cachedDuration = result
                }
            }
            guard cachedDuration > 0 else { return }
            let fraction = max(0, min(1, Double(playTime) / cachedDuration))
            Task { @MainActor in
                self.progress?.wrappedValue = fraction
            }
        }

        func playerView(_ playerView: YTPlayerView, didChangeTo state: YTPlayerState) {
            if state == .ended {
                if let onEnded {
                    Task { @MainActor in onEnded() }
                } else {
                    // Loop the trailer seamlessly when no onEnded is provided.
                    playerView.seek(toSeconds: 0, allowSeekAhead: true)
                    playerView.playVideo()
                }
            }
        }

        func playerView(_ playerView: YTPlayerView, receivedError error: YTPlayerError) {
            // Any embed error — not-embeddable, html5, video not found, etc.
            // Collapses the reel to its poster with no stream-extraction fallback.
            Task { @MainActor in self.onEmbedError?() }
        }
    }

}

// MARK: - Share Sheet

struct TrailerShareSheet: View {
    let trailer: TrailerItem
    @State private var didCopy: Bool = false
    @State private var showSystemShare: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RemoteImage(url: trailer.posterURL, contentMode: .fill,
                                fallbackColors: [trailer.platformColor.opacity(0.5), Color(hex: "04090F")])
                        .frame(width: 60, height: 80)
                        .clipShape(.rect(cornerRadius: 8))
                    Image(systemName: "play.fill")
                        .scaledFont(size: 20)
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(trailer.showName)
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(trailer.platformName)
                        .scaledFont(size: 10, weight: .bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(trailer.platformColor)
                        .clipShape(.rect(cornerRadius: 4))
                    Text("Trailer")
                        .scaledFont(size: 12)
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)

            Divider().background(Color.white.opacity(0.07))

            Text("SEND TO A FRIEND")
                .scaledFont(size: 11, weight: .semibold)
                .tracking(0.8)
                .foregroundStyle(Color.white.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 14)

            // Share grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 16) {
                ShareTile(icon: "link", label: didCopy ? "Copied" : "Copy") {
                    UIPasteboard.general.string = "https://guidestream.tv/trailer/\(trailer.trailerKey)"
                    withAnimation { didCopy = true }
                }
                ShareTile(icon: "message.fill", label: "Messages") { open("sms:") }
                ShareTile(icon: "phone.bubble", label: "WhatsApp") {
                    let txt = "https://guidestream.tv/trailer/\(trailer.trailerKey)"
                    let enc = txt.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    open("whatsapp://send?text=\(enc)")
                }
                ShareTile(icon: "camera", label: "Instagram") { open("instagram://") }
                ShareTile(icon: "bird", label: "X") {
                    let enc = "https://guidestream.tv/trailer/\(trailer.trailerKey)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    open("https://twitter.com/intent/tweet?url=\(enc)")
                }
                ShareTile(icon: "ellipsis.message", label: "Messenger") { open("fb-messenger://") }
                ShareTile(icon: "ellipsis", label: "More") { showSystemShare = true }
                ShareTile(icon: "square.and.arrow.down", label: "YouTube") {
                    UIPasteboard.general.string = "https://www.youtube.com/watch?v=\(trailer.trailerKey)"
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            Spacer()
        }
        .sheet(isPresented: $showSystemShare) {
            ActivityView(activityItems: [URL(string: "https://guidestream.tv/trailer/\(trailer.trailerKey)") as Any, "\(trailer.showName) — watch the trailer on GuideStream TV"])
        }
    }

    private func open(_ urlString: String) {
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}

private struct ShareTile: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                    Image(systemName: icon)
                        .scaledFont(size: 22, weight: .semibold)
                        .foregroundStyle(.white)
                }
                .frame(width: 56, height: 56)
                Text(label)
                    .scaledFont(size: 11, weight: .medium)
                    .foregroundStyle(Color.white.opacity(0.75))
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ActivityView (system share sheet)

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - UIApplication helper

extension UIApplication {
    func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let root = base ?? connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?.rootViewController
        if let nav = root as? UINavigationController { return topViewController(base: nav.visibleViewController) }
        if let tab = root as? UITabBarController, let sel = tab.selectedViewController {
            return topViewController(base: sel)
        }
        if let presented = root?.presentedViewController { return topViewController(base: presented) }
        return root
    }
}

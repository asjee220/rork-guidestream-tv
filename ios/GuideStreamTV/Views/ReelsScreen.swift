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
import WebKit
import AVFoundation
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
    var likedTrailers: Set<String> = []
    var likeCounts: [String: Int] = [:]
    var reelSwipeCount: Int = 0
    /// Lazily-populated TVDB next-episode data keyed by TMDB series id.
    var tvdbCache: [Int: TVDBReelInfo] = [:]

    private let tmdb = TMDBService.shared
    private var hasLoaded: Bool = false

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

        // Fetch the five source lists in parallel.
        async let trendingTask: [TMDBResult] = (try? tmdb.getTrending()) ?? []
        async let onAirTask: [TMDBResult] = (try? tmdb.getOnTheAir()) ?? []
        async let myStreamsTask: [UserStream] = fetchMyStreams()
        async let nowPlayingTask: [TMDBResult] = (try? tmdb.getNowPlayingMovies()) ?? []
        async let popularTVTask: [TMDBResult] = (try? tmdb.getPopularTV()) ?? []
        async let upcomingTask: [TMDBResult] = (try? tmdb.getUpcomingMovies()) ?? []

        let (trending, onAir, mine, nowPlaying, popularTV, upcoming) = await (trendingTask, onAirTask, myStreamsTask, nowPlayingTask, popularTVTask, upcomingTask)

        // For each show, fetch its YouTube trailer key + TMDB detail.
        // Keep the work parallel but capped to avoid hammering TMDB.
        let forYouItems = await buildItems(from: mineResults(mine), tab: .forYou)
        let trendingItems = await buildItems(from: Array(trending.prefix(50)), tab: .trending)
        let newItems = await buildItems(from: Array(onAir.prefix(50)), tab: .new)
        let nowPlayingItems = await buildItems(from: Array(nowPlaying.prefix(50)), tab: .new)
        let popularTVItems = await buildItems(from: Array(popularTV.prefix(50)), tab: .forYou)
        let comingSoonItems = await buildItems(from: Array(upcoming.prefix(50)), tab: .comingSoon)

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

        var combined = forYouCombined + trendingItems + newItems + nowPlayingItems + comingSoonItems

        // Deduplicate by trailer key so the same video doesn't appear twice.
        var seen = Set<String>()
        combined = combined.filter({ seen.insert($0.trailerKey).inserted })

        let rakutenReels = makeRakutenAdReels()
        var rakutenIndex = 0
        var adSlotCount = 0
        var finalFeed: [TrailerItem] = []

        for (i, item) in combined.enumerated() {
            finalFeed.append(item)

            if (i + 1) % 3 == 0 {
                adSlotCount += 1
                if adSlotCount % 2 == 1 {
                    // Odd ad slots (after reels 3, 9, 15...) → Rakuten
                    if !rakutenReels.isEmpty {
                        finalFeed.append(
                            rakutenReels[rakutenIndex % rakutenReels.count]
                        )
                        rakutenIndex += 1
                    }
                } else {
                    // Even ad slots (after reels 6, 12, 18...) → AdMob
                    finalFeed.append(makeAdMobReel(slot: adSlotCount))
                }
            }
        }

        // Safety net: if the feed was too short to insert any
        // Rakuten reel at all, append one now so it always appears.
        let hasRakuten = finalFeed.contains {
            $0.isSponsored && $0.platformId != "admob"
        }
        if !hasRakuten, let first = rakutenReels.first {
            let insertAt = min(2, finalFeed.count)
            finalFeed.insert(first, at: insertAt)
        }

        self.allTrailers = finalFeed
        self.hasLoaded = !finalFeed.isEmpty

        // Saved state now lives in the shared StreamsViewModel store, which
        // hydrates itself from the local cache on init and refreshes from
        // Supabase whenever the user signs in. Nothing else to do here.


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

    private func buildItems(from results: [TMDBResult], tab: ReelTab) async -> [TrailerItem] {
        await withTaskGroup(of: TrailerItem?.self) { group in
            for r in results {
                group.addTask { [tmdb] in
                    async let detailTask: TMDBTVDetail? = try? tmdb.getTVDetail(tmdbId: r.id)
                    async let keyTask: String? = try? (r.isTV ? tmdb.getTrailerKey(tmdbId: r.id) : tmdb.getMovieTrailerKey(tmdbId: r.id))
                    async let providerTask: TMDBWatchProvider? = try? tmdb.getTopWatchProvider(tmdbId: r.id, isTV: r.isTV)
                    let (detail, key, provider) = await (detailTask, keyTask, providerTask)
                    guard let key, !key.isEmpty else { return nil }
                    // Reels must point at an app users can actually open — skip titles
                    // with no verified US streaming provider.
                    guard let provider, let _ = ReelPlatform.recognizedKey(for: provider.providerName) else {
                        return nil
                    }

                    let name = detail?.name ?? r.displayName
                    let overview = (detail?.overview?.isEmpty == false ? detail?.overview : r.overview) ?? ""
                    let year = detail?.year ?? r.year
                    let genreName = detail?.genreNames.first ?? "DRAMA"
                    let plat = ReelPlatform.info(for: provider.providerName)

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
                        thumbnailURL: thumb,
                        youtubeURL: embed,
                        deepLinkURL: nil,
                        voteAverage: detail?.voteAverage ?? (r.voteAverage ?? 0),
                        likes: Int.random(in: 800...18_000),
                        comments: Int.random(in: 40...1_400),
                        tab: tab,
                        identityCode: identity,
                        gradeColor: plat.grade,
                        isSponsored: false
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

    private func makeAdMobReel(slot: Int) -> TrailerItem {
        let placeholders: [(String,String,String,String,String)] = [
            ("Stream smarter. Watch everything.",
             "GuideStream TV — every show, every service, one app.",
             "Watch now",
             "https://image.tmdb.org/t/p/w1280/etj8E2o0Bud0HkONVQPjyCkIvpv.jpg",
             "dQw4w9WgXcQ"),
            ("Upgrade your home theater",
             "TCL 4K QLED TV. Stunning picture, incredible sound.",
             "Shop now",
             "https://image.tmdb.org/t/p/w1280/zSWIOsYEWCBPEFrmVCBZAbMKFtA.jpg",
             "M7lc1UVf-VE"),
            ("Game Pass. 100+ games included.",
             "Xbox Game Pass Ultimate — play on console and mobile.",
             "Try free",
             "https://image.tmdb.org/t/p/w1280/9yBVqNruk6Ykrwc32qDbHTE0z5o.jpg",
             "sPbJ4oyIrXA"),
            ("Order dinner. Keep watching.",
             "DoorDash — get food delivered to your door tonight.",
             "Order now",
             "https://image.tmdb.org/t/p/w1280/1Rr5SrvHxMXHu5RjKpaMba8VTzi.jpg",
             "dQw4w9WgXcQ")
        ]
        let p = placeholders[slot % placeholders.count]
        return TrailerItem(
            id: "admob-\(slot)-\(Int.random(in:1000...9999))",
            tmdbId: -2,
            showName: p.0,
            synopsis: p.1,
            genre: "AD · \(p.2.uppercased())",
            runtime: p.2,
            platformId: "admob",
            platformName: "AD",
            platformColor: Color(hex: "1A6FE8"),
            platformTextColor: .white,
            backdropURL: URL(string: p.3),
            posterURL: URL(string: p.3),
            trailerKey: p.4,
            thumbnailURL: URL(string: p.3),
            youtubeURL: nil,
            deepLinkURL: nil,
            voteAverage: 0,
            likes: 0,
            comments: 0,
            tab: .forYou,
            identityCode: "AD",
            gradeColor: Color(hex: "1A6FE8").opacity(0.15),
            isSponsored: true
        )
    }

    // MARK: - Mutations

    func toggleLike(_ trailer: TrailerItem) {
        let id = trailer.id
        if likedTrailers.contains(id) {
            likedTrailers.remove(id)
            likeCounts[id] = (likeCounts[id] ?? trailer.likes) - 1
        } else {
            likedTrailers.insert(id)
            likeCounts[id] = (likeCounts[id] ?? trailer.likes) + 1
            WatchIntentLogger.shared.log(
                eventType: .trailerLiked,
                titleId: String(trailer.tmdbId)
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
                platform: trailer.platformId
            )
        }
    }

    func likeCount(for trailer: TrailerItem) -> Int {
        likeCounts[trailer.id] ?? trailer.likes
    }

    func isLiked(_ trailer: TrailerItem) -> Bool { likedTrailers.contains(trailer.id) }
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
    @State private var isMuted: Bool = false
    @State private var isPlaying: Bool = true
    @State private var showComments: Bool = false
    @State private var showShare: Bool = false
    @State private var showDetail: Bool = false
    @State private var detailSubject: DetailSubject?
    @State private var scrolledID: Int? = 0
    @State private var pendingInterstitialAt: Int? = nil
    /// Live translation while the user drags down to dismiss. Used to slide
    /// the whole feed down for visual feedback before commit.
    @State private var dismissDragOffset: CGFloat = 0
    @Environment(\.tabBarVisibility) private var tabBarVisibility

    /// Called when the user taps the dismiss chevron or completes a
    /// downward swipe-to-dismiss gesture. ContentView routes the user back
    /// to whichever tab they were on before opening Reels.
    let onDismiss: () -> Void

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

                if vm.isLoading && vm.allTrailers.isEmpty {
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
                        let prev = vm.currentIndex
                        vm.currentIndex = newValue
                        vm.reelSwipeCount += 1
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        if let trailer = vm.allTrailers[safe: newValue] {
                            logTrailerViewed(trailer)
                        }
                        prefetchNeighbors(around: newValue)
                        // Lazily enrich current + next reel with TVDB episode data.
                        if let trailer = vm.allTrailers[safe: newValue], trailer.tmdbId > 0, !trailer.isSponsored {
                            Task { await vm.enrichWithTVDB(tmdbId: trailer.tmdbId) }
                        }
                        if let nextTrailer = vm.allTrailers[safe: newValue + 1], nextTrailer.tmdbId > 0, !nextTrailer.isSponsored {
                            Task { await vm.enrichWithTVDB(tmdbId: nextTrailer.tmdbId) }
                        }
                        _ = prev
                    }
                }

                // Top-left dismiss chevron. Sits above all reel content with a
                // glassy background so it stays legible over any backdrop.
                VStack {
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
                        .padding(.top, max(topInset - 10, 6))
                        Spacer()
                    }
                    Spacer()
                }
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
            // Hide the floating tab bar so the reel fills the entire screen.
            tabBarVisibility.hide()
            await vm.loadIfNeeded()
            if scrolledID == nil { scrolledID = 0 }
            prefetchNeighbors(around: vm.currentIndex)
        }
        .onAppear { tabBarVisibility.hide() }
        .onDisappear { tabBarVisibility.show() }
        .sheet(isPresented: $showComments) {
            if let trailer = currentTrailer {
                TrailerCommentsSheet(trailer: trailer)
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
            tmdbId: trailer.tmdbId > 0 ? trailer.tmdbId : nil
        )
    }

    private var currentTrailer: TrailerItem? {
        guard vm.allTrailers.indices.contains(vm.currentIndex) else { return nil }
        return vm.allTrailers[vm.currentIndex]
    }

    /// Only allow the swipe-down dismiss when the user is on the very first
    /// reel — otherwise downward swipes mean "previous reel" and we mustn't
    /// fight the paging ScrollView.
    private var canDismissSwipe: Bool {
        vm.currentIndex == 0 && !vm.allTrailers.isEmpty
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
        if trailer.platformId == "admob" {
            AdMobReelCard(
                headline: trailer.showName,
                bodyText: trailer.synopsis,
                ctaText: trailer.runtime,
                advertiser: trailer.genre
                    .replacingOccurrences(of: "AD · ", with: "")
                    .capitalized,
                imageURL: trailer.backdropURL,
                trailerKey: trailer.trailerKey,
                isPlaying: isCurrent && isPlaying,
                isMuted: isMuted,
                playbackProgress: .constant(0),
                size: size,
                topInset: topInset,
                bottomInset: bottomInset,
                onTap: {
                    WatchIntentLogger.shared.log(
                        eventType: .adImpression,
                        metadata: [
                            "ad_type": "native_reel",
                            "position": index,
                            "slot": index / 5
                        ]
                    )
                }
            )
            .frame(width: size.width, height: size.height)
            .id(index)
        } else {
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
                isSaved: vm.isSaved(trailer),
                activeTab: trailer.tab,
                currentIndex: vm.currentIndex,
                totalCount: vm.allTrailers.count,
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
                onShare: { showShare = true },
                onTabSelect: { tab in
                    guard let idx = vm.allTrailers.firstIndex(where: { $0.tab == tab }) else { return }
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                        scrolledID = idx
                    }
                },
                onSponsorCTA: {
                    if trailer.platformId == "admob" {
                        WatchIntentLogger.shared.log(
                            eventType: .adImpression,
                            metadata: ["ad_type":"native_cta","position":index]
                        )
                    } else {
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
                    }
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
                }
            )
            .frame(width: size.width, height: size.height)
            .id(index)
        }
    }

    private func prefetchNeighbors(around index: Int) {}

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

    private func logTrailerViewed(_ trailer: TrailerItem) {
        if trailer.isSponsored {
            WatchIntentLogger.shared.log(
                eventType: .sponsoredReelViewed,
                platformId: trailer.platformId,
                metadata: ["position": vm.currentIndex, "sponsor": trailer.platformName]
            )
        } else {
            WatchIntentLogger.shared.log(
                eventType: .trailerViewed,
                titleId: String(trailer.tmdbId),
                platformId: trailer.platformId,
                metadata: [
                    "trailer_key": trailer.trailerKey,
                    "tab": trailer.tab.rawValue
                ]
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
    let isSaved: Bool
    let activeTab: ReelTab
    let currentIndex: Int
    let totalCount: Int

    let onTogglePlay: () -> Void
    let onToggleMute: () -> Void
    let onLike: () -> Void
    let onComments: () -> Void
    let onSave: () -> Void
    let onShare: () -> Void
    let onTabSelect: (ReelTab) -> Void
    let onSponsorCTA: () -> Void
    let onShowDetail: () -> Void

    @State private var contentOpacity: Double = 0.4
    @State private var likeBounce: CGFloat = 1.0
    @State private var embedFailed: Bool = false
    @State private var playbackProgress: Double = 0
    @State private var showTapIndicator: Bool = false
    @State private var tapIndicatorIcon: String = "speaker.slash.fill"
    @State private var tapIndicatorTask: Task<Void, Never>?
    @State private var glassAdDismissed: Bool = false
    @State private var glassAdTarget: (serviceId: String, name: String, color: Color)? = nil

    private func resolveGlassAd() -> (serviceId: String, name: String, color: Color)? {
        let current = trailer.platformId.lowercased()
        let selected = AuthViewModel.shared.selectedServices
            .map { $0.lowercased() }
        let pool: [(String, String, Color)] = [
            ("netflix", "Netflix", Color(red:0xE5/255, green:0x09/255, blue:0x14/255)),
            ("hbo", "Max", Color(red:0x00/255, green:0x1E/255, blue:0xE0/255)),
            ("hulu", "Hulu", Color(red:0x1C/255, green:0xE7/255, blue:0x83/255)),
            ("disney", "Disney+", Color(red:0x0E/255, green:0x29/255, blue:0x3F/255)),
            ("appletv", "Apple TV+", Color.black),
            ("prime", "Prime Video", Color(red:0x1A/255, green:0x20/255, blue:0x2C/255)),
            ("paramount","Paramount+", Color(red:0x00/255, green:0x64/255, blue:0xFF/255)),
            ("peacock", "Peacock", Color.black)
        ]
        // Prefer services the user doesn't already own AND aren't the
        // current platform. If everything is owned, drop the owned filter so
        // an ad still appears (only excluding the current platform). If even
        // that's empty, fall back to the full pool.
        let preferred = pool.filter { entry in
            entry.0 != current && !selected.contains(entry.0)
        }
        let secondary = pool.filter { $0.0 != current }
        let eligible: [(String, String, Color)]
        if !preferred.isEmpty { eligible = preferred }
        else if !secondary.isEmpty { eligible = secondary }
        else { eligible = pool }
        guard !eligible.isEmpty else { return nil }
        // Use tmdbId to deterministically pick different services
        // for different shows, giving variety across the feed.
        let index = abs(trailer.tmdbId) % eligible.count
        let entry = eligible[index]
        return (entry.0, entry.1, entry.2)
    }

    @ViewBuilder
    private var glassAdOverlay: some View {
        if !trailer.isSponsored,
           !glassAdDismissed,
           let target = glassAdTarget {
            VStack {
                Spacer()
                Button {
                    RakutenManager.shared.openAffiliateLink(
                        serviceId: target.serviceId,
                        metadata: [
                            "source": "glass_overlay",
                            "reel_platform": trailer.platformId,
                            "show": trailer.showName
                        ]
                    )
                    WatchIntentLogger.shared.log(
                        eventType: .affiliateLinkTapped,
                        platformId: target.serviceId,
                        metadata: [
                            "source": "reel_glass_overlay",
                            "show_platform": trailer.platformId
                        ]
                    )
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(target.color.opacity(0.12))
                                .frame(width: 40, height: 40)
                            if let service = StreamingCatalog.all
                                .first(where: { $0.id == target.serviceId }) {
                                ServiceBrandContent(
                                    display: service.display,
                                    size: .mini(32)
                                )
                                .frame(width: 32, height: 32)
                            } else {
                                Text(String(target.name.prefix(3)).uppercased())
                                    .scaledFont(size: 11, weight: .black)
                                    .foregroundStyle(target.color)
                            }
                        }
                        .frame(width: 40, height: 40)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Stream more on \(target.name)")
                                .scaledFont(size: 12, weight: .bold)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text("Tap to start your free trial")
                                .scaledFont(size: 10)
                                .foregroundStyle(Color.white.opacity(0.50))
                            Text("Sponsored · Rakuten")
                                .scaledFont(size: 9)
                                .foregroundStyle(Color.white.opacity(0.25))
                        }

                        Spacer(minLength: 0)

                        // Arrow indicator replaces the old button
                        Image(systemName: "arrow.up.right")
                            .scaledFont(size: 11, weight: .semibold)
                            .foregroundStyle(Color.white.opacity(0.45))
                            .padding(.trailing, 4)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(red: 8/255, green: 14/255,
                                         blue: 24/255).opacity(0.82))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.11),
                                            lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.bottom, bottomInset + 72)
                .overlay(alignment: .topTrailing) {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            glassAdDismissed = true
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .scaledFont(size: 12, weight: .semibold)
                            .foregroundStyle(Color.white.opacity(0.40))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                }
            }
        }
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
            if !trailer.trailerKey.isEmpty, !embedFailed {
                #if targetEnvironment(simulator)
                SimulatorTrailerPoster(trailer: trailer)
                    .frame(width: size.width, height: size.height)
                    .position(x: size.width / 2, y: size.height / 2)
                #else
                if isCurrent {
                    ZStack {
                        // Poster sits underneath so the reel is never blank
                        // while the IFrame embed loads.
                        SimulatorTrailerPoster(trailer: trailer)
                        YouTubePlayerView(
                            videoId: trailer.trailerKey,
                            isMuted: isMuted,
                            isPlaying: isPlaying,
                            progress: $playbackProgress,
                            onEmbedError: { embedFailed = true }
                        )
                        .allowsHitTesting(false)
                    }
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .position(x: size.width / 2, y: size.height / 2)
                } else {
                    // Neighbors show poster only — avoids spinning up multiple players simultaneously.
                    SimulatorTrailerPoster(trailer: trailer)
                        .frame(width: size.width, height: size.height)
                        .position(x: size.width / 2, y: size.height / 2)
                        .allowsHitTesting(false)
                }
                #endif
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

                            RailButton(icon: "message", label: formatCount(trailer.comments), tint: .white, action: onComments)
                        }

                        WatchListButton(saved: isSaved, sponsored: trailer.isSponsored, action: onSave)

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
                            .foregroundStyle(Color.white.opacity(0.60))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.white.opacity(0.30))
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
                            .background(trailer.platformColor)
                            .clipShape(.rect(cornerRadius: 6))
                        Text(trailer.genre)
                            .scaledFont(size: 11, weight: .bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.white.opacity(0.12))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.20)))
                            .clipShape(.rect(cornerRadius: 6))
                    }
                    .padding(.bottom, 8)

                    Text(trailer.showName)
                        .scaledFont(size: 28, weight: .bold)
                        .tracking(-0.8)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(.bottom, 10)

                    if !trailer.synopsis.isEmpty {
                        Text(trailer.synopsis)
                            .scaledFont(size: 14)
                            .foregroundStyle(Color.white.opacity(0.80))
                            .lineLimit(2)
                            .padding(.bottom, 8)
                    }

                    Text(trailer.runtime)
                        .scaledFont(size: 12, weight: .medium)
                        .foregroundStyle(Color.white.opacity(0.55))
                        .padding(.bottom, 14)

                    // TVDB next-episode air-date banner
                    if let tvdb = tvdbInfo, let code = tvdb.episodeCode {
                        tvdbNextEpisodeRow(tvdb: tvdb)
                            .padding(.bottom, 12)
                    }

                    HStack(spacing: 12) {
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
                        } else {
                            PlayOnPill(action: onShowDetail)
                        }
                    }
                }
                .padding(.leading, 22)
                .padding(.trailing, 90)
                .padding(.bottom, bottomInset + 38)
                .opacity(contentOpacity)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.6)) { contentOpacity = 1.0 }
                }
            }

            glassAdOverlay

            // Layer 19 — horizontal video scrubber, anchored just above the floating nav.
            VStack {
                Spacer()
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 3)
                    GeometryReader { barGeo in
                        Capsule()
                            .fill(Color(hex: "F5821F"))
                            .frame(width: max(0, min(1, playbackProgress)) * barGeo.size.width, height: 3)
                    }
                    .frame(height: 3)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, bottomInset + 14)
            }
            .allowsHitTesting(false)

            // Layer 21 — transient tap indicator (fades in then out after each tap)
            if showTapIndicator {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.45))
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.30), lineWidth: 1))
                    Image(systemName: tapIndicatorIcon)
                        .scaledFont(size: 32, weight: .black)
                        .foregroundStyle(.white)
                }
                .frame(width: 88, height: 88)
                .shadow(color: .black.opacity(0.35), radius: 18)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            glassAdTarget = resolveGlassAd()
            glassAdDismissed = false
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Tap anywhere on the reel toggles mute/unmute. We deliberately do
            // NOT navigate the user out of the app — every tap is a soft,
            // in-app interaction with a transient indicator that fades on its
            // own. (Play/pause still happens automatically when scrolling away
            // from a reel; tapping no longer pauses.)
            let willBeMuted = !isMuted
            onToggleMute()
            triggerTapIndicator(muted: willBeMuted)
        }
        .animation(.easeOut(duration: 0.15), value: isMuted)
    }

    private func triggerTapIndicator(muted: Bool) {
        tapIndicatorTask?.cancel()
        tapIndicatorIcon = muted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
            showTapIndicator = true
        }
        tapIndicatorTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.28)) {
                showTapIndicator = false
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
                    .scaledFont(size: 16, weight: active ? .bold : .medium)
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

    var body: some View {
        let thumb = URL(string: "https://img.youtube.com/vi/\(trailer.trailerKey)/maxresdefault.jpg")
        ZStack {
            RemoteImage(url: thumb,
                        contentMode: .fill,
                        fallbackColors: [trailer.platformColor.opacity(0.7), Color(hex: "04090F")])
            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.55)],
                           startPoint: .top, endPoint: .bottom)
            #if targetEnvironment(simulator)
            VStack(spacing: 10) {
                Image(systemName: "play.circle.fill")
                    .scaledFont(size: 56, weight: .bold)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 8)
                Text("Video playback unavailable in simulator")
                    .scaledFont(size: 10, weight: .medium)
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            #endif
        }
        .clipped()
        // Poster is purely decorative — taps must fall through to the reel's
        // mute-toggle gesture rather than opening YouTube in the browser.
        .allowsHitTesting(false)
    }
}

// MARK: - YouTube WKWebView (IFrame embed)

/// Official youtube.com/embed IFrame player. Progress events are fed back
/// through the ytbridge message handler so the scrubber bar stays in sync.
private struct YouTubePlayerView: UIViewRepresentable {
    let videoId: String
    let isMuted: Bool
    let isPlaying: Bool
    var progress: Binding<Double>? = nil
    var onEmbedError: (() -> Void)? = nil

    func makeUIView(context: Context) -> WKWebView {
        // Activate a playback-friendly audio session so the WebView is allowed to
        // start audio without a user gesture (it's muted at first, but iOS still
        // checks the audio session before letting the video decoder spin up).
        Self.activateAudioSessionIfNeeded()

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = false
        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "ytbridge")
        config.userContentController = userContent
        // Tell the embedded player we're mobile Safari so YouTube serves the right
        // playback pipeline.
        config.applicationNameForUserAgent = "Version/17.0 Mobile/15E148 Safari/604.1"

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.bounces = false
        webView.isUserInteractionEnabled = true
        if #available(iOS 16.4, *) { webView.isInspectable = false }
        context.coordinator.onEmbedError = onEmbedError
        context.coordinator.progress = progress
        Self.load(videoId: videoId, muted: isMuted, into: webView)
        context.coordinator.lastVideoId = videoId
        context.coordinator.lastMuted = isMuted
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onEmbedError = onEmbedError
        context.coordinator.progress = progress
        // Only reload the HTML when the videoId itself changes.
        if context.coordinator.lastVideoId != videoId {
            Self.load(videoId: videoId, muted: isMuted, into: webView)
            context.coordinator.lastVideoId = videoId
            context.coordinator.lastMuted = isMuted
            progress?.wrappedValue = 0
            return
        }
        // Mute toggle without reloading — sends IFrame API command so the
        // video does not restart or flash.
        if context.coordinator.lastMuted != isMuted {
            let muteCmd = isMuted ? "mute" : "unMute"
            let js = """
            try {
              var f = document.getElementById('player');
              if (f && f.contentWindow) {
                f.contentWindow.postMessage(JSON.stringify({event:'command', func:'\(muteCmd)', args:[]}), '*');
              }
            } catch(e) {}
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
            context.coordinator.lastMuted = isMuted
        }
        // Toggle play/pause via the IFrame API postMessage channel.
        let funcName = isPlaying ? "playVideo" : "pauseVideo"
        let js = """
        try {
          var f = document.getElementById('player');
          if (f && f.contentWindow) {
            f.contentWindow.postMessage(JSON.stringify({event:'command', func:'\(funcName)', args:[]}), '*');
          }
        } catch(e) {}
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        // Pause the video so audio doesn't continue in the background.
        let js = """
        try {
          var f = document.getElementById('player');
          if (f && f.contentWindow) {
            f.contentWindow.postMessage(JSON.stringify({event:'command', func:'pauseVideo', args:[]}), '*');
          }
        } catch(e) {}
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private static func activateAudioSessionIfNeeded() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            // best effort — autoplay still works for muted video without this
        }
    }

    private static func load(videoId: String, muted: Bool, into webView: WKWebView) {
        // Wrap the embed in a tiny HTML doc so we can attach `playsinline` and
        // `webkit-playsinline` attributes to the iframe element itself — those
        // attributes are what actually let the video render inline on iOS, the
        // URL query param is insufficient on its own.
        let muteFlag = muted ? 1 : 0
        let html = """
        <!DOCTYPE html>
        <html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
        <style>html,body{margin:0;padding:0;background:#000;height:100%;width:100%;overflow:hidden;}
        iframe{position:absolute;inset:0;width:100%;height:100%;border:0;display:block;}</style>
        </head><body>
        <iframe id="player"
          src="https://www.youtube.com/embed/\(videoId)?autoplay=1&mute=\(muteFlag)&playsinline=1&controls=0&rel=0&modestbranding=1&showinfo=0&iv_load_policy=3&fs=0&disablekb=1&loop=1&playlist=\(videoId)&enablejsapi=1&origin=https://www.youtube.com"
          frameborder="0"
          allow="autoplay; encrypted-media; picture-in-picture"
          allowfullscreen
          playsinline
          webkit-playsinline></iframe>
        <script>
          var f = document.getElementById('player');
          window.__gsCT = 0;
          window.__gsDur = 0;
          f.addEventListener('load', function(){
            try {
              f.contentWindow.postMessage(JSON.stringify({event:'listening', id:'player'}), '*');
              f.contentWindow.postMessage(JSON.stringify({event:'command', func:'addEventListener', args:['onError']}), '*');
              f.contentWindow.postMessage(JSON.stringify({event:'command', func:'addEventListener', args:['onReady']}), '*');
              // Kick off playback again after the player frame is up — covers the
              // case where autoplay was deferred during initial iframe load.
              setTimeout(function(){
                try { f.contentWindow.postMessage(JSON.stringify({event:'command', func:'playVideo', args:[]}), '*'); } catch(e){}
              }, 250);
            } catch(e) {}
          });
          // Poll currentTime and duration so the progress scrubber stays in sync.
          setInterval(function(){
            try {
              f.contentWindow.postMessage(JSON.stringify({event:'command', func:'getCurrentTime', args:[]}), '*');
              f.contentWindow.postMessage(JSON.stringify({event:'command', func:'getDuration', args:[]}), '*');
            } catch(e) {}
          }, 500);
          window.addEventListener('message', function(ev){
            try {
              var d = typeof ev.data === 'string' ? JSON.parse(ev.data) : ev.data;
              if (d && d.event === 'onError') {
                window.webkit.messageHandlers.ytbridge.postMessage({type:'error', code:d.info});
              }
              if (d && d.event === 'infoDelivery' && d.info) {
                if (d.info.currentTime !== undefined) window.__gsCT = d.info.currentTime;
                if (d.info.duration !== undefined) window.__gsDur = d.info.duration;
                if (window.__gsDur > 0) {
                  window.webkit.messageHandlers.ytbridge.postMessage({type:'progress', currentTime: window.__gsCT, duration: window.__gsDur});
                }
              }
            } catch(e) {}
          });
        </script>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var lastVideoId: String = ""
        var lastMuted: Bool = true
        var onEmbedError: (() -> Void)?
        var progress: Binding<Double>?

        nonisolated func userContentController(_ userContentController: WKUserContentController,
                                               didReceive message: WKScriptMessage) {
            guard message.name == "ytbridge" else { return }
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }
            if type == "error" {
                Task { @MainActor in self.onEmbedError?() }
            }
            if type == "progress",
               let currentTime = body["currentTime"] as? Double,
               let duration = body["duration"] as? Double,
               duration > 0 {
                let fraction = max(0, min(1, currentTime / duration))
                Task { @MainActor in self.progress?.wrappedValue = fraction }
            }
        }
    }

}

// MARK: - Comments Sheet

struct TrailerCommentsSheet: View {
    let trailer: TrailerItem

    @State private var draft: String = ""
    @State private var comments: [CommentItem] = CommentItem.mock

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Comments")
                    .scaledFont(size: 17, weight: .semibold)
                    .foregroundStyle(.white)
                Text("\(comments.count)")
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.white.opacity(0.55))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider().background(Color.white.opacity(0.07))

            ScrollView {
                VStack(spacing: 18) {
                    ForEach(comments) { c in
                        CommentRow(item: c)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }

            // Input bar
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(hex: "F5821F"))
                    .overlay(Text(String((AuthViewModel.shared.currentUser?.email ?? "GS").prefix(2)).uppercased()).scaledFont(size: 11, weight: .bold).foregroundStyle(.white))
                    .frame(width: 28, height: 28)
                TextField("", text: $draft, prompt: Text("Add a comment…").foregroundColor(Color.white.opacity(0.40)))
                    .foregroundStyle(.white)
                    .tint(Color(hex: "F5821F"))
                Button(action: {
                    guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    let initials = String((AuthViewModel.shared.currentUser?.email ?? "GS").prefix(2)).uppercased()
                    comments.insert(CommentItem(username: "you", initials: initials, color: Color(hex: "F5821F"), verified: false, timestamp: "just now", text: draft.trimmingCharacters(in: .whitespacesAndNewlines), likes: 0), at: 0)
                    draft = ""
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }) {
                    Image(systemName: "paperplane.fill")
                        .foregroundStyle(Color(hex: "F5821F"))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Color.white.opacity(0.06))
            .overlay(Capsule().stroke(Color.white.opacity(0.10)))
            .clipShape(Capsule())
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
    }
}

struct CommentItem: Identifiable {
    let id = UUID()
    let username: String
    let initials: String
    let color: Color
    let verified: Bool
    let timestamp: String
    let text: String
    let likes: Int

    static let mock: [CommentItem] = [
        .init(username: "cinema_mark", initials: "CM", color: .blue, verified: true,
              timestamp: "2h", text: "This is going to be the show of the year. Trailer alone is cinema.", likes: 124),
        .init(username: "stream_sara", initials: "SS", color: .orange, verified: false,
              timestamp: "4h", text: "Finally a return to form 🔥", likes: 41),
        .init(username: "tv_jake", initials: "TJ", color: .purple, verified: false,
              timestamp: "1d", text: "The cinematography in this is unreal.", likes: 18)
    ]
}

private struct CommentRow: View {
    let item: CommentItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(item.color)
                .overlay(Text(item.initials).scaledFont(size: 12, weight: .bold).foregroundStyle(.white))
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.username)
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(.white)
                    if item.verified {
                        ZStack {
                            Circle().fill(Color(hex: "F5821F")).frame(width: 14, height: 14)
                            Image(systemName: "checkmark")
                                .scaledFont(size: 8, weight: .black)
                                .foregroundStyle(.white)
                        }
                    }
                    Text(item.timestamp)
                        .scaledFont(size: 12)
                        .foregroundStyle(Color.white.opacity(0.40))
                }
                Text(item.text)
                    .scaledFont(size: 14)
                    .foregroundStyle(Color.white.opacity(0.85))
                HStack(spacing: 14) {
                    Text("Like")
                        .scaledFont(size: 12)
                        .foregroundStyle(Color.white.opacity(0.45))
                    Text("Reply")
                        .scaledFont(size: 12)
                        .foregroundStyle(Color.white.opacity(0.45))
                }
            }
            Spacer()
            VStack(spacing: 2) {
                Image(systemName: "hand.thumbsup")
                    .foregroundStyle(Color.white.opacity(0.45))
                Text("\(item.likes)")
                    .scaledFont(size: 10)
                    .foregroundStyle(Color.white.opacity(0.45))
            }
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

// MARK: - AdMob Full-Screen Reel Card

private struct AdMobReelCard: View {
    let headline: String
    let bodyText: String
    let ctaText: String
    let advertiser: String
    let imageURL: URL?
    let trailerKey: String
    let isPlaying: Bool
    let isMuted: Bool
    @Binding var playbackProgress: Double
    let size: CGSize
    let topInset: CGFloat
    let bottomInset: CGFloat
    let onTap: () -> Void

    var body: some View {
        ZStack {
            RemoteImage(
                url: imageURL,
                contentMode: .fill,
                fallbackColors: [
                    Color(hex: "0B1828"),
                    Color(hex: "04090F")
                ]
            )
            .frame(width: size.width, height: size.height)
            .clipped()

            if !trailerKey.isEmpty && isPlaying {
                YouTubePlayerView(
                    videoId: trailerKey,
                    isMuted: true,
                    isPlaying: isPlaying,
                    progress: $playbackProgress,
                    onEmbedError: { }
                )
                .allowsHitTesting(false)
                .frame(width: size.width, height: size.height)
                .clipped()
                .position(x: size.width / 2, y: size.height / 2)
            }

            // Colour grade
            Color(hex: "1A6FE8").opacity(0.12)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Identity letterforms
            Text("AD")
                .scaledFont(size: 240, weight: .black)
                .foregroundStyle(Color.white.opacity(0.04))
                .tracking(-9.6)
                .offset(y: -80)
                .allowsHitTesting(false)

            // Top scrim
            VStack {
                LinearGradient(
                    colors: [Color.navy.opacity(0.75),
                             Color.navy.opacity(0.30), .clear],
                    startPoint: .top, endPoint: .bottom)
                    .frame(height: 130)
                Spacer()
            }
            .allowsHitTesting(false)

            // Bottom scrim
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.clear,
                             Color.navy.opacity(0.55),
                             Color.navy.opacity(0.92),
                             Color.navy],
                    startPoint: .top, endPoint: .bottom)
                    .frame(height: 440)
            }
            .allowsHitTesting(false)

            // Sponsored + advertiser name row
            VStack {
                HStack {
                    Text("Sponsored")
                        .scaledFont(size: 10, weight: .semibold)
                        .foregroundStyle(Color.white.opacity(0.60))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.20))
                        .clipShape(.rect(cornerRadius: 4))
                        .padding(.leading, 14)
                        .padding(.top, topInset + 14)
                    Spacer()
                    Text(advertiser)
                        .scaledFont(size: 10, weight: .medium)
                        .foregroundStyle(Color.white.opacity(0.45))
                        .padding(.trailing, 14)
                        .padding(.top, topInset + 14)
                }
                Spacer()
            }

            // Right rail — dimmed, no actions on ad reels
            VStack {
                Spacer().frame(height: size.height * 0.30)
                HStack {
                    Spacer()
                    VStack(spacing: 28) {
                        ForEach(["heart", "message",
                                 "arrowshape.turn.up.right"],
                                id: \.self) { icon in
                            VStack(spacing: 4) {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(0.30))
                                        .overlay(Circle()
                                            .stroke(Color.white.opacity(0.08),
                                                    lineWidth: 1))
                                    Image(systemName: icon)
                                        .scaledFont(size: 20, weight: .semibold)
                                        .foregroundStyle(
                                            Color.white.opacity(0.20))
                                }
                                .frame(width: 52, height: 52)
                            }
                        }
                    }
                    .padding(.trailing, 18)
                }
                Spacer()
            }
            .allowsHitTesting(false)

            // Bottom content
            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 0) {
                    // Ad pill
                    Text("Ad")
                        .scaledFont(size: 11, weight: .bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(hex: "F5821F"))
                        .clipShape(.rect(cornerRadius: 6))
                        .padding(.bottom, 8)

                    Text(headline)
                        .scaledFont(size: 28, weight: .bold)
                        .tracking(-0.8)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(.bottom, 10)

                    Text(bodyText)
                        .scaledFont(size: 14)
                        .foregroundStyle(Color.white.opacity(0.78))
                        .lineLimit(2)
                        .padding(.bottom, 14)

                    Button(action: onTap) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.right")
                                .scaledFont(size: 13, weight: .bold)
                            Text(ctaText)
                                .scaledFont(size: 15, weight: .bold)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color(hex: "F5821F"))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 22)
                .padding(.trailing, 90)
                .padding(.bottom, bottomInset + 38)
            }

            // AdChoices badge — required for AdMob compliance
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.20),
                                    lineWidth: 1)
                        Text("i")
                            .scaledFont(size: 9, weight: .medium)
                            .foregroundStyle(Color.white.opacity(0.35))
                    }
                    .frame(width: 16, height: 16)
                    .padding(.trailing, 14)
                    .padding(.bottom, bottomInset + 44)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

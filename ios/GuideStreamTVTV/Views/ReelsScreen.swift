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
import AVKit
import Supabase
import YouTubeKit

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

    var label: String {
        switch self {
        case .forYou: return "For You"
        case .trending: return "Trending"
        case .new: return "New"
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

        // Fetch the three source lists in parallel.
        async let trendingTask: [TMDBResult] = (try? tmdb.getTrending()) ?? []
        async let onAirTask: [TMDBResult] = (try? tmdb.getOnTheAir()) ?? []
        async let myStreamsTask: [UserStream] = fetchMyStreams()

        let (trending, onAir, mine) = await (trendingTask, onAirTask, myStreamsTask)

        // For each show, fetch its YouTube trailer key + TMDB detail.
        // Keep the work parallel but capped to avoid hammering TMDB.
        let forYouItems = await buildItems(from: mineResults(mine), tab: .forYou)
        let trendingItems = await buildItems(from: Array(trending.prefix(15)), tab: .trending)
        let newItems = await buildItems(from: Array(onAir.prefix(15)), tab: .new)

        var combined = forYouItems + trendingItems + newItems
        // Insert sponsored reel at slot 4 (0-indexed) if we have content.
        if combined.count > 4 {
            combined.insert(makeSponsoredReel(), at: 4)
        } else if !combined.isEmpty {
            combined.append(makeSponsoredReel())
        }

        self.allTrailers = combined
        self.hasLoaded = !combined.isEmpty

        // Saved state now lives in the shared StreamsViewModel store, which
        // hydrates itself from the local cache on init and refreshes from
        // Supabase whenever the user signs in. Nothing else to do here.

        // Pre-resolve the first few trailer stream URLs so playback starts
        // instantly when the user lands on the feed.
        for trailer in combined.prefix(3) where !trailer.isSponsored && !trailer.trailerKey.isEmpty {
            TrailerStreamCache.shared.prefetch(trailer.trailerKey)
        }
    }

    private func mineResults(_ streams: [UserStream]) -> [TMDBResult] {
        streams.prefix(15).compactMap { s -> TMDBResult? in
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
                    async let keyTask: String? = try? tmdb.getTrailerKey(tmdbId: r.id)
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

    private func makeSponsoredReel() -> TrailerItem {
        let plat = ReelPlatform.info(for: "netflix")
        return TrailerItem(
            id: "sponsored-netflix-1",
            tmdbId: -1,
            showName: "Stream the world's biggest hits",
            synopsis: "Movies, series and live events. Try Netflix free for a month.",
            genre: "SPONSORED · NETFLIX",
            runtime: "Limited offer",
            platformId: "netflix",
            platformName: plat.name,
            platformColor: plat.color,
            platformTextColor: .white,
            backdropURL: nil,
            posterURL: nil,
            trailerKey: "",
            thumbnailURL: nil,
            youtubeURL: nil,
            deepLinkURL: nil,
            voteAverage: 0,
            likes: 0,
            comments: 0,
            tab: .forYou,
            identityCode: "NFX",
            gradeColor: Color.red.opacity(0.18),
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
                        if vm.reelSwipeCount % 5 == 0 {
                            // Fire interstitial *after* the swipe settles so the reel transition feels native.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                showInterstitial { }
                            }
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
        #if os(tvOS)
        .fullScreenCover(isPresented: $showComments) {
            if let trailer = currentTrailer {
                TrailerCommentsSheet(trailer: trailer)
            }
        }
        .fullScreenCover(isPresented: $showShare) {
            if let trailer = currentTrailer {
                TrailerShareSheet(trailer: trailer)
            }
        }
        .fullScreenCover(item: $detailSubject) { subject in
            EpisodeDetailSheet(subject: subject)
        }
        #else
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
        #endif
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
        ReelView(
            trailer: trailer,
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
                RakutenManager.shared.openAffiliateLink(
                    serviceId: trailer.platformId,
                    metadata: ["position": vm.currentIndex, "source": "reel"]
                )
                WatchIntentLogger.shared.log(
                    eventType: .sponsoredReelTapped,
                    platformId: trailer.platformId,
                    metadata: ["position": vm.currentIndex]
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
            }
        )
    }

    private func prefetchNeighbors(around index: Int) {
        let offsets = [-1, 0, 1, 2]
        for o in offsets {
            let i = index + o
            guard let t = vm.allTrailers[safe: i], !t.isSponsored, !t.trailerKey.isEmpty else { continue }
            TrailerStreamCache.shared.prefetch(t.trailerKey)
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
            if !trailer.isSponsored, !trailer.trailerKey.isEmpty, !embedFailed {
                #if targetEnvironment(simulator)
                SimulatorTrailerPoster(trailer: trailer)
                    .frame(width: size.width, height: size.height)
                    .position(x: size.width / 2, y: size.height / 2)
                #else
                if isCurrent {
                    ZStack {
                        // Poster sits underneath so the reel is never blank
                        // while the AVPlayer is resolving the YouTube stream URL.
                        SimulatorTrailerPoster(trailer: trailer)
                        YouTubeNativePlayerView(
                            videoId: trailer.trailerKey,
                            isMuted: isMuted,
                            isPlaying: isPlaying,
                            progress: $playbackProgress,
                            onError: { embedFailed = true }
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
                        .scaledFont(size: 40, weight: .bold)
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

                    HStack(spacing: 12) {
                        if trailer.isSponsored {
                            Button(action: onSponsorCTA) {
                                Text("Try \(trailer.platformName.capitalized) Free")
                                    .scaledFont(size: 15, weight: .bold)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .background(Color(hex: "F5821F"))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
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

// MARK: - Stream URL prefetch cache

/// Resolves YouTube progressive stream URLs ahead of time so that when a reel
/// becomes current, the AVPlayer can install immediately without waiting on
/// YouTubeKit. Cuts visible lag from ~1–2s to near-instant on real devices.
@MainActor
final class TrailerStreamCache {
    static let shared = TrailerStreamCache()

    private var cache: [String: URL] = [:]
    private var inflight: Set<String> = []

    func cached(_ videoId: String) -> URL? { cache[videoId] }

    func prefetch(_ videoId: String) {
        guard !videoId.isEmpty, cache[videoId] == nil, !inflight.contains(videoId) else { return }
        inflight.insert(videoId)
        Task { [weak self] in
            let resolved: URL? = await Self.resolve(videoId: videoId)
            await MainActor.run {
                guard let self else { return }
                if let resolved { self.cache[videoId] = resolved }
                self.inflight.remove(videoId)
            }
        }
    }

    nonisolated static func resolve(videoId: String) async -> URL? {
        do {
            let yt = YouTube(videoID: videoId, methods: [.local, .remote])
            let streams = try await yt.streams
            let combined = streams.filterVideoAndAudio()
            let pick = combined.lowestResolutionStream()
                ?? combined.first
                ?? streams.filterVideoOnly().lowestResolutionStream()
                ?? streams.first
            return pick?.url
        } catch {
            return nil
        }
    }
}

// MARK: - Native YouTube Player (AVPlayer + YouTubeKit)

/// Plays a YouTube video natively via AVPlayer. YouTubeKit resolves the direct
/// progressive stream URL (audio+video combined) on-device, then we hand it to
/// AVPlayer. This is dramatically more reliable than WKWebView + IFrame on
/// real devices — there's no embed handshake, no referrer/origin checks, no
/// silent black-frame failures.
private struct YouTubeNativePlayerView: UIViewRepresentable {
    let videoId: String
    let isMuted: Bool
    let isPlaying: Bool
    var progress: Binding<Double>? = nil
    var onError: (() -> Void)? = nil

    func makeUIView(context: Context) -> PlayerContainerView {
        Self.activateAudioSessionIfNeeded()
        let v = PlayerContainerView()
        v.backgroundColor = .black
        context.coordinator.container = v
        context.coordinator.onError = onError
        context.coordinator.progress = progress
        context.coordinator.load(videoId: videoId, muted: isMuted, playing: isPlaying)
        return v
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        context.coordinator.onError = onError
        context.coordinator.progress = progress
        context.coordinator.update(videoId: videoId, muted: isMuted, playing: isPlaying)
    }

    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    private static func activateAudioSessionIfNeeded() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {}
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        weak var container: PlayerContainerView?
        var player: AVPlayer?
        var looper: AVPlayerLooper?
        var queuePlayer: AVQueuePlayer?
        var currentVideoId: String = ""
        var resolveTask: Task<Void, Never>?
        var onError: (() -> Void)?
        var loopObserver: NSObjectProtocol?
        var progress: Binding<Double>?
        var timeObserverToken: Any?

        func load(videoId: String, muted: Bool, playing: Bool) {
            guard currentVideoId != videoId else { return }
            currentVideoId = videoId
            resolveTask?.cancel()
            teardownPlayer()

            // Fast path — URL already prefetched. Install immediately so playback starts
            // the moment the reel becomes current (no spinner, no black frame).
            if let cached = TrailerStreamCache.shared.cached(videoId) {
                installPlayer(url: cached, muted: muted, playing: playing)
                return
            }

            resolveTask = Task { [weak self] in
                guard let self else { return }
                let resolved = await TrailerStreamCache.resolve(videoId: videoId)
                if Task.isCancelled { return }
                await MainActor.run {
                    guard self.currentVideoId == videoId else { return }
                    guard let url = resolved else { self.onError?(); return }
                    TrailerStreamCache.shared.cached(videoId).map { _ in } // keep cache as source of truth via prefetch
                    self.installPlayer(url: url, muted: muted, playing: playing)
                }
            }
        }

        func update(videoId: String, muted: Bool, playing: Bool) {
            if currentVideoId != videoId {
                load(videoId: videoId, muted: muted, playing: playing)
                return
            }
            player?.isMuted = muted
            if playing { player?.play() } else { player?.pause() }
        }

        private func installPlayer(url: URL, muted: Bool, playing: Bool) {
            guard let container else { return }
            let item = AVPlayerItem(url: url)
            let queue = AVQueuePlayer()
            queue.isMuted = muted
            queue.actionAtItemEnd = .advance
            let loop = AVPlayerLooper(player: queue, templateItem: item)
            self.queuePlayer = queue
            self.looper = loop
            self.player = queue

            let layer = AVPlayerLayer(player: queue)
            layer.videoGravity = .resizeAspectFill
            container.setPlayerLayer(layer)
            if playing { queue.play() }
            attachTimeObserver(to: queue)
        }

        private func attachTimeObserver(to player: AVPlayer) {
            let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
            timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                guard let self else { return }
                let current = time.seconds
                let duration = player.currentItem?.duration.seconds ?? 0
                guard duration.isFinite, duration > 0 else { return }
                let pct = max(0, min(1, current / duration))
                self.progress?.wrappedValue = pct
            }
        }

        func teardown() {
            resolveTask?.cancel()
            resolveTask = nil
            teardownPlayer()
        }

        private func teardownPlayer() {
            if let obs = loopObserver { NotificationCenter.default.removeObserver(obs); loopObserver = nil }
            if let token = timeObserverToken {
                queuePlayer?.removeTimeObserver(token)
                timeObserverToken = nil
            }
            queuePlayer?.pause()
            looper = nil
            queuePlayer = nil
            player = nil
            container?.setPlayerLayer(nil)
            progress?.wrappedValue = 0
        }
    }

    final class PlayerContainerView: UIView {
        private var currentLayer: AVPlayerLayer?

        func setPlayerLayer(_ layer: AVPlayerLayer?) {
            currentLayer?.removeFromSuperlayer()
            currentLayer = layer
            if let layer {
                layer.frame = bounds
                self.layer.addSublayer(layer)
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            currentLayer?.frame = bounds
        }
    }
}

// MARK: - YouTube WKWebView (legacy, unused)

private struct YouTubePlayerView: UIViewRepresentable {
    let videoId: String
    let isMuted: Bool
    let isPlaying: Bool
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
        Self.load(videoId: videoId, muted: isMuted, into: webView)
        context.coordinator.lastVideoId = videoId
        context.coordinator.lastMuted = isMuted
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onEmbedError = onEmbedError
        if context.coordinator.lastVideoId != videoId || context.coordinator.lastMuted != isMuted {
            Self.load(videoId: videoId, muted: isMuted, into: webView)
            context.coordinator.lastVideoId = videoId
            context.coordinator.lastMuted = isMuted
            return
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
          window.addEventListener('message', function(ev){
            try {
              var d = typeof ev.data === 'string' ? JSON.parse(ev.data) : ev.data;
              if (d && d.event === 'onError') {
                window.webkit.messageHandlers.ytbridge.postMessage({type:'error', code:d.info});
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

        nonisolated func userContentController(_ userContentController: WKUserContentController,
                                               didReceive message: WKScriptMessage) {
            guard message.name == "ytbridge" else { return }
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String,
                  type == "error" else { return }
            Task { @MainActor in self.onEmbedError?() }
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
                    .overlay(Text("MA").scaledFont(size: 11, weight: .bold).foregroundStyle(.white))
                    .frame(width: 28, height: 28)
                TextField("", text: $draft, prompt: Text("Add a comment…").foregroundColor(Color.white.opacity(0.40)))
                    .foregroundStyle(.white)
                    .tint(Color(hex: "F5821F"))
                Image(systemName: "paperplane.fill")
                    .foregroundStyle(Color(hex: "F5821F"))
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
                ShareTile(icon: "ellipsis", label: "More") {}
                ShareTile(icon: "square.and.arrow.down", label: "Save") {}
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            Spacer()
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

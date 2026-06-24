//
//  HomeView.swift
//  GuideStreamTV
//

import SwiftUI
import UserNotifications

// MARK: - Home Models

struct Platform {
    let name: String
    let color: Color

    static let netflix = Platform(name: "NETFLIX", color: Color(red: 0xE5/255, green: 0x09/255, blue: 0x14/255))
    static let hbo = Platform(name: "HBO", color: Color(red: 0x5A/255, green: 0x1F/255, blue: 0xCB/255))
    static let appleTV = Platform(name: "Apple TV+", color: Color(red: 0x10/255, green: 0x10/255, blue: 0x10/255))
    static let hulu = Platform(name: "HULU", color: Color(red: 0x1C/255, green: 0xE7/255, blue: 0x83/255))
    static let prime = Platform(name: "PRIME", color: Color(red: 0x00/255, green: 0xA8/255, blue: 0xE1/255))
    static let disney = Platform(name: "DISNEY+", color: Color(red: 0x11/255, green: 0x3C/255, blue: 0xCF/255))
    static let paramount = Platform(name: "PARAMOUNT+", color: Color(red: 0x00/255, green: 0x64/255, blue: 0xFF/255))
    static let peacock = Platform(name: "PEACOCK", color: Color(red: 0x00/255, green: 0x00/255, blue: 0x00/255))
    static let starz = Platform(name: "STARZ", color: Color(red: 0x00/255, green: 0x00/255, blue: 0x00/255))
    static let showtime = Platform(name: "SHOWTIME", color: Color(red: 0xD8/255, green: 0x00/255, blue: 0x00/255))
    static let crunchyroll = Platform(name: "CRUNCHYROLL", color: Color(red: 0xF4/255, green: 0x7B/255, blue: 0x20/255))
    static let youtube = Platform(name: "YOUTUBE", color: Color(red: 0xFF/255, green: 0x00/255, blue: 0x00/255))

    /// Maps a TMDB watch-provider name to one of our branded Platforms. Returns nil if we don't
    /// recognise the provider, so callers can hide items rather than label them generically.
    static func from(providerName raw: String?) -> Platform? {
        guard let raw, !raw.isEmpty else { return nil }
        let key = raw.lowercased()
        if key.contains("netflix") { return .netflix }
        if key.contains("max") || key.contains("hbo") { return .hbo }
        if key.contains("apple tv") { return .appleTV }
        if key.contains("disney") { return .disney }
        if key.contains("hulu") { return .hulu }
        if key.contains("amazon") || key.contains("prime video") { return .prime }
        if key.contains("paramount") { return .paramount }
        if key.contains("peacock") { return .peacock }
        if key.contains("starz") { return .starz }
        if key.contains("showtime") { return .showtime }
        if key.contains("crunchyroll") { return .crunchyroll }
        if key.contains("youtube") { return .youtube }
        return nil
    }
}

struct Episode: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let season: String
    let duration: String
    let platform: String
    let platformColor: Color
    let isNew: Bool
    let progress: Double
    let posterColors: [Color]
    let symbol: String
    let posterUrl: String?
    let tmdbId: Int?

    init(title: String, season: String, duration: String, platform: Platform, isNew: Bool = false, progress: Double = 0, posterColors: [Color], symbol: String, posterUrl: String? = nil, tmdbId: Int? = nil) {
        self.title = title
        self.season = season
        self.duration = duration
        self.platform = platform.name
        self.platformColor = platform.color
        self.isNew = isNew
        self.progress = progress
        self.posterColors = posterColors
        self.symbol = symbol
        self.posterUrl = posterUrl
        self.tmdbId = tmdbId
    }
}

struct PosterShow: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let meta: String
    let posterColors: [Color]
    let symbol: String
    var posterUrl: String? = nil
    var tmdbId: Int? = nil
    var voteAverage: Double? = nil
    var seasonCount: Int? = nil
}

/// Default gradient colors used as a tasteful fallback while TMDB images load or when they fail.
enum HomeFallback {
    static let posterColors: [Color] = [
        Color(red: 0.20, green: 0.15, blue: 0.45),
        Color(red: 0.04, green: 0.02, blue: 0.10)
    ]
}

/// A show's next upcoming episode sourced from TheTVDB.
/// Drives the "Upcoming Episodes" horizontal row on the home screen.
struct TVDBUpcomingItem: Identifiable {
    let id: Int
    let showTitle: String
    let posterUrl: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let episodeName: String?
    let airDate: Date?
    let platform: Platform?
}

/// A movie in theaters heading to streaming — drives the "Coming to Streaming" rail.
struct ComingToStreamingItem: Identifiable, Hashable {
    let id = UUID()
    let show: PosterShow
    let badgeText: String
    let isDated: Bool
    let whereText: String
}

// MARK: - HomeView

struct HomeView: View {
    var onOpenAgent: () -> Void = {}

    @State private var widgetBannerDismissed: Bool = false
    @State private var path: [HomeRoute] = []
    @State private var detailSubject: DetailSubject?
    @State private var showSearch: Bool = false
    @State private var searchResultForDetail: SearchResult?
    @State private var showServicesSheet: Bool = false
    @State private var showWatchListSheet: Bool = false
    @State private var auth = AuthViewModel.shared
    @State private var streams = StreamsViewModel.shared
    @State private var castPlayback = CastPlaybackState.shared
    @State private var trending: [TMDBResult] = []
    @State private var onAir: [TMDBResult] = []
    @State private var bingeFallback: [TMDBResult] = []
    @State private var newToday: [TMDBResult] = []
    @State private var sportsGames: [SportsGame] = []
    @State private var newsStreams: [NewsStream] = []
    @State private var selectedGame: SportsGame?
    /// Cached top US streaming provider per TMDB id. Items without an entry have no real
    /// streaming service and are filtered out of the UI.
    @State private var providerByTmdb: [Int: Platform] = [:]
    @State private var popularOnServiceResults: [String: [TMDBResult]] = [:]
    private let tmdbProviderIdMap: [String: Int] = ["netflix": 8, "prime": 9, "disney": 337, "hbo": 1899, "hulu": 15, "appletv": 350, "paramount": 531, "peacock": 386, "starz": 43, "showtime": 37, "crunchyroll": 283, "amc": 526, "discovery": 584, "mubi": 11, "britbox": 151, "fubo": 257, "tubi": 73, "pluto": 300, "youtube": 192]
    @State private var topRated: [TMDBResult] = []
    @State private var genreShows: [TMDBResult] = []
    @State private var recommendedShows: [TMDBResult] = []
    @State private var expiringItems: [(tmdbId: Int, title: String, daysLeft: Int, sourceId: String)] = []
    @State private var selectedGenreId: Int = 80
    @State private var selectedGenreName: String = "Crime"
    @State private var tvdbUpcomingItems: [TVDBUpcomingItem] = []
    @State private var genreHighlighted: Bool = false
    @State private var becauseYouWatchHighlighted: Bool = false
    @State private var comingToStreaming: [ComingToStreamingItem] = []

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                // Atmosphere — mirrors the login/sign-in screen background so the
                // branded depth feeling carries through every surface in the app.
                GeometryReader { geo in
                    Circle()
                        .fill(Color.blue.opacity(0.18))
                        .frame(width: geo.size.width * 0.9)
                        .blur(radius: 90)
                        .offset(x: -geo.size.width * 0.35, y: -geo.size.height * 0.35)
                    Circle()
                        .fill(Color.orange.opacity(0.10))
                        .frame(width: geo.size.width * 0.7)
                        .blur(radius: 80)
                        .offset(x: geo.size.width * 0.4, y: geo.size.height * 0.45)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                ScrollViewReader { scrollProxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        Color.clear.frame(height: 56)

                        // Search bar tap target — opens SearchView
                        Button {
                            showSearch = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.4))
                                Text("Search shows, movies, sports…")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.white.opacity(0.3))
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .background(Color.white.opacity(0.07))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)

                        if !heroItems.isEmpty {
                            HomeHeroCarousel(
                                items: heroItems,
                                onSelectMedia: { result, platform in
                                    WatchIntentLogger.shared.log(
                                        eventType: .cardTapped,
                                        titleId: String(result.id),
                                        platformId: platform?.name.lowercased() ?? "tmdb",
                                        metadata: ["section": "hero_carousel"]
                                    )
                                    detailSubject = .show(mediaAsPoster(result, platform: platform))
                                },
                                onSelectGame: { game in
                                    WatchIntentLogger.shared.log(
                                        eventType: .cardTapped,
                                        titleId: WatchIntentLogger.titleSlug("\(game.away.abbreviation)-\(game.home.abbreviation)-\(game.sport)"),
                                        platformId: (game.broadcasts.first ?? "").lowercased(),
                                        metadata: [
                                            "section": "hero_carousel",
                                            "kind": "sport",
                                            "state": game.state.rawValue
                                        ]
                                    )
                                    selectedGame = game
                                },
                                onSelectNews: { news in
                                    WatchIntentLogger.shared.log(
                                        eventType: .cardTapped,
                                        titleId: String(news.id),
                                        platformId: (news.providerName ?? "tmdb").lowercased(),
                                        metadata: [
                                            "section": "hero_carousel",
                                            "kind": "news",
                                            "outlet": news.outlet
                                        ]
                                    )
                                    openNewsArticle(news)
                                }
                            )
                        }

                        WatchListSection(
                            items: watchListEpisodes,
                            isAuthenticated: auth.isAuthenticated,
                            onSeeAll: {
                                WatchIntentLogger.shared.log(
                                    eventType: .cardTapped,
                                    metadata: ["section": "watch_list_see_all"]
                                )
                                showWatchListSheet = true
                            },
                            onOpen: { ep in
                                WatchIntentLogger.shared.log(
                                    eventType: .cardTapped,
                                    titleId: WatchIntentLogger.titleSlug(ep.title),
                                    platformId: ep.platform.lowercased(),
                                    metadata: ["section": "watch_list"]
                                )
                                detailSubject = .episode(ep)
                            }
                        )
                        .padding(.horizontal, 20)

                        NewEpisodesSection(
                            sectionTitle: (streams.userStreams.isEmpty && !trending.isEmpty) ? "Trending This Week" : "New Episodes",
                            episodes: liveNewEpisodes,
                            onSeeAll: {
                                WatchIntentLogger.shared.log(
                                    eventType: .cardTapped,
                                    metadata: ["section": "new_episodes_see_all"]
                                )
                                path.append(.newEpisodes)
                            },
                            onOpen: { ep in
                                WatchIntentLogger.shared.log(
                                    eventType: .cardTapped,
                                    titleId: WatchIntentLogger.titleSlug(ep.title),
                                    platformId: ep.platform.lowercased()
                                )
                                detailSubject = .episode(ep)
                            }
                        )
                        .padding(.horizontal, 20)

                        if !comingToStreaming.isEmpty {
                            ComingToStreamingSection(
                                items: comingToStreaming,
                                onOpen: { item in
                                    WatchIntentLogger.shared.log(
                                        eventType: .cardTapped,
                                        titleId: WatchIntentLogger.titleSlug(item.show.title),
                                        metadata: ["section": "coming_to_streaming"]
                                    )
                                    detailSubject = .show(item.show)
                                }
                            )
                            .padding(.horizontal, 20)
                        }

                        if !whatsNewTodayShows.isEmpty {
                            WhatsNewTodaySection(
                                shows: whatsNewTodayShows,
                                onSeeAll: {
                                    WatchIntentLogger.shared.log(
                                        eventType: .cardTapped,
                                        metadata: ["section": "whats_new_today_see_all"]
                                    )
                                    path.append(.whatsNewToday)
                                },
                                onOpen: { show in
                                    WatchIntentLogger.shared.log(
                                        eventType: .cardTapped,
                                        titleId: WatchIntentLogger.titleSlug(show.title),
                                        metadata: ["section": "whats_new_today"]
                                    )
                                    detailSubject = .show(show)
                                }
                            )
                            .padding(.horizontal, 20)
                        }

                        if !topPicksShows.isEmpty {
                            TopPicksSection(
                                shows: topPicksShows,
                                onSeeAll: {
                                    WatchIntentLogger.shared.log(
                                        eventType: .cardTapped,
                                        metadata: ["section": "top_picks_see_all"]
                                    )
                                    path.append(.topPicks)
                                },
                                onOpen: { show in
                                    WatchIntentLogger.shared.log(
                                        eventType: .cardTapped,
                                        titleId: WatchIntentLogger.titleSlug(show.title),
                                        metadata: ["section": "top_picks"]
                                    )
                                    detailSubject = .show(show)
                                }
                            )
                            .padding(.horizontal, 20)
                        }

                        if !trendingRankedShows.isEmpty {
                            TrendingRankedSection(
                                shows: trendingRankedShows,
                                onSeeAll: {
                                    WatchIntentLogger.shared.log(
                                        eventType: .cardTapped,
                                        metadata: ["section": "trending_ranked_see_all"]
                                    )
                                    path.append(.trending)
                                },
                                onOpen: { show in
                                    WatchIntentLogger.shared.log(
                                        eventType: .cardTapped,
                                        titleId: WatchIntentLogger.titleSlug(show.title),
                                        metadata: ["section": "trending_ranked"]
                                    )
                                    detailSubject = .show(show)
                                }
                            )
                            .padding(.horizontal, 20)
                        }

                        if !leavingSoonShows.isEmpty {
                            LeavingSoonSection(
                                shows: leavingSoonShows,
                                onSeeAll: {
                                    WatchIntentLogger.shared.log(
                                        eventType: .cardTapped,
                                        metadata: ["section": "leaving_soon_see_all"]
                                    )
                                    path.append(.leavingSoon)
                                },
                                onOpen: { show in
                                    WatchIntentLogger.shared.log(
                                        eventType: .cardTapped,
                                        titleId: WatchIntentLogger.titleSlug(show.title),
                                        metadata: ["section": "leaving_soon"]
                                    )
                                    detailSubject = .show(show)
                                }
                            )
                            .padding(.horizontal, 20)
                        }

                        ForEach(StreamingCatalog.ordered(from: auth.selectedServices), id: \.id) { service in
                            if let results = popularOnServiceResults[service.id], !results.isEmpty {
                                let shows = results.map { r in
                                    PosterShow(
                                        title: r.displayName,
                                        meta: r.year.map { "\($0)" } ?? (r.isTV ? "Series" : "Movie"),
                                        posterColors: [service.glow.opacity(0.85), service.bg],
                                        symbol: "play.fill",
                                        posterUrl: r.posterUrl,
                                        tmdbId: r.id
                                    )
                                }
                                PopularOnServiceSection(
                                    serviceName: service.name,
                                    accentColor: service.glow,
                                    shows: shows,
                                    onOpen: { show in
                                        WatchIntentLogger.shared.log(
                                            eventType: .cardTapped,
                                            titleId: WatchIntentLogger.titleSlug(show.title),
                                            metadata: ["section": "popular_on_\(service.id)"]
                                        )
                                        detailSubject = .show(show)
                                    }
                                )
                                .padding(.horizontal, 20)
                            }
                        }

                        ForEach(showsBySelectedPlatform, id: \.name) { row in
                            PlatformRow(
                                platformName: row.name,
                                platformColor: row.color,
                                shows: row.shows,
                                onOpen: { show in
                                    WatchIntentLogger.shared.log(
                                        eventType: .cardTapped,
                                        titleId: WatchIntentLogger.titleSlug(show.title),
                                        platformId: row.name.lowercased(),
                                        metadata: ["section": "platform_row"]
                                    )
                                    detailSubject = .show(show)
                                }
                            )
                            .padding(.horizontal, 20)
                        }

                        if !trendingRanked.isEmpty {
                            TrendingRankedSection(
                                shows: trendingRanked,
                                onSeeAll: nil,
                                onOpen: { show in
                                    WatchIntentLogger.shared.log(
                                        eventType: .cardTapped,
                                        titleId: WatchIntentLogger.titleSlug(show.title),
                                        metadata: ["section": "trending_ranked"]
                                    )
                                    detailSubject = .show(show)
                                }
                            )
                            .padding(.horizontal, 20)
                        }

                        GenreDiscoverySection(highlighted: false) { genreId, genreName, mediaType in
                            selectedGenreId = genreId
                            selectedGenreName = genreName
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                scrollProxy.scrollTo("browseByGenre", anchor: .top)
                            }
                            // Dramatic pulse sequence for the Because You Watch panel
                            becauseYouWatchHighlighted = false
                            Task {
                                let shows: [TMDBResult]?
                                switch mediaType {
                                case "movie":
                                    shows = try? await TMDBService.shared.getDiscoverByGenre(genreId, mediaType: "movie")
                                case "international":
                                    shows = try? await TMDBService.shared.getDiscoverInternational()
                                default:
                                    shows = try? await TMDBService.shared.getDiscoverByGenre(genreId)
                                }
                                if let shows {
                                    genreShows = shows
                                    recommendedShows = shows
                                    await hydrateProviders()
                                    // Phase 1: slow grow-in with relaxed spring
                                    await MainActor.run {
                                        withAnimation(.spring(response: 0.55, dampingFraction: 0.55, blendDuration: 0)) {
                                            becauseYouWatchHighlighted = true
                                        }
                                    }
                                    try? await Task.sleep(for: .milliseconds(550))
                                    // Phase 2: leisurely snap-back overshoot
                                    await MainActor.run {
                                        withAnimation(.spring(response: 0.75, dampingFraction: 0.6, blendDuration: 0)) {
                                            becauseYouWatchHighlighted = false
                                        }
                                    }
                                    try? await Task.sleep(for: .milliseconds(800))
                                    // Phase 3: gentle settle into persistent glow
                                    await MainActor.run {
                                        withAnimation(.spring(response: 1.1, dampingFraction: 0.7, blendDuration: 0.15)) {
                                            becauseYouWatchHighlighted = true
                                        }
                                    }
                                }
                            }
                        }
                        .id("browseByGenre")
                        .padding(.horizontal, 20)

                        if !recommendedShows.isEmpty {
                            let recShows = recommendedShows
                                .filter { providerByTmdb[$0.id] != nil }
                                .prefix(12)
                                .map { mediaAsPoster($0, platform: providerByTmdb[$0.id]) }
                            if !recShows.isEmpty {
                                BecauseYouWatchSection(
                                    genreName: selectedGenreName,
                                    shows: recShows,
                                    highlighted: becauseYouWatchHighlighted,
                                    onOpen: { show in
                                        WatchIntentLogger.shared.log(
                                            eventType: .cardTapped,
                                            titleId: WatchIntentLogger.titleSlug(show.title),
                                            metadata: [
                                                "section": "because_you_watch",
                                                "genre": selectedGenreName
                                            ]
                                        )
                                        detailSubject = .show(show)
                                    }
                                )
                                .scaleEffect(becauseYouWatchHighlighted ? 1.06 : 1.0)
                                .animation(.spring(response: 0.75, dampingFraction: 0.55), value: becauseYouWatchHighlighted)
                                .shadow(color: becauseYouWatchHighlighted ? Color.orange.opacity(0.45) : .clear, radius: becauseYouWatchHighlighted ? 24 : 0, y: becauseYouWatchHighlighted ? 6 : 0)
                                .animation(.spring(response: 0.8, dampingFraction: 0.6), value: becauseYouWatchHighlighted)
                                .padding(.horizontal, 20)
                            }
                        }

                        if !topRatedShows.isEmpty {
                            TopRatedSection(
                                shows: topRatedShows,
                                onOpen: { show in
                                    WatchIntentLogger.shared.log(
                                        eventType: .cardTapped,
                                        titleId: WatchIntentLogger.titleSlug(show.title),
                                        metadata: ["section": "top_rated"]
                                    )
                                    detailSubject = .show(show)
                                }
                            )
                            .padding(.horizontal, 20)
                        }

                        if !leavingSoonShows.isEmpty {
                            LeavingSoonSection(
                                shows: leavingSoonShows,
                                onSeeAll: nil,
                                onOpen: { show in
                                    WatchIntentLogger.shared.log(
                                        eventType: .cardTapped,
                                        titleId: WatchIntentLogger.titleSlug(show.title),
                                        metadata: ["section": "leaving_soon"]
                                    )
                                    detailSubject = .show(show)
                                }
                            )
                            .padding(.horizontal, 20)
                        }

                        if !newSeasonsYouKnow.isEmpty {
                            NewSeasonsSection(
                                results: newSeasonsYouKnow,
                                providerByTmdb: providerByTmdb,
                                streams: streams,
                                onOpen: { show in
                                    WatchIntentLogger.shared.log(
                                        eventType: .cardTapped,
                                        titleId: WatchIntentLogger.titleSlug(show.title),
                                        metadata: ["section": "new_seasons"]
                                    )
                                    detailSubject = .show(show)
                                }
                            )
                            .padding(.horizontal, 20)
                        }

                        if !tvdbUpcomingItems.isEmpty {
                            UpcomingEpisodesRow(
                                items: tvdbUpcomingItems,
                                onOpen: { item in
                                    WatchIntentLogger.shared.log(
                                        eventType: .cardTapped,
                                        titleId: String(item.id),
                                        metadata: ["section": "upcoming_episodes"]
                                    )
                                    detailSubject = .show(PosterShow(
                                        title: item.showTitle,
                                        meta: item.platform?.name ?? "Upcoming",
                                        posterColors: item.platform.map { [$0.color, $0.color.opacity(0.7)] } ?? HomeFallback.posterColors,
                                        symbol: "sparkles",
                                        posterUrl: item.posterUrl,
                                        tmdbId: item.id
                                    ))
                                }
                            )
                            .padding(.horizontal, 20)
                        }

                        if !widgetBannerDismissed {
                            WidgetPromoBanner(
                                onSetUp: {
                                    WatchIntentLogger.shared.log(eventType: .widgetSetupTapped)
                                    path.append(.widgetSetup)
                                },
                                onDismiss: { withAnimation(.easeOut(duration: 0.25)) { widgetBannerDismissed = true } }
                            )
                            .padding(.horizontal, 20)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // Continue Watching is intentionally hidden when the user hasn't watched anything yet —
                        // showing fake "continue watching" entries for shows the user never opened is worse than nothing.
                        if !continueWatchingEpisodes.isEmpty {
                            ContinueWatchingSection(
                                episodes: continueWatchingEpisodes,
                                onSeeAll: {
                                    WatchIntentLogger.shared.log(
                                        eventType: .cardTapped,
                                        metadata: ["section": "continue_watching_see_all"]
                                    )
                                    path.append(.continueWatching)
                                },
                                onOpen: { ep in
                                    WatchIntentLogger.shared.log(
                                        eventType: .continueWatching,
                                        titleId: WatchIntentLogger.titleSlug(ep.title),
                                        platformId: ep.platform.lowercased()
                                    )
                                    detailSubject = .episode(ep)
                                }
                            )
                            .padding(.horizontal, 20)
                        }

                        if !bingeReadyShows.isEmpty {
                            BingeReadySection(
                                sectionTitle: bingeReadyTitle,
                                tag: bingeReadyTag,
                                shows: bingeReadyShows,
                                onSeeAll: {
                                    WatchIntentLogger.shared.log(
                                        eventType: .cardTapped,
                                        metadata: ["section": "binge_ready_see_all"]
                                    )
                                    path.append(.bingeWorthy)
                                },
                                onOpen: { show in
                                    WatchIntentLogger.shared.log(
                                        eventType: .cardTapped,
                                        titleId: WatchIntentLogger.titleSlug(show.title),
                                        metadata: ["section": "binge_ready"]
                                    )
                                    detailSubject = .show(show)
                                }
                            )
                            .padding(.horizontal, 20)
                        }

                        if !newsStreams.isEmpty {
                            NewsSection(
                                items: newsStreams,
                                onSeeAll: {
                                    WatchIntentLogger.shared.log(
                                        eventType: .cardTapped,
                                        metadata: ["section": "news_see_all"]
                                    )
                                    path.append(.news)
                                },
                                onOpen: { news in
                                    WatchIntentLogger.shared.log(
                                        eventType: .cardTapped,
                                        titleId: String(news.id),
                                        platformId: (news.providerName ?? "tmdb").lowercased(),
                                        metadata: ["section": "news", "outlet": news.outlet]
                                    )
                                    openNewsArticle(news)
                                }
                            )
                            .padding(.horizontal, 20)
                        }

                        Color.clear.frame(height: 96)
                    }
                    .padding(.top, 4)
                }
                .tracksTabBarVisibility()
                } // ScrollViewReader

                VStack(spacing: 0) {
                    PageBar(
                        selectedServiceIds: orderedSelectedServiceIds,
                        onServicesPill: { showServicesSheet = true }
                    )
                    if let session = castPlayback.current {
                        PlayingOnBanner(
                            session: session,
                            onTapRemote: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                if session.deviceKind == .roku {
                                    castPlayback.openRokuRemote()
                                }
                            },
                            onDismiss: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.easeOut(duration: 0.25)) {
                                    castPlayback.stop()
                                }
                            }
                        )
                        .padding(.horizontal, 14)
                        .padding(.top, 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .background(.ultraThinMaterial)
                .opacity(0.75)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.white.opacity(0.05))
                        .frame(height: 0.5)
                }
                .allowsHitTesting(true)
                .animation(.spring(response: 0.4, dampingFraction: 0.82), value: castPlayback.current?.id)
            }
            .background(BrandBackground())
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .newEpisodes:
                    NewEpisodesListView(
                        episodes: liveNewEpisodes,
                        onSelect: { ep in detailSubject = .episode(ep) }
                    )
                case .bingeWorthy:
                    BingeWorthyListView(
                        shows: allBingeReadyShows,
                        sectionTitle: bingeReadyTitle,
                        onSelect: { show in detailSubject = .show(show) }
                    )
                case .whatsNewToday:
                    WhatsNewTodayListView(
                        shows: allWhatsNewTodayShows,
                        onSelect: { show in detailSubject = .show(show) }
                    )
                case .news:
                    NewsListView(
                        items: newsStreams,
                        onSelect: { news in openNewsArticle(news) }
                    )
                case .widgetSetup:
                    WidgetSetupView()
                case .topPicks:
                    BingeWorthyListView(
                        shows: topPicksShows,
                        sectionTitle: "Top Picks for You",
                        tag: "TOP PICK",
                        onSelect: { show in detailSubject = .show(show) }
                    )
                case .trending:
                    BingeWorthyListView(
                        shows: trendingRankedShows,
                        sectionTitle: "Trending This Week",
                        tag: "TRENDING",
                        onSelect: { show in detailSubject = .show(show) }
                    )
                case .leavingSoon:
                    BingeWorthyListView(
                        shows: leavingSoonShows,
                        sectionTitle: "Leaving Soon",
                        tag: "LEAVING SOON",
                        onSelect: { show in detailSubject = .show(show) }
                    )
                case .continueWatching:
                    ContinueWatchingGridView(
                        episodes: continueWatchingEpisodes,
                        onSelect: { ep in detailSubject = .episode(ep) }
                    )
                }
            }
            .sheet(item: $detailSubject) { subject in
                EpisodeDetailSheet(subject: subject)
            }
            .sheet(item: $selectedGame) { game in
                SportsWatchSheet(game: game)
            }
            .fullScreenCover(isPresented: $showSearch) {
                SearchView(isPresented: $showSearch) { result in
                    showSearch = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        if result.isTV {
                            searchResultForDetail = result
                        } else {
                            detailSubject = .show(PosterShow(
                                title: result.title,
                                meta: "Movie",
                                posterColors: HomeFallback.posterColors,
                                symbol: "play.fill",
                                posterUrl: result.posterUrl,
                                tmdbId: result.id
                            ))
                        }
                    }
                }
            }
            .fullScreenCover(item: $searchResultForDetail) { result in
                ShowDetailScreen(
                    titleId: String(result.id),
                    title: result.title,
                    posterUrl: result.posterUrl,
                    backdropUrl: result.backdropUrl,
                    isTV: true,
                    onBack: { searchResultForDetail = nil }
                )
            }
            .sheet(isPresented: $showServicesSheet) {
                ServicesBottomSheet()
            }
            .sheet(isPresented: $showWatchListSheet) {
                WatchListBottomSheet()
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(Color.orange)
        .task {
            await clearBadgeAndMarkSeen()
            await streams.refreshAll()
            await loadTrendingIfNeeded()
            await loadComingToStreaming()
        }
        .refreshable {
            await streams.refreshAll()
            await loadTrendingIfNeeded()
            await loadComingToStreaming()
        }
    }

    /// Clear the app icon badge and flag day-old new episodes as seen so the next launch doesn't re-pulse them.
    private func clearBadgeAndMarkSeen() async {
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
        await streams.markStaleEpisodesSeen()
    }

    /// Selected service ids in catalogue order — keeps the pill's stacked icons
    /// in the same priority as the onboarding grid (Netflix first, Prime next, etc.).
    private var orderedSelectedServiceIds: [String] {
        StreamingCatalog.ordered(from: auth.selectedServices).map { $0.id }
    }

    private func loadTrendingIfNeeded() async {
        // Always load TMDB content so the hero, new-episodes, and binge sections never fall back to a gradient-only state.
        async let trendingCall = try? TMDBService.shared.getTrending()
        async let onAirCall = try? TMDBService.shared.getOnTheAir()
        async let endedCall = try? TMDBService.shared.getDiscoverEnded()
        async let newTodayCall = try? TMDBService.shared.getNewToday()
        async let sportsCall = SportsService.shared.fetchAll()
        async let newsCall = NewsService.shared.fetchTopNewsStreams(limit: 10)
        async let topRatedCall = try? TMDBService.shared.getTopRated()
        async let genreCall = try? TMDBService.shared.getDiscoverByGenre(selectedGenreId)
        let (t, a, e, n, s, news, tr, genre) = await (trendingCall, onAirCall, endedCall, newTodayCall, sportsCall, newsCall, topRatedCall, genreCall)
        if let t { trending = t }
        if let a { onAir = a }
        if let e { bingeFallback = e }
        if let n { newToday = n }
        if let tr { topRated = tr }
        if let genre { genreShows = genre }
        sportsGames = s
        newsStreams = news
        await hydrateProviders()
        await loadPopularOnServices()

        // TVDB enrichment fires after providers resolve so we can attach
        // platform badges — non-blocking, silently ignored when TVDB is down.
        Task { await fetchTVDBUpcoming() }

        // Fetch expiring titles — prioritises watchlist IDs, falls back
        // to trending + on-air so the section always has content.
        let watchListIds = streams.userStreams.compactMap { Int($0.titleId) }
        let trendingIds = trending.map { $0.id }
        let onAirIds = onAir.map { $0.id }
        // Deduplicate: watchlist first, then trending, then on-air
        var seen = Set<Int>()
        var poolIds: [Int] = []
        for id in (watchListIds + trendingIds + onAirIds) where seen.insert(id).inserted {
            poolIds.append(id)
        }
        if !poolIds.isEmpty {
            expiringItems = await WatchmodeService.shared.getExpiringTitles(tmdbIds: poolIds)
        }

        let topGenreId = topGenreFromWatchList()
        if topGenreId.id != selectedGenreId {
            selectedGenreId = topGenreId.id
            selectedGenreName = topGenreId.name
            if let rec = try? await TMDBService.shared.getDiscoverByGenre(topGenreId.id) {
                recommendedShows = rec
            }
        } else {
            recommendedShows = genreShows
        }
    }

    /// Fetches the next upcoming episode for each watch-listed show from
    /// TheTVDB. Runs sequentially to respect MainActor isolation; 8 shows
    /// complete in ~3 seconds. Items without a TVDB match are skipped.
    private func fetchTVDBUpcoming() async {
        let watchTmdbIds = streams.userStreams.compactMap { Int($0.titleId) }.prefix(8)
        guard !watchTmdbIds.isEmpty else { return }
        var items: [TVDBUpcomingItem] = []
        for tmdbId in watchTmdbIds {
            guard let tvdbId = try? await TheTVDBService.shared.tvdbSeriesId(forTMDBId: tmdbId),
                  let nextEp = try? await TheTVDBService.shared.nextEpisode(seriesId: tvdbId)
            else { continue }
            let show = (trending + onAir).first { $0.id == tmdbId }
            items.append(TVDBUpcomingItem(
                id: tmdbId,
                showTitle: show?.displayName ?? "Unknown",
                posterUrl: show?.posterUrl,
                seasonNumber: nextEp.seasonNumber,
                episodeNumber: nextEp.episodeNumber,
                episodeName: nextEp.name,
                airDate: nextEp.airDate,
                platform: show.flatMap { providerByTmdb[$0.id] }
            ))
        }
        tvdbUpcomingItems = items
    }

    /// Maps known platform IDs to genre biases.
    /// Falls back to Drama (18) if no signal.
    private func topGenreFromWatchList() -> (id: Int, name: String) {
        let titles = streams.userStreams.compactMap { $0.title?.lowercased() }
        let crimeKeywords = ["crime","murder","detective","law","police","heist","thriller","dark","drug"]
        let scifiKeywords = ["space","star","alien","future","robot","sci","tech","galaxy"]
        let comedyKeywords = ["comedy","funny","laugh","sitcom","office","friends","park"]

        var crimeCt = 0, scifiCt = 0, comedyCt = 0
        for t in titles {
            if crimeKeywords.contains(where: { t.contains($0) }) { crimeCt += 1 }
            if scifiKeywords.contains(where: { t.contains($0) }) { scifiCt += 1 }
            if comedyKeywords.contains(where: { t.contains($0) }) { comedyCt += 1 }
        }
        let max = [crimeCt, scifiCt, comedyCt].max() ?? 0
        if max == 0 { return (18, "Drama") }
        if crimeCt == max { return (80, "Crime") }
        if scifiCt == max { return (10765, "Sci-Fi") }
        return (35, "Comedy")
    }

    /// Look up the top US streaming provider for every loaded TMDB result in parallel.
    /// Items with no recognised streaming service are intentionally left out of the dictionary
    /// so the rendering layer can hide them.
    private func hydrateProviders() async {
        let combined: [TMDBResult] = trending + onAir + bingeFallback + newToday + genreShows + recommendedShows
        let unique = Array(Dictionary(grouping: combined, by: { $0.id }).compactMapValues { $0.first }.values)
        let toFetch = unique.filter { providerByTmdb[$0.id] == nil }
        guard !toFetch.isEmpty else { return }

        let resolved: [(Int, Platform)] = await withTaskGroup(of: (Int, Platform)?.self) { group in
            for r in toFetch {
                group.addTask {
                    let provider = try? await TMDBService.shared.getTopWatchProvider(tmdbId: r.id, isTV: r.isTV)
                    guard let provider, let platform = Platform.from(providerName: provider.providerName) else {
                        return nil
                    }
                    return (r.id, platform)
                }
            }
            var out: [(Int, Platform)] = []
            for await pair in group {
                if let pair { out.append(pair) }
            }
            return out
        }

        var next = providerByTmdb
        for (id, platform) in resolved { next[id] = platform }
        providerByTmdb = next
    }

    /// Fetches popular TV shows AND movies for each of the user's selected
    /// streaming services using TMDB's provider-filtered discover endpoint.
    /// Each service gets up to 10 TV shows and 5 movies, merged and capped
    /// to 12 total so the horizontal rail stays snappy.
    private func loadPopularOnServices() async {
        let services = StreamingCatalog.ordered(from: auth.selectedServices)
        let collected: [(String, [TMDBResult])] = await withTaskGroup(
            of: (String, [TMDBResult]).self
        ) { group in
            for service in services {
                guard let providerId = tmdbProviderIdMap[service.id] else { continue }
                group.addTask {
                    async let tvItems = (try? await TMDBService.shared.getPopularOnService(tmdbProviderId: providerId)) ?? []
                    async let movieItems = (try? await TMDBService.shared.getPopularMoviesOnService(tmdbProviderId: providerId)) ?? []
                    let (tv, movies) = await (tvItems, movieItems)
                    // Interleave: show → movie → show → movie so both types are visible.
                    var merged: [TMDBResult] = []
                    let tvSlice = tv.prefix(10)
                    let movieSlice = movies.prefix(5)
                    var ti = tvSlice.makeIterator()
                    var mi = movieSlice.makeIterator()
                    while merged.count < 12 {
                        if let t = ti.next() { merged.append(t) }
                        if merged.count >= 12 { break }
                        if let m = mi.next() { merged.append(m) }
                        if merged.count >= 12 { break }
                        if ti.next() == nil && mi.next() == nil { break }
                    }
                    return (service.id, merged)
                }
            }
            var results: [(String, [TMDBResult])] = []
            for await pair in group {
                if !pair.1.isEmpty { results.append(pair) }
            }
            return results
        }
        var dict: [String: [TMDBResult]] = [:]
        for (id, items) in collected where !items.isEmpty {
            dict[id] = items
        }
        popularOnServiceResults = dict
    }

    // MARK: - Derived content

    /// Builds the heterogeneous hero carousel. Leads with up to two live
    /// sports broadcasts, then injects up to 2 news tiles right after the
    /// sports block (always slotted before the entertainment titles so
    /// breaking-news content sits front-and-center), then fills the rest
    /// with up to 15 trending titles that have a confirmed streaming
    /// provider, and finally one upcoming sports event when the rail is
    /// still thin. Titles without provider info are skipped so the rail
    /// never advertises a service we can't actually deeplink to.
    private var heroItems: [HeroItem] {
        var items: [HeroItem] = []

        let liveGames = sportsGames.filter { $0.state == .live }.prefix(2)
        for g in liveGames { items.append(.game(g)) }

        // Insert up to 2 news tiles immediately after the sports block so
        // news rides the high-priority real estate at the start of the rail.
        for news in newsStreams.prefix(2) {
            items.append(.news(news))
        }

        let mediaPool = trending + onAir + bingeFallback
        var seen: Set<Int> = []
        var media: [HeroItem] = []
        for r in mediaPool {
            if seen.contains(r.id) { continue }
            seen.insert(r.id)
            guard let platform = providerByTmdb[r.id] else { continue }
            media.append(.media(r, platform))
            if media.count >= 15 { break }
        }
        items.append(contentsOf: media)

        if items.count < 8, let nextUp = sportsGames.first(where: { $0.state == .pre }) {
            items.append(.game(nextUp))
        }
        return items
    }

    /// Opens a news article in Safari. News items come from NewsAPI —
    /// they're publisher articles, not TMDB titles, so there's no
    /// streaming service to resolve. The article URL (or the outlet's
    /// live-stream fallback) takes the user to the original story.
    private func openNewsArticle(_ news: NewsStream) {
        let target = news.articleUrl ?? news.fallbackWebURL
        guard let urlString = target, let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }

    private func mediaAsPoster(_ r: TMDBResult, platform: Platform?) -> PosterShow {
        let colors: [Color] = platform.map { [$0.color, $0.color.opacity(0.7)] } ?? HomeFallback.posterColors
        return PosterShow(
            title: r.displayName,
            meta: r.year.map { "\($0)" } ?? (r.isTV ? "Series" : "Movie"),
            posterColors: colors,
            symbol: "play.tv.fill",
            posterUrl: r.posterUrl,
            tmdbId: r.id,
            voteAverage: r.voteAverage
        )
    }

    /// Continue Watching only ever shows real telemetry-derived rows — never mock placeholders.
    private var continueWatchingEpisodes: [Episode] {
        // No backing data source yet; intentionally empty so the section hides.
        []
    }

    private var bingeReadyTitle: String {
        streams.userStreams.isEmpty ? "Binge Worthy" : "Binge Ready 🎉"
    }

    private var bingeReadyTag: String {
        streams.userStreams.isEmpty ? "BINGE WORTHY" : "FULL SEASON"
    }

    private var bingeReadyShows: [PosterShow] {
        Array(allBingeReadyShows.prefix(12))
    }

    /// Full Binge Worthy list (no count limit) used by the "See all" list view.
    private var allBingeReadyShows: [PosterShow] {
        bingeFallback
            .filter { providerByTmdb[$0.id] != nil }
            .map { r in
                PosterShow(
                    title: r.displayName,
                    meta: r.year.map { "\($0)" } ?? "Complete series",
                    posterColors: HomeFallback.posterColors,
                    symbol: "play.tv.fill",
                    posterUrl: r.posterUrl,
                    tmdbId: r.id,
                    voteAverage: r.voteAverage
                )
            }
    }

    /// What's New Today — trending TV/movies dropping today. Only includes
    /// items with a confirmed streaming provider so each card has a real
    /// "Watch on X" deeplink behind it.
    private var whatsNewTodayShows: [PosterShow] {
        Array(allWhatsNewTodayShows.prefix(12))
    }

    private var allWhatsNewTodayShows: [PosterShow] {
        newToday
            .filter { providerByTmdb[$0.id] != nil }
            .map { r in
                PosterShow(
                    title: r.displayName,
                    meta: r.year.map { "\($0)" } ?? (r.isTV ? "New series" : "New release"),
                    posterColors: HomeFallback.posterColors,
                    symbol: "flame.fill",
                    posterUrl: r.posterUrl,
                    tmdbId: r.id,
                    voteAverage: r.voteAverage
                )
            }
    }

    /// Top picks — trending titles scored by vote average and displayed with
    /// a match-percentage badge. Deduplicated against other recommendation rows.
    private var topPicksShows: [PosterShow] {
        trending
            .filter { providerByTmdb[$0.id] != nil }
            .map { r in
                let baseScore = (r.voteAverage ?? 7.0) / 10.0
                let clamped = max(72, min(98, Int(baseScore * 100)))
                return PosterShow(
                    title: r.displayName,
                    meta: "\(clamped)% Match",
                    posterColors: HomeFallback.posterColors,
                    symbol: "star.fill",
                    posterUrl: r.posterUrl,
                    tmdbId: r.id,
                    voteAverage: r.voteAverage
                )
            }
            .sorted { ($0.voteAverage ?? 0) > ($1.voteAverage ?? 0) }
            .prefix(12)
            .map { $0 }
    }

    /// Trending ranked — same pool as top picks but deduplicated so the
    /// same title never appears in both rows.
    private var trendingRankedShows: [PosterShow] {
        let topPickIds = Set(topPicksShows.compactMap { $0.tmdbId })
        return trending
            .filter { providerByTmdb[$0.id] != nil }
            .filter { !topPickIds.contains($0.id) }
            .map { r in
                PosterShow(
                    title: r.displayName,
                    meta: providerByTmdb[r.id]?.name ?? "",
                    posterColors: HomeFallback.posterColors,
                    symbol: "chart.bar.fill",
                    posterUrl: r.posterUrl,
                    tmdbId: r.id,
                    voteAverage: r.voteAverage
                )
            }
            .prefix(12)
            .map { $0 }
    }

    /// Leaving Soon — real expiration data from Watchmode, with a curated fallback
    /// so the section is never empty while the API resolves.
    private var leavingSoonShows: [PosterShow] {
        let live = expiringItems
            .filter { $0.daysLeft <= 7 }
            .compactMap { item -> PosterShow? in
                let platform = Platform.from(providerName: item.sourceId)
                let platformName = platform?.name ?? item.sourceId.uppercased()
                let daysText = item.daysLeft == 0 ? "Today"
                    : item.daysLeft == 1 ? "1 day left"
                    : "\(item.daysLeft) days left"
                let posterUrl: String? = streams.userStreams
                    .first(where: { Int($0.titleId) == item.tmdbId })?.posterUrl
                    ?? trending.first(where: { $0.id == item.tmdbId })?.posterUrl
                    ?? onAir.first(where: { $0.id == item.tmdbId })?.posterUrl
                return PosterShow(
                    title: item.title,
                    meta: "\(daysText) · \(platformName)",
                    posterColors: HomeFallback.posterColors,
                    symbol: "clock.badge.exclamationmark",
                    posterUrl: posterUrl,
                    tmdbId: item.tmdbId
                )
            }
        if !live.isEmpty { return live }
        // Curated fallback — well-known titles commonly cycling off services.
        // Replaced by live Watchmode data as soon as the API responds.
        return [
            PosterShow(title: "Breaking Bad", meta: "2 days left · NETFLIX", posterColors: [Color(red: 0x0A/255, green: 0x3E/255, blue: 0x2A/255), Color(red: 0x1A/255, green: 0x1A/255, blue: 0x2E/255)], symbol: "clock.badge.exclamationmark", tmdbId: 1396),
            PosterShow(title: "The Office", meta: "3 days left · PEACOCK", posterColors: [Color(red: 0x2D/255, green: 0x2D/255, blue: 0x3A/255), Color(red: 0x1A/255, green: 0x1A/255, blue: 0x2E/255)], symbol: "clock.badge.exclamationmark", tmdbId: 2316),
            PosterShow(title: "Yellowstone", meta: "4 days left · PARAMOUNT+", posterColors: [Color(red: 0x3A/255, green: 0x2E/255, blue: 0x17/255), Color(red: 0x1A/255, green: 0x1A/255, blue: 0x2E/255)], symbol: "clock.badge.exclamationmark", tmdbId: 73586),
            PosterShow(title: "The Handmaid's Tale", meta: "5 days left · HULU", posterColors: [Color(red: 0x2A/255, green: 0x1A/255, blue: 0x1A/255), Color(red: 0x1A/255, green: 0x2E/255, blue: 0x2A/255)], symbol: "clock.badge.exclamationmark", tmdbId: 69478),
            PosterShow(title: "The Boys", meta: "6 days left · PRIME", posterColors: [Color(red: 0x1A/255, green: 0x1A/255, blue: 0x3A/255), Color(red: 0x1A/255, green: 0x2E/255, blue: 0x2E/255)], symbol: "clock.badge.exclamationmark", tmdbId: 76479),
            PosterShow(title: "Andor", meta: "Today · DISNEY+", posterColors: [Color(red: 0x2A/255, green: 0x2A/255, blue: 0x1A/255), Color(red: 0x3A/255, green: 0x3A/255, blue: 0x2E/255)], symbol: "clock.badge.exclamationmark", tmdbId: 83867),
        ]
    }

    /// Episode cards built from the user's saved watch list. Skips the
    /// platform badge entirely (empty string) when the saved row's platform
    /// is missing or a generic placeholder — the detail sheet's Watchmode
    /// lookup will fill in the real service when the user taps in.
    var watchListEpisodes: [Episode] {
        streams.userStreams.map { row in
            let raw = (row.platform ?? "").trimmingCharacters(in: .whitespaces)
            let platformName = raw.uppercased()
            let lowerRaw = raw.lowercased()
            let isGenericPlaceholder = raw.isEmpty
                || platformName == "STREAM"
                || lowerRaw == "streaming"
                || lowerRaw == "streaming services"
            let platform: Platform
            switch platformName {
            case "NETFLIX": platform = .netflix
            case "HBO", "HBO MAX", "MAX": platform = .hbo
            case "APPLE TV+", "APPLETV", "APPLE": platform = .appleTV
            case "HULU": platform = .hulu
            case "PRIME", "AMAZON", "AMAZON PRIME": platform = .prime
            case "DISNEY+", "DISNEY": platform = .disney
            case "PARAMOUNT+", "PARAMOUNT", "PARAMOUNT PLUS": platform = .paramount
            case "PEACOCK": platform = .peacock
            case "CRUNCHYROLL": platform = .crunchyroll
            case "YOUTUBE": platform = .youtube
            default:
                // Empty name means the rendering layer hides the chip
                // entirely — better than the old "STREAM" placeholder.
                platform = Platform(name: isGenericPlaceholder ? "" : platformName, color: Color.orange)
            }
            return Episode(
                title: row.title ?? "Untitled",
                season: "Watch List",
                duration: "",
                platform: platform,
                isNew: false,
                posterColors: HomeFallback.posterColors,
                symbol: "bookmark.fill",
                posterUrl: row.posterUrl,
                tmdbId: Int(row.titleId)
            )
        }
    }

    /// Maps TMDB results into Episode cards when no Supabase rows are available. Items without
    /// a known streaming provider are omitted entirely so the UI never claims "On Air" as a service.
    private func tmdbAsEpisodes(_ results: [TMDBResult]) -> [Episode] {
        results.compactMap { r -> Episode? in
            guard let platform = providerByTmdb[r.id] else { return nil }
            return Episode(
                title: r.displayName,
                season: r.year.map { "\($0)" } ?? "New",
                duration: "",
                platform: platform,
                isNew: true,
                posterColors: HomeFallback.posterColors,
                symbol: "flame.fill",
                posterUrl: r.posterUrl,
                tmdbId: r.id
            )
        }
        .prefix(12)
        .map { $0 }
    }

    /// Prefer live Supabase rows; otherwise fall back to TMDB on-air, then trending. Never returns mock data,
    /// and never returns titles that don't have a verified streaming provider.
    var liveNewEpisodes: [Episode] {
        if streams.newEpisodes.isEmpty {
            let onAirEpisodes = tmdbAsEpisodes(onAir)
            if !onAirEpisodes.isEmpty { return onAirEpisodes }
            let trendingEpisodes = tmdbAsEpisodes(trending)
            if !trendingEpisodes.isEmpty { return trendingEpisodes }
            return []
        }
        return streams.newEpisodes.compactMap { row -> Episode? in
            let raw = (row.platform ?? "").trimmingCharacters(in: .whitespaces)
            let platformName = raw.uppercased()
            let lowerRaw = raw.lowercased()
            // New episodes without a real streaming platform are skipped —
            // a "STREAM" label has no app to open and is misleading.
            let isGenericPlaceholder = raw.isEmpty
                || platformName == "STREAM"
                || lowerRaw == "streaming"
                || lowerRaw == "streaming services"
            guard !isGenericPlaceholder else { return nil }
            let platform: Platform
            switch platformName {
            case "NETFLIX": platform = .netflix
            case "HBO", "HBO MAX", "MAX": platform = .hbo
            case "APPLE TV+", "APPLETV", "APPLE": platform = .appleTV
            case "HULU": platform = .hulu
            case "PRIME", "AMAZON", "AMAZON PRIME": platform = .prime
            case "DISNEY+", "DISNEY": platform = .disney
            case "PARAMOUNT+", "PARAMOUNT", "PARAMOUNT PLUS": platform = .paramount
            case "PEACOCK": platform = .peacock
            case "CRUNCHYROLL": platform = .crunchyroll
            case "YOUTUBE": platform = .youtube
            default: platform = Platform(name: platformName, color: Color.blue)
            }
            let season = row.season ?? 1
            let episode = row.episode ?? 1
            let duration = row.durationMinutes.map { "\($0)min" } ?? ""
            // Prefer the episode still, fall back to the show poster, so detail + see-all both render real art.
            let imageUrl = row.posterUrl
            let tmdbId = Int(row.titleId)
            return Episode(
                title: row.title ?? "Untitled",
                season: "S\(season) E\(episode)",
                duration: duration,
                platform: platform,
                isNew: row.isNew ?? true,
                posterColors: [Color(red: 0.20, green: 0.15, blue: 0.45), Color(red: 0.04, green: 0.02, blue: 0.10)],
                symbol: "sparkles",
                posterUrl: imageUrl,
                tmdbId: tmdbId
            )
        }
    }

    // MARK: - Derived content (new sections)

    /// Section 2: Platform rows — groups loaded TMDB results by platform,
    /// filtered to user's selected services.
    private var showsBySelectedPlatform: [(name: String, color: Color, shows: [PosterShow])] {
        let selected = auth.selectedServices.map { $0.lowercased() }
        let order = ["netflix","hbo","hulu","disney","appletv","prime","paramount","peacock"]
        let pool = trending + onAir + newToday
        var map: [String: (Color, [PosterShow])] = [:]
        for r in pool {
            guard let plat = providerByTmdb[r.id] else { continue }
            let key = plat.name.lowercased()
            let owned = selected.contains { s in
                key.contains(s) ||
                (s == "appletv" && key.contains("apple")) ||
                (s == "hbo" && (key.contains("hbo") || key.contains("max")))
            }
            guard owned else { continue }
            let show = mediaAsPoster(r, platform: plat)
            if map[key] == nil {
                map[key] = (plat.color, [show])
            } else if !(map[key]!.1.contains(where: { $0.tmdbId == r.id })) {
                map[key]!.1.append(show)
            }
        }
        return order.compactMap { key in
            guard let (color, shows) = map[key], shows.count >= 3 else { return nil }
            let displayName = providerByTmdb.values.first { $0.name.lowercased().contains(key) }?.name ?? key.capitalized
            return (displayName, color, Array(shows.prefix(12)))
        }
    }

    /// Section 3: Trending with rank numbers
    private var trendingRanked: [PosterShow] {
        trending
            .filter { providerByTmdb[$0.id] != nil }
            .prefix(10)
            .map { mediaAsPoster($0, platform: providerByTmdb[$0.id]) }
    }

    /// Section 6: Top rated
    private var topRatedShows: [PosterShow] {
        topRated
            .filter { providerByTmdb[$0.id] != nil }
            .prefix(12)
            .map { mediaAsPoster($0, platform: providerByTmdb[$0.id]) }
    }

    /// Loads movies currently in theaters and resolves their upcoming US
    /// digital streaming release dates. Dated items with a known release
    /// date come first; heuristic "coming soon" items follow. Capped at 12.
    private func loadComingToStreaming() async {
        guard let movies = try? await TMDBService.shared.getNowPlayingMovies() else { return }

        let calendar = Calendar.current
        let today = Date()
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: today) ?? today

        let dateFmt: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "MMM d"
            return f
        }()

        let rawFmt: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            return f
        }()

        var items: [ComingToStreamingItem] = []
        let pool = movies.prefix(15)

        let resolved: [(ComingToStreamingItem, Date?)] = await withTaskGroup(
            of: (ComingToStreamingItem, Date?)?.self
        ) { group in
            for movie in pool {
                group.addTask {
                    let releaseResult = try? await TMDBService.shared.getUSDigitalReleaseDate(movieId: movie.id)

                    if let digital = releaseResult {
                        // Has a future digital date — dated item
                        let badge = dateFmt.string(from: digital.date)
                        let whereText: String = {
                            if let n = digital.note?.trimmingCharacters(in: .whitespaces), !n.isEmpty {
                                return n
                            }
                            return "Streaming soon"
                        }()
                        return (ComingToStreamingItem(
                            show: PosterShow(
                                title: movie.displayName,
                                meta: whereText,
                                posterColors: HomeFallback.posterColors,
                                symbol: "film.fill",
                                posterUrl: movie.posterUrl,
                                tmdbId: movie.id
                            ),
                            badgeText: badge,
                            isDated: true,
                            whereText: whereText
                        ), digital.date)
                    } else if let rawDate = movie.releaseDate,
                              let releaseDate = rawFmt.date(from: rawDate),
                              releaseDate <= thirtyDaysAgo {
                        // No future digital date, but the theatrical release was
                        // at least 30 days ago — heuristic "coming soon" item
                        return (ComingToStreamingItem(
                            show: PosterShow(
                                title: movie.displayName,
                                meta: "In theaters now",
                                posterColors: HomeFallback.posterColors,
                                symbol: "film.fill",
                                posterUrl: movie.posterUrl,
                                tmdbId: movie.id
                            ),
                            badgeText: "Coming soon",
                            isDated: false,
                            whereText: "In theaters now"
                        ), nil)
                    }
                    return nil
                }
            }

            var out: [(ComingToStreamingItem, Date?)] = []
            for await pair in group {
                if let p = pair { out.append(p) }
            }
            return out
        }

        // Sort: dated items (earliest first), then heuristic items
        items = resolved.sorted { a, b in
            if a.1 != nil, b.1 == nil { return true }
            if a.1 == nil, b.1 != nil { return false }
            if let da = a.1, let db = b.1 { return da < db }
            return false
        }.map { $0.0 }

        let capped = Array(items.prefix(12))
        await MainActor.run { comingToStreaming = capped }
    }

    /// Section 8: New seasons of shows you follow
    private var newSeasonsYouKnow: [TMDBResult] {
        let savedIds = Set(streams.userStreams.compactMap { Int($0.titleId) })
        return onAir
            .filter { savedIds.contains($0.id) }
            .prefix(8)
            .map { $0 }
    }
}

// MARK: - PageBar

private struct PageBar: View {
    let selectedServiceIds: [String]
    let onServicesPill: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            BrandWordmark(wordmarkSize: .nav)
            Spacer()
            if !selectedServiceIds.isEmpty {
                ServicesPill(serviceIds: selectedServiceIds, onTap: onServicesPill)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
    }
}

// MARK: - Sections

private struct SectionGlassCard<Content: View>: View {
    let title: String
    let onSeeAll: (() -> Void)?
    let highlighted: Bool
    /// Optional custom accent color used for the "See all" link and the
    /// highlighted stroke. Defaults to brand orange so existing call sites
    /// keep their current visual.
    let accentColor: Color
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        highlighted: Bool = false,
        accentColor: Color = Color.orange,
        onSeeAll: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.highlighted = highlighted
        self.accentColor = accentColor
        self.onSeeAll = onSeeAll
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                if let onSeeAll {
                    Button(action: onSeeAll) {
                        HStack(spacing: 2) {
                            Text("See all")
                                .scaledFont(size: 13, weight: .semibold)
                            Image(systemName: "arrow.right")
                                .scaledFont(size: 11, weight: .bold)
                        }
                        .foregroundStyle(accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            content()
                .padding(.vertical, 6)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 14))
    }
}

private struct NewEpisodesSection: View {
    let sectionTitle: String
    let episodes: [Episode]
    let onSeeAll: () -> Void
    let onOpen: (Episode) -> Void

    var body: some View {
        SectionGlassCard(title: sectionTitle, highlighted: true, onSeeAll: onSeeAll) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(episodes) { ep in
                        EpisodeThumbCard(episode: ep, onTap: { onOpen(ep) })
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }
}

private struct ContinueWatchingSection: View {
    let episodes: [Episode]
    let onSeeAll: () -> Void
    let onOpen: (Episode) -> Void

    var body: some View {
        SectionGlassCard(title: "Continue Watching", onSeeAll: onSeeAll) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(episodes) { ep in
                        EpisodeThumbCard(episode: ep, onTap: { onOpen(ep) })
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }
}

private struct BingeReadySection: View {
    let sectionTitle: String
    let tag: String
    let shows: [PosterShow]
    let onSeeAll: () -> Void
    let onOpen: (PosterShow) -> Void

    var body: some View {
        SectionGlassCard(title: sectionTitle, onSeeAll: onSeeAll) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(shows) { show in
                        PosterCard(show: show, tag: tag, onTap: { onOpen(show) })
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }
}

// MARK: - Top Picks (Section 2)

private struct TopPicksSection: View {
    let shows: [PosterShow]
    let onSeeAll: (() -> Void)?
    let onOpen: (PosterShow) -> Void

    var body: some View {
        SectionGlassCard(
            title: "Top Picks for You",
            accentColor: Color.blue,
            onSeeAll: onSeeAll
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(shows) { show in
                        Button {
                            onOpen(show)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(
                                            LinearGradient(
                                                colors: show.posterColors,
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 110, height: 155)
                                    RemoteImage(
                                        urlString: show.posterUrl,
                                        contentMode: .fill,
                                        fallbackColors: show.posterColors
                                    )
                                    .frame(width: 110, height: 155)
                                    .clipShape(.rect(cornerRadius: 10))
                                    .allowsHitTesting(false)
                                }
                                .overlay(alignment: .bottomTrailing) {
                                    if show.meta.contains("%") {
                                        Text(show.meta)
                                            .scaledFont(size: 8, weight: .bold)
                                            .foregroundStyle(Color.white)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 3)
                                            .background(
                                                RoundedRectangle(cornerRadius: 5)
                                                    .fill(Color(red: 0.10, green: 0.44, blue: 0.91).opacity(0.88))
                                            )
                                            .padding(5)
                                            .allowsHitTesting(false)
                                    }
                                }
                                .overlay(alignment: .bottomLeading) {
                                    if !show.meta.contains("%"),
                                       let plat = Platform.from(providerName: show.meta) {
                                        NetworkBadge(platform: plat)
                                            .padding(5)
                                            .allowsHitTesting(false)
                                    }
                                }
                                .clipShape(.rect(cornerRadius: 10))

                                Text(show.title)
                                    .scaledFont(size: 12, weight: .semibold)
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(1)
                                    .frame(width: 110, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }
}

// MARK: - Watch List section

private struct WatchListSection: View {
    let items: [Episode]
    let isAuthenticated: Bool
    let onSeeAll: () -> Void
    let onOpen: (Episode) -> Void

    var body: some View {
        SectionGlassCard(
            title: "My Watch List",
            onSeeAll: items.isEmpty ? nil : onSeeAll
        ) {
            if items.isEmpty {
                emptyState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(items) { ep in
                            EpisodeThumbCard(episode: ep, onTap: { onOpen(ep) })
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var emptyState: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.orange.opacity(0.14))
                    .frame(width: 52, height: 52)
                Image(systemName: "bookmark.fill")
                    .scaledFont(size: 22, weight: .semibold)
                    .foregroundStyle(Color.orange)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(isAuthenticated ? "Nothing saved yet" : "Sign in to start your list")
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(.white)
                Text(isAuthenticated
                     ? "Tap the + on any show, movie, or game to save it here for tonight."
                     : "Create an account to keep your shows, movies, and games in sync across devices.")
                    .scaledFont(size: 12)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }
}

// MARK: - What's New Today section

private struct WhatsNewTodaySection: View {
    let shows: [PosterShow]
    let onSeeAll: () -> Void
    let onOpen: (PosterShow) -> Void

    var body: some View {
        SectionGlassCard(title: "What's New Today", highlighted: true, onSeeAll: onSeeAll) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(shows) { show in
                        PosterCard(show: show, tag: "NEW TODAY", onTap: { onOpen(show) })
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }
}

// MARK: - News section

/// Horizontal rail of the top news streams across every connected
/// streaming service. Uses the brand teal/green so news stands apart
/// from the orange entertainment treatment and the blue sports rail.
private struct NewsSection: View {
    let items: [NewsStream]
    let onSeeAll: () -> Void
    let onOpen: (NewsStream) -> Void

    var body: some View {
        SectionGlassCard(
            title: "News",
            highlighted: true,
            accentColor: Color.newsGreen,
            onSeeAll: onSeeAll
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { news in
                        NewsCard(news: news, onTap: { onOpen(news) })
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }
}

private struct NewsCard: View {
    let news: NewsStream
    let onTap: () -> Void

    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Color.newsGreen
                    .frame(width: 220, height: 124)
                    .overlay {
                        RemoteImage(
                            urlString: news.backdropUrl ?? news.posterUrl,
                            contentMode: .fill,
                            fallbackColors: [Color.newsGreen, Color(red: 0.04, green: 0.20, blue: 0.18)]
                        )
                        .frame(width: 220, height: 124)
                        .clipped()
                        .allowsHitTesting(false)
                    }
                    .overlay(
                        LinearGradient(
                            colors: [
                                Color.newsGreen.opacity(0.0),
                                Color.newsGreen.opacity(0.4),
                                Color(red: 0.04, green: 0.20, blue: 0.18).opacity(0.85)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .allowsHitTesting(false)
                    )
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 4) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .scaledFont(size: 8, weight: .black)
                                .symbolEffect(.variableColor.iterative.reversing, options: .repeating)
                            Text("LIVE")
                                .scaledFont(size: 8, weight: .heavy)
                                .tracking(0.6)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.newsGreen)
                        )
                        .padding(8)
                        .allowsHitTesting(false)
                    }
                    .overlay(alignment: .bottomLeading) {
                        Text(news.outlet.uppercased())
                            .scaledFont(size: 9, weight: .heavy)
                            .tracking(0.6)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.black.opacity(0.55))
                            )
                            .padding(8)
                            .allowsHitTesting(false)
                    }
                    .clipShape(.rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(news.title)
                        .scaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let provider = news.providerName, let date = news.publishedAt {
                        Text("\(provider) · \(Self.formatter.localizedString(for: date, relativeTo: Date()))")
                            .scaledFont(size: 11)
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)
                    } else if let provider = news.providerName {
                        Text(provider)
                            .scaledFont(size: 11)
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)
                    } else if let date = news.publishedAt {
                        Text(Self.formatter.localizedString(for: date, relativeTo: Date()))
                            .scaledFont(size: 11)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .frame(width: 220, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Playing on banner

/// Persistent pill shown beneath the page header while a cast session is
/// active. Tells the user which TV is currently playing their pick and
/// gives a one-tap entry into the Roku Remote app (when applicable) plus
/// a dismiss control that ends the session locally.
private struct PlayingOnBanner: View {
    let session: CastPlaybackState.ActiveSession
    let onTapRemote: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        session.deviceKind == .roku
                        ? Color(red: 0x66/255, green: 0x2D/255, blue: 0x91/255).opacity(0.55)
                        : Color.white.opacity(0.18)
                    )
                    .frame(width: 38, height: 38)
                Image(systemName: session.deviceKind == .appleTV ? "appletv" : "tv.inset.filled")
                    .scaledFont(size: 17, weight: .regular)
                    .foregroundStyle(.white)
                // Animated signal arc — mirrors the dismiss-on-success badge
                // inside the CastToTVSheet so the visual language carries
                // forward into the home banner.
                Image(systemName: "wifi")
                    .scaledFont(size: 9, weight: .bold)
                    .foregroundStyle(Color(red: 0x3D/255, green: 0xE0/255, blue: 0x6A/255))
                    .padding(3)
                    .background(Circle().fill(Color.navy))
                    .offset(x: 13, y: -11)
                    .symbolEffect(.variableColor.iterative.reversing, options: .repeating)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Playing on \(session.deviceName)")
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(session.title)
                    .scaledFont(size: 11)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if session.deviceKind == .roku {
                Button(action: onTapRemote) {
                    Image(systemName: "av.remote.fill")
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Roku Remote")
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .scaledFont(size: 12, weight: .bold)
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss cast session")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.75))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.newsGreen.opacity(0.5), Color.orange.opacity(0.5)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }
}

// MARK: - Cards

private struct EpisodeThumbCard: View {
    let episode: Episode
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Color.black
                    .frame(width: 148, height: 88)
                    .overlay {
                        LinearGradient(
                            colors: episode.posterColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .allowsHitTesting(false)
                    }
                    .overlay {
                        RemoteImage(
                            urlString: episode.posterUrl,
                            contentMode: .fill,
                            fallbackColors: episode.posterColors
                        )
                        .frame(width: 148, height: 88)
                        .clipped()
                        .allowsHitTesting(false)
                    }
                    .overlay(alignment: .center) {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 30, height: 30)
                            .overlay(
                                Image(systemName: "play.fill")
                                    .scaledFont(size: 11, weight: .bold)
                                    .foregroundStyle(.white)
                                    .offset(x: 1)
                            )
                            .allowsHitTesting(false)
                    }
                    .overlay(alignment: .bottomLeading) {
                        // Only render the platform chip when we have a real,
                        // recognised streaming service — empty / "STREAM" /
                        // "Streaming" placeholders are never shown.
                        if !episode.platform.isEmpty,
                           episode.platform.uppercased() != "STREAM",
                           episode.platform.lowercased() != "streaming" {
                            Text(episode.platform)
                                .scaledFont(size: 8, weight: .bold)
                                .tracking(0.4)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(episode.platformColor)
                                )
                                .padding(6)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if episode.isNew {
                            Text("NEW")
                                .scaledFont(size: 8, weight: .heavy)
                                .tracking(0.6)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color.orange)
                                )
                                .padding(6)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if episode.progress > 0 {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.10))
                                    Rectangle()
                                        .fill(Color.orange)
                                        .frame(width: geo.size.width * episode.progress)
                                        .shadow(color: Color.orange.opacity(0.6), radius: 4)
                                }
                            }
                            .frame(height: 4)
                            .allowsHitTesting(false)
                        }
                    }
                    .clipShape(.rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(episode.title)
                        .scaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text("\(episode.season) · \(episode.duration)")
                        .scaledFont(size: 11)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
                .frame(width: 148, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct PosterCard: View {
    let show: PosterShow
    let tag: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    Color.black
                        .frame(width: 110, height: 155)
                        .overlay {
                            LinearGradient(
                                colors: show.posterColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .allowsHitTesting(false)
                        }
                        .overlay {
                            RemoteImage(
                                urlString: show.posterUrl,
                                contentMode: .fill,
                                fallbackColors: show.posterColors
                            )
                            .frame(width: 110, height: 155)
                            .clipped()
                            .allowsHitTesting(false)
                        }
                        .overlay(alignment: .bottom) {
                            Text(tag)
                                .scaledFont(size: 8, weight: .bold)
                                .tracking(0.8)
                                .foregroundStyle(Color.orange)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(Color.orange.opacity(0.30))
                                .allowsHitTesting(false)
                        }
                        .clipShape(.rect(cornerRadius: 10))

                    if let score = show.voteAverage, score > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .scaledFont(size: 7, weight: .bold)
                                .foregroundStyle(Color(red:1, green:0.77, blue:0.24))
                            Text(String(format: "%.1f", score))
                                .scaledFont(size: 8, weight: .bold)
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.72))
                                .overlay(
                                    Capsule().stroke(
                                        Color(red:1,green:0.77,blue:0.24).opacity(0.35),
                                        lineWidth: 0.5)
                                )
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(5)
                        .allowsHitTesting(false)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(show.title)
                        .scaledFont(size: 12, weight: .semibold)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text(show.meta)
                        .scaledFont(size: 10)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
                .frame(width: 110, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Widget Promo

private struct WidgetPromoBanner: View {
    let onSetUp: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Rectangle()
                .fill(Color.orange)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 8) {
                Text("NEW")
                    .scaledFont(size: 9, weight: .heavy)
                    .tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange))

                Text("GuideStream on Your Home Screen")
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("See what's up next without opening the app")
                    .scaledFont(size: 12)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 14) {
                    Button(action: onSetUp) {
                        Text("Set Up")
                            .scaledFont(size: 12, weight: .bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.orange)
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: onDismiss) {
                        Text("Dismiss")
                            .scaledFont(size: 12, weight: .medium)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
            .padding(.vertical, 14)

            Spacer(minLength: 0)

            MiniWidgetPreview()
                .padding(.trailing, 14)
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.white.opacity(0.07)
                .background(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 14))
    }
}

private struct MiniWidgetPreview: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0xFF/255, green: 0x9A/255, blue: 0x3C/255),
                        Color(red: 0xE6/255, green: 0x72/255, blue: 0x1A/255)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 72, height: 72)
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 6, height: 6)
                    .padding(8)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 36, height: 44)
                    .blur(radius: 0.4)
            }
            .shadow(color: Color.orange.opacity(0.35), radius: 12, y: 6)
    }
}

// MARK: - Platform Row (Section 2)

private struct PlatformRow: View {
    let platformName: String
    let platformColor: Color
    let shows: [PosterShow]
    let onOpen: (PosterShow) -> Void

    var body: some View {
        SectionGlassCard(
            title: "Popular on \(platformName)",
            accentColor: platformColor
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(shows) { show in
                        PosterCard(show: show, tag: "", onTap: { onOpen(show) })
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }
}

// MARK: - Trending Ranked (Section 3)

private struct TrendingRankedSection: View {
    let shows: [PosterShow]
    let onSeeAll: (() -> Void)?
    let onOpen: (PosterShow) -> Void

    var body: some View {
        SectionGlassCard(title: "Trending This Week", onSeeAll: onSeeAll) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(shows.enumerated()), id: \.offset) { idx, show in
                        Button {
                            onOpen(show)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(
                                            LinearGradient(
                                                colors: show.posterColors,
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 110, height: 155)
                                    RemoteImage(
                                        urlString: show.posterUrl,
                                        contentMode: .fill,
                                        fallbackColors: show.posterColors
                                    )
                                    .frame(width: 110, height: 155)
                                    .clipShape(.rect(cornerRadius: 10))
                                    .allowsHitTesting(false)
                                }
                                .overlay(alignment: .topLeading) {
                                    Text("#\(idx + 1)")
                                        .scaledFont(size: 11, weight: .heavy)
                                        .foregroundStyle(Color.white.opacity(0.55))
                                        .padding(6)
                                        .allowsHitTesting(false)
                                }
                                .overlay(alignment: .bottomLeading) {
                                    if let plat = Platform.from(providerName: show.meta) {
                                        NetworkBadge(platform: plat)
                                            .padding(5)
                                            .allowsHitTesting(false)
                                    }
                                }
                                .clipShape(.rect(cornerRadius: 10))

                                Text(show.title)
                                    .scaledFont(size: 12, weight: .semibold)
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(1)
                                    .frame(width: 110, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }
}

// MARK: - Genre Discovery (Section 4)

private struct GenreDiscoverySection: View {
    let highlighted: Bool
    let onSelectGenre: (Int, String, String) -> Void

    /// Genre data: (id, name, icon, color, mediaType).
    /// "movie" is used for Romance (10749 is a movie-only TMDB genre).
    /// "international" triggers a foreign-language TV discovery call.
    private let genres: [(Int, String, String, Color, String)] = [
        (80, "Crime & Thriller", "flame", Color(red:0.86,green:0.15,blue:0.15), "tv"),
        (10765, "Sci-Fi", "sparkles", Color(red:0.55,green:0.36,blue:0.96), "tv"),
        (35, "Comedy", "face.smiling", Color(red:0.13,green:0.77,blue:0.42), "tv"),
        (18, "Drama", "theatermasks", Color(red:0.92,green:0.62,blue:0.12), "tv"),
        (10759, "Action", "bolt", Color(red:0.96,green:0.38,blue:0.15), "tv"),
        (99, "Documentary", "video", Color(red:0.10,green:0.60,blue:0.88), "tv"),
        (10749, "Romance", "heart.fill", Color(red:0.98,green:0.28,blue:0.52), "movie"),
        (10769, "International", "globe", Color(red:0.18,green:0.65,blue:0.55), "international")
    ]

    var body: some View {
        SectionGlassCard(
            title: "Browse by genre",
            highlighted: highlighted
        ) {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                ForEach(genres, id: \.0) { id, name, icon, color, mediaType in
                    Button {
                        onSelectGenre(id, name, mediaType)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Image(systemName: icon)
                                .scaledFont(size: 20, weight: .semibold)
                                .foregroundStyle(color)
                            Text(name)
                                .scaledFont(size: 11, weight: .bold)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(color.opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(color.opacity(0.25), lineWidth: 0.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }
}

// MARK: - Because You Watch (Section 5)

private struct BecauseYouWatchSection: View {
    let genreName: String
    let shows: [PosterShow]
    let highlighted: Bool
    let onOpen: (PosterShow) -> Void

    var body: some View {
        SectionGlassCard(
            title: "Because you watch \(genreName)",
            highlighted: highlighted,
            accentColor: Color.orange
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(shows) { show in
                        PosterCard(show: show, tag: "", onTap: { onOpen(show) })
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }
}

// MARK: - Top Rated (Section 6)

private struct TopRatedSection: View {
    let shows: [PosterShow]
    let onOpen: (PosterShow) -> Void

    var body: some View {
        SectionGlassCard(
            title: "Top rated right now",
            accentColor: Color(red:1,green:0.77,blue:0.24)
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(shows) { show in
                        PosterCard(show: show, tag: "", onTap: { onOpen(show) })
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }
}

// MARK: - Leaving Soon (Section 7)

private struct LeavingSoonSection: View {
    let shows: [PosterShow]
    let onSeeAll: (() -> Void)?
    let onOpen: (PosterShow) -> Void

    /// Extracts the platform color from a show's meta field (formatted as "N days left · PLATFORM").
    private func platformColor(for show: PosterShow) -> Color {
        let parts = show.meta.split(separator: "·")
        guard parts.count >= 2 else { return Color.orange }
        let name = String(parts[1]).trimmingCharacters(in: .whitespaces)
        return Platform.from(providerName: name)?.color ?? Color.orange
    }

    /// Extracts just the days-left portion (e.g. "5 days left") from the meta field.
    private func daysLeftText(for show: PosterShow) -> String {
        let parts = show.meta.split(separator: "·")
        guard let first = parts.first else { return show.meta }
        return String(first).trimmingCharacters(in: .whitespaces)
    }

    /// Extracts just the platform name from the meta field.
    private func platformName(for show: PosterShow) -> String {
        let parts = show.meta.split(separator: "·")
        guard parts.count >= 2 else { return "" }
        return String(parts[1]).trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        SectionGlassCard(
            title: "Leaving Soon",
            highlighted: true,
            accentColor: Color.orange,
            onSeeAll: onSeeAll
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(shows) { show in
                        let pColor = platformColor(for: show)
                        Button {
                            onOpen(show)
                        } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                ZStack {
                                    RemoteImage(
                                        urlString: show.posterUrl,
                                        contentMode: .fill,
                                        fallbackColors: show.posterColors
                                    )
                                    .frame(width: 130, height: 80)
                                    .clipped()
                                    .allowsHitTesting(false)
                                }
                                .frame(width: 130, height: 80)
                                .overlay(alignment: .topLeading) {
                                    Text(daysLeftText(for: show))
                                        .scaledFont(size: 9, weight: .bold)
                                        .foregroundStyle(pColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(
                                            RoundedRectangle(cornerRadius: 5)
                                                .fill(Color.black.opacity(0.65))
                                        )
                                        .padding(5)
                                        .allowsHitTesting(false)
                                }
                                .clipShape(.rect(cornerRadius: 10))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(show.title)
                                        .scaledFont(size: 11, weight: .semibold)
                                        .foregroundStyle(Color.textPrimary)
                                        .lineLimit(2)
                                    Text(platformName(for: show))
                                        .scaledFont(size: 9)
                                        .foregroundStyle(pColor.opacity(0.85))
                                        .lineLimit(1)
                                }
                                .padding(8)
                            }
                            .frame(width: 130)
                            .background(Color.white.opacity(0.05))
                            .background(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(pColor.opacity(0.35), lineWidth: 1)
                            )
                            .clipShape(.rect(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }
}

// MARK: - New Seasons (Section 8)

private struct NewSeasonsSection: View {
    let results: [TMDBResult]
    let providerByTmdb: [Int: Platform]
    let streams: StreamsViewModel
    let onOpen: (PosterShow) -> Void

    var body: some View {
        SectionGlassCard(
            title: "New seasons — shows you follow",
            highlighted: true,
            accentColor: Color.orange
        ) {
            VStack(spacing: 0) {
                ForEach(results) { r in
                    let plat = providerByTmdb[r.id]
                    Button {
                        onOpen(PosterShow(
                            title: r.displayName,
                            meta: r.year.map { "\($0)" } ?? "Series",
                            posterColors: HomeFallback.posterColors,
                            symbol: "play.tv.fill",
                            posterUrl: r.posterUrl,
                            tmdbId: r.id,
                            voteAverage: r.voteAverage
                        ))
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(plat?.color ?? Color.orange)
                                    .frame(width: 52, height: 52)
                                if let url = r.posterUrl {
                                    RemoteImage(
                                        urlString: url,
                                        contentMode: .fill,
                                        fallbackColors: HomeFallback.posterColors
                                    )
                                    .frame(width: 52, height: 52)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(r.displayName)
                                    .scaledFont(size: 13, weight: .bold)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                if let plat {
                                    Text(plat.name)
                                        .scaledFont(size: 10)
                                        .foregroundStyle(Color.white.opacity(0.45))
                                }
                                HStack(spacing: 5) {
                                    if let score = r.voteAverage, score > 0 {
                                        HStack(spacing: 2) {
                                            Image(systemName: "star.fill")
                                                .scaledFont(size: 8)
                                                .foregroundStyle(Color(red:1,green:0.77,blue:0.24))
                                            Text(String(format:"%.1f",score))
                                                .scaledFont(size: 9, weight: .bold)
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    Text("New season")
                                        .scaledFont(size: 9, weight: .semibold)
                                        .foregroundStyle(Color.orange)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(Color.orange.opacity(0.15))
                                        )
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "play.fill")
                                .scaledFont(size: 13, weight: .bold)
                                .foregroundStyle(Color.orange)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    if r.id != results.last?.id {
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 0.5)
                            .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Badges

private struct NetworkBadge: View {
    let platform: Platform
    var body: some View {
        Text(platform.name)
            .scaledFont(size: 8, weight: .bold)
            .tracking(0.6)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(platform.color)
            )
    }
}

private struct NewChip: View {
    var body: some View {
        Text("NEW")
            .scaledFont(size: 8.5, weight: .heavy)
            .tracking(0.6)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.orange)
            )
    }
}

// MARK: - Upcoming Episodes (TVDB)

/// Horizontal scrolling row of next-upcoming episodes from TheTVDB.
/// Each card shows the show poster, episode code, episode name, and air date.
private struct UpcomingEpisodesRow: View {
    let items: [TVDBUpcomingItem]
    let onOpen: (TVDBUpcomingItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(Color.orange)
                Text("Upcoming Episodes")
                    .scaledFont(size: 17, weight: .semibold)
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        Button { onOpen(item) } label: {
                            UpcomingEpisodeCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Upcoming Episode Card

private struct UpcomingEpisodeCard: View {
    let item: TVDBUpcomingItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Poster thumbnail
            ZStack(alignment: .bottomLeading) {
                if let url = item.posterUrl {
                    RemoteImage(
                        urlString: url,
                        contentMode: .fill,
                        fallbackColors: item.platform.map { [$0.color, $0.color.opacity(0.7)] } ?? HomeFallback.posterColors
                    )
                    .frame(width: 148, height: 88)
                    .clipShape(.rect(cornerRadius: 10))
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: item.platform.map { [$0.color, $0.color.opacity(0.7)] } ?? HomeFallback.posterColors,
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 148, height: 88)
                }

                // Platform badge
                if let platform = item.platform {
                    Text(platform.name)
                        .scaledFont(size: 8, weight: .heavy)
                        .tracking(0.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(platform.color.opacity(0.85))
                        )
                        .padding(6)
                }
            }

            // Show title
            Text(item.showTitle)
                .scaledFont(size: 11, weight: .semibold)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)

            // Episode code + name
            if let season = item.seasonNumber, let episode = item.episodeNumber {
                HStack(spacing: 4) {
                    Text("S\(season) E\(episode)")
                        .scaledFont(size: 13, weight: .bold)
                        .foregroundStyle(.white)
                    if let name = item.episodeName {
                        Text("•")
                            .scaledFont(size: 13)
                            .foregroundStyle(Color.textTertiary)
                        Text(name)
                            .scaledFont(size: 13, weight: .medium)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
            }

            // Air date
            if let date = item.airDate {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .scaledFont(size: 10, weight: .medium)
                        .foregroundStyle(Color.orange)
                    Text(airDateFormatter.string(from: date))
                        .scaledFont(size: 11, weight: .medium)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .frame(width: 148, alignment: .leading)
    }

    private var airDateFormatter: DateFormatter {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt
    }
}

// MARK: - Popular on Service section

private struct PopularOnServiceSection: View {
    let serviceName: String
    let accentColor: Color
    let shows: [PosterShow]
    let onOpen: (PosterShow) -> Void

    var body: some View {
        SectionGlassCard(
            title: "Popular on \(serviceName)",
            highlighted: false,
            accentColor: accentColor,
            onSeeAll: nil
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(shows) { show in
                        PosterCard(show: show, tag: "", onTap: { onOpen(show) })
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }
}

// MARK: - Coming to Streaming

private struct ComingToStreamingSection: View {
    let items: [ComingToStreamingItem]
    let onOpen: (ComingToStreamingItem) -> Void

    var body: some View {
        SectionGlassCard(title: "Coming to Streaming", highlighted: true, onSeeAll: nil) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(items) { item in
                        ComingSoonPosterCard(item: item, onTap: { onOpen(item) })
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }
}

private struct ComingSoonPosterCard: View {
    let item: ComingToStreamingItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    Color.black
                        .frame(width: 150, height: 225)
                        .overlay {
                            LinearGradient(
                                colors: item.show.posterColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .allowsHitTesting(false)
                        }
                        .overlay {
                            RemoteImage(
                                urlString: item.show.posterUrl,
                                contentMode: .fill,
                                fallbackColors: item.show.posterColors
                            )
                            .frame(width: 150, height: 225)
                            .clipped()
                            .allowsHitTesting(false)
                        }
                        .overlay(alignment: .bottom) {
                            badgeLabel
                        }
                        .clipShape(.rect(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.show.title)
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text(item.show.meta)
                        .scaledFont(size: 11)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
                .frame(width: 150, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var badgeLabel: some View {
        if item.isDated {
            Text(item.badgeText)
                .scaledFont(size: 11, weight: .bold)
                .foregroundStyle(Color.navy)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.orange)
                .allowsHitTesting(false)
        } else {
            Text(item.badgeText)
                .scaledFont(size: 11, weight: .medium)
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
                .allowsHitTesting(false)
        }
    }
}

#Preview {
    ZStack {
        Color.navy.ignoresSafeArea()
        HomeView()
    }
    .preferredColorScheme(.dark)
}

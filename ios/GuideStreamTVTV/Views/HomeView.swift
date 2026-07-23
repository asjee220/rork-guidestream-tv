//
//  HomeView.swift
//  GuideStreamTV
//

import SwiftUI
import UIKit
import UserNotifications

// MARK: - Home Models

struct Platform {
    let name: String
    let color: Color
    var textColor: Color
    var catalogId: String?
    var displayName: String

    init(name: String, color: Color, textColor: Color = .white, catalogId: String? = nil, displayName: String? = nil) {
        self.name = name
        self.color = color
        self.textColor = textColor
        self.catalogId = catalogId
        self.displayName = displayName ?? name
    }

    // MARK: - Legacy pins (12 tvOS catalogue entries, exact label + colour)

    static let netflix     = Platform(name: "NETFLIX",     color: Color(red: 0xE5/255, green: 0x09/255, blue: 0x14/255), catalogId: "netflix",     displayName: "Netflix")
    static let hbo         = Platform(name: "HBO",         color: Color(red: 0x5A/255, green: 0x1F/255, blue: 0xCB/255), catalogId: "max",         displayName: "Max")
    static let appleTV     = Platform(name: "Apple TV+",   color: Color(red: 0x10/255, green: 0x10/255, blue: 0x10/255), catalogId: "appletv",     displayName: "Apple TV+")
    static let hulu        = Platform(name: "HULU",        color: Color(red: 0x1C/255, green: 0xE7/255, blue: 0x83/255), catalogId: "hulu",        displayName: "Hulu")
    static let prime       = Platform(name: "PRIME",       color: Color(red: 0x00/255, green: 0xA8/255, blue: 0xE1/255), catalogId: "prime",       displayName: "Prime Video")
    static let disney      = Platform(name: "DISNEY+",     color: Color(red: 0x11/255, green: 0x3C/255, blue: 0xCF/255), catalogId: "disney",      displayName: "Disney+")
    static let paramount   = Platform(name: "PARAMOUNT+", color: Color(red: 0x00/255, green: 0x64/255, blue: 0xFF/255), catalogId: "paramount",   displayName: "Paramount+")
    static let peacock     = Platform(name: "PEACOCK",     color: Color(red: 0x00/255, green: 0x00/255, blue: 0x00/255), catalogId: "peacock",     displayName: "Peacock")
    static let starz       = Platform(name: "STARZ",       color: Color(red: 0x00/255, green: 0x00/255, blue: 0x00/255), catalogId: "starz",       displayName: "Starz")
    static let showtime    = Platform(name: "SHOWTIME",    color: Color(red: 0xD8/255, green: 0x00/255, blue: 0x00/255), catalogId: "showtime",    displayName: "Showtime")
    static let crunchyroll = Platform(name: "CRUNCHYROLL", color: Color(red: 0xF4/255, green: 0x7B/255, blue: 0x20/255), catalogId: "crunchyroll", displayName: "Crunchyroll")
    static let youtube     = Platform(name: "YOUTUBE",     color: Color(red: 0xFF/255, green: 0x00/255, blue: 0x00/255), catalogId: "youtube",     displayName: "YouTube")

    // MARK: - hbo / max equivalence

    /// The server brand map uses the iPhone namespace where HBO is `hbo`,
    /// while the tvOS StreamingCatalog uses `max`. This normalises both
    /// directions so resolved catalog ids always match tvOS service ids.
    static func normalizeCatalogId(_ id: String) -> String {
        id == "hbo" ? "max" : id
    }

    // MARK: - Normalisation

    /// Lowercase, strip channel suffixes, strip leading "the", replace
    /// standalone "plus" with "+", then remove every character that is
    /// not a lowercase letter or digit.
    private static func normalise(_ raw: String) -> String {
        var s = raw.lowercased()
        let suffixes = ["amazon channel", "apple tv channel", "roku premium channel"]
        for suffix in suffixes where s.hasSuffix(suffix) {
            s = String(s.dropLast(suffix.count))
            break
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("the ") { s = String(s.dropFirst(4)) }
        s = s.split(separator: " ").map { $0 == "plus" ? "+" : String($0) }.joined(separator: " ")
        return s.filter { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") }
    }

    // MARK: - Text colour from luminance

    private static func textColor(for bg: Color) -> Color {
        let ui = UIColor(bg)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let lum = 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)
        return lum > 0.6
            ? Color(red: Double(r) * 0.15, green: Double(g) * 0.15, blue: Double(b) * 0.15)
            : .white
    }

    // MARK: - Hex colour parsing

    /// Parses a 6-digit hex string (no leading #) into a Color, or nil.
    private static func colorFromHex(_ hex: String) -> Color? {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    // MARK: - Legacy lookup by catalog id

    private static func legacyByCatalogId(_ id: String) -> Platform? {
        switch id {
        case "netflix":     return .netflix
        case "max":         return .hbo
        case "appletv":     return .appleTV
        case "hulu":        return .hulu
        case "prime":       return .prime
        case "disney":      return .disney
        case "paramount":   return .paramount
        case "peacock":     return .peacock
        case "starz":       return .starz
        case "showtime":    return .showtime
        case "crunchyroll": return .crunchyroll
        case "youtube":     return .youtube
        default:            return nil
        }
    }

    // MARK: - Local fallback (12 tvOS catalogue entries)

    private static func localFallback(for normalised: String) -> Platform? {
        for service in StreamingCatalog.all {
            if normalise(service.name) == normalised {
                return legacyByCatalogId(service.id)
            }
        }
        return nil
    }

    // MARK: - Resolution: provider id (primary)

    /// Looks up a TMDB provider id in the server brand map. Returns a
    /// Platform only when the row carries a non-null catalog_id. Returns
    /// nil otherwise so callers hide the item rather than label it
    /// generically.
    static func from(providerId: Int) -> Platform? {
        guard providerId > 0 else { return nil }
        guard let row = TVProviderBrandMapService.shared.rows.first(where: { $0.tmdbProviderId == providerId }) else { return nil }
        guard let catalogId = row.catalogId else { return nil }
        let normalized = normalizeCatalogId(catalogId)
        if let legacy = legacyByCatalogId(normalized) { return legacy }
        // Prefer badge_hex and badge_label from the server map.
        if let hex = row.badgeHex, let color = colorFromHex(hex),
           let label = row.badgeLabel, !label.isEmpty {
            return Platform(
                name: label.uppercased(),
                color: color,
                textColor: textColor(for: color),
                catalogId: normalized,
                displayName: label
            )
        }
        // Fall back to local catalogue entry if one exists.
        if let legacy = localFallback(for: normalized) { return legacy }
        // Null or missing badge fields — hide the item.
        return nil
    }

    // MARK: - Resolution: provider name (fallback)

    /// Maps a TMDB watch-provider name to a branded Platform. Returns nil
    /// if we don't recognise the provider, so callers can hide items
    /// rather than label them generically. Resolution order: server map
    /// by alias, then local fallback, then nil. No substring or contains
    /// fallback at any stage — that is precisely the defect being removed.
    static func from(providerName raw: String?) -> Platform? {
        guard let raw, !raw.isEmpty else { return nil }
        let normalised = normalise(raw)

        // 1. Server map by alias
        for row in TVProviderBrandMapService.shared.rows {
            for alias in row.aliases {
                if normalise(alias) == normalised {
                    guard let catalogId = row.catalogId else { return nil }
                    let normalized = normalizeCatalogId(catalogId)
                    if let legacy = legacyByCatalogId(normalized) { return legacy }
                    // Prefer badge_hex and badge_label from the server map.
                    if let hex = row.badgeHex, let color = colorFromHex(hex),
                       let label = row.badgeLabel, !label.isEmpty {
                        return Platform(
                            name: label.uppercased(),
                            color: color,
                            textColor: textColor(for: color),
                            catalogId: normalized,
                            displayName: label
                        )
                    }
                    // Fall back to local catalogue entry if one exists.
                    if let legacy = localFallback(for: normalized) { return legacy }
                    return nil
                }
            }
        }

        // 2. Local fallback (12 tvOS catalogue entries)
        return localFallback(for: normalised)
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
}

/// Default gradient colors used as a tasteful fallback while TMDB images load or when they fail.
enum HomeFallback {
    static let posterColors: [Color] = [
        Color(red: 0.20, green: 0.15, blue: 0.45),
        Color(red: 0.04, green: 0.02, blue: 0.10)
    ]
}

// MARK: - HomeView

struct HomeView: View {
    var onOpenAgent: () -> Void = {}

    @State private var widgetBannerDismissed: Bool = false
    @State private var path: [HomeRoute] = []
    @State private var detailSubject: DetailSubject?
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
    @State private var selectedGame: SportsGame?
    /// Cached top US streaming provider per TMDB id. Items without an entry have no real
    /// streaming service and are filtered out of the UI.
    @State private var providerByTmdb: [Int: Platform] = [:]

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        Color.clear.frame(height: 56)
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
                            sectionTitle: (streams.userStreams.isEmpty && !trending.isEmpty) ? "Everyone's Watching" : "New Episodes",
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

                        Color.clear.frame(height: 96)
                    }
                    .padding(.top, 4)
                }
                .tracksTabBarVisibility()

                VStack(spacing: 0) {
                    PageBar(
                        selectedServiceIds: orderedSelectedServiceIds,
                        onServicesPill: { showServicesSheet = true }
                    )
                    if let session = castPlayback.current {
                        PlayingOnBanner(
                            session: session,
                            onTapRemote: {
                                if session.deviceKind == .roku {
                                    castPlayback.openRokuRemote()
                                }
                            },
                            onDismiss: {
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
                .animation(.spring(response: 0.4, dampingFraction: 0.82), value: castPlayback.current?.id)
            }
            .background(Color.navy.ignoresSafeArea())
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
                case .widgetSetup:
                    WidgetSetupView()
                }
            }
            #if os(tvOS)
            .fullScreenCover(item: $detailSubject) { subject in
                EpisodeDetailSheet(subject: subject)
            }
            .fullScreenCover(item: $selectedGame) { game in
                SportsWatchSheet(game: game)
            }
            .fullScreenCover(isPresented: $showServicesSheet) {
                ServicesBottomSheet()
            }
            .fullScreenCover(isPresented: $showWatchListSheet) {
                WatchListBottomSheet()
            }
            #else
            .sheet(item: $detailSubject) { subject in
                EpisodeDetailSheet(subject: subject)
            }
            .sheet(item: $selectedGame) { game in
                SportsWatchSheet(game: game)
            }
            .sheet(isPresented: $showServicesSheet) {
                ServicesBottomSheet()
            }
            .sheet(isPresented: $showWatchListSheet) {
                WatchListBottomSheet()
            }
            #endif
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(Color.orange)
        .task {
            await clearBadgeAndMarkSeen()
            await streams.refreshAll()
            await loadTrendingIfNeeded()
        }
        .refreshable {
            await streams.refreshAll()
            await loadTrendingIfNeeded()
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
        // Refresh the provider brand map from the server (fire-and-forget;
        // cached rows from UserDefaults are already loaded at init).
        Task { await TVProviderBrandMapService.shared.refresh() }
        async let trendingCall = try? TMDBService.shared.getTrending()
        async let onAirCall = try? TMDBService.shared.getOnTheAir()
        async let endedCall = try? TMDBService.shared.getDiscoverEnded()
        async let newTodayCall = try? TMDBService.shared.getNewToday()
        async let sportsCall = SportsService.shared.fetchAll()
        let (t, a, e, n, s) = await (trendingCall, onAirCall, endedCall, newTodayCall, sportsCall)
        if let t { trending = t }
        if let a { onAir = a }
        if let e { bingeFallback = e }
        if let n { newToday = n }
        sportsGames = s
        await hydrateProviders()
    }

    /// Look up the top US streaming provider for every loaded TMDB result in parallel.
    /// Items with no recognised streaming service are intentionally left out of the dictionary
    /// so the rendering layer can hide them.
    private func hydrateProviders() async {
        let combined: [TMDBResult] = trending + onAir + bingeFallback + newToday
        let unique = Array(Dictionary(grouping: combined, by: { $0.id }).compactMapValues { $0.first }.values)
        let toFetch = unique.filter { providerByTmdb[$0.id] == nil }
        guard !toFetch.isEmpty else { return }

        let resolved: [(Int, Platform)] = await withTaskGroup(of: (Int, Platform)?.self) { group in
            for r in toFetch {
                group.addTask {
                    let provider = try? await TMDBService.shared.getTopWatchProvider(tmdbId: r.id, isTV: r.isTV)
                    guard let provider, let platform = Platform.from(providerId: provider.providerId) ?? Platform.from(providerName: provider.providerName) else {
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

    private func mediaAsPoster(_ r: TMDBResult, platform: Platform?) -> PosterShow {
        let colors: [Color] = platform.map { [$0.color, $0.color.opacity(0.7)] } ?? HomeFallback.posterColors
        return PosterShow(
            title: r.displayName,
            meta: r.year.map { "\($0)" } ?? (r.isTV ? "Series" : "Movie"),
            posterColors: colors,
            symbol: "play.tv.fill",
            posterUrl: r.posterUrl,
            tmdbId: r.id
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
                    tmdbId: r.id
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
                    tmdbId: r.id
                )
            }
    }

    /// Episode cards built from the user's saved watch list. Falls back to a
    /// neutral platform when the saved row didn't capture one.
    var watchListEpisodes: [Episode] {
        streams.userStreams.map { row in
            let platformName = (row.platform ?? "").uppercased()
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
            default: platform = Platform(name: platformName.isEmpty ? "STREAM" : platformName, color: Color.orange)
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
        return streams.newEpisodes.map { row in
            let platformName = (row.platform ?? "").uppercased()
            let platform: Platform
            switch platformName {
            case "NETFLIX": platform = .netflix
            case "HBO", "HBO MAX", "MAX": platform = .hbo
            case "APPLE TV+", "APPLETV", "APPLE": platform = .appleTV
            case "HULU": platform = .hulu
            case "PRIME", "AMAZON", "AMAZON PRIME": platform = .prime
            case "DISNEY+", "DISNEY": platform = .disney
            default: platform = Platform(name: platformName.isEmpty ? "STREAM" : platformName, color: Color.blue)
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
}

// MARK: - PageBar

private struct PageBar: View {
    let selectedServiceIds: [String]
    let onServicesPill: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Guide")
                    .scaledFont(size: 22, weight: .semibold, design: .default)
                    .foregroundStyle(Color.textPrimary)
                Text("Stream")
                    .scaledFont(size: 22, weight: .semibold, design: .default)
                    .foregroundStyle(Color.orange)
                Text(" TV")
                    .scaledFont(size: 16, weight: .regular, design: .default)
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            Spacer()
            if !selectedServiceIds.isEmpty {
                ServicesPill(serviceIds: selectedServiceIds, onTap: onServicesPill)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(
            Color.navy.opacity(0.92)
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .top)
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)
        }
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
        .background(
            Color.white.opacity(0.07)
                .background(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(highlighted ? accentColor.opacity(0.30) : Color.white.opacity(0.10), lineWidth: 1)
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
    let onOpen: (Episode) -> Void

    var body: some View {
        SectionGlassCard(title: "Continue Watching", onSeeAll: {}) {
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
                    .clipShape(.rect(cornerRadius: 10))

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

// MARK: - Badges

private struct NetworkBadge: View {
    let platform: Platform
    var body: some View {
        Text(platform.name.count > 12 ? String(platform.name.prefix(12)) : platform.name)
            .scaledFont(size: 8, weight: .bold)
            .tracking(0.6)
            .foregroundStyle(platform.textColor)
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

#Preview {
    ZStack {
        Color.navy.ignoresSafeArea()
        HomeView()
    }
    .preferredColorScheme(.dark)
}

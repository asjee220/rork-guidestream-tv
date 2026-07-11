//
//  HomeDestinations.swift
//  GuideStreamTV
//

import SwiftUI

enum HomeRoute: Hashable {
    case newEpisodes
    case bingeWorthy
    case whatsNewToday
    case news
    case widgetSetup
    case continueWatching
    case topPicks
    case trending
    case leavingSoon
    case popularOnServiceCategories(serviceId: String, providerId: Int)
}

// MARK: - Popular on Service — category browse

/// Full-screen category browser reached via the "See all" link on each
/// "Popular on {service}" home rail. A single horizontally-scrolling pill
/// row (All + genre tabs) pinned above a two-column poster grid. Each
/// category loads lazily and is cached; the All tab combines TV + movies
/// and is seeded from the rail's already-built posters so it never blanks.
struct PopularOnServiceCategoriesView: View {
    let serviceId: String
    let providerId: Int
    let initialShows: [PosterShow]
    var onSelect: (PosterShow) -> Void

    /// One selectable category. `all` combines TV + movies; `.genre`
    /// carries the TMDB genre id + media type; `.international` uses the
    /// original-language discover method.
    private struct CategoryTab: Identifiable, Hashable {
        let id: String
        let name: String
        let kind: Kind

        enum Kind: Hashable {
            case all
            case genre(Int, String)
            case international
        }
    }

    private let categories: [CategoryTab] = [
        CategoryTab(id: "all", name: "All", kind: .all),
        CategoryTab(id: "crime", name: "Crime & Thriller", kind: .genre(80, "tv")),
        CategoryTab(id: "scifi", name: "Sci-Fi", kind: .genre(10765, "tv")),
        CategoryTab(id: "comedy", name: "Comedy", kind: .genre(35, "tv")),
        CategoryTab(id: "drama", name: "Drama", kind: .genre(18, "tv")),
        CategoryTab(id: "action", name: "Action", kind: .genre(10759, "tv")),
        CategoryTab(id: "documentary", name: "Documentary", kind: .genre(99, "tv")),
        CategoryTab(id: "romance", name: "Romance", kind: .genre(10749, "movie")),
        CategoryTab(id: "international", name: "International", kind: .international)
    ]

    @State private var selectedCategory: String = "all"
    @State private var resultsByCategory: [String: [PosterShow]] = [:]
    @State private var loadingCategories: Set<String> = []
    @State private var didSeedAll = false

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    private var service: StreamingService? { StreamingCatalog.service(for: serviceId) }
    private var serviceName: String { service?.name ?? "Streaming" }
    private var glow: Color { service?.glow ?? Color(red: 0.42, green: 0.45, blue: 0.55) }
    private var bg: Color { service?.bg ?? Color(red: 0.08, green: 0.10, blue: 0.16) }

    private var currentShows: [PosterShow] { resultsByCategory[selectedCategory] ?? [] }
    private var currentIsLoading: Bool { loadingCategories.contains(selectedCategory) }

    /// Grid tag: POPULAR for the All tab, the uppercased category name otherwise.
    private var currentTag: String {
        if selectedCategory == "all" { return "POPULAR" }
        return (categories.first { $0.id == selectedCategory }?.name ?? "").uppercased()
    }

    var body: some View {
        VStack(spacing: 0) {
            pillRow
                .padding(.top, 10)
                .padding(.bottom, 6)

            contentRegion
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(BrandBackground())
        .navigationTitle("Popular on \(serviceName)")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.navy, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await seedAndLoadAll() }
        .onChange(of: selectedCategory) { _, newValue in
            guard newValue != "all", resultsByCategory[newValue] == nil,
                  let cat = categories.first(where: { $0.id == newValue })
            else { return }
            Task { await loadCategory(cat) }
        }
    }

    // MARK: - Pill row

    private var pillRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories) { cat in
                    let isSelected = cat.id == selectedCategory
                    Button {
                        selectedCategory = cat.id
                    } label: {
                        Text(cat.name)
                            .scaledFont(size: 13, weight: .semibold)
                            .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.85))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(isSelected ? glow : Color.white.opacity(0.10))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
        .overlay(alignment: .trailing) {
            LinearGradient(
                colors: [Color.navy.opacity(0), Color.navy],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 44)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentRegion: some View {
        if currentShows.isEmpty && currentIsLoading {
            VStack {
                Spacer()
                ProgressView().tint(.white)
                Spacer()
            }
        } else if currentShows.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "tray")
                    .scaledFont(size: 34, weight: .regular)
                    .foregroundStyle(Color.white.opacity(0.35))
                Text("Nothing here yet")
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(Color.white.opacity(0.55))
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(currentShows) { show in
                        Button(action: { select(show) }) {
                            BingeGridCard(show: show, tag: currentTag)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 120)
            }
        }
    }

    // MARK: - Actions

    private func select(_ show: PosterShow) {
        WatchIntentLogger.shared.log(
            eventType: .cardTapped,
            titleId: WatchIntentLogger.titleSlug(show.title),
            metadata: ["section": "popular_on_\(serviceId)_category_\(selectedCategory)"]
        )
        onSelect(show)
    }

    // MARK: - Loading

    private func poster(from r: TMDBResult) -> PosterShow {
        PosterShow(
            title: r.displayName,
            meta: r.year.map { "\($0)" } ?? (r.isTV ? "Series" : "Movie"),
            posterColors: [glow.opacity(0.85), bg],
            symbol: "play.fill",
            posterUrl: r.posterUrl,
            tmdbId: r.id,
            isTV: r.isTV
        )
    }

    /// Seeds the All tab from the rail posters, then replaces it with the
    /// full combined TV + movie list. Never blocks: the seed shows instantly.
    private func seedAndLoadAll() async {
        if !didSeedAll {
            didSeedAll = true
            if resultsByCategory["all"] == nil {
                resultsByCategory["all"] = Array(initialShows.prefix(25))
            }
        }
        loadingCategories.insert("all")
        async let tvCall = (try? await TMDBService.shared.getPopularOnService(tmdbProviderId: providerId)) ?? []
        async let movieCall = (try? await TMDBService.shared.getPopularMoviesOnService(tmdbProviderId: providerId)) ?? []
        let (tv, movies) = await (tvCall, movieCall)
        var interleaved: [TMDBResult] = []
        let maxCount = max(tv.count, movies.count)
        for i in 0..<maxCount {
            if i < tv.count { interleaved.append(tv[i]) }
            if i < movies.count { interleaved.append(movies[i]) }
        }
        var merged: [PosterShow] = []
        var seen = Set<Int>()
        for r in interleaved where seen.insert(r.id).inserted {
            merged.append(poster(from: r))
            if merged.count >= 25 { break }
        }
        if !merged.isEmpty {
            resultsByCategory["all"] = merged
        }
        loadingCategories.remove("all")
    }

    private func loadCategory(_ cat: CategoryTab) async {
        guard resultsByCategory[cat.id] == nil, !loadingCategories.contains(cat.id) else { return }
        loadingCategories.insert(cat.id)
        let results: [TMDBResult]
        switch cat.kind {
        case .all:
            results = []
        case .genre(let genreId, let mediaType):
            results = (try? await TMDBService.shared.getPopularOnServiceByGenre(tmdbProviderId: providerId, genreId: genreId, mediaType: mediaType)) ?? []
        case .international:
            results = (try? await TMDBService.shared.getPopularOnServiceInternational(tmdbProviderId: providerId)) ?? []
        }
        resultsByCategory[cat.id] = results.prefix(25).map { poster(from: $0) }
        loadingCategories.remove(cat.id)
    }
}

enum DetailSubject: Identifiable, Hashable {
    case episode(Episode)
    case show(PosterShow)

    var id: String {
        switch self {
        case .episode(let e): return "ep-\(e.id.uuidString)"
        case .show(let s): return "sh-\(s.id.uuidString)"
        }
    }
}

// MARK: - Episode Detail Sheet

struct EpisodeDetailSheet: View {
    let subject: DetailSubject
    @Environment(\.dismiss) private var dismiss

    @State private var resolvedBackdrop: String?
    @State private var showCastSheet: Bool = false
    @State private var streams = StreamsViewModel.shared
    @State private var social = SocialViewModel.shared
    @State private var isToggleSaving: Bool = false
    @State private var showComments: Bool = false
    @State private var isTogglingLike: Bool = false
    @State private var isTogglingWatched: Bool = false
    /// Watchmode-resolved source for the show (top US sub > free > tve > rent).
    /// When set, drives the platform label, color, and the "Watch on" deeplink so
    /// shows show their real streaming service instead of the placeholder "HBO Max".
    @State private var resolvedSource: WatchmodeSource?
    /// TMDB-resolved provider name — middle-tier fallback when Watchmode
    /// returns no usable source. Drives the platform label and badge.
    @State private var resolvedProviderName: String? = nil
    @State private var resolvedOverview: String?
    @State private var isResolvingSource: Bool = false
    @State private var adDismissed: Bool = false
    @State private var showFullDetail: Bool = false
    /// Latest episode (season, episode) pulled from TMDB when the subject is a
    /// show. Drives the "Watch S:1 EP:10 on Paramount+" button label.
    @State private var showLatestEpisode: (seasonNum: Int, episodeNum: Int)? = nil
    /// Per-episode deep link URL resolved from Watchmode's episode-level
    /// sources endpoint. When non-nil, the watch button opens this URL
    /// instead of `episodeDeeplinkURL` so that Paramount+ and other
    /// services land on the exact episode rather than the show home.
    @State private var episodeDeepLinkURL: URL?
    /// Per-episode Roku ECP launch path from Watchmode's `roku_url` field.
    /// When non-nil, passed to `CastToTVSheet` so the Roku launch can use
    /// the exact channel+contentID path instead of the webUrl fallback.
    @State private var episodeRokuURL: String? = nil
    @State private var episodeSourceUnavailable: Bool = false
    @State private var isResolvingEpisodeSources: Bool = false
    /// All US streaming sources for this title. Drives the "Where to Watch"
    /// chip row and lets the user pick an active source when subscribed to
    /// two or more of them.
    @State private var allSources: [WatchmodeSource] = []

    private var platformColor: Color {
        if let name = resolvedSource?.name { return brandColor(for: name) }
        if let p = resolvedProviderName, !p.isEmpty { return brandColor(for: p) }
        switch subject {
        case .episode(let e): return e.platformColor
        case .show(let s): return s.posterColors.first ?? Color(red: 0x6A/255, green: 0x3F/255, blue: 0xE0/255)
        }
    }

    private var affiliateAdData:
    (serviceId: String, headline: String, subtext: String)? {
        let rawPlatform: String = {
            if let name = resolvedSource?.name { return name }
            if case .episode(let e) = subject { return e.platform }
            return ""
        }()
        let current = normalisedServiceKey(rawPlatform)

        let owned = AuthViewModel.shared.selectedServices
            .map { normalisedServiceKey($0) }

        let pool: [(String, String, String)] = [
            ("netflix", "Stream more on Netflix",
             "Unlimited shows & movies · Try free"),
            ("hbo", "Watch more on Max",
             "HBO, Max Originals & more · Try free"),
            ("hulu", "Live TV + streaming on Hulu",
             "Starting at $7.99/mo · Try free"),
            ("disney", "Disney+, Hulu & ESPN+ bundle",
             "Disney Bundle · Try free"),
            ("appletv", "Award-winning originals",
             "Apple TV+ · First month free"),
            ("prime", "Included with Prime",
             "Prime Video · Try free"),
            ("paramount", "NFL on CBS & live sports",
             "Paramount+ · Try free"),
            ("peacock", "Stream free on Peacock",
             "NBC shows & live sports · Free tier")
        ]

        // Prefer a service the user doesn't already own and isn't the
        // current platform. If they own everything, fall back to any pool
        // entry that isn't the current platform so an ad still appears.
        if let preferred = pool.first(where: { entry in
            entry.0 != current && !owned.contains(entry.0)
        }) {
            return (preferred.0, preferred.1, preferred.2)
        }
        if let fallback = pool.first(where: { $0.0 != current }) {
            return (fallback.0, fallback.1, fallback.2)
        }
        return pool.first.map { ($0.0, $0.1, $0.2) }
    }

    private func normalisedServiceKey(_ raw: String) -> String {
        let k = raw.lowercased()
        if k.contains("netflix") { return "netflix" }
        if k.contains("max") || k.contains("hbo") { return "hbo" }
        if k.contains("hulu") { return "hulu" }
        if k.contains("disney") { return "disney" }
        if k.contains("apple") { return "appletv" }
        if k.contains("prime") || k.contains("amazon") { return "prime" }
        if k.contains("paramount") { return "paramount" }
        if k.contains("peacock") { return "peacock" }
        return k
    }

    /// True when we can confidently name an actual streaming service for
    /// this title. Drives whether we render the where-to-watch chip and
    /// the Watch CTA at all — we deliberately don't show "Streaming
    /// services" anywhere because that isn't a real platform the user can
    /// open.
    private var hasResolvedPlatform: Bool {
        if resolvedSource?.name != nil { return true }
        if let p = resolvedProviderName, !p.isEmpty { return true }
        if case .episode(let e) = subject, !e.platform.isEmpty, e.platform.uppercased() != "STREAM" {
            return true
        }
        return false
    }

    private var platformName: String {
        if let name = resolvedSource?.name { return gsDisplayName(for: name).uppercased() }
        if let p = resolvedProviderName, !p.isEmpty { return gsDisplayName(for: p).uppercased() }
        switch subject {
        case .episode(let e) where !e.platform.isEmpty && e.platform.uppercased() != "STREAM":
            return e.platform
        default:
            return isResolvingSource ? "…" : ""
        }
    }

    private var whereToWatchLabel: String {
        if let name = resolvedSource?.name { return gsDisplayName(for: name) }
        if let p = resolvedProviderName, !p.isEmpty { return gsDisplayName(for: p) }
        switch subject {
        case .episode(let e) where !e.platform.isEmpty && e.platform.uppercased() != "STREAM":
            return e.platform.capitalized
        default:
            return isResolvingSource ? "Finding service…" : ""
        }
    }

    private var aboutText: String {
        if let overview = resolvedOverview, !overview.isEmpty { return overview }
        return "Tap Watch on \(whereToWatchLabel) to open this title in the streaming app."
    }

    /// `true` when the resolved source is a paid subscription the user
    /// does not have — drives the "Get" label on the watch CTA.
    private var requiresGet: Bool {
        guard let source = resolvedSource,
              source.type.lowercased() == "sub" else { return false }
        return !AuthViewModel.shared.subscribesToService(named: source.name)
    }

    /// Availability helper caption shown below the watch CTA. Returns
    /// `nil` (no view rendered) for subscribed, unknown, or unresolved types.
    private var availabilityCaption: String? {
        guard let source = resolvedSource else { return nil }
        let type = source.type.lowercased()
        let name = gsDisplayName(for: source.name)
        if type == "free" { return "Free on \(name)" }
        if type == "tve" { return "Available on \(name) with a TV provider" }
        if type == "sub" { return AuthViewModel.shared.subscribesToService(named: source.name) ? nil : "Requires a \(name) subscription" }
        return nil
    }

    /// `true` when we're a show (or anything without explicit episode info).
    /// Drives both the Watchmode lookup (`tmdb_tv_id` vs `tmdb_movie_id`) and
    /// the Roku ECP `MediaType` parameter ("series" vs "movie").
    private var isTV: Bool {
        if case .episode = subject { return true }
        if case .show(let s) = subject { return s.isTV }
        return true
    }

    private func brandColor(for name: String) -> Color {
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

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 18)

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 20)

                actionsRow
                    .padding(.horizontal, 20)
                    .padding(.vertical, 22)

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 20)

                affiliateBanner
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                watchContextCard
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                whereToWatchRow
                    .padding(.horizontal, 20)
                    .padding(.top, 22)

                watchActions
                    .padding(.horizontal, 20)
                    .padding(.top, 22)

                if let caption = availabilityCaption {
                    Text(caption)
                        .scaledFont(size: 13)
                        .foregroundStyle(Color.white.opacity(0.5))
                        .padding(.top, 6)
                        .padding(.horizontal, 20)
                }

                secondaryPillRow
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                aboutSection
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .padding(.bottom, 28)
            }
        }
        .background(Color(red: 0x13/255, green: 0x18/255, blue: 0x1D/255).ignoresSafeArea())
        .presentationDetents([.fraction(0.8), .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .sheet(isPresented: $showCastSheet) {
            CastToTVSheet(
                isPresented: $showCastSheet,
                showTitle: title,
                platform: whereToWatchLabel,
                tmdbId: tmdbId,
                isTV: isTV,
                watchmodeSource: resolvedSource,
                episodeRokuURL: episodeRokuURL
            )
        }
        .sheet(isPresented: $showComments) {
            TitleCommentsSheet(
                titleId: socialTitleKey,
                title: title,
                subtitle: meta,
                posterUrl: posterUrl,
                posterColors: colors,
                accent: Color.orange
            )
        }
        .task(id: tmdbId ?? -1) {
            adDismissed = false
            episodeSourceUnavailable = false
            isResolvingEpisodeSources = false
            // Run source resolution and TMDB detail fetch in parallel
            // so showLatestEpisode is ready before the user can tap
            // "Full details" — otherwise knownLatestEpisode is nil and
            // the detail screen falls to the wrong season/episode.
            async let _source = resolveStreamingSource()
            async let _episode: Void = {
                if let tid = tmdbId, isTV {
                    if let detail = try? await TMDBService.shared.getTVDetail(tmdbId: tid),
                       let last = detail.lastEpisodeToAir,
                       let sn = last.seasonNumber, let en = last.episodeNumber {
                        await MainActor.run {
                            self.showLatestEpisode = (sn, en)
                            NSLog("[EP_SHEET_DIAG] tmdbId=\(tid) lastEpisodeToAir=S\(sn):E\(en) name=\(last.name ?? "nil")")
                        }
                    } else {
                        NSLog("[EP_SHEET_DIAG] tmdbId=\(tid) lastEpisodeToAir=NIL — TMDB returned no last_episode_to_air")
                    }
                }
            }()
            await _source
            await _episode
            // Resolve per-episode deep link from Watchmode's episode-level
            // sources so the watch button opens the exact episode in the
            // streaming app (not just the show home page).
            if let tid = tmdbId, isTV, let ctx = episodeContext {
                await MainActor.run { self.isResolvingEpisodeSources = true }
                defer { Task { @MainActor in self.isResolvingEpisodeSources = false } }

                let epSources = await WatchmodeService.shared.episodeSources(
                    tmdbId: tid, isTV: true,
                    season: ctx.seasonNum, episode: ctx.episodeNum
                )
                let best: WatchmodeSource? = epSources.flatMap {
                    Self.bestEpisodeSource(from: $0, resolvedSource: resolvedSource)
                }
                let url: URL? = epSources.flatMap {
                    Self.episodeSourceURL(from: $0, resolvedSource: best)
                }
                let rokuPath: String? = epSources.flatMap {
                    Self.episodeRokuPath(from: $0, resolvedSource: best)
                }
                await MainActor.run {
                    if let best { self.resolvedSource = best }
                    self.episodeDeepLinkURL = url
                    self.episodeRokuURL = rokuPath
                    self.episodeSourceUnavailable = (best == nil)
                    self.isResolvingEpisodeSources = false
                }
            }
        }
        .fullScreenCover(isPresented: $showFullDetail) {
            ShowDetailScreen(
                titleId: tmdbId.map(String.init) ?? "",
                title: title,
                posterUrl: posterUrl,
                backdropUrl: resolvedBackdrop,
                isTV: isTV,
                knownLatestEpisode: showLatestEpisode,
                onBack: { showFullDetail = false }
            )
        }
        .task(id: socialTitleKey) {
            await social.refreshCounts(titleId: socialTitleKey)
        }
    }

    /// Stable identifier used to scope likes & comments. Episodes and shows
    /// with a TMDB id key off that (matches the watchlist's `titleId`).
    /// Anything without a tmdbId falls back to a slug of the title so the
    /// social state still has a stable home.
    private var socialTitleKey: String {
        if let tmdbId { return String(tmdbId) }
        return WatchIntentLogger.titleSlug(title)
    }

    // MARK: - Source resolution

    /// Looks up the title's real top streaming source via the shared
    /// StreamingSourceResolver, which runs all network calls inside a
    /// `Task.detached` (immune to view-lifecycle cancellation) and applies
    /// US-region filtering, network-priority selection, and reseller
    /// deprioritisation.
    private func resolveStreamingSource() async {
        guard let tmdbId, resolvedSource == nil, !isResolvingSource else { return }
        // Skip the lookup for episode rows that already carry a platform we
        // recognise — their `e.platform` string is more accurate than what
        // Watchmode would return for the parent show.
        if case .episode(let e) = subject, !e.platform.isEmpty {
            // Still try to fetch sources so the watch button can use the
            // canonical Watchmode URL, but tolerate failure.
        }
        isResolvingSource = true
        defer { isResolvingSource = false }

        let hint: String? = {
            if case .episode(let e) = subject, !e.platform.isEmpty {
                return e.platform
            }
            return nil
        }()

        let r = await StreamingSourceResolver.shared.resolve(
            tmdbId: tmdbId,
            isTV: isTV,
            episodePlatformHint: hint
        )

        await MainActor.run {
            self.resolvedSource = r.primarySource
            self.resolvedOverview = r.overview
            self.resolvedProviderName = r.providerNameFallback
            self.allSources = r.usSources
        }
    }

    /// Re-resolves the episode-level deep link + Roku path for a specific
    /// user-selected source. Factored from the initial `.task` episode-source
    /// logic so a chip tap can retarget the watch button to that service.
    private func resolveEpisodeSources(for source: WatchmodeSource) async {
        guard let tid = tmdbId, isTV, let ctx = episodeContext else { return }
        await MainActor.run { self.isResolvingEpisodeSources = true }
        let epSources = await WatchmodeService.shared.episodeSources(
            tmdbId: tid, isTV: true, season: ctx.seasonNum, episode: ctx.episodeNum
        )
        let url = epSources.flatMap { Self.episodeSourceURL(from: $0, resolvedSource: source) }
        let rokuPath = epSources.flatMap { Self.episodeRokuPath(from: $0, resolvedSource: source) }
        await MainActor.run {
            self.episodeDeepLinkURL = url
            self.episodeRokuURL = rokuPath
            self.episodeSourceUnavailable = false
            self.isResolvingEpisodeSources = false
        }
    }

    /// Handles a "Where to Watch" chip tap. When the user is subscribed to
    /// two or more of the title's services and taps a subscribed one, it
    /// becomes the active source (watch button follows). Otherwise it opens
    /// the source's deep link directly.
    private func onWhereToWatchTap(_ source: WatchmodeSource, subscribedCount: Int) {
        if subscribedCount >= 2, AuthViewModel.shared.subscribesToService(named: source.name) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            resolvedSource = source
            Task { await resolveEpisodeSources(for: source) }
        } else {
            if let web = source.webUrl, Self.isRealDeepLinkURL(web), let u = URL(string: web) {
                StreamingDeepLinker.openResolvedURL(
                    u, platform: source.name, title: title, tmdbId: tmdbId
                )
            } else {
                StreamingDeepLinker.open(
                    platform: source.name, title: title, tmdbId: tmdbId, isTV: isTV
                )
            }
        }
    }

    // MARK: - Where to watch row

    @ViewBuilder
    private var whereToWatchRow: some View {
        if !allSources.isEmpty {
            let sortedSources = allSources.sorted { a, b in
                let aSub = AuthViewModel.shared.subscribesToService(named: a.name)
                let bSub = AuthViewModel.shared.subscribesToService(named: b.name)
                if aSub != bSub { return aSub }
                return false
            }
            let subscribedCount = sortedSources.filter {
                AuthViewModel.shared.subscribesToService(named: $0.name)
            }.count
            VStack(alignment: .leading, spacing: 10) {
                Text("WHERE TO WATCH")
                    .scaledFont(size: 12, weight: .heavy)
                    .tracking(1.4)
                    .foregroundStyle(Color.white.opacity(0.45))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(sortedSources) { source in
                            Button {
                                onWhereToWatchTap(source, subscribedCount: subscribedCount)
                            } label: {
                                ServiceBadge(
                                    name: source.name,
                                    color: brandColor(for: source.name),
                                    isSubscribed: AuthViewModel.shared.subscribesToService(named: source.name),
                                    isSelected: subscribedCount >= 2 && resolvedSource?.sourceId == source.sourceId
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }



    // MARK: - Affiliate banner

    @ViewBuilder
    private var affiliateBanner: some View {
        if !adDismissed, let ad = affiliateAdData,
           let service = StreamingCatalog.all
            .first(where: { $0.id == ad.serviceId }) {
            SponsoredSlotView(
                service: service,
                fallbackName: ad.headline,
                fallbackColor: .white,
                headline: ad.headline,
                subtitle: ad.subtext,
                onTap: {
                    RakutenManager.shared.openAffiliateLink(
                        serviceId: ad.serviceId,
                        metadata: [
                            "source": "episode_detail_sheet",
                            "platform_shown": platformName,
                            "title": title
                        ]
                    )
                },
                onDismiss: { adDismissed = true },
                adSource: "episode_detail_sheet"
            )
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Header row

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 16) {
            posterThumbnail
                .frame(width: 110, height: 150)
                .clipShape(.rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .scaledFont(size: 26, weight: .bold)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(meta)
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.white.opacity(0.55))

                HStack(spacing: 8) {
                    if hasResolvedPlatform || isResolvingSource {
                        Text(platformName.uppercased())
                            .scaledFont(size: 11, weight: .heavy)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(platformColor))
                    }

                    Text("Drama")
                        .scaledFont(size: 12, weight: .semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                }
                .padding(.top, 2)

                HStack(spacing: 6) {
                    ForEach(0..<5, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .scaledFont(size: 11)
                            .foregroundStyle(Color(red: 0xFF/255, green: 0xC4/255, blue: 0x3D/255))
                    }
                    Text("9.6")
                        .scaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(.white)
                        .padding(.leading, 4)
                }
                .padding(.top, 2)

                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: social.isLiked(socialTitleKey) ? "heart.fill" : "heart")
                            .scaledFont(size: 12)
                            .foregroundStyle(Color.orange)
                        Text(formatSocialCount(social.likes(socialTitleKey)))
                            .scaledFont(size: 13, weight: .semibold)
                            .foregroundStyle(.white)
                    }
                    Text("·")
                        .scaledFont(size: 13)
                        .foregroundStyle(Color.white.opacity(0.4))
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left")
                            .scaledFont(size: 12)
                            .foregroundStyle(Color.white.opacity(0.7))
                        Text(formatSocialCount(social.commentTotal(socialTitleKey)))
                            .scaledFont(size: 13, weight: .semibold)
                            .foregroundStyle(.white)
                    }
                }
                .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
    }

    private var posterThumbnail: some View {
        Color.black
            .overlay {
                RemoteImage(
                    urlString: posterUrl,
                    contentMode: .fill,
                    fallbackColors: colors
                )
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                if hasResolvedPlatform {
                    Text(String(platformName.prefix(4)).uppercased())
                        .scaledFont(size: 10, weight: .heavy)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(platformColor))
                        .padding(8)
                }
            }
    }

    // MARK: - Actions row

    private var actionsRow: some View {
        let key = socialTitleKey
        let isLiked = social.isLiked(key)
        return HStack(spacing: 0) {
            circleAction(
                icon: isLiked ? "heart.fill" : "heart",
                label: "Like",
                tint: isLiked ? Color.orange : .white,
                showDot: false
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                guard !isTogglingLike else { return }
                isTogglingLike = true
                let mediaType = isTV ? "tv" : "movie"
                let likeTmdbId = tmdbId
                Task {
                    await social.toggleLike(titleId: key, mediaType: mediaType, tmdbId: likeTmdbId)
                    await MainActor.run { isTogglingLike = false }
                }
            }
            .frame(maxWidth: .infinity)

            circleAction(
                icon: social.isWatched(key) ? "eye.fill" : "eye",
                label: "Watched",
                tint: social.isWatched(key) ? Color(hex: "1A6FE8") : .white,
                showDot: false
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                guard !isTogglingWatched else { return }
                isTogglingWatched = true
                let mediaType = isTV ? "tv" : "movie"
                let watchedTmdbId = tmdbId
                Task {
                    await social.toggleWatched(titleId: key, titleName: title, mediaType: mediaType, tmdbId: watchedTmdbId)
                    await MainActor.run { isTogglingWatched = false }
                }
            }
            .frame(maxWidth: .infinity)

            circleAction(
                icon: "bubble.left.fill",
                label: "Comments",
                tint: .white,
                showDot: false
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showComments = true
                WatchIntentLogger.shared.log(
                    eventType: .commentsOpened,
                    titleId: key,
                    metadata: ["source": "episode_detail_sheet"]
                )
            }
            .frame(maxWidth: .infinity)

            ShareLink(
                item: URL(string: "https://guidestream.tv")!,
                subject: Text(title),
                message: Text("Watch \(title) on GuideStream TV")
            ) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 54, height: 54)
                        Image(systemName: "square.and.arrow.up")
                            .scaledFont(size: 22, weight: .regular)
                            .foregroundStyle(.white)
                    }
                    Text("Share")
                        .scaledFont(size: 13)
                        .foregroundStyle(Color.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity)

            circleAction(
                icon: "tv",
                label: "Send to TV",
                tint: .white,
                showDot: false,
                isLoading: isResolvingEpisodeSources
            ) {
                guard !isResolvingEpisodeSources else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showCastSheet = true
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func circleAction(
        icon: String,
        label: String,
        tint: Color,
        showDot: Bool,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 54, height: 54)
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: icon)
                            .scaledFont(size: 22, weight: .regular)
                            .foregroundStyle(tint)
                    }
                    if showDot && !isLoading {
                        Circle()
                            .fill(Color(red: 0x3D/255, green: 0xE0/255, blue: 0x6A/255))
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color(red: 0x13/255, green: 0x18/255, blue: 0x1D/255), lineWidth: 2))
                            .offset(x: 16, y: -16)
                    }
                }
                Text(label)
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
    }

    /// Compact count formatting used by the actions row + meta line:
    /// 0 -> "0", 1234 -> "1.2K", 1_234_567 -> "1.2M".
    private func formatSocialCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ABOUT")
                .scaledFont(size: 12, weight: .heavy)
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.45))
            Text(aboutText)
                .scaledFont(size: 15)
                .foregroundStyle(Color.white.opacity(0.85))
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Watch context card

    @ViewBuilder
    private var watchContextCard: some View {
        if case .episode(let episode) = subject {
            HStack(spacing: 12) {
                Color.black
                    .frame(width: 56, height: 56)
                    .overlay {
                        RemoteImage(
                            urlString: episode.posterUrl,
                            contentMode: .fill,
                            fallbackColors: episode.posterColors
                        )
                        .allowsHitTesting(false)
                    }
                    .clipShape(.rect(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("\(episode.season) ·")
                            .scaledFont(size: 12, weight: .semibold)
                            .foregroundStyle(Color.white.opacity(0.55))
                        Text(episode.progress > 0 ? "Resume" : "Most recent")
                            .scaledFont(size: 12, weight: .semibold)
                            .foregroundStyle(.white)
                    }
                    Text(episode.title)
                        .scaledFont(size: 13, weight: .bold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if episode.progress > 0 {
                    Text("\(Int(episode.progress * 100))%")
                        .scaledFont(size: 10, weight: .heavy)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.orange))
                } else if episode.isNew {
                    Text("NEW")
                        .scaledFont(size: 10, weight: .heavy)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.orange))
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
                    )
            )
            .overlay(alignment: .bottom) {
                if episode.progress > 0 {
                    GeometryReader { geo in
                        Color.orange
                            .frame(width: geo.size.width * episode.progress, height: 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .clipShape(.rect(cornerRadius: 14))
        }
    }

    // MARK: - Secondary pill row

    private var secondaryPillRow: some View {
        HStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                guard let tmdbId else { return }
                Task {
                    let key: String?
                    if isTV {
                        key = try? await TMDBService.shared.getTrailerKey(tmdbId: tmdbId)
                    } else {
                        key = try? await TMDBService.shared.getMovieTrailerKey(tmdbId: tmdbId)
                    }
                    await MainActor.run {
                        if let key {
                            UIApplication.shared.open(URL(string: "https://www.youtube.com/watch?v=\(key)")!)
                        } else {
                            let query = "\(title) trailer".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
                            UIApplication.shared.open(URL(string: "https://www.youtube.com/results?search_query=\(query)")!)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "film")
                        .scaledFont(size: 14)
                    Text("Trailer")
                        .scaledFont(size: 13, weight: .medium)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            Button {
                showFullDetail = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .scaledFont(size: 14)
                    Text("Full details")
                        .scaledFont(size: 13, weight: .medium)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - CTA

    private var watchActions: some View {
        // `.top` alignment keeps the full-width Watch CTA pinned to the top
        // while the watchlist circle + label hangs below — same vertical
        // rhythm as the Reels rail button.
        HStack(alignment: .top, spacing: 12) {
            if hasResolvedPlatform || isResolvingSource {
                watchButton
            }
            watchlistButton
        }
    }

    /// Season/episode numbers for the current detail subject. When we're
    /// viewing an episode the numbers come from the episode model; when
    /// viewing a show we pull `last_episode_to_air` from TMDB so the watch
    /// button can read "Watch S:4 EP:7 on Max" instead of "Watch on Max".
    private var episodeContext: (seasonNum: Int, episodeNum: Int)? {
        switch subject {
        case .episode(let e):
            let parts = e.season.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
            if parts.count >= 2,
               let s = Int(parts[0]), let ep = Int(parts[1]) {
                return (s, ep)
            }
            return showLatestEpisode
        case .show:
            return showLatestEpisode
        }
    }

    /// Builds an episode-specific deeplink URL by appending season/episode path
    /// segments to the show-level web_url. Falls back to the original URL when
    /// the show-level URL doesn't contain a known show path.
    private func episodeDeeplinkURL(from base: URL, season: Int, episode: Int) -> URL {
        let baseStr = base.absoluteString
        let episodePath = "/season/\(season)/episode/\(episode)"
        // Services that support path-based season/episode deep links.
        if baseStr.contains("paramountplus.com") || baseStr.contains("paramount") {
            let stripped = baseStr.hasSuffix("/") ? String(baseStr.dropLast()) : baseStr
            return URL(string: stripped + episodePath) ?? base
        }
        if baseStr.contains("peacocktv.com") || baseStr.contains("peacock") {
            let stripped = baseStr.hasSuffix("/") ? String(baseStr.dropLast()) : baseStr
            return URL(string: stripped + episodePath) ?? base
        }
        if baseStr.contains("hulu.com") {
            let stripped = baseStr.hasSuffix("/") ? String(baseStr.dropLast()) : baseStr
            return URL(string: stripped + episodePath) ?? base
        }
        // Amazon uses query params: ?season=<s>&episode=<e>
        if baseStr.contains("amazon.com") || baseStr.contains("primevideo.com") || baseStr.contains("amazon") {
            return URL(string: baseStr + "?season=\(season)&episode=\(episode)") ?? base
        }
        // Netflix, Apple TV+, Max, Disney+ use opaque IDs —
        // return the show-level URL as a best-effort fallback.
        return base
    }

    private var watchButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            // Gated "Get" path: route through Rakuten affiliate so the
            // tap is attributable and earns commission. The Watch path
            // (below) keeps the existing deep-link resolution.
            if requiresGet,
               RakutenManager.shared.hasAffiliate(forServiceNamed: resolvedSource?.name ?? "") {
                RakutenManager.shared.openAffiliateLink(
                    forServiceNamed: resolvedSource?.name ?? "",
                    metadata: [
                        "source": "episode_detail_get_cta",
                        "title": title,
                        "tmdb_id": tmdbId as Any
                    ]
                )
            } else if let epURL = episodeDeepLinkURL {
                StreamingDeepLinker.openResolvedURL(
                    epURL,
                    platform: whereToWatchLabel,
                    title: title,
                    tmdbId: tmdbId
                )
            } else if let pre = preResolvedDeepLinkURL {
                let finalURL: URL = {
                    if let ctx = episodeContext {
                        return episodeDeeplinkURL(from: pre, season: ctx.seasonNum, episode: ctx.episodeNum)
                    }
                    return pre
                }()
                StreamingDeepLinker.openResolvedURL(
                    finalURL,
                    platform: whereToWatchLabel,
                    title: title,
                    tmdbId: tmdbId
                )
            } else {
                StreamingDeepLinker.open(
                    platform: whereToWatchLabel,
                    title: title,
                    tmdbId: tmdbId,
                    isTV: isTV
                )
            }

            // Defer dismiss so the URL open completes first — iOS
            // sometimes drops opens fired mid-dismiss animation.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                dismiss()
            }
        } label: {
            HStack(spacing: 8) {
                if (isResolvingSource && resolvedSource == nil) || isResolvingEpisodeSources {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                if let ctx = episodeContext, !episodeSourceUnavailable {
                    Text(requiresGet ? "Get S:\(ctx.seasonNum) EP:\(ctx.episodeNum)" : "Watch S:\(ctx.seasonNum) EP:\(ctx.episodeNum)")
                        .scaledFont(size: 15, weight: .semibold)
                        .lineLimit(1)
                } else {
                    Text(resolvedSource == nil && isResolvingSource
                         ? "Finding service…"
                         : (requiresGet ? "Get on" : "Watch on"))
                        .scaledFont(size: 17, weight: .semibold)
                        .lineLimit(1)
                }
                if hasResolvedPlatform, !whereToWatchLabel.isEmpty {
                    Text(whereToWatchLabel)
                        .scaledFont(size: 11, weight: .bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6).fill(platformColor))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Capsule().fill(Color.orange))
            .shadow(color: Color.orange.opacity(0.55), radius: 22, y: 0)
        }
        .buttonStyle(.plain)
        .disabled(tmdbId == nil || isResolvingEpisodeSources)
    }

    /// Circular + watchlist button shown next to the main Watch CTA. Visual
    /// rules mirror the Reels rail button so users get a consistent
    /// "save to my list" affordance everywhere a title is shown:
    ///
    /// * **Not saved** — solid orange circle with a `plus` glyph + "Watch List"
    ///   label below.
    /// * **Saved** — transparent circle with a white stroke (outlined) + a
    ///   checkmark glyph and "Saved" label below.
    @ViewBuilder
    private var watchlistButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            toggleWatchList()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    if isSaved {
                        Circle()
                            .fill(Color.clear)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1.8))
                    } else {
                        Circle()
                            .fill(Color.orange)
                            .shadow(color: Color.orange.opacity(0.55), radius: 14, y: 0)
                    }
                    if isToggleSaving {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: isSaved ? "checkmark" : "plus")
                            .scaledFont(size: 22, weight: .bold)
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 56, height: 56)

                Text(isSaved ? "Saved" : "Watch List")
                    .scaledFont(size: 11, weight: .semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .disabled(tmdbId == nil || isToggleSaving)
        .accessibilityLabel(isSaved ? "Saved to watch list. Tap to remove." : "Add to watch list")
    }

    // MARK: - Debug probe (temporary)



    /// True when this title's id is already present in the Supabase-backed
    /// `user_streams` list.
    private var isSaved: Bool {
        guard let tmdbId else { return false }
        let key = String(tmdbId)
        return streams.userStreams.contains { $0.titleId == key }
    }

    private func toggleWatchList() {
        guard let tmdbId else { return }
        let key = String(tmdbId)
        let snapshotSaved = isSaved
        isToggleSaving = true
        Task {
            if snapshotSaved {
                await streams.removeFromMyStreams(titleId: key)
            } else {
                await streams.addToMyStreams(
                    titleId: key,
                    title: title,
                    posterUrl: posterUrl,
                    platform: resolvedSource?.name ?? whereToWatchLabel
                )
            }
            await MainActor.run { isToggleSaving = false }
        }
    }

    private var title: String {
        switch subject {
        case .episode(let e): return e.title
        case .show(let s): return s.title
        }
    }

    private var meta: String {
        switch subject {
        case .episode(let e): return "\(e.season) · \(e.duration) · \(e.platform)"
        case .show(let s): return s.meta
        }
    }

    private var colors: [Color] {
        switch subject {
        case .episode(let e): return e.posterColors
        case .show(let s): return s.posterColors
        }
    }

    private var symbol: String {
        switch subject {
        case .episode(let e): return e.symbol
        case .show(let s): return s.symbol
        }
    }

    /// Prefer the real TMDB still/poster; we also resolve a backdrop lazily by tmdbId for a richer hero.
    private var posterUrl: String? {
        switch subject {
        case .episode(let e): return e.posterUrl
        case .show(let s): return s.posterUrl
        }
    }

    private var tmdbId: Int? {
        switch subject {
        case .episode(let e): return e.tmdbId
        case .show(let s): return s.tmdbId
        }
    }

    /// Title-specific URL from the already-resolved Watchmode source.
    /// Prefers `ios_url` (real deep link when Watchmode is on a paid plan);
    /// otherwise the canonical `web_url`, which iOS routes into the
    /// streaming app via universal links. `nil` if no source has resolved
    /// yet — caller falls back to the async lookup.
    private var preResolvedDeepLinkURL: URL? {
        guard let src = resolvedSource else { return nil }
        if let s = src.iosUrl, Self.isRealDeepLinkURL(s), let u = URL(string: s) { return u }
        if let s = src.webUrl, Self.isRealDeepLinkURL(s), let u = URL(string: s) { return u }
        return nil
    }

    /// Replicates `StreamingSourceResolver.sourceRank` locally (that
    /// helper is private). sub ranks best, then free, then tve.
    /// rent/purchase/buy are excluded by the caller.
    private static func episodeSourceRank(_ s: WatchmodeSource) -> Int {
        switch s.type.lowercased() {
        case "sub": return 0
        case "free": return 1
        case "tve": return 2
        default: return 3
        }
    }

    /// Selects the best episode-level source: first by matching the
    /// resolved title-level source's `sourceId` (requiring a real deep
    /// link), otherwise re-picking using sub > free > tve ranking
    /// (excluding rent/purchase/buy), preferring non-resellers, and
    /// requiring a real deep-link URL. Returns nil when no usable
    /// source survives the filter.
    private static func bestEpisodeSource(
        from episodeSources: [WatchmodeSource],
        resolvedSource: WatchmodeSource?
    ) -> WatchmodeSource? {
        if let rs = resolvedSource,
           let match = episodeSources.first(where: { $0.sourceId == rs.sourceId }) {
            if let s = match.iosUrl, Self.isRealDeepLinkURL(s) { return match }
            if let s = match.webUrl, Self.isRealDeepLinkURL(s) { return match }
        }
        let eligible = episodeSources.filter { src in
            let t = src.type.lowercased()
            guard t == "sub" || t == "free" || t == "tve" else { return false }
            let iosOk = src.iosUrl.flatMap { Self.isRealDeepLinkURL($0) } ?? false
            let webOk = src.webUrl.flatMap { Self.isRealDeepLinkURL($0) } ?? false
            return iosOk || webOk
        }
        guard !eligible.isEmpty else { return nil }
        let ranked = eligible.sorted { a, b in
            let ra = Self.episodeSourceRank(a)
            let rb = Self.episodeSourceRank(b)
            if ra != rb { return ra < rb }
            let aReseller = a.name.lowercased().contains("(via ")
            let bReseller = b.name.lowercased().contains("(via ")
            if aReseller != bReseller { return !aReseller }
            return false
        }
        return ranked.first
    }

    /// Picks the best URL from a set of episode-level Watchmode sources
    /// that matches the (possibly re-picked) resolved source by `sourceId`.
    /// Prefers `ios_url` when it's a real deep link; falls back to `web_url`.
    /// Returns `nil` when no matching source is found or all URLs are
    /// free-tier placeholders.
    private static func episodeSourceURL(
        from episodeSources: [WatchmodeSource],
        resolvedSource: WatchmodeSource?
    ) -> URL? {
        guard let rs = resolvedSource,
              let src = episodeSources.first(where: { $0.sourceId == rs.sourceId }) else { return nil }
        if let s = src.iosUrl, Self.isRealDeepLinkURL(s), let u = URL(string: s) { return u }
        if let s = src.webUrl, Self.isRealDeepLinkURL(s), let u = URL(string: s) { return u }
        return nil
    }

    /// Picks the `roku_url` from episode-level Watchmode sources that
    /// matches the (possibly re-picked) resolved source by `sourceId`.
    /// Returns the `rokuUrl` when it is non-nil, non-empty, and contains
    /// "launch/". Returns `nil` when no matching source is found or the
    /// field is unusable. Mirrors `episodeSourceURL` but returns the raw
    /// Roku ECP path string instead of a full HTTP URL.
    private static func episodeRokuPath(
        from episodeSources: [WatchmodeSource],
        resolvedSource: WatchmodeSource?
    ) -> String? {
        guard let rs = resolvedSource,
              let src = episodeSources.first(where: { $0.sourceId == rs.sourceId }),
              let rokuUrl = src.rokuUrl,
              !rokuUrl.isEmpty,
              rokuUrl.contains("launch/") else { return nil }
        // Reject Watchmode free-tier placeholders.
        let lower = rokuUrl.lowercased()
        if lower.contains("deeplinks available") || lower.contains("paid plan") { return nil }
        return rokuUrl
    }

    /// Rejects Watchmode's free-tier placeholder string
    /// ("Deeplinks available for paid plans only.").
    private static func isRealDeepLinkURL(_ s: String) -> Bool {
        let lower = s.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.contains("://") else { return false }
        if lower.contains("deeplinks available") || lower.contains("paid plan") { return false }
        return URL(string: s) != nil
    }
}

// MARK: - New Episodes List

struct NewEpisodesListView: View {
    let episodes: [Episode]
    var onSelect: (Episode) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(episodes) { ep in
                    Button(action: { onSelect(ep) }) {
                        EpisodeRow(episode: ep)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .background(BrandBackground())
        .navigationTitle("New Episodes")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.navy, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

// MARK: - Binge Worthy List

struct BingeWorthyListView: View {
    let shows: [PosterShow]
    let sectionTitle: String
    var tag: String = "BINGE"
    var onSelect: (PosterShow) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(shows) { show in
                    Button(action: { onSelect(show) }) {
                        BingeGridCard(show: show, tag: tag)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .background(BrandBackground())
        .navigationTitle(sectionTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.navy, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

// MARK: - What's New Today List

struct WhatsNewTodayListView: View {
    let shows: [PosterShow]
    var onSelect: (PosterShow) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(shows) { show in
                    Button(action: { onSelect(show) }) {
                        BingeGridCard(show: show, tag: "TODAY")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .background(BrandBackground())
        .navigationTitle("What's New Today")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.navy, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

// MARK: - News List

/// Full-screen list of the top news streams pulled from streaming services.
/// Uses a single-column row layout so each card has room for the outlet,
/// title, and provider — keeping the news rail more scannable than the
/// poster grid used by Binge Worthy / What's New Today.
struct NewsListView: View {
    let items: [NewsStream]
    var onSelect: (NewsStream) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(items) { news in
                    Button(action: { onSelect(news) }) {
                        NewsRow(news: news)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .background(BrandBackground())
        .navigationTitle("News")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.navy, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

private struct NewsRow: View {
    let news: NewsStream

    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        HStack(spacing: 14) {
            Color.newsGreen
                .frame(width: 110, height: 72)
                .overlay {
                    RemoteImage(
                        urlString: news.backdropUrl ?? news.posterUrl,
                        contentMode: .fill,
                        fallbackColors: [Color.newsGreen, Color(red: 0.04, green: 0.20, blue: 0.18)]
                    )
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 4) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .scaledFont(size: 7, weight: .black)
                        Text("LIVE")
                            .scaledFont(size: 7, weight: .heavy)
                            .tracking(0.5)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.newsGreen)
                    )
                    .padding(4)
                }
                .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(news.outlet.uppercased())
                        .scaledFont(size: 9, weight: .bold)
                        .tracking(0.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.newsGreen))
                    if let provider = news.providerName {
                        Text(provider)
                            .scaledFont(size: 9, weight: .semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.14)))
                    }
                }
                Text(news.title)
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let d = news.publishedAt {
                    Text(Self.formatter.localizedString(for: d, relativeTo: Date()))
                        .scaledFont(size: 12)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .scaledFont(size: 13, weight: .semibold)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(10)
        .background(
            Color.white.opacity(0.05)
                .background(.ultraThinMaterial)
        )
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.newsGreen.opacity(0.30), lineWidth: 1))
        .clipShape(.rect(cornerRadius: 12))
    }
}

private struct BingeGridCard: View {
    let show: PosterShow
    let tag: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.black
                .aspectRatio(2.0/3.0, contentMode: .fit)
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
                    .allowsHitTesting(false)
                }
                .clipShape(.rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(show.title)
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(show.meta)
                    .scaledFont(size: 11.5)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
    }
}

// MARK: - Continue Watching Grid

struct ContinueWatchingGridView: View {
    let episodes: [Episode]
    var onSelect: (Episode) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(episodes) { ep in
                    Button(action: { onSelect(ep) }) {
                        ContinueWatchingGridCard(episode: ep)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .background(BrandBackground())
        .navigationTitle("Continue Watching")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.navy, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

private struct ContinueWatchingGridCard: View {
    let episode: Episode

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.black
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
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
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .center) {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "play.fill")
                                .scaledFont(size: 16, weight: .bold)
                                .foregroundStyle(.white)
                                .offset(x: 1)
                        )
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .bottomLeading) {
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
                .overlay(alignment: .bottom) {
                    if episode.progress > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.12))
                                Rectangle()
                                    .fill(Color.orange)
                                    .frame(width: geo.size.width * episode.progress)
                                    .shadow(color: Color.orange.opacity(0.6), radius: 4)
                            }
                        }
                        .frame(height: 5)
                        .allowsHitTesting(false)
                    }
                }
                .clipShape(.rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(episode.title)
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text("\(episode.season) · \(episode.duration)")
                    .scaledFont(size: 11.5)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
    }
}

private struct EpisodeRow: View {
    let episode: Episode

    var body: some View {
        HStack(spacing: 14) {
            Color.black
                .frame(width: 120, height: 72)
                .overlay {
                    RemoteImage(
                        urlString: episode.posterUrl,
                        contentMode: .fill,
                        fallbackColors: episode.posterColors
                    )
                    .allowsHitTesting(false)
                }
                .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(episode.platform)
                        .scaledFont(size: 9, weight: .bold)
                        .tracking(0.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(episode.platformColor))
                    if episode.isNew {
                        Text("NEW")
                            .scaledFont(size: 9, weight: .heavy)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.orange))
                    }
                }
                Text(episode.title)
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text("\(episode.season) · \(episode.duration)")
                    .scaledFont(size: 12)
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .scaledFont(size: 13, weight: .semibold)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(10)
        .background(
            Color.white.opacity(0.05)
                .background(.ultraThinMaterial)
        )
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(.rect(cornerRadius: 12))
    }
}

// MARK: - Widget Setup

struct WidgetSetupView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
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
                    .frame(height: 180)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("UP NEXT")
                                .scaledFont(size: 10, weight: .heavy)
                                .tracking(1)
                                .foregroundStyle(.white.opacity(0.85))
                            Text("Stranger Things")
                                .scaledFont(size: 18, weight: .bold)
                                .foregroundStyle(.white)
                            Text("S:5 EP:1 · 64min")
                                .scaledFont(size: 12)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(16)
                    }
                    .shadow(color: Color.orange.opacity(0.4), radius: 24, y: 10)
                    .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 14) {
                    StepRow(number: 1, title: "Long press your home screen", subtitle: "Until apps start jiggling.")
                    StepRow(number: 2, title: "Tap the + button", subtitle: "In the top-left corner.")
                    StepRow(number: 3, title: "Search \"GuideStream\"", subtitle: "Pick a small, medium, or large widget.")
                    StepRow(number: 4, title: "Add Widget", subtitle: "Drop it anywhere on your home screen.")
                }
                .padding(.horizontal, 20)

                WidgetDiagnosticsCard()
                    .padding(.horizontal, 20)

                Button(action: { dismiss() }) {
                    Text("Got it")
                        .scaledFont(size: 16, weight: .bold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Capsule().fill(Color.orange))
                        .shadow(color: Color.orange.opacity(0.5), radius: 14, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer(minLength: 40)
            }
            .padding(.top, 16)
            .padding(.bottom, 120)
        }
        .background(BrandBackground())
        .navigationTitle("Set Up Widget")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.navy, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

/// Live diagnostic showing whether the App Group shared container is
/// actually reachable from the app, what payload the widget will read, and
/// a button to push known sample data end-to-end.
struct WidgetDiagnosticsCard: View {
    @State private var diag: WidgetDataService.Diagnostics?
    @State private var didSendTest: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "stethoscope")
                    .scaledFont(size: 13, weight: .bold)
                    .foregroundStyle(Color.orange)
                Text("Widget Diagnostics")
                    .scaledFont(size: 14, weight: .bold)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                        .scaledFont(size: 12, weight: .bold)
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
            }

            if let diag {
                // The file container is the ONLY reliable test of whether the
                // App Group is actually provisioned at runtime. UserDefaults(suiteName:)
                // returns non-nil even when the group is NOT entitled (it falls back
                // to a private container the widget can't see), so we don't surface it
                // as a separate green check — it would be a false positive.
                statusRow("App Group shared container", ok: diag.fileContainerReachable)
                statusRow("Data written for widget", ok: diag.hasPayload && diag.fileContainerReachable)

                if diag.fileContainerReachable, diag.hasPayload {
                    Text("Leaving soon: \(diag.leavingSoonCount) · Watchlist: \(diag.watchlistCount) · New eps: \(diag.newEpisodeCount)")
                        .scaledFont(size: 11)
                        .foregroundStyle(Color.textSecondary)
                    if let updated = diag.lastUpdated {
                        Text("Last written \(updated.formatted(.relative(presentation: .named)))")
                            .scaledFont(size: 11)
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                if !diag.fileContainerReachable {
                    Text("The App Group container isn't available on this build, so the widget can't read app data — no matter what the app writes. This is a signing/provisioning issue: the App Group must be registered in the provisioning profile that signs the build. Widgets share data only in a fully provisioned build (TestFlight or App Store), not in the preview/companion build.")
                        .scaledFont(size: 11)
                        .foregroundStyle(Color(red: 0xFF/255, green: 0x6B/255, blue: 0x6B/255))
                } else if !diag.hasPayload {
                    Text("Storage works but nothing has been written yet. Open the Home tab to load your shows, or tap below to send sample data.")
                        .scaledFont(size: 11)
                        .foregroundStyle(Color.textSecondary)
                }
            } else {
                Text("Checking…")
                    .scaledFont(size: 12)
                    .foregroundStyle(Color.textSecondary)
            }

            Button(action: sendTest) {
                Text(didSendTest ? "Sample sent — check your widget" : "Send test data to widget")
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(Capsule().fill(Color.orange.opacity(didSendTest ? 0.4 : 1)))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .onAppear(perform: refresh)
    }

    private func statusRow(_ label: String, ok: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .scaledFont(size: 13)
                .foregroundStyle(ok ? Color.green : Color(red: 0xFF/255, green: 0x6B/255, blue: 0x6B/255))
            Text(label)
                .scaledFont(size: 12)
                .foregroundStyle(Color.textPrimary)
            Spacer()
        }
    }

    private func refresh() {
        diag = WidgetDataService.shared.diagnostics()
    }

    private func sendTest() {
        WidgetDataService.shared.pushTestData()
        didSendTest = true
        refresh()
    }
}

private struct StepRow: View {
    let number: Int
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .scaledFont(size: 15, weight: .bold)
                .foregroundStyle(Color.orange)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.orange.opacity(0.14)))
                .overlay(Circle().stroke(Color.orange.opacity(0.35), lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(Color.textPrimary)
                Text(subtitle)
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Notifications Sheet

struct NotificationsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var streams = StreamsViewModel.shared
    @State private var trendingFallback: [TMDBResult] = []

    private var liveItems: [NotificationDisplayItem] {
        if !streams.newEpisodes.isEmpty {
            return streams.newEpisodes.prefix(50).map { row in
                NotificationDisplayItem(
                    id: row.id,
                    title: row.title ?? "New episode",
                    subtitle: subtitle(for: row),
                    time: relativeTime(row.releasedAt),
                    posterUrl: row.posterUrl,
                    titleId: row.titleId,
                    platformId: row.platform?.lowercased() ?? "",
                    type: "new_episode",
                    badge: "NEW"
                )
            }
        }
        return trendingFallback.prefix(20).map { r in
            NotificationDisplayItem(
                id: "tmdb-\(r.id)",
                title: r.displayName,
                subtitle: r.overview ?? "Trending on streaming this week.",
                time: r.year.map { "\($0)" } ?? "Trending",
                posterUrl: r.posterUrl,
                titleId: String(r.id),
                platformId: "tmdb",
                type: "trending",
                badge: "TRENDING"
            )
        }
    }

    private func subtitle(for row: NewEpisodeRow) -> String {
        let s = row.season ?? 1
        let e = row.episode ?? 1
        let platform = row.platform ?? ""
        if platform.isEmpty { return "S\(s) E\(e)" }
        return "S\(s) E\(e) · \(platform)"
    }

    private func relativeTime(_ date: Date?) -> String {
        guard let date else { return "" }
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .short
        return fmt.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Notifications")
                    .scaledFont(size: 22, weight: .semibold)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .scaledFont(size: 14, weight: .bold)
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)

            ScrollView {
                LazyVStack(spacing: 10) {
                    if liveItems.isEmpty {
                        Text("You're all caught up.")
                            .scaledFont(size: 13)
                            .foregroundStyle(Color.textSecondary)
                            .padding(.top, 40)
                    } else {
                        ForEach(liveItems) { item in
                            Button {
                                WatchIntentLogger.shared.log(
                                    eventType: .notificationOpened,
                                    titleId: item.titleId,
                                    platformId: item.platformId,
                                    metadata: ["notification_type": item.type]
                                )
                            } label: {
                                NotificationRow(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BrandBackground())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .task {
            await streams.refreshAll()
            if streams.newEpisodes.isEmpty,
               let results = try? await TMDBService.shared.getTrending() {
                trendingFallback = results
            }
        }
    }
}

struct NotificationDisplayItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let time: String
    let posterUrl: String?
    let titleId: String
    let platformId: String
    let type: String
    let badge: String
}

private struct NotificationRow: View {
    let item: NotificationDisplayItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Color.black
                .frame(width: 56, height: 80)
                .overlay {
                    RemoteImage(urlString: item.posterUrl, contentMode: .fill)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .topLeading) {
                    Text(item.badge)
                        .scaledFont(size: 8, weight: .heavy)
                        .tracking(0.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.orange)
                        )
                        .padding(4)
                }
                .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(item.subtitle)
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Text(item.time)
                .scaledFont(size: 11)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(.rect(cornerRadius: 12))
    }
}

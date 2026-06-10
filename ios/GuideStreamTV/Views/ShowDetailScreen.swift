//
//  ShowDetailScreen.swift
//  GuideStreamTV
//

import SwiftUI

// MARK: - Models

struct ShowDetailEpisode: Identifiable, Hashable {
    let id = UUID()
    let code: String          // "S4 E7"
    let title: String
    let duration: String      // "64 min"
    let status: EpStatus
    let progress: Double      // 0..1
}

enum EpStatus: Hashable {
    case continueWatching
    case new
    case none
}

struct WhereToWatchService: Identifiable, Hashable {
    let id: String
    let name: String
    let color: Color
    let iosUrl: String?
    let androidUrl: String?
    let webUrl: String?
    let format: String?

    init(id: String = UUID().uuidString, name: String, color: Color, iosUrl: String? = nil, androidUrl: String? = nil, webUrl: String? = nil, format: String? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.iosUrl = iosUrl
        self.androidUrl = androidUrl
        self.webUrl = webUrl
        self.format = format
    }
}

// MARK: - View Model (cached fetch)

@Observable
final class ShowDetailViewModel {
    var detail: WatchmodeTitleDetail?
    var tmdb: TMDBTVDetail?
    var season: TMDBSeason?
    var tvdbNextEpisode: TVDBEpisode?
    var tvdbSeries: TVDBSeriesExtended?
    var currentSeasonNumber: Int = 1
    var isLoading: Bool = false
    var errorMessage: String?
    private var loadedTitleId: String?

    /// Loads TMDB detail + Watchmode sources in parallel, then enriches with
    /// TVDB for higher-fidelity episode air-date data.
    /// `titleId` may be a TMDB integer id (preferred) or a legacy Watchmode id.
    func loadIfNeeded(titleId: String, isTV: Bool = true) async {
        guard loadedTitleId != titleId else { return }
        loadedTitleId = titleId
        isLoading = true
        errorMessage = nil

        if let tmdbId = Int(titleId), isTV {
            async let tmdbCall: TMDBTVDetail? = try? TMDBService.shared.getTVDetail(tmdbId: tmdbId)
            async let wmIdCall: String? = try? WatchmodeService.shared.watchmodeId(forTMDBId: tmdbId, isTV: isTV)
            let tmdbResult = await tmdbCall
            self.tmdb = tmdbResult
            let seasonNum = max(1, tmdbResult?.numberOfSeasons ?? 1)
            self.currentSeasonNumber = seasonNum
            async let seasonCall: TMDBSeason? = try? TMDBService.shared.getSeason(tmdbId: tmdbId, seasonNumber: seasonNum)
            if let wmId = await wmIdCall {
                self.detail = try? await WatchmodeService.shared.titleDetail(titleId: wmId)
            }
            self.season = await seasonCall

            // Fallback: if Watchmode returned no sources (common on free tier),
            // use TMDB watch providers so the "Where to Watch" section renders.
            if self.detail?.sources == nil {
                if let provider = try? await TMDBService.shared.getTopWatchProvider(tmdbId: tmdbId, isTV: isTV) {
                    let source = WatchmodeSource(
                        sourceId: provider.providerId,
                        name: provider.providerName,
                        type: "sub",
                        region: nil,
                        iosUrl: nil,
                        androidUrl: nil,
                        webUrl: nil,
                        format: nil,
                        endDate: nil
                    )
                    self.detail = WatchmodeTitleDetail(
                        id: self.detail?.id ?? tmdbId,
                        title: self.detail?.title ?? self.tmdb?.name ?? titleId,
                        year: self.detail?.year,
                        userRating: self.detail?.userRating,
                        plotOverview: self.detail?.plotOverview,
                        genreNames: self.detail?.genreNames,
                        trailer: self.detail?.trailer,
                        posterUrl: self.detail?.posterUrl,
                        backdrop: self.detail?.backdrop,
                        releaseDate: self.detail?.releaseDate,
                        endYear: self.detail?.endYear,
                        runtimeMinutes: self.detail?.runtimeMinutes,
                        usRating: self.detail?.usRating,
                        type: self.detail?.type,
                        sources: [source]
                    )
                }
            }

            // TVDB enrichment fires after core data loads — non-blocking,
            // silently ignored on failure so the sheet always renders.
            Task { await enrichWithTVDB(tmdbId: tmdbId) }
        } else {
            do {
                let result = try await WatchmodeService.shared.titleDetail(titleId: titleId)
                detail = result
            } catch {
                errorMessage = error.localizedDescription
                loadedTitleId = nil
            }
        }
        isLoading = false
    }

    /// Looks up the TVDB series id from the TMDB id, then fetches the next
    /// upcoming episode and extended series info in parallel.
    private func enrichWithTVDB(tmdbId: Int) async {
        guard let tvdbId = try? await TheTVDBService.shared.tvdbSeriesId(forTMDBId: tmdbId)
        else { return }
        async let nextEp = try? TheTVDBService.shared.nextEpisode(seriesId: tvdbId)
        async let series = try? TheTVDBService.shared.seriesExtended(tvdbId)
        let (ep, s) = await (nextEp, series)
        tvdbNextEpisode = ep
        tvdbSeries = s
    }

    func loadSeason(_ seasonNumber: Int) async {
        guard let tmdbId = tmdb?.id else { return }
        currentSeasonNumber = seasonNumber
        season = try? await TMDBService.shared.getSeason(tmdbId: tmdbId, seasonNumber: seasonNumber)
    }

    var services: [WhereToWatchService] {
        guard let sources = detail?.sources else { return [] }

        func canonicalName(_ raw: String) -> String {
            let key = raw.lowercased()
            if key.contains("netflix") { return "Netflix" }
            if key.contains("max") || key.contains("hbo") { return "Max" }
            if key.contains("hulu") { return "Hulu" }
            if key.contains("disney") { return "Disney+" }
            if key.contains("apple") { return "Apple TV+" }
            if key.contains("prime") || key.contains("amazon") { return "Prime Video" }
            if key.contains("paramount") { return "Paramount+" }
            if key.contains("peacock") { return "Peacock" }
            if key.contains("youtube") { return "YouTube" }
            if key.contains("starz") { return "Starz" }
            if key.contains("showtime") { return "Showtime" }
            if key.contains("crunchyroll") { return "Crunchyroll" }
            return ""
        }

        var seen = Set<String>()
        var result: [WhereToWatchService] = []
        let subSources = sources
            .filter { $0.type.lowercased() == "sub" }
            .sorted { sourceRank($0) < sourceRank($1) }

        for s in subSources {
            let canonical = canonicalName(s.name)
            guard !canonical.isEmpty else { continue }
            if seen.contains(canonical) { continue }
            seen.insert(canonical)
            result.append(WhereToWatchService(
                id: canonical,
                name: canonical,
                color: brandColor(for: canonical),
                iosUrl: s.iosUrl,
                androidUrl: s.androidUrl,
                webUrl: s.webUrl,
                format: s.format
            ))
        }
        return result
    }

    /// First subscription source returned by Watchmode. Used to drive the
    /// orange CTA at the bottom of the screen and the service badges in the
    /// "Where to Watch" row.
    var primaryService: WhereToWatchService? { services.first }

    /// Best deep link URL (prefer iOS native scheme, then web) from the first
    /// subscription source. Filters out Watchmode free-tier placeholders that
    /// otherwise short-circuit `URL(string:)` callers into doing nothing.
    var primaryDeeplink: URL? {
        guard let s = services.first else { return nil }
        if let ios = s.iosUrl, Self.isRealURL(ios), let u = URL(string: ios) { return u }
        if let web = s.webUrl, Self.isRealURL(web), let u = URL(string: web) { return u }
        return nil
    }

    /// Watchmode's free tier returns the literal string
    /// `"Deeplinks available for paid plans only."` in `ios_url` / `android_url`.
    /// Anything that isn't a real http(s) URL must be rejected before we hand
    /// it to `UIApplication.shared.open`.
    private static func isRealURL(_ s: String) -> Bool {
        let lower = s.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return false }
        return URL(string: s) != nil
    }

    private func sourceRank(_ s: WatchmodeSource) -> Int {
        switch s.type.lowercased() {
        case "sub": return 0
        case "free": return 1
        case "tve": return 2
        case "rent": return 3
        case "buy": return 4
        default: return 5
        }
    }

    private func brandColor(for name: String) -> Color {
        let key = name.lowercased()
        if key.contains("netflix") { return Color(red: 0xE5/255, green: 0x09/255, blue: 0x14/255) }
        if key.contains("hbo") || key.contains("max") { return Color(red: 0x5B/255, green: 0x2D/255, blue: 0x8E/255) }
        if key.contains("hulu") { return Color(red: 0x1C/255, green: 0xE7/255, blue: 0x83/255) }
        if key.contains("disney") { return Color(red: 0.05, green: 0.10, blue: 0.42) }
        if key.contains("apple") { return Color(white: 0.12) }
        if key.contains("prime") || key.contains("amazon") { return Color(red: 0.0, green: 0.66, blue: 0.93) }
        if key.contains("paramount") { return Color(red: 0.0, green: 0.40, blue: 0.95) }
        if key.contains("peacock") { return Color(red: 0.05, green: 0.05, blue: 0.10) }
        if key.contains("youtube") { return Color(red: 0.90, green: 0.10, blue: 0.10) }
        return Color(white: 0.18)
    }
}

// MARK: - ShowDetailScreen

struct ShowDetailScreen: View {
    var titleId: String = "tt-succession"
    var title: String = "Succession"
    var posterUrl: String? = nil
    var backdropUrl: String? = nil
    var isTV: Bool = true
    var onBack: () -> Void = {}
    var onPlayOn: () -> Void = {}

    /// TMDB id parsed from `titleId` when possible — lets PlayOnBottomSheet
    /// resolve the real streaming source via Watchmode and deeplink to the
    /// correct title page.
    private var resolvedTmdbId: Int? { Int(titleId) }

    @State private var scrollOffset: CGFloat = 0
    @State private var synopsisExpanded: Bool = false
    @State private var liked: Bool = false
    @State private var notifyOn: Bool = true
    @State private var showComments: Bool = false
    @State private var streams = StreamsViewModel.shared
    @State private var selectedSeason: String = "Season 4"
    @State private var playOnOpen: Bool = false
    @State private var showMoreEpisodes: Bool = false
    @State private var vm = ShowDetailViewModel()

    private let platformId = "hbo"
    private let fallbackSynopsis = "The Roy family is known for controlling the biggest media and entertainment company in the world. However, their world changes when their father steps back from the company. As power shifts and alliances fracture, each sibling jockeys for control in a ruthless game of legacy, loyalty, and survival."

    private let fallbackGenres = ["Drama", "Satire", "Family"]

    private var synopsis: String { vm.tmdb?.overview ?? vm.detail?.plotOverview ?? fallbackSynopsis }
    private var genres: [String] {
        let names = vm.tmdb?.genreNames ?? vm.detail?.genreNames ?? []
        return names.isEmpty ? fallbackGenres : names
    }
    private var displayTitle: String { vm.tmdb?.name ?? vm.detail?.title ?? title }
    private var ratingText: String {
        if let r = vm.tmdb?.voteAverage { return String(format: "%.1f", r) }
        if let r = vm.detail?.userRating { return String(format: "%.1f", r) }
        return "4.8"
    }
    private var yearText: String {
        if let y = vm.tmdb?.year { return String(y) }
        if let y = vm.detail?.year { return String(y) }
        return "2024"
    }
    private var heroImageUrl: String? {
        vm.tmdb?.backdropUrl ?? backdropUrl ?? posterUrl
    }
    private var tmdbEpisodes: [TMDBEpisode] { vm.season?.episodes ?? [] }

    /// The most recent episode from the loaded season. Falls back to
    /// the last static fallback episode when TMDB data hasn't loaded yet.
    private var latestEpisode: (seasonNum: Int, episodeNum: Int, name: String, runtime: String)? {
        if let ep = tmdbEpisodes.last {
            let runtime = ep.runtime.map { "\($0) min" } ?? ""
            return (vm.currentSeasonNumber, ep.episodeNumber, ep.name ?? "Latest Episode", runtime)
        }
        if let ep = episodes.last {
            let season = parseSeason(ep.code)
            let epNum = parseEpisode(ep.code)
            return (season, epNum, ep.title, ep.duration)
        }
        return nil
    }

    /// Short service name for display inside the watch button badge.
    private var primaryServiceShortName: String? {
        guard let name = vm.primaryService?.name else { return nil }
        let key = name.lowercased()
        if key.contains("paramount") { return "P+" }
        if key.contains("disney") { return "D+" }
        if key.contains("apple") { return "TV+" }
        if key.contains("prime") || key.contains("amazon") { return "Prime" }
        if key.contains("peacock") { return "Peacock" }
        if key.contains("netflix") { return "Netflix" }
        if key.contains("hulu") { return "Hulu" }
        if key.contains("max") || key.contains("hbo") { return "Max" }
        if key.contains("crunchyroll") { return "Crunchyroll" }
        return name
    }

    private var isSaved: Bool {
        let key = titleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        return streams.userStreams.contains { $0.titleId == key }
    }

    /// Network / platform name for the subtitle. Prefers Watchmode's primary
    /// service over TMDB's networks so the label matches the badge below it
    /// (e.g. "Max" instead of "HBO" when a network has rebranded).
    private var networkName: String? {
        if let svc = vm.primaryService { return svc.name }
        return vm.tmdb?.networks?.first?.name
    }

    /// TVDB next-episode air date formatted for display (e.g. "Airs May 30, 2026").
    private var tvdbNextAirDateText: String? {
        guard let date = vm.tvdbNextEpisode?.airDate else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        return "Airs \(fmt.string(from: date))"
    }

    /// TVDB series status label. Falls back to TMDB status when TVDB unavailable.
    private var seriesStatusText: String? {
        vm.tvdbSeries?.status?.name ?? vm.tmdb?.status
    }

    private let episodes: [ShowDetailEpisode] = [
        .init(code: "S4 E7", title: "Tailgate Party", duration: "64 min", status: .continueWatching, progress: 0.45),
        .init(code: "S4 E8", title: "America Decides", duration: "67 min", status: .new, progress: 0),
        .init(code: "S4 E9", title: "Church and State", duration: "72 min", status: .none, progress: 0),
        .init(code: "S4 E10", title: "With Open Eyes", duration: "88 min", status: .none, progress: 0)
    ]

    var body: some View {
        ZStack(alignment: .top) {
            Color.navy.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    genresRow
                    socialCounter
                    whereToWatchSection
                    fanActivitySection
                    synopsisSection
                    episodesSection
                    Color.clear.frame(height: 140)
                }
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetKey.self,
                            value: -geo.frame(in: .named("showDetailScroll")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "showDetailScroll")
            .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = $0 }

            compactHeader
                .opacity(stickyOpacity)
                .offset(y: stickyOffset)
                .animation(.easeOut(duration: 0.18), value: scrollOffset > 220)
                .allowsHitTesting(stickyOpacity > 0.5)

            bottomActionBar
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)

            PlayOnBottomSheet(
                isOpen: playOnOpen,
                onClose: { playOnOpen = false },
                showTitle: displayTitle,
                showSubtitle: "Season 4 \u{00B7} Episode 7 \u{00B7} Tailgate Party",
                thumbnailUrl: posterUrl,
                tmdbId: resolvedTmdbId,
                isTV: isTV,
                onDeviceSelected: { _ in
                    playOnOpen = false
                    onPlayOn()
                }
            )
            .allowsHitTesting(playOnOpen)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showComments) {
            CommentsViewerSheet()
        }
        .onAppear {
            WatchIntentLogger.shared.log(
                eventType: .episodeDetailViewed,
                titleId: titleId
            )
        }
        .task(id: titleId) {
            await vm.loadIfNeeded(titleId: titleId, isTV: isTV)
            if let n = vm.tmdb?.numberOfSeasons {
                selectedSeason = "Season \(n)"
            }
        }
    }

    /// Opens the streaming app for a specific tapped service badge.
    ///
    /// Fast path: when the view-model already has a matching Watchmode
    /// source loaded (i.e. the user can see the service badge), feed its
    /// HTTPS `web_url` straight to `openResolvedURL` — iOS routes it
    /// into the streaming app via universal links so the app lands on
    /// the title page, not its home screen.
    ///
    /// Falls back to `StreamingDeepLinker.open` (which performs a fresh
    /// Watchmode lookup) if no matching source is loaded yet, or to a
    /// platform search URL when Watchmode can't resolve the title.
    private func openDeeplink(serviceName: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if let url = preResolvedURL(forService: serviceName) {
            StreamingDeepLinker.openResolvedURL(
                url,
                platform: serviceName,
                title: displayTitle,
                tmdbId: resolvedTmdbId,
                titleSlug: titleId
            )
            return
        }

        StreamingDeepLinker.open(
            platform: serviceName,
            title: displayTitle,
            tmdbId: resolvedTmdbId,
            isTV: isTV,
            titleSlug: titleId
        )
    }

    /// Looks up a title-specific URL for the tapped service from the
    /// view-model's cached Watchmode sources. Filters out Watchmode
    /// free-tier placeholders.
    private func preResolvedURL(forService serviceName: String) -> URL? {
        let key = serviceName.lowercased()
        let services = vm.services
        let match = services.first { svc in
            let n = svc.name.lowercased()
            if key.contains("netflix") { return n.contains("netflix") }
            if key.contains("hbo") || key.contains("max") { return n.contains("max") || n.contains("hbo") }
            if key.contains("hulu") { return n.contains("hulu") }
            if key.contains("disney") { return n.contains("disney") }
            if key.contains("apple") { return n.contains("apple tv") }
            if key.contains("prime") || key.contains("amazon") { return n.contains("amazon") || n.contains("prime") }
            if key.contains("paramount") { return n.contains("paramount") }
            if key.contains("peacock") { return n.contains("peacock") }
            if key.contains("youtube") { return n.contains("youtube") }
            return n.contains(key) || key.contains(n)
        } ?? services.first

        guard let svc = match else { return nil }
        if let s = svc.iosUrl, Self.isRealDeepLinkURL(s), let u = URL(string: s) { return u }
        if let s = svc.webUrl, Self.isRealDeepLinkURL(s), let u = URL(string: s) { return u }
        return nil
    }

    private static func isRealDeepLinkURL(_ s: String) -> Bool {
        let lower = s.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.contains("://") else { return false }
        if lower.contains("deeplinks available") || lower.contains("paid plan") { return false }
        return URL(string: s) != nil
    }

    private func toggleWatchList() {
        let key = titleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            if isSaved {
                await streams.removeFromMyStreams(titleId: key)
            } else {
                await streams.addToMyStreams(
                    titleId: key,
                    title: displayTitle,
                    posterUrl: posterUrl,
                    platform: vm.primaryService?.name
                )
            }
        }
    }

    private func openPlayOn() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        playOnOpen = true
    }

    /// Parses "S4 E7" into the integer season number.
    private func parseSeason(_ code: String) -> Int {
        let parts = code.split(separator: " ")
        guard let s = parts.first, s.hasPrefix("S") else { return 0 }
        return Int(s.dropFirst()) ?? 0
    }

    /// Parses "S4 E7" into the integer episode number.
    private func parseEpisode(_ code: String) -> Int {
        let parts = code.split(separator: " ")
        guard parts.count >= 2, parts[1].hasPrefix("E") else { return 0 }
        return Int(parts[1].dropFirst()) ?? 0
    }

    private var stickyOpacity: Double { scrollOffset > 220 ? 1 : 0 }
    private var stickyOffset: CGFloat { scrollOffset > 220 ? 0 : -8 }

    // MARK: Compact Header

    private var compactHeader: some View {
        ZStack {
            Color.navy.opacity(0.85)
                .background(.ultraThinMaterial)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                }

            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
                Text(displayTitle)
                    .scaledFont(size: 16, weight: .semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)

                PlayOnTriggerButton(compact: true, action: openPlayOn)
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 56)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: Hero

    private var hero: some View {
        GeometryReader { geo in
            let h = min(geo.size.width * 0.56, 280)
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [
                        Color(red: 0x1A/255, green: 0x05/255, blue: 0x33/255),
                        Color(red: 0x0A/255, green: 0x1F/255, blue: 0x52/255),
                        Color.navy
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                GridTexture().opacity(0.4).allowsHitTesting(false)

                if let heroUrl = heroImageUrl, let url = URL(string: heroUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .allowsHitTesting(false)
                        default:
                            Color.clear
                        }
                    }
                    .frame(width: geo.size.width, height: h)
                    .clipped()
                    .opacity(0.85)
                    .allowsHitTesting(false)

                    LinearGradient(
                        colors: [Color.navy.opacity(0.25), .clear, Color.navy],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }

                LinearGradient(
                    colors: [.clear, Color.navy],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: h * 0.55)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

                // Top chrome
                HStack {
                    glassRoundButton(symbol: "arrow.left", action: onBack)
                    Spacer()
                    glassRoundButton(symbol: "square.and.arrow.up", action: {})
                }
                .padding(.horizontal, 16)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 8)

                // Title block
                VStack(alignment: .leading, spacing: 10) {
                    Text(displayTitle)
                        .scaledFont(size: titleSize(for: geo.size.width), weight: .semibold, design: .default)
                        .foregroundStyle(.white)
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill")
                            .scaledFont(size: 12, weight: .bold)
                            .foregroundStyle(Color(red: 1, green: 0.78, blue: 0.2))
                        Text(ratingText)
                            .scaledFont(size: 13, weight: .semibold)
                            .foregroundStyle(.white)
                        dot
                        Text(yearText)
                            .scaledFont(size: 13)
                            .foregroundStyle(Color.textSecondary)
                        if let net = networkName {
                            dot
                            Text(net)
                                .scaledFont(size: 13, weight: .medium)
                                .foregroundStyle(Color.textSecondary)
                        }
                        dot
                        Text("TV-MA")
                            .scaledFont(size: 11, weight: .semibold)
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .frame(width: geo.size.width, height: h)
            .clipped()
        }
        .frame(height: min(UIScreen.main.bounds.width * 0.56, 280))
    }

    private var dot: some View {
        Text("·").scaledFont(size: 13).foregroundStyle(Color.textTertiary)
    }

    private func titleSize(for width: CGFloat) -> CGFloat {
        min(max(width * 0.09, 28), 40)
    }

    private func glassRoundButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .scaledFont(size: 15, weight: .semibold)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(Color.navy.opacity(0.55))
                        .background(.ultraThinMaterial, in: Circle())
                )
                .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Genres

    private var genresRow: some View {
        HStack(spacing: 8) {
            ForEach(genres, id: \.self) { g in
                Text(g)
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(Color.white.opacity(0.70))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: Social counter row

    private var socialCounter: some View {
        HStack(spacing: 16) {
            Button(action: { showComments = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .scaledFont(size: 14, weight: .bold)
                        .foregroundStyle(Color.orange)
                    Text("24.8K")
                        .scaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)

            Button(action: { showComments = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left")
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(Color.white.opacity(0.75))
                    Text("3.1K")
                        .scaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    // MARK: Next Episode (TVDB)

    /// Shows the next upcoming episode air date from TVDB, plus series status.
    /// Hidden when no TVDB data has loaded yet.
    private var nextEpisodeBanner: some View {
        HStack(spacing: 12) {
            // Left: episode thumbnail / placeholder
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "sparkles")
                        .scaledFont(size: 18, weight: .semibold)
                        .foregroundStyle(Color.orange)
                }

            // Right: episode details
            VStack(alignment: .leading, spacing: 3) {
                if let ep = vm.tvdbNextEpisode {
                    HStack(spacing: 4) {
                        Text("S\(ep.seasonNumber ?? 0) E\(ep.episodeNumber ?? 0)")
                            .scaledFont(size: 12, weight: .heavy)
                            .foregroundStyle(Color.orange)
                        if let name = ep.name {
                            Text("•")
                                .scaledFont(size: 12)
                                .foregroundStyle(Color.textTertiary)
                            Text(name)
                                .scaledFont(size: 13, weight: .semibold)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                    }
                }
                HStack(spacing: 6) {
                    if let airText = tvdbNextAirDateText {
                        Label(airText, systemImage: "calendar")
                            .scaledFont(size: 12)
                            .foregroundStyle(Color.textSecondary)
                    }
                    if let status = seriesStatusText {
                        Text("•")
                            .scaledFont(size: 12)
                            .foregroundStyle(Color.textTertiary)
                        Text(status)
                            .scaledFont(size: 12, weight: .medium)
                            .foregroundStyle(status.lowercased().contains("returning") ? Color.green : Color.textSecondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: Synopsis

    private var synopsisSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("About")
                .scaledFont(size: 17, weight: .semibold)
                .foregroundStyle(.white)

            Text(synopsis)
                .scaledFont(size: 14)
                .foregroundStyle(Color.textSecondary)
                .lineSpacing(4)
                .lineLimit(synopsisExpanded ? nil : 3)

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) { synopsisExpanded.toggle() }
            }) {
                Text(synopsisExpanded ? "Less" : "More")
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(Color.orange)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    // MARK: Episodes

    private var episodesSection: some View {
        EpisodeAvailabilitySection(
            tmdbId: resolvedTmdbId,
            isTV: isTV,
            titleId: titleId,
            onEpisodeTap: { row in
                if case .available(_, _, let url) = row.state, let url = url {
                    UIApplication.shared.open(url)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        )
        .padding(.top, 8)
    }

    // MARK: Where to Watch

    private var whereToWatchSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Where to Watch")
                .scaledFont(size: 17, weight: .semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 20)

            let services = vm.services
            if services.isEmpty {
                Text(vm.isLoading ? "Finding services…" : "No streaming sources found.")
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(services) { s in
                            Button {
                                openDeeplink(serviceName: s.name)
                            } label: {
                                ServiceBadge(service: s)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .padding(.top, 24)
    }

    // MARK: Fan activity

    private var fanActivitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Fan Activity")
                .scaledFont(size: 15, weight: .semibold)
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                fanButton(label: "24.8K", filled: liked) {
                    LikeIcon(liked: liked)
                } action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { liked.toggle() }
                }

                fanButton(label: "3.1K") {
                    Image(systemName: "bubble.left")
                        .scaledFont(size: 18, weight: .semibold)
                        .foregroundStyle(.white)
                } action: {
                    showComments = true
                }

                fanButton(label: isSaved ? "Saved" : "Save") {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .scaledFont(size: 18, weight: .semibold)
                        .foregroundStyle(isSaved ? Color.orange : .white)
                } action: {
                    toggleWatchList()
                }

                fanButton(label: "Notify", showDot: notifyOn) {
                    Image(systemName: notifyOn ? "bell.fill" : "bell")
                        .scaledFont(size: 18, weight: .semibold)
                        .foregroundStyle(.white)
                } action: {
                    withAnimation { notifyOn.toggle() }
                }
            }
        }
        .padding(16)
        .glassCard()
        .padding(.horizontal, 20)
        .padding(.top, 24)
    }

    @ViewBuilder
    private func fanButton<Icon: View>(
        label: String,
        filled: Bool = false,
        showDot: Bool = false,
        @ViewBuilder icon: () -> Icon,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 8) {
            Button(action: action) {
                icon()
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Color.white.opacity(0.07)))
                    .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))
                    .overlay(alignment: .topTrailing) {
                        if showDot {
                            Circle()
                                .fill(Color(red: 0.20, green: 0.78, blue: 0.35))
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(Color.navy, lineWidth: 2))
                                .offset(x: 2, y: -2)
                        }
                    }
            }
            .buttonStyle(.plain)

            Text(label)
                .scaledFont(size: 11, weight: .semibold)
                .foregroundStyle(Color.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Bottom action bar

    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)

            VStack(spacing: 10) {

                // Episode context strip
                if let ep = latestEpisode {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 38, height: 26)
                            .overlay(
                                Image(systemName: "play.fill")
                                    .scaledFont(size: 8, weight: .bold)
                                    .foregroundStyle(Color.white.opacity(0.45))
                            )

                        VStack(alignment: .leading, spacing: 1) {
                            Text("S\(ep.seasonNum) · E\(ep.episodeNum) · Most recent")
                                .scaledFont(size: 9, weight: .semibold)
                                .foregroundStyle(Color.white.opacity(0.38))
                            Text("\(ep.name)\(ep.runtime.isEmpty ? "" : " · \(ep.runtime)")")
                                .scaledFont(size: 11, weight: .semibold)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        Text("NEW")
                            .scaledFont(size: 7, weight: .heavy)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Color.orange)
                            )
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
                            )
                    )
                }

                // Primary watch button + Watch List circle (side by side,
                // same layout as before — circle button preserved exactly)
                HStack(spacing: 8) {
                    Button(action: {
                        if let svc = vm.primaryService {
                            openDeeplink(serviceName: svc.name)
                        } else {
                            WatchIntentLogger.shared.log(
                                eventType: .deeplinkFired,
                                titleId: titleId,
                                platformId: platformId
                            )
                            openPlayOn()
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .scaledFont(size: 15, weight: .bold)

                            if let ep = latestEpisode {
                                Text("Watch S\(ep.seasonNum) E\(ep.episodeNum)")
                                    .scaledFont(size: 15, weight: .bold)
                            } else {
                                Text("Watch Now")
                                    .scaledFont(size: 15, weight: .bold)
                            }

                            if let badge = primaryServiceShortName {
                                Text(badge.uppercased())
                                    .scaledFont(size: 9, weight: .heavy)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .fill(Color.white.opacity(0.22))
                                    )
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Capsule().fill(Color.orange))
                        .shadow(color: Color.orange.opacity(0.35), radius: 14, y: 6)
                    }
                    .buttonStyle(.plain)

                    Button(action: toggleWatchList) {
                        Image(systemName: isSaved ? "checkmark" : "plus")
                            .scaledFont(size: 20, weight: .bold)
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(isSaved ? Color.orange.opacity(0.20) : Color.white.opacity(0.08)))
                            .overlay(Circle().stroke(isSaved ? Color.orange : Color.white.opacity(0.14), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                // Two outlined secondary buttons
                HStack(spacing: 8) {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showMoreEpisodes = true
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "list.bullet")
                                .scaledFont(size: 12, weight: .semibold)
                                .foregroundStyle(Color.white.opacity(0.55))
                            Text("More episodes")
                                .scaledFont(size: 12, weight: .semibold)
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            Capsule().fill(Color.white.opacity(0.05))
                        )
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onBack()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "info.circle")
                                .scaledFont(size: 12, weight: .semibold)
                                .foregroundStyle(Color.white.opacity(0.55))
                            Text("Full details")
                                .scaledFont(size: 12, weight: .semibold)
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            Capsule().fill(Color.white.opacity(0.05))
                        )
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .background(
                Color.navy.opacity(0.90)
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
        .fullScreenCover(isPresented: $showMoreEpisodes) {
            MoreEpisodesScreen(
                titleId: titleId,
                title: displayTitle,
                posterUrl: posterUrl,
                isTV: isTV,
                onBack: { showMoreEpisodes = false }
            )
        }
    }
}

// MARK: - Like Icon with bounce

private struct LikeIcon: View {
    let liked: Bool
    var body: some View {
        Image(systemName: liked ? "heart.fill" : "heart")
            .scaledFont(size: 18, weight: .semibold)
            .foregroundStyle(liked ? Color.orange : .white)
            .scaleEffect(liked ? 1.15 : 1.0)
    }
}

// MARK: - Episode small card

private struct EpisodeCardSmall: View {
    let episode: ShowDetailEpisode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.black
                .frame(width: 148, height: 88)
                .overlay {
                    LinearGradient(
                        colors: [
                            Color(red: 0.20, green: 0.10, blue: 0.45),
                            Color(red: 0.06, green: 0.08, blue: 0.22)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .allowsHitTesting(false)
                }
                .overlay {
                    Image(systemName: "play.fill")
                        .scaledFont(size: 28, weight: .regular)
                        .foregroundStyle(.white.opacity(0.6))
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .topLeading) {
                    statusBadge
                        .padding(8)
                }
                .overlay(alignment: .bottom) {
                    if episode.progress > 0 {
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.white.opacity(0.15))
                                .frame(height: 4)
                            Rectangle().fill(Color.orange)
                                .frame(width: 148 * episode.progress, height: 4)
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: 10))

            HStack {
                Text(episode.code)
                    .scaledFont(size: 11, weight: .bold)
                    .foregroundStyle(Color.textTertiary)
                Spacer()
                Text(episode.duration)
                    .scaledFont(size: 11)
                    .foregroundStyle(Color.textTertiary)
            }

            Text(episode.title)
                .scaledFont(size: 13, weight: .semibold)
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .frame(width: 148, alignment: .leading)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch episode.status {
        case .continueWatching:
            Text("CONTINUE")
                .scaledFont(size: 9, weight: .heavy)
                .foregroundStyle(Color.orange)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.orange.opacity(0.20)))
                .overlay(Capsule().stroke(Color.orange.opacity(0.45), lineWidth: 1))
        case .new:
            Text("NEW")
                .scaledFont(size: 9, weight: .heavy)
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.orange))
        case .none:
            EmptyView()
        }
    }
}

// MARK: - TMDB Episode small card

private struct TMDBEpisodeCardSmall: View {
    let episode: TMDBEpisode
    let seasonNumber: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color(red: 0x2D/255, green: 0x14/255, blue: 0x54/255)
                .frame(width: 148, height: 88)
                .overlay {
                    LinearGradient(
                        colors: [
                            Color(red: 0x2D/255, green: 0x14/255, blue: 0x54/255),
                            Color(red: 0x0D/255, green: 0x2D/255, blue: 0x6E/255)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .allowsHitTesting(false)
                }
                .overlay {
                    if let stillUrl = episode.stillUrl, let url = URL(string: stillUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().aspectRatio(contentMode: .fill)
                            default:
                                Image(systemName: "play.fill")
                                    .scaledFont(size: 28, weight: .regular)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        .frame(width: 148, height: 88)
                        .clipped()
                        .allowsHitTesting(false)
                    } else {
                        Image(systemName: "play.fill")
                            .scaledFont(size: 28, weight: .regular)
                            .foregroundStyle(.white.opacity(0.6))
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(.rect(cornerRadius: 10))

            HStack {
                Text("S\(seasonNumber) E\(episode.episodeNumber)")
                    .scaledFont(size: 11, weight: .bold)
                    .foregroundStyle(Color.textTertiary)
                Spacer()
                if let r = episode.runtime, r > 0 {
                    Text("\(r) min")
                        .scaledFont(size: 11)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            Text(episode.name ?? "Episode \(episode.episodeNumber)")
                .scaledFont(size: 13, weight: .semibold)
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .frame(width: 148, alignment: .leading)
    }
}

// MARK: - Service badge

private struct ServiceBadge: View {
    let service: WhereToWatchService

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(service.color)
                .frame(width: 8, height: 8)
            Text(service.name)
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(service.color.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(service.color.opacity(0.45), lineWidth: 1)
        )
    }
}

// MARK: - PlayOn trigger

struct PlayOnTriggerButton: View {
    var compact: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "tv")
                    .scaledFont(size: 14, weight: .semibold)
                Text("Play on")
                    .scaledFont(size: 12, weight: .semibold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 12 : 16)
            .frame(width: compact ? 90 : 110, height: compact ? 32 : 40)
            .background(Capsule().fill(Color.white.opacity(0.12)))
            .overlay(Capsule().stroke(Color.white.opacity(0.20), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Grid texture

private struct GridTexture: View {
    var body: some View {
        Canvas { ctx, size in
            let spacing: CGFloat = 40
            let color = Color.white.opacity(0.04)
            var x: CGFloat = 0
            while x <= size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(path, with: .color(color), lineWidth: 1)
                x += spacing
            }
            var y: CGFloat = 0
            while y <= size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(path, with: .color(color), lineWidth: 1)
                y += spacing
            }
        }
    }
}

// MARK: - Scroll offset key

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Comments Viewer Sheet

struct CommentsViewerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .comments

    enum Tab: Hashable { case likes, comments }

    private let likes: [(name: String, color: Color)] = [
        ("Alex Carter", Color(red: 0.95, green: 0.45, blue: 0.10)),
        ("Sam Lin", Color(red: 0.18, green: 0.55, blue: 0.95)),
        ("Priya Shah", Color(red: 0.60, green: 0.25, blue: 0.85)),
        ("Jules Park", Color(red: 0.20, green: 0.78, blue: 0.55)),
        ("Mara Vance", Color(red: 0.95, green: 0.30, blue: 0.45)),
        ("Theo Ward", Color(red: 0.30, green: 0.70, blue: 0.90))
    ]

    private let comments: [(name: String, time: String, text: String, color: Color)] = [
        ("Alex Carter", "2h", "Kendall's monologue this week was unreal. Best episode of the season.", Color(red: 0.95, green: 0.45, blue: 0.10)),
        ("Sam Lin", "4h", "Shiv's storyline is what's keeping me hooked.", Color(red: 0.18, green: 0.55, blue: 0.95)),
        ("Priya Shah", "8h", "Cinematography is on another level lately.", Color(red: 0.60, green: 0.25, blue: 0.85)),
        ("Jules Park", "1d", "Roman fans where you at 😭", Color(red: 0.20, green: 0.78, blue: 0.55)),
        ("Mara Vance", "1d", "The pacing in this season finale was perfect.", Color(red: 0.95, green: 0.30, blue: 0.45))
    ]

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.25))
                .frame(width: 40, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 14)

            HStack(spacing: 0) {
                tabButton("Likes", .likes)
                tabButton("Comments", .comments)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 12) {
                    if tab == .likes {
                        ForEach(likes.indices, id: \.self) { i in
                            likeRow(name: likes[i].name, color: likes[i].color)
                        }
                    } else {
                        ForEach(comments.indices, id: \.self) { i in
                            commentRow(comments[i])
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.navy.ignoresSafeArea())
        .presentationDetents([.fraction(0.8), .large])
        .presentationDragIndicator(.hidden)
        .presentationContentInteraction(.scrolls)
    }

    private func tabButton(_ label: String, _ value: Tab) -> some View {
        Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { tab = value } }) {
            VStack(spacing: 8) {
                Text(label)
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(tab == value ? .white : Color.textSecondary)
                Rectangle()
                    .fill(tab == value ? Color.orange : Color.clear)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func likeRow(name: String, color: Color) -> some View {
        HStack(spacing: 12) {
            avatar(name: name, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(.white)
                Text("liked this")
                    .scaledFont(size: 12)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "heart.fill")
                .scaledFont(size: 14, weight: .bold)
                .foregroundStyle(Color.orange)
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(.rect(cornerRadius: 12))
    }

    private func commentRow(_ c: (name: String, time: String, text: String, color: Color)) -> some View {
        HStack(alignment: .top, spacing: 12) {
            avatar(name: c.name, color: c.color)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(c.name)
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(.white)
                    Text(c.time)
                        .scaledFont(size: 11)
                        .foregroundStyle(Color.textTertiary)
                }
                Text(c.text)
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.textPrimary.opacity(0.85))
                    .lineSpacing(3)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(.rect(cornerRadius: 12))
    }

    private func avatar(name: String, color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 36, height: 36)
            .overlay {
                Text(initials(name))
                    .scaledFont(size: 13, weight: .bold)
                    .foregroundStyle(.white)
            }
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined()
    }
}

#Preview {
    ShowDetailScreen()
}

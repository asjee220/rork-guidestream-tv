//
//  MacTitleSheet.swift
//  GuideStreamTVMac
//
//  Title detail, laid out like tvOS TVTitleSheet (GUI-88): a full-bleed
//  backdrop hero with the cadence badge, tracked uppercase wordmark, service
//  mark + "Series · Genre" line, the targeted episode (or synopsis), the
//  year · runtime fact line and the action row — "Watch on <mark>" pill,
//  then Watchlist, Watched? and Like circles. Below it the same sections in
//  the same order: Episodes (season pills + stills), Trailers & Clips,
//  More Like This, Details, Cast.
//
//  Same data and rules as tvOS: TVWatchmodeResolver with season/episode,
//  the latest aired episode pre-targeted, subscription-first watch logic
//  (one owned service opens directly; several — or only rent/buy — asks).
//  Mac differences: sources open their web player (no streaming apps on
//  macOS), trailers play in-app, and More Like This swaps the sheet's title.
//

import SwiftUI

struct MacTitleSheet: View {
    let ref: MacTitleRef
    @Environment(\.dismiss) private var dismiss

    @State private var current: MacTitleRef
    @State private var streams = TVStreamsViewModel.shared
    @State private var social = SocialViewModel.shared

    @State private var resolved: TVWatchmodeResolver.TVResolvedStreaming?
    @State private var isResolving = false
    @State private var didProbeMediaType = false
    @State private var backdropUrl: String?
    @State private var selectedServiceName: String?
    @State private var showWatchOptions = false

    @State private var season = 1
    @State private var episode = 1
    @State private var seasonSummaries: [TMDBSeasonSummary] = []
    @State private var browsingSeason = 1
    @State private var episodes: [TMDBEpisode] = []
    @State private var recommendations: [TVTMDBResult] = []
    @State private var titleVideos: [TVTitleVideo] = []
    @State private var cast: [TMDBCastMember] = []
    @State private var genreText: String?
    @State private var cadenceBadge: String?
    @State private var playingVideo: TVTitleVideo?
    /// Report a problem (A) and the "Did it open?" return check (C).
    @State private var reportContext: ReportContext?
    @State private var returnPrompt: DeepLinkReturnCheck.Pending?

    init(ref: MacTitleRef) {
        self.ref = ref
        _current = State(initialValue: ref)
    }

    private var tmdbId: Int? { current.tmdbId }
    private var isTV: Bool {
        if current.tmdbId != nil { return current.isTV }
        return resolved?.resolvedMediaType == "tv"
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MacColor.navy
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        hero.id("top")
                        VStack(alignment: .leading, spacing: 40) {
                            if isTV, !episodes.isEmpty { episodesSection }
                            if !titleVideos.isEmpty { trailersSection }
                            if !recommendations.isEmpty { moreLikeThisSection }
                            detailsSection
                            if !cast.isEmpty { castSection }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                    }
                }
                .onChange(of: current.id) { _, _ in proxy.scrollTo("top", anchor: .top) }
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .padding(16)

            if let prompt = returnPrompt {
                MacReturnCheckBanner(
                    pending: prompt,
                    onYes: {
                        DeepLinkReturnCheck.shared.record(prompt, opened: true)
                        returnPrompt = nil
                    },
                    onNo: {
                        DeepLinkReturnCheck.shared.record(prompt, opened: false)
                        returnPrompt = nil
                        reportContext = prompt.reportContext
                    },
                    onDismiss: { returnPrompt = nil }
                )
                .padding(.top, 60)
                .frame(maxWidth: .infinity, alignment: .top)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(width: 1100, height: 800)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            DeepLinkReturnCheck.shared.noteLeft()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if let prompt = DeepLinkReturnCheck.shared.consumeOnReturn() {
                withAnimation(.easeOut(duration: 0.2)) { returnPrompt = prompt }
            }
        }
        .sheet(item: $reportContext) { ctx in
            MacReportProblemSheet(context: ctx, onClose: { reportContext = nil })
        }
        .task(id: current.id) { await loadAll() }
        .sheet(item: $playingVideo) { video in
            VStack(spacing: 0) {
                MacYouTubePlayer(videoId: video.key)
                    .frame(width: 960, height: 540)
                HStack {
                    Text(video.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Button("Done") { playingVideo = nil }.keyboardShortcut(.cancelAction)
                }
                .padding(12)
            }
            .background(MacColor.navy)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geo in
                TVRemoteImage(urlString: backdropUrl ?? current.backdropUrl ?? current.posterUrl, contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .overlay {
                        LinearGradient(colors: [.black.opacity(0.25), .black.opacity(0.75), MacColor.navy],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .overlay {
                        LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .leading, endPoint: .center)
                    }
            }

            VStack(alignment: .leading, spacing: 14) {
                if let cadenceBadge {
                    Text(cadenceBadge)
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(.black.opacity(0.55), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
                }
                Text(current.title.uppercased())
                    .font(.system(size: 46, weight: .heavy))
                    .tracking(9)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                HStack(spacing: 10) {
                    TVServiceBrandMark(providerName: playServiceName, size: 24)
                    Text(heroMetaLine).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                }
                if let line = heroEpisodeLine {
                    line.font(.system(size: 14)).foregroundStyle(.white.opacity(0.78))
                        .lineLimit(3).frame(maxWidth: 640, alignment: .leading)
                } else if let synopsis = synopsisText {
                    Text(synopsis).font(.system(size: 14)).foregroundStyle(.white.opacity(0.78))
                        .lineLimit(3).frame(maxWidth: 640, alignment: .leading)
                }
                if !heroFactLine.isEmpty {
                    Text(heroFactLine).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.72))
                }
                HStack(alignment: .top, spacing: 16) {
                    watchButton
                    circleAction(isSaved ? "checkmark.circle.fill" : "plus.circle.fill", tint: .white, help: isSaved ? "In your watchlist" : "Add to watchlist") {
                        Task { await toggleWatchlist() }
                    }
                    circleAction(isWatched ? "eye.fill" : "eye", tint: isWatched ? MacColor.blue : .white,
                                 caption: isWatched ? "Watched" : "Watched?", help: "Mark watched") {
                        Task { await social.toggleWatched(titleId: current.titleId, titleName: current.title,
                                                          mediaType: isTV ? "tv" : "movie", tmdbId: tmdbId) }
                    }
                    circleAction(isLiked ? "heart.fill" : "heart", tint: isLiked ? MacColor.orange : .white, help: "Like") {
                        Task { await social.toggleLike(titleId: current.titleId, mediaType: isTV ? "tv" : "movie", tmdbId: tmdbId) }
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 44)
            .padding(.bottom, 30)
        }
        .frame(height: 500)
    }

    private func circleAction(_ icon: String, tint: Color, caption: String? = nil, help: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color.white.opacity(0.10)))
                if let caption {
                    Text(caption).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var watchButton: some View {
        Button(action: launchWatch) {
            HStack(spacing: 10) {
                if isResolving && resolved == nil {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "play.fill").font(.system(size: 15, weight: .bold))
                }
                Text("Watch on").font(.system(size: 15, weight: .semibold))
                TVServiceBrandMark(providerName: playServiceName, size: 26)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.16)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.18), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isResolving && resolved == nil)
        .popover(isPresented: $showWatchOptions, arrowEdge: .bottom) { watchOptionsPopover }
    }

    private var watchOptionsPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Watch \(current.title)").font(.system(size: 13, weight: .bold)).padding(.bottom, 2)
            ForEach(watchOptions, id: \.sourceId) { src in
                Button {
                    selectedServiceName = src.name
                    showWatchOptions = false
                    open(src)
                } label: {
                    HStack(spacing: 10) {
                        TVServiceBrandMark(providerName: src.name, size: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Platform.from(providerName: src.name)?.displayName ?? src.name)
                                .font(.system(size: 13, weight: .semibold))
                            Text(kindLabel(src)).font(.system(size: 11)).foregroundStyle(MacColor.text3)
                        }
                        Spacer(minLength: 20)
                        Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold)).foregroundStyle(MacColor.text2)
                    }
                    .padding(8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    // MARK: - Hero text

    private var synopsisText: String? {
        if let o = resolved?.overview, !o.isEmpty { return o }
        if let o = current.overview, !o.isEmpty { return o }
        return nil
    }

    private var heroMetaLine: String {
        var parts = [isTV ? "Series" : "Movie"]
        if let genreText, !genreText.isEmpty { parts.append(genreText) }
        return parts.joined(separator: " · ")
    }

    private var targetedEpisode: TMDBEpisode? {
        episodes.first { $0.episodeNumber == episode && ($0.seasonNumber ?? browsingSeason) == season }
    }

    private var heroEpisodeLine: Text? {
        guard isTV, let ep = targetedEpisode else { return nil }
        let name = ep.name ?? "Episode \(ep.episodeNumber)"
        let head = Text("S\(season), E\(episode) · \(name):").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
        guard let overview = ep.overview, !overview.isEmpty else { return head }
        return head + Text("  " + overview)
    }

    private var heroFactLine: String {
        var parts: [String] = []
        if let year = current.year { parts.append(String(year)) }
        if let runtime = targetedEpisode?.runtime { parts.append("\(runtime)m") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Watch logic (tvOS TVTitleSheet rules)

    private var usSources: [TVWatchmodeResolver.TVResolvedSource] { resolved?.usSources ?? [] }

    private var activeSource: TVWatchmodeResolver.TVResolvedSource? {
        if let selected = selectedServiceName,
           AuthViewModel.shared.subscribesToService(named: selected),
           let match = usSources.first(where: { $0.name == selected }) { return match }
        return resolved?.primarySource
    }

    private var playServiceName: String {
        if let n = activeSource?.name, !n.isEmpty { return n }
        if let n = resolved?.providerNameFallback, !n.isEmpty { return n }
        return "Streaming"
    }

    private func isTransactional(_ s: TVWatchmodeResolver.TVResolvedSource) -> Bool {
        ["rent", "buy", "purchase"].contains(s.type.lowercased())
    }

    private var subscribedSources: [TVWatchmodeResolver.TVResolvedSource] {
        usSources.filter { !isTransactional($0) && AuthViewModel.shared.subscribesToService(named: $0.name) }
    }
    private var transactionalSources: [TVWatchmodeResolver.TVResolvedSource] { usSources.filter(isTransactional) }

    /// Owned first, then rent/buy; one row per service name. Free and other
    /// subscriptions follow so the popover is also a complete Where to Watch.
    private var watchOptions: [TVWatchmodeResolver.TVResolvedSource] {
        var seen = Set<String>()
        let rest = usSources.filter { s in !subscribedSources.contains { $0.sourceId == s.sourceId }
            && !transactionalSources.contains { $0.sourceId == s.sourceId } }
        return (subscribedSources + transactionalSources + rest)
            .filter { webURL(for: $0) != nil && seen.insert($0.name.lowercased()).inserted }
    }

    private var subscribedLabelName: String? {
        [activeSource.flatMap { isTransactional($0) ? nil : $0.name }, resolved?.providerNameFallback]
            .compactMap { $0 }.filter { !$0.isEmpty }
            .first { AuthViewModel.shared.subscribesToService(named: $0) }
    }

    private var needsWatchOptions: Bool {
        if subscribedSources.count >= 2 { return true }
        if subscribedSources.isEmpty, subscribedLabelName == nil, transactionalSources.count >= 2 { return true }
        return false
    }

    private func launchWatch() {
        if subscribedSources.count == 1 {
            open(subscribedSources[0])
        } else if subscribedSources.isEmpty, let owned = subscribedLabelName,
                  let src = usSources.first(where: { TVDeepLinkResolver.isSameBrand($0.name, owned) }) {
            open(src)
        } else if needsWatchOptions || activeSource.flatMap(webURL(for:)) == nil {
            showWatchOptions = !watchOptions.isEmpty
        } else if let src = activeSource {
            open(src)
        }
    }

    private func episodeSource(matching s: TVWatchmodeResolver.TVResolvedSource) -> TVWatchmodeResolver.TVResolvedSource? {
        guard let ep = resolved?.episodeSource, ep.sourceId == s.sourceId else { return nil }
        return ep
    }

    private func webURL(for s: TVWatchmodeResolver.TVResolvedSource) -> URL? {
        TVDeepLinkResolver.webURL(for: s, episode: episodeSource(matching: s))
    }

    private func open(_ s: TVWatchmodeResolver.TVResolvedSource) {
        guard let url = webURL(for: s) else { return }
        var meta: [String: Any] = ["source": "mac_title_sheet_watch", "media_type": isTV ? "tv" : "movie", "source_type": s.type]
        if let tmdbId { meta["tmdb_id"] = tmdbId }
        WatchIntentLogger.shared.log(eventType: .deeplinkFired, titleId: current.titleId,
                                     platformId: Platform.from(providerName: s.name)?.catalogId ?? s.name,
                                     metadata: meta)
        DeepLinkReturnCheck.shared.arm(title: current.title, platform: s.name, tmdbId: tmdbId, titleId: current.titleId)
        MacLinkOpener.open(url)
    }

    private func kindLabel(_ s: TVWatchmodeResolver.TVResolvedSource) -> String {
        switch s.type.lowercased() {
        case "sub": return AuthViewModel.shared.subscribesToService(named: s.name) ? "Included with your plan" : "Subscription"
        case "free": return "Free"
        case "rent": return s.price.map { String(format: "Rent · $%.2f", $0) } ?? "Rent"
        case "buy", "purchase": return s.price.map { String(format: "Buy · $%.2f", $0) } ?? "Buy"
        default: return s.type.capitalized
        }
    }

    // MARK: - Watchlist / social

    /// TMDB titles are saved by the bare id (as the phones write them); older
    /// tvOS rows used "tmdb:tv:" — both count as saved.
    private var watchlistId: String { tmdbId.map(String.init) ?? current.titleId }
    private var isSaved: Bool { streams.contains(titleId: watchlistId) || streams.contains(titleId: current.titleId) }
    private var isLiked: Bool { social.isLiked(current.titleId) }
    private var isWatched: Bool { social.isWatched(current.titleId) }

    private func toggleWatchlist() async {
        if isSaved {
            if streams.contains(titleId: watchlistId) { await streams.remove(titleId: watchlistId) }
            if streams.contains(titleId: current.titleId) { await streams.remove(titleId: current.titleId) }
        } else {
            await streams.add(titleId: watchlistId, title: current.title, posterUrl: current.posterUrl,
                              platform: activeSource?.name ?? resolved?.providerNameFallback,
                              isTV: tmdbId == nil ? nil : isTV)
        }
    }

    // MARK: - Sections

    private func sectionHeader(_ title: String, accent: Color = MacColor.orange) -> some View {
        HStack(spacing: 10) {
            Capsule().fill(accent).frame(width: 4, height: 20).shadow(color: accent.opacity(0.65), radius: 6)
            Text(title).font(.system(size: 19, weight: .heavy))
        }
        .padding(.horizontal, 44)
    }

    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Episodes")
            if seasonSummaries.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(seasonSummaries, id: \.id) { s in
                            let n = s.seasonNumber ?? 1
                            Button {
                                browsingSeason = n
                                Task { await loadEpisodes(season: n) }
                            } label: {
                                Text(s.name ?? "Season \(n)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(n == browsingSeason ? Color.black : MacColor.text2)
                                    .padding(.horizontal, 16).padding(.vertical, 7)
                                    .background(n == browsingSeason ? Color.white.opacity(0.92) : Color.white.opacity(0.10), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 44)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(episodes, id: \.id) { ep in episodeCard(ep) }
                }
                .padding(.horizontal, 44)
                .padding(.vertical, 4)
            }
        }
    }

    /// Selecting an episode targets it and watches it — the same as tvOS.
    private func episodeCard(_ ep: TMDBEpisode) -> some View {
        let isTarget = (ep.seasonNumber ?? browsingSeason) == season && ep.episodeNumber == episode
        return MacHoverCard(selected: isTarget) {
            season = ep.seasonNumber ?? browsingSeason
            episode = ep.episodeNumber
            Task {
                await resolveStreamingData()
                launchWatch()
            }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomLeading) {
                    Color(white: 0.06)
                        .overlay { TVRemoteImage(urlString: ep.stillUrl, contentMode: .fill).allowsHitTesting(false) }
                        .overlay { LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .bottom, endPoint: .center) }
                    if let runtime = ep.runtime {
                        Text("\(runtime)m").font(.system(size: 11, weight: .semibold)).padding(8)
                    }
                }
                .frame(width: 280, height: 158)
                .clipShape(RoundedRectangle(cornerRadius: MacLayout.cardRadius))
                VStack(alignment: .leading, spacing: 3) {
                    Text("EPISODE \(ep.episodeNumber)").font(.system(size: 10, weight: .heavy)).tracking(1)
                        .foregroundStyle(MacColor.text2)
                    Text(ep.name ?? "Episode \(ep.episodeNumber)").font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                    if let o = ep.overview, !o.isEmpty {
                        Text(o).font(.system(size: 12)).foregroundStyle(MacColor.text2).lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    if let air = ep.airDate, !air.isEmpty {
                        Text(air).font(.system(size: 11, weight: .medium)).foregroundStyle(MacColor.text3)
                    }
                }
                .frame(width: 280, alignment: .leading)
            }
        }
    }

    private var trailersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Trailers & Clips", accent: MacColor.blue)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(titleVideos) { video in
                        MacHoverCard(selected: false) {
                            WatchIntentLogger.shared.log(eventType: .cardTapped, titleId: current.titleId,
                                                         metadata: ["section": "trailers_and_clips", "video_id": video.key,
                                                                    "video_type": video.type, "surface": "mac_title_sheet"])
                            playingVideo = video
                        } content: {
                            VStack(alignment: .leading, spacing: 8) {
                                ZStack(alignment: .bottomLeading) {
                                    Color(white: 0.06)
                                        .overlay { TVRemoteImage(urlString: video.thumbnailURL, contentMode: .fill).allowsHitTesting(false) }
                                        .overlay { LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .bottom, endPoint: .center) }
                                    HStack(spacing: 6) {
                                        Image(systemName: "play.circle.fill").font(.system(size: 16, weight: .bold))
                                        Text(video.type).font(.system(size: 12, weight: .semibold))
                                    }
                                    .padding(10)
                                }
                                .frame(width: 260, height: 146)
                                .clipShape(RoundedRectangle(cornerRadius: MacLayout.cardRadius))
                                Text(video.name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(MacColor.text2)
                                    .lineLimit(2).multilineTextAlignment(.leading)
                                    .frame(width: 260, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(.horizontal, 44)
                .padding(.vertical, 4)
            }
        }
    }

    private var moreLikeThisSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("More Like This")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(recommendations) { item in
                        MacPosterCard(title: item.displayName, subtitle: item.isTV ? "Series" : "Movie",
                                      posterUrl: item.posterUrl) {
                            current = MacTitleRef(result: item)
                        }
                    }
                }
                .padding(.horizontal, 44)
                .padding(.vertical, 6)
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Details")
            VStack(alignment: .leading, spacing: 10) {
                detailRow("Type", isTV ? "Series" : "Movie")
                if let year = current.year { detailRow("Released", String(year)) }
                if let name = resolved?.providerNameFallback ?? activeSource?.name, !name.isEmpty {
                    detailRow("Streaming on", Platform.from(providerName: name)?.displayName ?? name)
                }
                if isTV, !seasonSummaries.isEmpty { detailRow("Seasons", String(seasonSummaries.count)) }
                if let s = synopsisText { detailRow("Synopsis", s) }
            }
            .padding(.horizontal, 44)

            // A — report a wrong service or a link that doesn't open.
            MacReportProblemLink {
                reportContext = ReportContext(
                    entryPoint: "detail_link",
                    titleName: current.title,
                    providerName: activeSource?.name ?? resolved?.providerNameFallback,
                    titleId: current.titleId,
                    tmdbId: tmdbId,
                    isTV: isTV
                )
            }
            .padding(.horizontal, 44)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 24) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(MacColor.text2)
                .frame(width: 130, alignment: .leading)
            Text(value).font(.system(size: 13)).frame(maxWidth: 760, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private var castSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Cast")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Array(cast.prefix(24).enumerated()), id: \.offset) { _, m in
                        VStack(alignment: .leading, spacing: 6) {
                            ZStack {
                                Color(white: 0.10)
                                if let p = m.profilePath, !p.isEmpty {
                                    TVRemoteImage(urlString: TVTMDBImage.url(p, size: .poster342), contentMode: .fill)
                                } else {
                                    Image(systemName: "person.fill").font(.system(size: 30)).foregroundStyle(.white.opacity(0.35))
                                }
                            }
                            .frame(width: 120, height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: MacLayout.cardRadius))
                            .overlay(RoundedRectangle(cornerRadius: MacLayout.cardRadius).stroke(Color.white.opacity(0.08), lineWidth: 1))
                            Text(m.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                            if let c = m.character, !c.isEmpty {
                                Text(c).font(.system(size: 11.5)).foregroundStyle(MacColor.text2).lineLimit(1)
                            }
                        }
                        .frame(width: 120, alignment: .leading)
                    }
                }
                .padding(.horizontal, 44)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Loading

    private func loadAll() async {
        // Reset per-title state (More Like This swaps `current`).
        resolved = nil; selectedServiceName = nil; didProbeMediaType = false
        backdropUrl = nil; episodes = []; seasonSummaries = []; recommendations = []
        titleVideos = []; cast = []; genreText = nil; cadenceBadge = nil
        season = 1; episode = 1

        WatchIntentLogger.shared.log(eventType: .cardTapped, titleId: current.titleId, metadata: ["surface": "mac"])
        await social.refreshCounts(titleId: current.titleId)

        guard let tid = tmdbId else { return }
        let tv = current.isTV

        let needsBackdrop = current.backdropUrl == nil
        async let backdropTask: String? = needsBackdrop
            ? TVTMDBService.shared.getBackdropPath(tmdbId: tid, isTV: tv) : nil
        async let recsTask = TVTMDBService.shared.getRecommendations(tmdbId: tid, isTV: tv)
        async let videosTask = TVTMDBService.shared.getVideos(tmdbId: tid, isTV: tv)
        async let castTask = TVTMDBService.shared.getCast(tmdbId: tid, isTV: tv)

        // Target the latest aired episode before resolving, like tvOS.
        if tv {
            let fresh = await TVTMDBService.shared.getTVFreshness(tmdbId: tid)
            if let s = fresh.latestSeason, let e = fresh.latestEpisode { season = s; episode = e }
        }
        async let resolveTask: Void = resolveStreamingData()

        if tv {
            async let genreTask: String? = try? TVTMDBService.shared.getTVGenre(tmdbId: tid)
            let summaries = await TVTMDBService.shared.getSeasonSummaries(tmdbId: tid)
            seasonSummaries = summaries
            browsingSeason = summaries.first(where: { $0.seasonNumber == season })?.seasonNumber
                ?? summaries.last?.seasonNumber ?? 1
            await loadEpisodes(season: browsingSeason)
            cadenceBadge = Self.weeklyCadenceBadge(from: episodes)
            genreText = await genreTask
        }

        if let path = await backdropTask { backdropUrl = TVTMDBImage.url(path, size: .backdrop1280) }
        let (recs, videos, people) = await (recsTask, videosTask, castTask)
        recommendations = Array(recs.prefix(20))
        titleVideos = videos
        cast = people
        _ = await resolveTask
    }

    private func loadEpisodes(season number: Int) async {
        guard let tid = tmdbId else { return }
        let fetched = try? await TVTMDBService.shared.getSeason(tmdbId: tid, seasonNumber: number)
        episodes = fetched?.episodes ?? []
    }

    private func resolveStreamingData() async {
        guard let tid = tmdbId else { return }
        let knownIsTV: Bool? = didProbeMediaType ? (resolved?.resolvedMediaType == "tv") : current.isTV
        isResolving = true
        let result = await TVWatchmodeResolver.shared.resolve(
            tmdbId: tid, isTV: knownIsTV,
            season: knownIsTV == true ? season : nil,
            episode: knownIsTV == true ? episode : nil,
            subscribedServices: Array(AuthViewModel.shared.selectedServices),
            episodePlatformHint: selectedServiceName
        )
        resolved = result
        isResolving = false
    }

    /// "New episode every Sunday" — only when the last two aired episodes are
    /// a week apart and the latest is recent (tvOS rule).
    private static func weeklyCadenceBadge(from list: [TMDBEpisode]) -> String? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        let aired = list.compactMap { $0.airDate.flatMap(fmt.date(from:)) }.filter { $0 <= Date() }.sorted()
        guard aired.count >= 2, let latest = aired.last,
              latest > Date().addingTimeInterval(-21 * 86_400) else { return nil }
        let gap = latest.timeIntervalSince(aired[aired.count - 2]) / 86_400
        guard gap >= 6, gap <= 8 else { return nil }
        let weekday = DateFormatter()
        weekday.dateFormat = "EEEE"
        return "New episode every \(weekday.string(from: latest))"
    }
}

/// Plain button with the Mac hover outline, for episode and clip cards.
private struct MacHoverCard<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: MacLayout.cardRadius)
                .strokeBorder(selected ? MacColor.orange : (hovering ? Color.white.opacity(0.7) : .clear),
                              lineWidth: selected ? 2.5 : 2)
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .allowsHitTesting(false)
        }
        .onHover { hovering = $0 }
    }
}

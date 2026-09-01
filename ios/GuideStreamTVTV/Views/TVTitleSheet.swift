//
//  TVTitleSheet.swift
//  GuideStreamTVTV
//
//  Detail sheet that opens when the user clicks a tile. Acts as the
//  single mutate-the-watch-list surface so cards across the app stay
//  decluttered — every tile just opens this sheet.
//

import SwiftUI

/// Lightweight payload describing a title that can be saved. Built from
/// either a TMDB result, news item, or watch list row.
struct TVTitleDetail: Identifiable, Hashable {
    let titleId: String
    let title: String
    let overview: String?
    let posterUrl: String?
    let backdropUrl: String?
    let tag: String
    let accent: Color
    let year: Int?
    let platform: String?
    /// Media-type hint from the `is_tv` column on `user_streams` or from a
    /// TMDB result. When non-nil, the sheet uses it directly and skips the
    /// backend media-type probe. Declared last with a default so every
    /// existing construction site continues to compile unchanged.
    var isTVHint: Bool? = nil

    var id: String { titleId }
}

// MARK: - Focus fields

private enum SheetFocus: Hashable {
    case play, like, watched, watchList, close
}

// MARK: - Sheet

struct TVTitleSheet: View {
    private static let sectionsTopAnchor = "gui88.sectionsTop"

    let detail: TVTitleDetail
    let onDismiss: (Bool) -> Void

    @State private var streams = TVStreamsViewModel.shared
    @State private var social = SocialViewModel.shared
    @FocusState private var focusedField: SheetFocus?
    @Environment(\.dismiss) private var dismiss

    // Resolution state
    @State private var resolvedStreaming: TVWatchmodeResolver.TVResolvedStreaming?
    @State private var isResolving = false

    // Season / episode stepper (TV only)
    @State private var season: Int = 1
    @State private var episode: Int = 1

    // Currently selected Where-to-Watch service. Nil means use the resolved
    // primary. Reset when a new title loads so every title starts on its
    // default primary.
    @State private var selectedServiceName: String?

    // Guard so at most one automatic media-type probe resolve fires per
    // presented sheet. Reset to false in the same .task that resets
    // selectedServiceName when a new title loads.
    @State private var didProbeMediaType: Bool = false

    // Guard so the season/episode pre-fill from TMDB freshness fires at
    // most once per presented sheet. Reset in the same .task that resets
    // selectedServiceName when a new title loads.
    @State private var didPrefillEpisode: Bool = false

    // MARK: GUI-88 — sectioned detail state

    /// Numbered seasons for a series (TMDB's season 0 "Specials" filtered
    /// out). Empty for movies and for anything that fails to resolve, which
    /// is what hides the season picker.
    @State private var seasonSummaries: [TMDBSeasonSummary] = []
    /// The season the Episodes rail is showing — not necessarily the one the
    /// deep link targets, which stays on `season`/`episode`.
    @State private var browsingSeason: Int = 1
    @State private var episodes: [TMDBEpisode] = []
    @State private var isLoadingEpisodes: Bool = false
    @State private var recommendations: [TVTMDBResult] = []
    /// One title-scoped reel, or nil when the title has no playable trailer.
    /// Nil hides Trailers & Clips rather than showing tiles that do nothing.
    @State private var trailerReel: TVReelItem?
    @State private var reelsPresentation: TVReelsPresentation?
    /// "Series · Drama · Thriller" for the hero meta line. Nil until TMDB
    /// answers, which simply shortens the line.
    @State private var genreText: String?
    /// "New episode every Sunday", derived from the gap between the last two
    /// aired episodes. Nil unless that gap is genuinely weekly, so the badge
    /// never claims a cadence the schedule does not support.
    @State private var cadenceBadge: String?

    // Parsed from titleId via the tvOS TVTitleID helper (mirrors the iOS
    // TitleID enum). Accepts both bare numeric ids ("94997") and the
    // legacy prefixed form ("tmdb:tv:1396").
    private var tmdbId: Int? {
        TVTitleID.tmdbId(from: detail.titleId)
    }

    /// The media type when known from the row hint or the title_id prefix.
    /// `nil` for bare numeric ids with no `is_tv` hint — the backend probe
    /// resolves these. This optional form is what gets passed to the
    /// resolver; `isTV` (below) is the display-facing Bool with a fallback.
    private var isTVValue: Bool? {
        if let hint = detail.isTVHint { return hint }
        switch TVTitleID.mediaType(from: detail.titleId) {
        case "tv": return true
        case "movie": return false
        default: return nil
        }
    }

    /// Display-facing media type: the optional when known, otherwise falls
    /// back to the backend-resolved media type. Drives stepper visibility
    /// and the mediaType strings sent to SocialViewModel. Before the first
    /// resolve of an unknown-type title, returns false (stepper hidden).
    private var isTV: Bool {
        if let value = isTVValue { return value }
        return resolvedStreaming?.resolvedMediaType == "tv"
    }

    /// YouTube channel id when `titleId` is a `yt:` creator row. When
    /// non-nil, the sheet skips Watchmode resolution entirely and routes
    /// the Play button to the YouTube tvOS app.
    private var youTubeChannelId: String? {
        TVTitleID.youtubeChannelId(from: detail.titleId)
    }

    private var isSaved: Bool {
        streams.contains(titleId: detail.titleId)
    }

    private var isLiked: Bool {
        social.isLiked(detail.titleId)
    }

    private var isWatched: Bool {
        social.isWatched(detail.titleId)
    }

    /// Whether the action-row should render the Play button or a non-
    /// interactive "open the app manually" hint. YouTube creator rows always
    /// launch via the YouTube app. For streaming services, true only when the
    /// active platform is verified-launchable on tvOS. While the service is
    /// still resolving (no name known yet), defaults to true so a launchable
    /// service can still surface once resolution completes.
    private var showPlayButton: Bool {
        if youTubeChannelId != nil { return true }
        let name = activeSource?.name ?? detail.platform ?? ""
        guard !name.isEmpty else { return true }
        return TVOSDeepLinker.isLaunchable(platform: name)
    }

    // All resolved US streaming sources for this title.
    private var usSources: [TVWatchmodeResolver.TVResolvedSource] {
        resolvedStreaming?.usSources ?? []
    }

    // The source the Play button and label currently act on. Honors an explicit
    // chip selection when the viewer subscribes to it and it's in the source
    // list; otherwise falls back to the resolved primary.
    private var activeSource: TVWatchmodeResolver.TVResolvedSource? {
        if let selected = selectedServiceName,
           AuthViewModel.shared.subscribesToService(named: selected),
           let match = usSources.first(where: { $0.name == selected }) {
            return match
        }
        return resolvedStreaming?.primarySource
    }

    // Count of resolved sources the viewer subscribes to — drives whether
    // chips enter selection mode (2+) or launch directly (0 or 1).
    private var subscribedSourceCount: Int {
        usSources.filter { AuthViewModel.shared.subscribesToService(named: $0.name) }.count
    }

    // Sources ordered subscribed-first, preserving original order within groups.
    private var sortedSources: [TVWatchmodeResolver.TVResolvedSource] {
        usSources.enumerated().sorted { a, b in
            let aSub = AuthViewModel.shared.subscribesToService(named: a.element.name)
            let bSub = AuthViewModel.shared.subscribesToService(named: b.element.name)
            if aSub != bSub { return aSub && !bSub }
            return a.offset < b.offset
        }.map { $0.element }
    }

    // Best display name for the Play button
    private var playServiceName: String {
        if let name = activeSource?.name, !name.isEmpty {
            return name
        }
        if let name = resolvedStreaming?.providerNameFallback, !name.isEmpty {
            return name
        }
        return detail.platform ?? "Streaming"
    }

    // Best deep-link URL for the Play button — strictly from activeSource,
    // subject to the brand guard.
    private var bestDeepLinkURL: URL? {
        guard let source = activeSource else { return nil }
        return guardedDeepLink(for: source)
    }

    // Best web URL for fallback — strictly from activeSource, brand-guarded.
    private var bestWebURL: URL? {
        guard let source = activeSource else { return nil }
        return guardedWebURL(for: source)
    }

    // Synopsis text — resolved overview preferred, existing overview as fallback
    private var synopsisText: String? {
        if let resolved = resolvedStreaming?.overview, !resolved.isEmpty {
            return resolved
        }
        if let existing = detail.overview, !existing.isEmpty {
            return existing
        }
        return nil
    }

    var body: some View {
        ZStack {
            backdropLayer

            // GUI-88: the screen was a single non-scrolling ZStack — poster
            // left, one column right, nothing below the fold. It is now a
            // full-screen hero followed by sections the viewer walks down
            // into, the way the Apple TV title screen behaves.
            ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                // Deliberately NOT a LazyVStack. The hero is a full screen
                // tall, so with lazy construction nothing below it is ever
                // built while the hero is on screen — the focus engine then
                // has no view to move down to and the remote just cycles
                // sideways through the hero's own buttons. TVHomeView gets
                // away with a LazyVStack only because its hero carries a
                // negative bottom padding that pulls the first rail into
                // view. This screen is six sections, not a feed, so eager
                // construction costs nothing.
                VStack(alignment: .leading, spacing: 64) {
                    heroSection
                        .containerRelativeFrame(.vertical)

                    // The title rides at the top of everything below the
                    // hero, so the first move down lands on a page headed by
                    // the show's name rather than mid-rail.
                    sectionsTitleHeader
                        .id(Self.sectionsTopAnchor)

                    if !usSources.isEmpty, youTubeChannelId == nil {
                        whereToWatchSection
                    }
                    if isTV, youTubeChannelId == nil, !episodes.isEmpty {
                        episodesSection
                    }
                    if trailerReel != nil {
                        trailersSection
                    }
                    if !recommendations.isEmpty {
                        moreLikeThisSection
                    }
                    detailsSection

                    Color.clear.frame(height: 60)
                }
            }
            .ignoresSafeArea()
            // The focus engine scrolls the focused view into view, but it
            // stops as soon as the target is on screen, which leaves the
            // title half-way up. `focusedField` is non-nil only while a hero
            // button holds focus, so the moment it clears, focus has moved
            // into the sections and the page is pinned to the title.
            .onChange(of: focusedField) { previous, current in
                guard previous != nil, current == nil else { return }
                withAnimation(.easeOut(duration: 0.35)) {
                    proxy.scrollTo(Self.sectionsTopAnchor, anchor: .top)
                }
            }
            }
        }
        // Close is the remote's Menu button now that the on-screen Close
        // button is gone, matching Apple's own detail screen.
        .onExitCommand { dismiss() }
        .task {
            selectedServiceName = nil
            didProbeMediaType = false
            didPrefillEpisode = false
            await loadData()
            await loadSections()
        }
        .fullScreenCover(item: $reelsPresentation) { payload in
            TVReelsView(injectedReels: payload.feed, startIndex: payload.startIndex)
        }
        .onChange(of: season) { _, _ in
            Task { await resolveStreamingData() }
        }
        .onChange(of: episode) { _, _ in
            Task { await resolveStreamingData() }
        }
        .onChange(of: selectedServiceName) { _, _ in
            Task { await resolveStreamingData() }
        }
    }

    // MARK: - GUI-88 sections

    /// Cinematic backdrop behind every section. Unchanged from the previous
    /// layout apart from the gradient running further down, so text stays
    /// legible over art once the viewer has scrolled.
    private var backdropLayer: some View {
        TVRemoteImage(urlString: detail.backdropUrl ?? detail.posterUrl, contentMode: .fill)
            .ignoresSafeArea()
            .overlay {
                LinearGradient(
                    colors: [.black.opacity(0.35), .black.opacity(0.88), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
    }

    private func sectionHeader(_ title: String, accent: Color = TVTheme.orange) -> some View {
        HStack(spacing: 14) {
            Capsule()
                .fill(accent)
                .frame(width: 6, height: 30)
                .shadow(color: accent.opacity(0.65), radius: 10)
            Text(title)
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 80)
    }

    /// Full-screen first page: art, title, synopsis, the season/episode
    /// target and every action. Everything here already existed — it is
    /// re-laid-out, not rebuilt.
    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer(minLength: 0)

            if let cadence = cadenceBadge {
                Text(cadence)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(.black.opacity(0.55), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
            }

            // Wordmark treatment, matching the mock: uppercase and tracked
            // out rather than the 56pt black title the sheet used to show.
            Text(detail.title.uppercased())
                .font(.system(size: 76, weight: .heavy))
                .tracking(16)
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.5)

            HStack(spacing: 14) {
                if let short = serviceShortCode {
                    Text(short)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(detail.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                Text(heroMetaLine)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }

            if let line = heroEpisodeLine {
                line
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(3)
                    .frame(maxWidth: 900, alignment: .leading)
            } else if let synopsis = synopsisText {
                Text(synopsis)
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(3)
                    .frame(maxWidth: 900, alignment: .leading)
            }

            if !heroFactLine.isEmpty {
                Text(heroFactLine)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }

            // Mock's action row: the primary watch pill, then Watch List,
            // Watched and Like as round buttons. The season/episode stepper
            // and the on-screen Close button are gone — Close is now the
            // remote's Menu button via .onExitCommand, which is what Apple's
            // own detail screen does.
            HStack(spacing: 22) {
                if showPlayButton { playButton } else { manualOpenHint }
                watchListButton
                watchedButton
                likeButton
            }
            .padding(.top, 6)
            // Same reason TVRail sections its header and its cards: a move
            // down out of this row should resolve to the next section, not
            // be decided by which view happens to overlap its frame.
            .focusSection()
        }
        .padding(.horizontal, 80)
        .padding(.bottom, 130)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Two-letter service badge for the meta line, e.g. "P+" for Paramount+.
    private var serviceShortCode: String? {
        guard let name = activeSource?.name ?? detail.platform, !name.isEmpty else { return nil }
        let words = name.split(separator: " ")
        let initials = words.prefix(2).compactMap { $0.first }.map(String.init).joined()
        return name.contains("+") ? String(initials.prefix(1)) + "+" : initials.uppercased()
    }

    /// "Series · Drama · Thriller", degrading to just the media type when
    /// TMDB has not answered with genres.
    private var heroMetaLine: String {
        var parts = [isTV ? "Series" : "Movie"]
        if let genreText, !genreText.isEmpty { parts.append(genreText) }
        return parts.joined(separator: " · ")
    }

    /// "S3, E5 · Wish the Fight Away: <overview>" — the bold prefix names the
    /// episode the Play button is currently targeting, so the hero and the
    /// deep link always agree.
    private var heroEpisodeLine: Text? {
        guard isTV, youTubeChannelId == nil else { return nil }
        guard let ep = episodes.first(where: {
            $0.episodeNumber == episode && ($0.seasonNumber ?? browsingSeason) == season
        }) else { return nil }
        let name = ep.name ?? "Episode \(ep.episodeNumber)"
        let head = Text("S\(season), E\(episode) · \(name):").font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
        guard let overview = ep.overview, !overview.isEmpty else { return head }
        return head + Text("  " + overview)
    }

    /// "2024 · 53m". Runtime comes from the targeted episode, which is the
    /// one piece of Apple's fact row this app genuinely has.
    private var heroFactLine: String {
        var parts: [String] = []
        if let year = detail.year { parts.append(String(year)) }
        if let ep = episodes.first(where: {
            $0.episodeNumber == episode && ($0.seasonNumber ?? browsingSeason) == season
        }), let runtime = ep.runtime {
            parts.append("\(runtime)m")
        }
        return parts.joined(separator: " · ")
    }

    /// Title pinned above the first section, so a move down out of the hero
    /// lands on a page headed by the show's name — the second reference shot
    /// on GUI-88.
    private var sectionsTitleHeader: some View {
        Text(detail.title.uppercased())
            .font(.system(size: 44, weight: .heavy))
            .tracking(10)
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 80)
            .padding(.top, 40)
    }

    /// The chips that already shipped, lifted into their own section.
    private var whereToWatchSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Where to Watch")
            whereToWatchRow
                .padding(.horizontal, 80)
        }
        .focusSection()
    }

    // MARK: Episodes

    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Episodes")

            if seasonSummaries.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(seasonSummaries, id: \.id) { summary in
                            seasonPill(for: summary)
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 8)
                }
                .focusSection()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 32) {
                    ForEach(episodes, id: \.id) { ep in
                        episodeCard(ep)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 24)
            }
            .focusSection()
        }
    }

    private func seasonPill(for summary: TMDBSeasonSummary) -> some View {
        let number = summary.seasonNumber ?? 1
        let isOn = number == browsingSeason
        return Button {
            browsingSeason = number
            Task { await loadEpisodes(season: number) }
        } label: {
            Text(summary.name ?? "Season \(number)")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(isOn ? Color.black : TVTheme.textSecondary)
                .padding(.horizontal, 26)
                .padding(.vertical, 12)
                .background(isOn ? Color.white.opacity(0.92) : Color.white.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// 16:9 still with the episode's own metadata under it, matching the
    /// Apple TV episode rail. Selecting one re-targets the deep link at that
    /// episode — `season`/`episode` drive `resolveStreamingData`, so the Play
    /// button then opens that episode rather than the series page. That is
    /// something Apple's own screen cannot do for third-party services.
    private func episodeCard(_ ep: TMDBEpisode) -> some View {
        let isTarget = (ep.seasonNumber ?? browsingSeason) == season && ep.episodeNumber == episode
        return Button {
            season = ep.seasonNumber ?? browsingSeason
            episode = ep.episodeNumber
            focusedField = showPlayButton ? .play : .watchList
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .bottomLeading) {
                    Color(white: 0.05)
                        .overlay { TVRemoteImage(urlString: ep.stillUrl, contentMode: .fill).allowsHitTesting(false) }
                        .overlay {
                            LinearGradient(colors: [.black.opacity(0.75), .clear],
                                           startPoint: .bottom, endPoint: .center)
                        }
                    if let runtime = ep.runtime {
                        Text("\(runtime)m")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(12)
                    }
                }
                .frame(width: 420, height: 236)
                .clipShape(.rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isTarget ? detail.accent : Color.white.opacity(0.08),
                                lineWidth: isTarget ? 3 : 1)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Episode \(ep.episodeNumber)")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(TVTheme.textSecondary)
                        .tracking(1.2)
                    Text(ep.name ?? "Episode \(ep.episodeNumber)")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let overview = ep.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.system(size: 19))
                            .foregroundStyle(TVTheme.textSecondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    if let air = ep.airDate, !air.isEmpty {
                        Text(air)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(TVTheme.textTertiary)
                    }
                }
                .frame(width: 420, alignment: .leading)
            }
        }
        .buttonStyle(.card)
    }

    // MARK: Trailers & Clips

    /// Opens Reels on this title, the way the phone and Android do it —
    /// `TVReelsView(injectedReels:startIndex:)` mirrors the iPhone's
    /// `ReelsScreen(injectedReels:injectedStartIndex:)`. The row is only
    /// built when a playable trailer actually resolved, so it never shows
    /// a tile that leads nowhere.
    private var trailersSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Trailers & Clips", accent: TVTheme.blue)
            HStack(spacing: 32) {
                if let reel = trailerReel {
                    Button {
                        WatchIntentLogger.shared.log(
                            eventType: .cardTapped,
                            titleId: detail.titleId,
                            metadata: ["section": "trailers_and_clips"]
                        )
                        reelsPresentation = TVReelsPresentation(feed: [reel], startIndex: 0)
                    } label: {
                        ZStack(alignment: .bottomLeading) {
                            Color(white: 0.05)
                                .overlay {
                                    TVRemoteImage(urlString: reel.backdropUrl ?? reel.posterUrl, contentMode: .fill)
                                        .allowsHitTesting(false)
                                }
                                .overlay {
                                    LinearGradient(colors: [.black.opacity(0.8), .clear],
                                                   startPoint: .bottom, endPoint: .center)
                                }
                            HStack(spacing: 12) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 30, weight: .bold))
                                Text("Play trailer")
                                    .font(.system(size: 22, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(18)
                        }
                        .frame(width: 480, height: 270)
                        .clipShape(.rect(cornerRadius: 14))
                    }
                    .buttonStyle(.card)
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 20)
        }
        .focusSection()
    }

    // MARK: More Like This

    private var moreLikeThisSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("More Like This")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 32) {
                    ForEach(recommendations) { item in
                        TVPosterCard(
                            title: item.displayName,
                            subtitle: item.isTV ? "Series" : "Movie",
                            posterUrl: item.posterUrl,
                            accent: TVTheme.orange,
                            isSaved: streams.contains(titleId: item.canonicalTitleId)
                        ) {
                            // Re-presenting the sheet from inside itself would
                            // stack full-screen covers, so this dismisses back
                            // to the caller, which owns presentation.
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 24)
            }
            .focusSection()
        }
    }

    // MARK: Details

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Details")
            VStack(alignment: .leading, spacing: 16) {
                detailRow("Type", detail.tag.capitalized)
                if let year = detail.year { detailRow("Released", String(year)) }
                if let platform = detail.platform, !platform.isEmpty {
                    detailRow("Streaming on", platform)
                }
                if isTV, !seasonSummaries.isEmpty {
                    detailRow("Seasons", String(seasonSummaries.count))
                }
                if let synopsis = synopsisText {
                    detailRow("Synopsis", synopsis)
                }
            }
            .padding(.horizontal, 80)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 40) {
            Text(label)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(TVTheme.textSecondary)
                .frame(width: 220, alignment: .leading)
            Text(value)
                .font(.system(size: 20))
                .foregroundStyle(.white)
                .frame(maxWidth: 1100, alignment: .leading)
        }
    }

    // MARK: - GUI-88 section loading

    /// Seasons, episodes, recommendations and the trailer reel, all fail-soft:
    /// a section that resolves to nothing simply does not render.
    private func loadSections() async {
        guard let tid = tmdbId else { return }
        let tv = isTV

        async let recsTask = TVTMDBService.shared.getRecommendations(tmdbId: tid, isTV: tv)
        async let reelTask = buildTrailerReel(tmdbId: tid, isTV: tv)

        if tv, youTubeChannelId == nil {
            let summaries = await TVTMDBService.shared.getSeasonSummaries(tmdbId: tid)
            seasonSummaries = summaries
            // Open on the season the deep link is already targeting, so the
            // rail and the Play button agree on first paint.
            let opening = summaries.first(where: { $0.seasonNumber == season })?.seasonNumber
                ?? summaries.last?.seasonNumber ?? 1
            browsingSeason = opening
            await loadEpisodes(season: opening)
        }

        if tv {
            genreText = try? await TVTMDBService.shared.getTVGenre(tmdbId: tid)
        }
        cadenceBadge = weeklyCadenceBadge(from: episodes)

        let (recs, reel) = await (recsTask, reelTask)
        recommendations = Array(recs.prefix(20))
        trailerReel = reel
    }

    /// "New episode every Sunday", but only when the last two aired episodes
    /// are genuinely a week apart. A show that has finished, or that dropped
    /// a whole season at once, gets no badge rather than a false promise.
    private func weeklyCadenceBadge(from list: [TMDBEpisode]) -> String? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        let now = Date()
        let aired = list.compactMap { ep -> Date? in
            guard let raw = ep.airDate, let d = fmt.date(from: raw) else { return nil }
            return d
        }.sorted()
        guard aired.count >= 2 else { return nil }
        // Only claim a cadence while the show is still running.
        guard let latest = aired.last, latest > now.addingTimeInterval(-21 * 86_400) else { return nil }
        let gap = latest.timeIntervalSince(aired[aired.count - 2]) / 86_400
        guard gap >= 6, gap <= 8 else { return nil }
        let weekday = DateFormatter()
        weekday.dateFormat = "EEEE"
        return "New episode every \(weekday.string(from: latest))"
    }

    private func loadEpisodes(season number: Int) async {
        guard let tid = tmdbId else { return }
        isLoadingEpisodes = true
        defer { isLoadingEpisodes = false }
        let fetched = try? await TVTMDBService.shared.getSeason(tmdbId: tid, seasonNumber: number)
        episodes = fetched?.episodes ?? []
    }

    private func buildTrailerReel(tmdbId tid: Int, isTV tv: Bool) async -> TVReelItem? {
        let keys: [String]
        if let verified = await TVTrailerResolveService.resolve(tmdbId: tid, isTV: tv) {
            keys = verified
        } else {
            keys = await TVTMDBService.shared.getTrailerKeys(tmdbId: tid, isTV: tv)
        }
        guard !keys.isEmpty else { return nil }
        return TVReelItem(
            id: "tmdb:\(tv ? "tv" : "movie"):\(tid)",
            tmdbId: tid,
            isTV: tv,
            title: detail.title,
            synopsis: synopsisText ?? "",
            backdropUrl: detail.backdropUrl,
            posterUrl: detail.posterUrl,
            year: detail.year,
            genre: nil,
            platformName: detail.platform,
            platformId: nil,
            trailerKeys: keys,
            isSponsored: false,
            advertiserKey: nil
        )
    }

    // MARK: - Where to Watch chips

    private var whereToWatchRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("WHERE TO WATCH")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(TVTheme.textTertiary)
                .tracking(2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(sortedSources, id: \.sourceId) { source in
                        serviceChip(for: source)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func serviceChip(for source: TVWatchmodeResolver.TVResolvedSource) -> some View {
        let isSubscribed = AuthViewModel.shared.subscribesToService(named: source.name)
        let isActive = activeSource?.sourceId == source.sourceId
        return Button {
            if subscribedSourceCount >= 2 && isSubscribed {
                selectedServiceName = source.name
            } else {
                // Only launch when the service is verified-launchable on
                // tvOS; otherwise the chip stays a where-to-watch indicator.
                if TVOSDeepLinker.isLaunchable(platform: source.name) {
                    open(source: source)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(gsDisplayName(for: source.name))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                if isSubscribed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(brandColor(for: source.name))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isActive ? TVTheme.orange : Color.white.opacity(0.12),
                            lineWidth: isActive ? 4 : 1)
            )
        }
        .buttonStyle(.card)
    }

    // MARK: - Season / Episode stepper

    private var seasonEpisodeStepper: some View {
        HStack(spacing: 32) {
            // Season
            HStack(spacing: 16) {
                Button {
                    if season > 1 { season -= 1 }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(season > 1 ? TVTheme.orange : TVTheme.textTertiary)
                }
                .buttonStyle(.card)
                .disabled(season <= 1)

                VStack(spacing: 2) {
                    Text("Season")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(TVTheme.textTertiary)
                    Text("\(season)")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(minWidth: 80)

                Button {
                    season += 1
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(TVTheme.orange)
                }
                .buttonStyle(.card)
            }

            // Episode
            HStack(spacing: 16) {
                Button {
                    if episode > 1 { episode -= 1 }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(episode > 1 ? TVTheme.orange : TVTheme.textTertiary)
                }
                .buttonStyle(.card)
                .disabled(episode <= 1)

                VStack(spacing: 2) {
                    Text("Episode")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(TVTheme.textTertiary)
                    Text("\(episode)")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(minWidth: 80)

                Button {
                    episode += 1
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(TVTheme.orange)
                }
                .buttonStyle(.card)
            }
        }
    }

    // MARK: - Manual-open hint (non-launchable services)

    /// Non-interactive guidance shown in place of the Play button for
    /// streaming services whose tvOS app cannot be launched from another
    /// app. Plain view (not a Button, not focusable) so it never steals
    /// focus from a real control.
    private var manualOpenHint: some View {
        HStack(spacing: 12) {
            Image(systemName: "tv")
                .font(.system(size: 24, weight: .bold))
            Text("Open the \(playServiceName) app on your Apple TV to watch.")
                .font(.system(size: 20, weight: .semibold))
        }
        .foregroundStyle(TVTheme.textSecondary)
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    // MARK: - Play button

    private var playButton: some View {
        Button {
            if let channelId = youTubeChannelId {
                TVOSDeepLinker.openYouTubeChannel(channelId: channelId, name: detail.title)
            } else if let source = activeSource {
                open(source: source)
            } else {
                // No resolved source — fall back to the name-based open chain.
                TVOSDeepLinker.open(platform: playServiceName, title: detail.title)
            }
        } label: {
            HStack(spacing: 14) {
                if isResolving && resolvedStreaming == nil {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 28, weight: .bold))
                }
                Text(youTubeChannelId != nil ? "Play on YouTube" : "Play on \(playServiceName.capitalized)")
                    .font(.system(size: 22, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .buttonStyle(.card)
        .focused($focusedField, equals: .play)
        .disabled(isResolving && resolvedStreaming == nil && youTubeChannelId == nil)
    }

    // MARK: - Like button

    private var likeButton: some View {
        Button {
            Task {
                await social.toggleLike(
                    titleId: detail.titleId,
                    mediaType: isTV ? "tv" : "movie",
                    tmdbId: tmdbId
                )
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 24, weight: .bold))
                Text(isLiked ? "Liked" : "Like")
                    .font(.system(size: 22, weight: .semibold))
            }
            .foregroundStyle(isLiked ? TVTheme.orange : .white)
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .buttonStyle(.card)
        .focused($focusedField, equals: .like)
    }

    // MARK: - Watched button

    private var watchedButton: some View {
        Button {
            Task {
                await social.toggleWatched(
                    titleId: detail.titleId,
                    titleName: detail.title,
                    mediaType: isTV ? "tv" : "movie",
                    tmdbId: tmdbId
                )
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isWatched ? "eye.fill" : "eye")
                    .font(.system(size: 24, weight: .bold))
                Text(isWatched ? "Watched" : "Watched?")
                    .font(.system(size: 22, weight: .semibold))
            }
            .foregroundStyle(isWatched ? TVTheme.blue : .white)
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .buttonStyle(.card)
        .focused($focusedField, equals: .watched)
    }

    // MARK: - Watch List button

    private var watchListButton: some View {
        Button {
            Task {
                await streams.toggle(
                    titleId: detail.titleId,
                    title: detail.title,
                    posterUrl: detail.posterUrl,
                    platform: detail.platform
                )
                onDismiss(streams.contains(titleId: detail.titleId))
                dismiss()
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 28, weight: .bold))
                Text(isSaved ? "Remove from Watch List" : "Add to Watch List")
                    .font(.system(size: 22, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .buttonStyle(.card)
        .focused($focusedField, equals: .watchList)
    }

    // MARK: - Close button

    private var closeButton: some View {
        Button {
            onDismiss(isSaved)
            dismiss()
        } label: {
            Text("Close")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
        }
        .buttonStyle(.card)
        .focused($focusedField, equals: .close)
    }

    // MARK: - Data loading

    private func loadData() async {
        // Refresh like state
        await social.refreshCounts(titleId: detail.titleId)

        // Pre-select the latest aired episode for TV titles. Skip for
        // YouTube creator rows and non-TV titles. Fail soft — if the
        // TMDB lookup errors, season/episode stay at their defaults.
        if youTubeChannelId == nil, isTVValue != false, let tid = tmdbId {
            let fresh = await TVTMDBService.shared.getTVFreshness(tmdbId: tid)
            if !didPrefillEpisode, let s = fresh.latestSeason, let e = fresh.latestEpisode {
                season = s
                episode = e
                didPrefillEpisode = true
            }
        }

        // Resolve streaming sources — skip for YouTube creator rows, which
        // route directly to the YouTube app and have no Watchmode data.
        if youTubeChannelId == nil {
            await resolveStreamingData()
        }

        // Set initial focus — Play when launchable, otherwise Watch List
        // so focus never targets the non-interactive manual-open hint.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            focusedField = showPlayButton ? .play : .watchList
        }
    }

    private func resolveStreamingData() async {
        guard let tid = tmdbId else { return }
        // After a successful probe, use the resolved media type for subsequent
        // resolves so episode/season changes are episode-accurate.
        let knownIsTV: Bool?
        if didProbeMediaType, let resolved = resolvedStreaming?.resolvedMediaType {
            knownIsTV = (resolved == "tv")
        } else {
            knownIsTV = isTVValue
        }
        isResolving = true
        let result = await TVWatchmodeResolver.shared.resolve(
            tmdbId: tid,
            isTV: knownIsTV,
            season: (knownIsTV == true) ? season : nil,
            episode: (knownIsTV == true) ? episode : nil,
            subscribedServices: Array(AuthViewModel.shared.selectedServices),
            episodePlatformHint: selectedServiceName
        )
        resolvedStreaming = result
        // Probe follow-up: if the media type was unknown at request time and
        // the backend resolved it to "tv", issue exactly one follow-up
        // resolve with the now-known type and the current season/episode so
        // a bare-numeric series identifier reaches its episode-accurate
        // source. `isResolving` stays true across the recursive call to
        // avoid a loading-state flicker.
        if !didProbeMediaType, isTVValue == nil, result?.resolvedMediaType == "tv" {
            didProbeMediaType = true
            await resolveStreamingData()
        } else {
            isResolving = false
        }
    }

    // MARK: - Deep-link launch + brand guard

    /// Opens a specific resolved source, preferring a guarded deep link and
    /// falling back to the name-based open chain. Shared by the Play button and
    /// the chip launch path.
    private func open(source: TVWatchmodeResolver.TVResolvedSource) {
        if let deepLink = guardedDeepLink(for: source) {
            TVOSDeepLinker.open(
                platform: source.name,
                title: detail.title,
                contentURL: guardedWebURL(for: source),
                tvosDeepLink: deepLink
            )
        } else {
            TVOSDeepLinker.open(platform: source.name, title: detail.title)
        }
    }

    /// The episode source only applies when it belongs to the same service as
    /// the given source (shared source_id), so a selected service never opens
    /// another service's episode link.
    private func episodeSource(matching source: TVWatchmodeResolver.TVResolvedSource) -> TVWatchmodeResolver.TVResolvedSource? {
        guard let ep = resolvedStreaming?.episodeSource, ep.sourceId == source.sourceId else { return nil }
        return ep
    }

    private func guardedDeepLink(for source: TVWatchmodeResolver.TVResolvedSource) -> URL? {
        let ep = episodeSource(matching: source)
        // Reorder so native-scheme candidates (nflx://, aiv://, vuduapp://,
        // etc.) are preferred over https universal links, preserving the
        // existing episode-before-title precedence within each group. tvOS
        // has no browser, so an https URL placed first can silently consume
        // the launch and land the user nowhere. The brand guard is applied
        // unchanged at every step.
        let tvosUrls = [ep?.tvosUrl, source.tvosUrl]
        let iosUrls = [ep?.iosUrl, source.iosUrl]
        let webUrls = [ep?.webUrl, source.webUrl]

        func isWebScheme(_ url: URL) -> Bool {
            let scheme = url.scheme?.lowercased() ?? ""
            return scheme == "http" || scheme == "https"
        }

        // Pass 1: native-scheme tvosUrls then native-scheme iosUrls.
        for candidate in tvosUrls + iosUrls {
            if let str = candidate, let url = URL(string: str), !isWebScheme(url),
               urlAllowed(url, forService: source.name) {
                return url
            }
        }
        // Pass 2: https tvosUrls then https iosUrls (universal links).
        for candidate in tvosUrls + iosUrls {
            if let str = candidate, let url = URL(string: str), isWebScheme(url),
               urlAllowed(url, forService: source.name) {
                return url
            }
        }
        // Pass 3: web URLs.
        for candidate in webUrls {
            if let str = candidate, let url = URL(string: str),
               urlAllowed(url, forService: source.name) {
                return url
            }
        }
        return nil
    }

    private func guardedWebURL(for source: TVWatchmodeResolver.TVResolvedSource) -> URL? {
        let ep = episodeSource(matching: source)
        let candidates = [ep?.webUrl, source.webUrl]
        for candidate in candidates {
            if let str = candidate, let url = URL(string: str), urlAllowed(url, forService: source.name) {
                return url
            }
        }
        return nil
    }

    /// A URL is allowed for a service only when the URL's detected brand is nil
    /// or equal to the service's brand token. A different non-nil brand is
    /// rejected (guards against wrong-app deep links, e.g. a Prime link served
    /// for an Apple TV+ title).
    private func urlAllowed(_ url: URL, forService name: String) -> Bool {
        guard let detected = brandToken(forURL: url) else { return true }
        return detected == brandToken(forServiceName: name)
    }

    private func brandToken(forURL url: URL) -> String? {
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host?.lowercased() ?? ""
        if scheme == "aiv" || host.contains("amazon") || host.contains("primevideo") { return "amazon" }
        if scheme == "nflx" || host.contains("netflix") { return "netflix" }
        if scheme == "videos" || host.contains("apple") { return "apple" }
        if host.contains("hulu") { return "hulu" }
        if scheme == "disneyplus" || host.contains("disney") { return "disney" }
        if scheme == "hbomax" || host.contains("max") || host.contains("hbo") { return "max" }
        if scheme == "paramountplus" || host.contains("paramount") { return "paramount" }
        if scheme == "peacock" || host.contains("peacock") { return "peacock" }
        if scheme == "youtube" || host.contains("youtube") { return "youtube" }
        if host.contains("crunchyroll") { return "crunchyroll" }
        return nil
    }

    private func brandToken(forServiceName name: String) -> String? {
        guard let catalogId = Platform.from(providerName: name)?.catalogId else { return nil }
        // Map catalog ids to the URL-brand-token space used by brandToken(forURL:).
        switch catalogId {
        case "prime":   return "amazon"
        case "appletv": return "apple"
        default:        return catalogId
        }
    }

    // MARK: - Brand styling (local copies mirroring the tvOS ShowDetailScreen /
    // PlayOnBottomSheet helpers)

    private func brandColor(for name: String) -> Color {
        Platform.from(providerName: name)?.color ?? Color(white: 0.18)
    }

    private func gsDisplayName(for raw: String) -> String {
        Platform.from(providerName: raw)?.displayName ?? raw
    }
}

// MARK: - Trailer reels presentation payload

/// Carries the title-scoped Reels feed and the tapped start index into the
/// full-screen cover. Mirrors `TrailerReelsPresentation` on iPhone.
struct TVReelsPresentation: Identifiable {
    let id = UUID()
    let feed: [TVReelItem]
    let startIndex: Int
}

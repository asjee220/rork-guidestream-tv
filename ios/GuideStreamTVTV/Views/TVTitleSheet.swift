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

    /// How much of the screen the first section is allowed to occupy while
    /// the hero is still the page. The hero is a screen tall *minus* this,
    /// so the episodes row is cut off by the bottom edge rather than sitting
    /// just below it — the standard lean-back cue that there is more down
    /// there. Home does the same thing with a negative bottom padding.
    private static let foldPeek: CGFloat = 260

    let detail: TVTitleDetail
    let onDismiss: (Bool) -> Void

    @State private var streams = TVStreamsViewModel.shared
    @State private var social = SocialViewModel.shared
    @FocusState private var focusedField: SheetFocus?
    @Environment(\.dismiss) private var dismiss

    // Resolution state
    @State private var resolvedStreaming: TVWatchmodeResolver.TVResolvedStreaming?
    @State private var isResolving = false

    /// Presented when the title can be watched more than one way — several
    /// subscribed services, or several rent/buy offers. One tap on the watch
    /// button still means "watch it" when there is only one answer.
    @State private var showWatchOptions = false
    @FocusState private var focusedOption: Int?
    @FocusState private var focusedSeason: Int?
    @FocusState private var focusedCast: Int?

    /// Billed cast, TMDB order. Empty hides the section.
    @State private var cast: [TMDBCastMember] = []

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

    // Sources the viewer pays a subscription for.
    private var subscribedSources: [TVWatchmodeResolver.TVResolvedSource] {
        usSources.filter { AuthViewModel.shared.subscribesToService(named: $0.name) }
    }

    // Rent and buy offers. "purchase" is Watchmode's other spelling for buy;
    // watchmode_resolve v23 normalises the tier key server-side, but the raw
    // type still arrives either way.
    private var transactionalSources: [TVWatchmodeResolver.TVResolvedSource] {
        usSources.filter { ["rent", "buy", "purchase"].contains($0.type.lowercased()) }
    }

    /// Everything the watch button could reasonably open: what the viewer
    /// already pays for, then what they can rent or buy.
    private var watchOptions: [TVWatchmodeResolver.TVResolvedSource] {
        subscribedSources + transactionalSources
    }

    /// True when the service this title is *labelled* with is one the viewer
    /// subscribes to, even though Watchmode returned no row for it.
    ///
    /// This is the common case, not an edge one: Watchmode frequently returns
    /// only transactional rows for a current show — Star Trek came back as
    /// three "Buy $2.99" offers and no Paramount+ row — while the resolver's
    /// provider_name_fallback still names the service correctly, which is
    /// what the badge under the title has been showing all along. Offering to
    /// sell a viewer an episode they can already stream is the wrong answer.
    private var subscribesToLabelledService: Bool {
        let name = activeSource?.name
            ?? resolvedStreaming?.providerNameFallback
            ?? detail.platform
        guard let name, !name.isEmpty else { return false }
        return AuthViewModel.shared.subscribesToService(named: name)
    }

    /// The button only asks when it genuinely cannot pick: several
    /// subscriptions the viewer owns, or — owning none — several ways to pay.
    private var needsWatchOptions: Bool {
        if subscribedSources.count >= 2 { return true }
        if subscribedSources.isEmpty, !subscribesToLabelledService,
           transactionalSources.count >= 2 { return true }
        return false
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
                VStack(alignment: .leading, spacing: 0) {
                    heroSection
                        // A full screen, always. Shortening this frame is
                        // what broke it the first time: the hero's own block
                        // — badge, 76pt wordmark, meta, synopsis, actions —
                        // is taller than a screen minus the peek, so a
                        // VStack in a short fixed frame spilled its actions
                        // and half its wordmark past the bottom edge.
                        //
                        // The peek is made the way Home makes it instead:
                        // the hero's content is padded clear of the bottom
                        // band, and the sections are pulled up into it.
                        .containerRelativeFrame(.vertical)
                        .padding(.bottom, -Self.foldPeek)

                    // Episodes lead. The seasons row is what shows at the
                    // fold and what the first move down lands on, so the
                    // show's own wordmark is not repeated here — it is
                    // already the largest thing on the screen above.
                    VStack(alignment: .leading, spacing: 64) {
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

                        if !cast.isEmpty {
                            castSection
                        }

                        Color.clear.frame(height: 60)
                    }
                    .padding(.top, 24)
                    .id(Self.sectionsTopAnchor)
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
        .fullScreenCover(isPresented: $showWatchOptions) {
            watchOptionsSheet
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
    ///
    /// The art is pinned to an explicit screen-sized frame and clipped. A
    /// `.resizable()` image with `.aspectRatio(.fill)` and no frame reports
    /// the size it would *like* — the source asset's own dimensions — and in
    /// a ZStack that inflates the stack, and with it the container that
    /// `containerRelativeFrame(.vertical)` measures the hero against. The
    /// hero then came out taller than the screen: wordmark pushed to the
    /// bottom edge, action row off screen entirely.
    ///
    /// That is why the only title that behaved was the one with no artwork —
    /// its fallback is a gradient, which takes the size it is offered. The
    /// backdrop must never be able to drive layout.
    private var backdropLayer: some View {
        GeometryReader { proxy in
            TVRemoteImage(urlString: detail.backdropUrl ?? detail.posterUrl, contentMode: .fill)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .overlay {
                    LinearGradient(
                        colors: [.black.opacity(0.35), .black.opacity(0.88), .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        }
        .ignoresSafeArea()
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
                providerMark(for: playServiceName, size: 34)
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
            HStack(alignment: .top, spacing: 26) {
                watchButton
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
        // Clears the peeking episodes row the same way TVHomeView's metadata
        // clears its first rail. Was 130, when nothing sat below the fold.
        .padding(.bottom, Self.foldPeek + 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Two-letter service badge for the meta line, e.g. "P+" for Paramount+.
    private var serviceShortCode: String? {
        let raw = activeSource?.name
            ?? resolvedStreaming?.providerNameFallback
            ?? detail.platform
        guard let raw, !raw.isEmpty else { return nil }
        return shortCode(for: raw)
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
    ///
    /// Currently unused: the Sep 2 reference leads the second page with the
    /// seasons row instead, and repeating a 44pt wordmark one screen below a
    /// 76pt one reads as a header the viewer has to scroll past. Kept so
    /// restoring it is one line in the section stack.
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
        let focused = focusedSeason == number
        return Button {
            browsingSeason = number
            Task { await loadEpisodes(season: number) }
        } label: {
            Text(summary.name ?? "Season \(number)")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(isOn ? Color.black : TVTheme.textSecondary)
                .padding(.horizontal, 26)
                .padding(.vertical, 12)
                // Selection and focus are separate cues, the way the side
                // menu keeps its orange bar and its plate independent: the
                // filled capsule says which season is showing, the plate
                // says which pill the remote is on.
                .background(isOn ? Color.white.opacity(0.92) : Color.white.opacity(0.10), in: Capsule())
                .overlay(Capsule().fill(Color.white.opacity(focused && !isOn ? 0.16 : 0)))
                .overlay(Capsule().stroke(Color.white.opacity(focused ? 0.9 : 0), lineWidth: 2))
                .scaleEffect(focused ? 1.06 : 1.0)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
        .buttonStyle(TVFlatButtonStyle())
        .focusEffectDisabled()
        .focused($focusedSeason, equals: number)
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
            focusedField = .play
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

    // MARK: Cast

    /// Billed cast as a portrait rail. The cards do nothing when selected —
    /// there is no person screen on tvOS — but they are focusable anyway,
    /// because a section with no focusable view in it cannot be scrolled to:
    /// the focus engine is what moves this page.
    private var castSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Cast")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 28) {
                    ForEach(Array(cast.prefix(24).enumerated()), id: \.offset) { index, member in
                        castCard(member, index: index)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 14)
            }
        }
        .focusSection()
    }

    private func castCard(_ member: TMDBCastMember, index: Int) -> some View {
        let focused = focusedCast == index

        return VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Color(white: 0.10)
                if let path = member.profilePath, !path.isEmpty {
                    TVRemoteImage(urlString: TVTMDBImage.url(path, size: .poster342),
                                  contentMode: .fill)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .frame(width: 200, height: 300)
            .clipShape(.rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(focused ? 0.16 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(focused ? Color.white : Color.white.opacity(0.08),
                            lineWidth: focused ? 3 : 1)
            )

            Text(member.name)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            if let character = member.character, !character.isEmpty {
                Text(character)
                    .font(.system(size: 18))
                    .foregroundStyle(TVTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 200, alignment: .leading)
        .scaleEffect(focused ? 1.06 : 1.0)
        .animation(.easeOut(duration: 0.15), value: focused)
        .focusable()
        .focusEffectDisabled()
        .focused($focusedCast, equals: index)
    }

    // MARK: - GUI-88 section loading

    /// Seasons, episodes, recommendations and the trailer reel, all fail-soft:
    /// a section that resolves to nothing simply does not render.
    private func loadSections() async {
        guard let tid = tmdbId else { return }
        let tv = isTV

        async let recsTask = TVTMDBService.shared.getRecommendations(tmdbId: tid, isTV: tv)
        async let reelTask = buildTrailerReel(tmdbId: tid, isTV: tv)
        async let castTask = TVTMDBService.shared.getCast(tmdbId: tid, isTV: tv)

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

        let (recs, reel, people) = await (recsTask, reelTask, castTask)
        recommendations = Array(recs.prefix(20))
        trailerReel = reel
        cast = people
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
    // MARK: - Watch button

    /// "Watch on ▣" — the destination is named by the service mark rather
    /// than spelled out, which is what keeps the button one line whatever the
    /// service is called, and matches the badge under the title.
    ///
    /// One tap means watch. It only asks a question when there genuinely is
    /// one: several subscribed services, or several rent/buy offers. The open
    /// itself goes through the existing chain — the source's tvOS scheme,
    /// then its iOS scheme, then the universal link, then a search inside the
    /// app — so it lands on the title, not the service's home screen.
    private var watchButton: some View {
        Button {
            if let channelId = youTubeChannelId {
                TVOSDeepLinker.openYouTubeChannel(channelId: channelId, name: detail.title)
            } else if subscribedSources.count == 1 {
                // One service the viewer already pays for. There is nothing
                // to ask — rent and buy offers are not alternatives to a
                // subscription they own.
                open(source: subscribedSources[0])
            } else if subscribedSources.isEmpty, subscribesToLabelledService {
                // Subscribed to the service the title is labelled with, but
                // Watchmode gave no row for it. Open it by name — the same
                // chain, resolving through the deep linker's own catalogue.
                TVOSDeepLinker.open(platform: playServiceName, title: detail.title)
            } else if needsWatchOptions {
                showWatchOptions = true
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
                        .font(.system(size: 26, weight: .bold))
                }

                if youTubeChannelId != nil {
                    Text("Watch on YouTube")
                        .font(.system(size: 22, weight: .semibold))
                } else {
                    Text("Watch on")
                        .font(.system(size: 22, weight: .semibold))
                    providerMark(for: playServiceName, size: 40)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .buttonStyle(.card)
        .focused($focusedField, equals: .play)
        .disabled(isResolving && resolvedStreaming == nil && youTubeChannelId == nil)
    }

    // MARK: - Watch options

    /// Presented only when the button cannot pick for the viewer. Subscribed
    /// services first — what they already pay for is what they want — then
    /// rent and buy, each carrying its price when Watchmode returned one.
    private var watchOptionsSheet: some View {
        ZStack {
            Color.black.opacity(0.94).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Text(detail.title.uppercased())
                    .font(.system(size: 34, weight: .heavy))
                    .tracking(6)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text("Where do you want to watch?")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 18)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(watchOptions.enumerated()), id: \.offset) { index, source in
                            watchOptionRow(for: source, index: index)
                        }
                    }
                    // A focused row lifts 1.04, and a ScrollView clips to its
                    // own bounds — without this the first row lost its ends.
                    .padding(.horizontal, 26)
                    .padding(.vertical, 20)
                }
            }
            .padding(.horizontal, 120)
            .padding(.vertical, 90)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .onExitCommand { showWatchOptions = false }
    }

    private func watchOptionRow(for source: TVWatchmodeResolver.TVResolvedSource,
                                index: Int) -> some View {
        let subscribed = AuthViewModel.shared.subscribesToService(named: source.name)
        let focused = focusedOption == index
        return Button {
            // Remember the choice so the hero's badge, meta line and deep
            // link all agree with what was just opened.
            selectedServiceName = source.name
            showWatchOptions = false
            open(source: source)
        } label: {
            HStack(spacing: 22) {
                providerMark(for: source.name, size: 52)

                Text(gsDisplayName(for: source.name))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)

                Spacer(minLength: 24)

                Text(offerLabel(for: source, subscribed: subscribed))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 20)
            .frame(maxWidth: 900, alignment: .leading)
            // Neutral, so the brand-coloured mark is the thing carrying the
            // service's identity — a row painted in the same colour swallows
            // its own icon.
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(focused ? 0.16 : 0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(focused ? 0.85 : 0.10),
                            lineWidth: focused ? 2 : 1)
            )
            .scaleEffect(focused ? 1.04 : 1.0)
            .animation(.easeOut(duration: 0.15), value: focused)
        }
        .buttonStyle(TVFlatButtonStyle())
        .focusEffectDisabled()
        .focused($focusedOption, equals: index)
    }

    /// The service's own logo from `provider_brand_map`, falling back to the
    /// lettered badge when the map has no row or no logo for the name.
    /// The service's own mark, drawn the way iPhone's services pill draws
    /// it: a circle in the service's brand colour with its glyph on top.
    ///
    /// Deliberately not the TMDB logo. `provider_brand_map.logo_path` points
    /// at TMDB's provider artwork, which is served as JPEG — no alpha channel
    /// exists in the file, so the white is part of the image and clipping it
    /// to a circle only makes a white disc. The brand colour now resolves for
    /// far more services than it used to, since the map is actually loaded
    /// (0396b41), so drawing the mark ourselves is both cleaner and truer to
    /// the phone.
    private func providerMark(for name: String, size: CGFloat) -> some View {
        Circle()
            .fill(brandColor(for: name))
            .frame(width: size, height: size)
            .overlay {
                Text(shortCode(for: name))
                    .font(.system(size: size * 0.36, weight: .black))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(size * 0.14)
            }
            // Separates the mark from a row painted in the same colour.
            .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 1))
    }

    /// "P+" for Paramount+, "AT" for Apple TV+ — initials of the first two
    /// words, with a trailing + preserved.
    private func shortCode(for name: String) -> String {
        let display = gsDisplayName(for: name)
        let words = display.split(separator: " ")
        let initials = words.prefix(2).compactMap { $0.first }.map(String.init).joined()
        return display.contains("+") ? String(initials.prefix(1)) + "+" : initials.uppercased()
    }

    /// "Included" for something already paid for, otherwise "Rent $3.99" —
    /// and just "Rent" when the offer arrived without a price, which is what
    /// a TMDB-sourced fallback row looks like.
    private func offerLabel(for source: TVWatchmodeResolver.TVResolvedSource,
                            subscribed: Bool) -> String {
        let tier = source.type.lowercased()
        let name: String
        switch tier {
        case "rent": name = "Rent"
        case "buy", "purchase": name = "Buy"
        case "free": name = "Free"
        case "tve": name = "With TV provider"
        default: name = subscribed ? "Included" : "Subscription"
        }
        guard let price = source.price, price > 0 else { return name }
        return String(format: "%@ $%.2f", name, price)
    }

    // MARK: - Circular actions

    /// The tvOS reading of iPhone's `circleAction`: a circle with an icon and
    /// nothing else, because plus and heart say what they do. Only Watched
    /// carries its caption — an eye does not read as "have you seen this?"
    /// from ten feet away, and the phone labels it for the same reason.
    ///
    /// Focus is drawn from `focusedField` rather than a button style: the
    /// sheet already tracks it, and `.card` would put a rounded rectangle
    /// behind a circle.
    private func circleAction(
        field: SheetFocus,
        icon: String,
        tint: Color,
        caption: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let focused = focusedField == field
        return Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    // The side menu's plate, in circular form: white 16% when
                    // focused, nothing when not, plus the same 1.06 lift.
                    Circle()
                        .fill(Color.white.opacity(focused ? 0.16 : 0.06))
                    Image(systemName: icon)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 84, height: 84)
                .scaleEffect(focused ? 1.06 : 1.0)
                .animation(.easeOut(duration: 0.15), value: focused)

                if let caption {
                    Text(caption)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        // .plain still lets tvOS lay its own white focus slab over the
        // control — that pale rectangle survived .focusEffectDisabled() on
        // its own. An empty custom style draws nothing at all, which is how
        // TVSideMenu's rows stay clean.
        .buttonStyle(TVFlatButtonStyle())
        .focusEffectDisabled()
        .focused($focusedField, equals: field)
    }

    // MARK: - Like button

    private var likeButton: some View {
        circleAction(
            field: .like,
            icon: isLiked ? "heart.fill" : "heart",
            tint: isLiked ? TVTheme.orange : .white
        ) {
            Task {
                await social.toggleLike(
                    titleId: detail.titleId,
                    mediaType: isTV ? "tv" : "movie",
                    tmdbId: tmdbId
                )
            }
        }
    }

    // MARK: - Watched button

    private var watchedButton: some View {
        circleAction(
            field: .watched,
            icon: isWatched ? "eye.fill" : "eye",
            tint: isWatched ? TVTheme.blue : .white,
            caption: isWatched ? "Watched" : "Watched?"
        ) {
            Task {
                await social.toggleWatched(
                    titleId: detail.titleId,
                    titleName: detail.title,
                    mediaType: isTV ? "tv" : "movie",
                    tmdbId: tmdbId
                )
            }
        }
    }

    // MARK: - Watch List button

    private var watchListButton: some View {
        circleAction(
            field: .watchList,
            icon: isSaved ? "checkmark.circle.fill" : "plus.circle.fill",
            tint: .white
        ) {
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
        }
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

        // Watch is always the primary action now, so it is always where
        // focus starts.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            focusedField = .play
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

/// Draws nothing: no background, no lift, no focus decoration. Every focus
/// cue on this screen is drawn by the view itself, the way TVMenuButtonStyle
/// lets the side menu draw its own plate.
private struct TVFlatButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
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

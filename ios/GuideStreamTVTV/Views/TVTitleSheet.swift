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
            // Cinematic backdrop
            TVRemoteImage(urlString: detail.backdropUrl ?? detail.posterUrl, contentMode: .fill)
                .ignoresSafeArea()
                .overlay {
                    LinearGradient(
                        colors: [
                            .black.opacity(0.4),
                            .black.opacity(0.85),
                            .black
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            HStack(alignment: .top, spacing: 60) {
                // Poster
                TVRemoteImage(urlString: detail.posterUrl, contentMode: .fill)
                    .frame(width: 360, height: 540)
                    .clipShape(.rect(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.6), radius: 36, y: 18)

                VStack(alignment: .leading, spacing: 24) {
                    // Tag + year
                    HStack(spacing: 12) {
                        Text(detail.tag.uppercased())
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(detail.accent)
                            .tracking(2)
                        if let year = detail.year {
                            Text("·  \(String(year))")
                                .font(.system(size: 16, weight: .heavy))
                                .foregroundStyle(TVTheme.textSecondary)
                                .tracking(1)
                        }
                    }

                    // Title
                    Text(detail.title)
                        .font(.system(size: 56, weight: .black))
                        .foregroundStyle(.white)
                        .lineLimit(3)

                    // Synopsis
                    if let synopsis = synopsisText {
                        Text(synopsis)
                            .font(.system(size: 22))
                            .foregroundStyle(TVTheme.textSecondary)
                            .lineLimit(6)
                            .frame(maxWidth: 760, alignment: .leading)
                    }

                    // Season / Episode stepper (TV only, hidden for creators)
                    if isTV, youTubeChannelId == nil {
                        seasonEpisodeStepper
                    }

                    // Platform badge (only when no resolved source)
                    if resolvedStreaming == nil,
                       let platform = detail.platform, !platform.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "play.tv.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(detail.accent)
                            Text("Streaming on \(platform)")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.08), in: Capsule())
                    }

                    // Where to Watch chips (hidden when no resolved sources
                    // or for YouTube creator rows)
                    if !usSources.isEmpty, youTubeChannelId == nil {
                        whereToWatchRow
                    }

                    // Action buttons row
                    HStack(spacing: 24) {
                        // Play on <service>
                        playButton

                        // Like / Unlike
                        likeButton

                        // Watched toggle
                        watchedButton

                        // Watch List toggle
                        watchListButton

                        // Close
                        closeButton
                    }
                    .padding(.top, 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 60)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .task {
            selectedServiceName = nil
            didProbeMediaType = false
            didPrefillEpisode = false
            await loadData()
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
                open(source: source)
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
                Text(isWatched ? "Watched" : "Mark Watched")
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

        // Set initial focus to Play
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
        let webUrls = [ep?.webUrl, source.webUrl]

        func isWebScheme(_ url: URL) -> Bool {
            let scheme = url.scheme?.lowercased() ?? ""
            return scheme == "http" || scheme == "https"
        }

        // Pass 1: native-scheme tvosUrls only.
        for candidate in tvosUrls {
            if let str = candidate, let url = URL(string: str), !isWebScheme(url),
               urlAllowed(url, forService: source.name) {
                return url
            }
        }
        // Pass 2: https tvosUrls (universal links).
        for candidate in tvosUrls {
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

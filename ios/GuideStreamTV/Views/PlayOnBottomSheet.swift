//
//  PlayOnBottomSheet.swift
//  GuideStreamTV
//

import SwiftUI
import UIKit

enum PlayOnDeviceType {
    case iphone
    case appleTv
    case tv
}

struct PlayOnDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let sublabel: String
    let type: PlayOnDeviceType
}

enum PlayOnRowState: Equatable {
    case `default`
    case selected
    case connecting
}

struct PlayOnBottomSheet: View {
    let isOpen: Bool
    let onClose: () -> Void
    let showTitle: String
    let showSubtitle: String
    let thumbnailUrl: String?
    var tmdbId: Int? = nil
    var isTV: Bool = true
    var initialSelectedDevice: String = "living-room"
    let onDeviceSelected: (String) -> Void

    /// Optional overrides for metadata shown in the header. When nil the
    /// hardcoded fallback values are used (backward-compatible with the
    /// Play On flow from ShowDetailScreen).
    var metadataLine: String? = nil
    var genreLine: String? = nil
    /// When non-nil the "View Full Details" button calls this instead of
    /// `onClose`, letting callers navigate to the full ShowDetailScreen.
    var onViewFullDetails: (() -> Void)? = nil

    /// When non-nil the watch button label changes from "Watch on <service>"
    /// to "Watch S:4 EP:7 on <service>", and the deep link URL is extended
    /// with season/episode path segments where the platform supports it.
    var watchSeasonNum: Int? = nil
    var watchEpisodeNum: Int? = nil

    // Illustrative fallback metadata used until the live Watchmode lookup
    // resolves (or as a fallback when the API is unavailable). Overridden
    // by `metadataLine` / `genreLine` when those are set.
    private var yearsLabel: String { metadataLine ?? "2018–2023 · 4 Seasons · TV-MA" }
    private var genreLabel: String { genreLine ?? "Drama" }
    private let rating: Double = 9.6
    private let likeCount: String = "2.4K"
    private let commentCount: String = "183"
    private let fallbackAboutText: String = "Tap the watch button to open this title in the streaming app."
    private var availabilityLabel: String? {
        guard let source = resolvedSource else { return nil }
        let type = source.type.lowercased()
        let name = gsDisplayName(for: source.name)
        if type == "free" { return "Free on \(name)" }
        if type == "tve" { return "Available on \(name) with a TV provider" }
        if type == "sub" { return AuthViewModel.shared.subscribesToService(named: source.name) ? nil : "Requires a \(name) subscription" }
        return nil
    }
    private let watchCTAColor: Color = Color.orange

    @State private var isLiked: Bool = false
    @State private var isNotifying: Bool = true
    @State private var showCastSheet: Bool = false
    /// Watchmode-resolved source for this title. When present, drives the
    /// platform label, brand color, and the watch CTA deeplink.
    @State private var resolvedSource: WatchmodeSource?
    @State private var resolvedOverview: String?
    @State private var isResolvingSource: Bool = false
    /// Per-episode deep link URL resolved from Watchmode's episode-level
    /// sources endpoint. When non-nil, the watch button opens this URL
    /// so the streaming app lands on the exact episode.
    @State private var episodeDeepLinkURL: URL?
    @State private var episodeSourceUnavailable: Bool = false
    @State private var isResolvingEpisodeSources: Bool = false

    private var resolvedPlatformName: String {
        let raw = resolvedSource?.name ?? (isResolvingSource ? "…" : "")
        return raw.isEmpty || raw == "…" ? raw : gsDisplayName(for: raw)
    }

    private var platformLabel: String { resolvedPlatformName.uppercased() }

    /// True once we have a real streaming service name from Watchmode. Used
    /// to hide platform chips and CTAs when no service is available rather
    /// than rendering a meaningless "Streaming" placeholder.
    private var hasResolvedPlatform: Bool { resolvedSource?.name != nil }

    /// `true` when the resolved source is a paid subscription the user
    /// does not have — drives the "Get" label on the watch CTA.
    private var requiresGet: Bool {
        guard let source = resolvedSource,
              source.type.lowercased() == "sub" else { return false }
        return !AuthViewModel.shared.subscribesToService(named: source.name)
    }

    private var whereToWatchLabel: String {
        if let name = resolvedSource?.name { return gsDisplayName(for: name) }
        return isResolvingSource ? "Finding service…" : ""
    }

    private var platformColor: Color { brandColor(for: resolvedPlatformName) }

    private var aboutText: String { resolvedOverview ?? fallbackAboutText }

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

    /// `true` once Watchmode tells us the format is a movie. Used to forward
    /// the correct `MediaType` to Roku ECP and to drive the right Watchmode
    /// search field (`tmdb_movie_id` vs `tmdb_tv_id`).
    private var resolvedIsTV: Bool {
        if let fmt = resolvedSource?.format?.lowercased() {
            return fmt.contains("tv") || fmt.contains("series")
        }
        return isTV
    }

    /// Title-specific URL from the already-resolved Watchmode source.
    /// Prefers `ios_url` when Watchmode returned a real deep link (paid
    /// tier); falls back to the canonical `web_url` which iOS routes into
    /// the app via universal links. `nil` when the source hasn't resolved
    /// yet — caller falls back to the async lookup path.
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

    /// Filters out Watchmode free-tier placeholders
    /// ("Deeplinks available for paid plans only.") that aren't valid URLs.
    private static func isRealDeepLinkURL(_ s: String) -> Bool {
        let lower = s.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.contains("://") else { return false }
        if lower.contains("deeplinks available") || lower.contains("paid plan") { return false }
        return URL(string: s) != nil
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Color.black.opacity(isOpen ? 0.55 : 0)
                    .ignoresSafeArea()
                    .allowsHitTesting(isOpen)
                    .onTapGesture { close() }
                    .animation(.easeOut(duration: 0.2), value: isOpen)

                sheetContent(maxHeight: geo.size.height * 0.86)
                    .offset(y: isOpen ? 0 : geo.size.height)
                    .animation(.interpolatingSpring(stiffness: 280, damping: 26), value: isOpen)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showCastSheet) {
            CastToTVSheet(
                isPresented: $showCastSheet,
                showTitle: showTitle,
                platform: resolvedSource?.name ?? whereToWatchLabel,
                tmdbId: tmdbId,
                isTV: resolvedIsTV,
                watchmodeSource: resolvedSource
            )
        }
        .task(id: tmdbId ?? -1) {
            episodeSourceUnavailable = false
            isResolvingEpisodeSources = false
            await resolveStreamingSource()
        }
    }

    /// Resolves the title's actual streaming service via the shared
    /// StreamingSourceResolver, which runs all network calls inside a
    /// `Task.detached` (immune to view-lifecycle cancellation) and applies
    /// US-region filtering, network-priority selection, and reseller
    /// deprioritisation.
    private func resolveStreamingSource() async {
        guard let tmdbId, resolvedSource == nil, !isResolvingSource else { return }
        isResolvingSource = true
        defer { isResolvingSource = false }

        let r = await StreamingSourceResolver.shared.resolve(
            tmdbId: tmdbId,
            isTV: isTV
        )

        await MainActor.run {
            self.resolvedSource = r.primarySource
            self.resolvedOverview = r.overview
        }

        // Resolve per-episode deep link when season/episode info is
        // available, so the watch button opens the exact episode.
        // (tmdbId is already unwrapped by the guard let at the top of
        // this function, so it's a non-optional Int here.)
        if let s = watchSeasonNum, let e = watchEpisodeNum, resolvedIsTV {
            await MainActor.run { self.isResolvingEpisodeSources = true }
            defer { Task { @MainActor in self.isResolvingEpisodeSources = false } }

            let epSources = await WatchmodeService.shared.episodeSources(
                tmdbId: tmdbId, isTV: true, season: s, episode: e
            )
            let best: WatchmodeSource? = epSources.flatMap {
                Self.bestEpisodeSource(from: $0, resolvedSource: resolvedSource)
            }
            let url: URL? = epSources.flatMap {
                Self.episodeSourceURL(from: $0, resolvedSource: best)
            }
            await MainActor.run {
                if let best { self.resolvedSource = best }
                self.episodeDeepLinkURL = url
                self.episodeSourceUnavailable = (best == nil)
                self.isResolvingEpisodeSources = false
            }
        }
    }



    private func close() { onClose() }

    // MARK: - Sheet body

    private func sheetContent(maxHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 44, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow
                        .padding(.horizontal, 20)
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

                    aboutSection
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                    whereToWatchSection
                        .padding(.horizontal, 20)
                        .padding(.top, 22)

                    watchButton
                        .padding(.horizontal, 20)
                        .padding(.top, 22)

                    viewFullDetailsButton
                        .padding(.top, 16)
                        .padding(.bottom, 28)
                        .frame(maxWidth: .infinity)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: maxHeight, alignment: .top)
        .background(
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 28, topTrailing: 28), style: .continuous)
                .fill(Color(red: 0x06/255, green: 0x0C/255, blue: 0x18/255))
        )
        .clipShape(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 28, topTrailing: 28), style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 28, y: -10)
    }

    // MARK: - Header row (poster + meta)

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 16) {
            posterThumbnail
                .frame(width: 110, height: 150)
                .clipShape(.rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 8) {
                Text(showTitle)
                    .scaledFont(size: 26, weight: .bold)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(yearsLabel)
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.white.opacity(0.55))

                HStack(spacing: 8) {
                    if hasResolvedPlatform || isResolvingSource {
                        Text(platformLabel)
                            .scaledFont(size: 11, weight: .heavy)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(platformColor))
                    }

                    Text(genreLabel)
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
                    Text(String(format: "%.1f", rating))
                        .scaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(.white)
                        .padding(.leading, 4)
                }
                .padding(.top, 2)

                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .scaledFont(size: 12)
                            .foregroundStyle(Color.orange)
                        Text(likeCount)
                            .scaledFont(size: 13, weight: .semibold)
                            .foregroundStyle(.white)
                        Text("Likes")
                            .scaledFont(size: 13)
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                    Text("·")
                        .scaledFont(size: 13)
                        .foregroundStyle(Color.white.opacity(0.4))
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left")
                            .scaledFont(size: 12)
                            .foregroundStyle(Color.white.opacity(0.7))
                        Text(commentCount)
                            .scaledFont(size: 13, weight: .semibold)
                            .foregroundStyle(.white)
                        Text("Comments")
                            .scaledFont(size: 13)
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                }
                .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
    }

    private var posterThumbnail: some View {
        ZStack {
            if let urlString = thumbnailUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        posterFallback
                    }
                }
            } else {
                posterFallback
            }
        }
        .overlay(alignment: .bottomLeading) {
            if hasResolvedPlatform {
                Text(String(resolvedPlatformName.prefix(4)).uppercased())
                    .scaledFont(size: 10, weight: .heavy)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(platformColor))
                    .padding(8)
            }
        }
    }

    private var posterFallback: some View {
        LinearGradient(
            colors: [
                Color(red: 0xB8/255, green: 0x86/255, blue: 0x2C/255),
                Color(red: 0x6A/255, green: 0x4A/255, blue: 0x10/255)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Actions row

    private var actionsRow: some View {
        HStack(spacing: 0) {
            actionButton(
                icon: isLiked ? "heart.fill" : "heart",
                label: "Like",
                tint: isLiked ? Color.orange : .white,
                showDot: false
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isLiked.toggle() }
            }
            .frame(maxWidth: .infinity)

            actionButton(
                icon: "bell.fill",
                label: "Notify",
                tint: .white,
                showDot: isNotifying
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isNotifying.toggle() }
            }
            .frame(maxWidth: .infinity)

            actionButton(
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

    private func actionButton(icon: String, label: String, tint: Color, showDot: Bool, isLoading: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
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
                            .overlay(Circle().stroke(Color(red: 0x06/255, green: 0x0C/255, blue: 0x18/255), lineWidth: 2))
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

    // MARK: - Where to watch

    @ViewBuilder
    private var whereToWatchSection: some View {
        if hasResolvedPlatform || isResolvingSource {
            VStack(alignment: .leading, spacing: 10) {
                Text("WHERE TO WATCH")
                    .scaledFont(size: 12, weight: .heavy)
                    .tracking(1.4)
                    .foregroundStyle(Color.white.opacity(0.45))

                HStack(spacing: 10) {
                    if isResolvingSource && !hasResolvedPlatform {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.mini).tint(.white)
                            Text("Finding service…")
                                .scaledFont(size: 13, weight: .heavy)
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                    } else {
                        Text(whereToWatchLabel)
                            .scaledFont(size: 13, weight: .heavy)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(platformColor))
                    }
                }

                if let availabilityLabel {
                    Text(availabilityLabel)
                        .scaledFont(size: 13)
                        .foregroundStyle(Color.white.opacity(0.5))
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("WHERE TO WATCH")
                    .scaledFont(size: 12, weight: .heavy)
                    .tracking(1.4)
                    .foregroundStyle(Color.white.opacity(0.45))
                Text("Not currently available on any streaming service in your region.")
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - CTA

    @ViewBuilder
    private var watchButton: some View {
        if hasResolvedPlatform || isResolvingSource {
            actualWatchButton
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
        if baseStr.contains("amazon.com") || baseStr.contains("primevideo.com") || baseStr.contains("amazon") {
            return URL(string: baseStr + "?season=\(season)&episode=\(episode)") ?? base
        }
        // Netflix, Apple TV+, Max, Disney+ use opaque IDs —
        // return the show-level URL as a best-effort fallback.
        return base
    }

    private var actualWatchButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            WatchIntentLogger.shared.log(
                eventType: .playOnDeviceChosen,
                titleId: WatchIntentLogger.titleSlug(showTitle),
                metadata: ["device_id": "watch-on-platform", "platform": whereToWatchLabel]
            )

            // Best path: Watchmode episode-level sources gave us a
            // URL that deep-links directly to the exact episode.
            if let epURL = episodeDeepLinkURL {
                StreamingDeepLinker.openResolvedURL(
                    epURL,
                    platform: whereToWatchLabel,
                    title: showTitle,
                    tmdbId: tmdbId
                )
            } else if let pre = preResolvedDeepLinkURL {
                let finalURL: URL = {
                    if let s = watchSeasonNum, let e = watchEpisodeNum {
                        return episodeDeeplinkURL(from: pre, season: s, episode: e)
                    }
                    return pre
                }()
                StreamingDeepLinker.openResolvedURL(
                    finalURL,
                    platform: whereToWatchLabel,
                    title: showTitle,
                    tmdbId: tmdbId
                )
            } else {
                StreamingDeepLinker.open(
                    platform: whereToWatchLabel,
                    title: showTitle,
                    tmdbId: tmdbId,
                    isTV: resolvedIsTV
                )
            }

            // Defer the sheet dismiss by a beat so the URL open settles
            // first — iOS occasionally drops a foreground request that
            // fires while a sheet's dismiss animation is mid-flight.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                onDeviceSelected("watch-on-platform")
            }
        } label: {
            HStack(spacing: 8) {
                if (isResolvingSource && resolvedSource == nil) || isResolvingEpisodeSources {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                if let s = watchSeasonNum, let e = watchEpisodeNum, !episodeSourceUnavailable {
                    Text(requiresGet ? "Get S:\(s) EP:\(e)" : "Watch S:\(s) EP:\(e)")
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
            .background(
                Capsule().fill(watchCTAColor)
            )
            .shadow(color: watchCTAColor.opacity(0.55), radius: 22, y: 0)
        }
        .buttonStyle(.plain)
        .disabled(tmdbId == nil || isResolvingEpisodeSources)
    }

    private var viewFullDetailsButton: some View {
        Button {
            if let onViewFullDetails {
                onViewFullDetails()
            } else {
                close()
            }
        } label: {
            HStack(spacing: 6) {
                Text("View Full Details")
                    .scaledFont(size: 15, weight: .semibold)
                Image(systemName: "arrow.right")
                    .scaledFont(size: 13, weight: .semibold)
            }
            .foregroundStyle(Color.white.opacity(0.85))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        Color.navy.ignoresSafeArea()
        PlayOnBottomSheet(
            isOpen: true,
            onClose: {},
            showTitle: "Succession",
            showSubtitle: "S:4 EP:7 · Tailgate Party",
            thumbnailUrl: nil,
            onDeviceSelected: { _ in }
        )
    }
}

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
    /// Watchmode-resolved source for the show (top US sub > free > tve > rent).
    /// When set, drives the platform label, color, and the "Watch on" deeplink so
    /// shows show their real streaming service instead of the placeholder "HBO Max".
    @State private var resolvedSource: WatchmodeSource?
    @State private var resolvedOverview: String?
    @State private var isResolvingSource: Bool = false
    @State private var adDismissed: Bool = false
    @State private var showFullDetail: Bool = false

    private var platformColor: Color {
        if let name = resolvedSource?.name { return brandColor(for: name) }
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
        if case .episode(let e) = subject, !e.platform.isEmpty, e.platform.uppercased() != "STREAM" {
            return true
        }
        return false
    }

    private var platformName: String {
        if let name = resolvedSource?.name { return name.uppercased() }
        switch subject {
        case .episode(let e) where !e.platform.isEmpty && e.platform.uppercased() != "STREAM":
            return e.platform
        default:
            return isResolvingSource ? "…" : ""
        }
    }

    private var whereToWatchLabel: String {
        if let name = resolvedSource?.name { return name }
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

    /// `true` when we're a show (or anything without explicit episode info).
    /// Drives both the Watchmode lookup (`tmdb_tv_id` vs `tmdb_movie_id`) and
    /// the Roku ECP `MediaType` parameter ("series" vs "movie").
    private var isTV: Bool {
        if case .episode = subject { return true }
        // For shows we default to TV; we refine this once Watchmode tells us
        // the actual format. Most home-screen entries are series.
        if let fmt = resolvedSource?.format?.lowercased() {
            return fmt.contains("tv") || fmt.contains("series")
        }
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
        if key.contains("paramount") { return Color(red: 0.0, green: 0.40, blue: 0.95) }
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

                watchActions
                    .padding(.horizontal, 20)
                    .padding(.top, 22)

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
                isTV: isTV
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
            await resolveStreamingSource()
        }
        .fullScreenCover(isPresented: $showFullDetail) {
            ShowDetailScreen(
                titleId: tmdbId.map(String.init) ?? "",
                title: title,
                posterUrl: posterUrl,
                backdropUrl: resolvedBackdrop,
                isTV: isTV,
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

    /// Looks up the title's real top streaming source via Watchmode. We use
    /// this both for displaying the correct platform name in the sheet and
    /// for opening the right app on tap. Falls back silently if the lookup
    /// fails — the existing fallback URL keeps the button working.
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
        do {
            let inferTV = isTV
            guard let watchmodeId = try await WatchmodeService.shared.watchmodeId(forTMDBId: tmdbId, isTV: inferTV) else { return }
            let detail = try await WatchmodeService.shared.titleDetail(titleId: watchmodeId)
            await MainActor.run {
                self.resolvedOverview = detail.plotOverview
            }
            guard let sources = detail.sources else { return }
            let ranked = sources.sorted { a, b in sourceRank(a) < sourceRank(b) }
            // Prefer a source whose name matches the episode's platform when
            // we have one; otherwise pick the top-ranked sub source.
            let preferred: WatchmodeSource? = {
                if case .episode(let e) = subject, !e.platform.isEmpty {
                    let p = e.platform.lowercased()
                    if let match = ranked.first(where: { matches(sourceName: $0.name, platform: p) }) {
                        return match
                    }
                }
                return ranked.first
            }()
            if let chosen = preferred {
                await MainActor.run { self.resolvedSource = chosen }
            }
        } catch {
            #if DEBUG
            print("[EpisodeDetailSheet] Watchmode lookup failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func sourceRank(_ s: WatchmodeSource) -> Int {
        switch s.type.lowercased() {
        case "sub": return 0
        case "free": return 1
        case "tve": return 2
        case "rent": return 3
        case "purchase", "buy": return 4
        default: return 5
        }
    }

    private func matches(sourceName: String, platform: String) -> Bool {
        let s = sourceName.lowercased()
        let p = platform.lowercased()
        if p.contains("netflix") { return s.contains("netflix") }
        if p.contains("hbo") || p.contains("max") { return s.contains("max") || s.contains("hbo") }
        if p.contains("hulu") { return s.contains("hulu") }
        if p.contains("disney") { return s.contains("disney") }
        if p.contains("apple") { return s.contains("apple tv") }
        if p.contains("prime") || p.contains("amazon") { return s.contains("amazon") || s.contains("prime") }
        if p.contains("paramount") { return s.contains("paramount") }
        if p.contains("peacock") { return s.contains("peacock") }
        if p.contains("youtube") { return s.contains("youtube") }
        if p.contains("showtime") { return s.contains("showtime") }
        if p.contains("starz") { return s.contains("starz") }
        if p.contains("crunchyroll") { return s.contains("crunchyroll") }
        return s.contains(p) || p.contains(s)
    }

    // MARK: - Affiliate banner

    @ViewBuilder
    private var affiliateBanner: some View {
        if !adDismissed, let ad = affiliateAdData,
           let service = StreamingCatalog.all
            .first(where: { $0.id == ad.serviceId }) {
            Button {
                RakutenManager.shared.openAffiliateLink(
                    serviceId: ad.serviceId,
                    metadata: [
                        "source": "episode_detail_sheet",
                        "platform_shown": platformName,
                        "title": title
                    ]
                )
            } label: {
                HStack(spacing: 12) {
                    ServiceMiniIcon(service: service, size: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(ad.headline)
                            .scaledFont(size: 13, weight: .semibold)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(ad.subtext)
                            .scaledFont(size: 11)
                            .foregroundStyle(Color.white.opacity(0.50))
                        Text("Sponsored")
                            .scaledFont(size: 9)
                            .foregroundStyle(Color.white.opacity(0.25))
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.up.right")
                        .scaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(Color.white.opacity(0.35))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                )
                .padding(.horizontal, 20)
            }
            .buttonStyle(.plain)
            .overlay(alignment: .topTrailing) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        adDismissed = true
                    }
                } label: {
                    Image(systemName: "xmark")
                        .scaledFont(size: 12, weight: .semibold)
                        .foregroundStyle(Color.white.opacity(0.35))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: -8, y: -8)
            }
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
                Task {
                    await social.toggleLike(titleId: key)
                    await MainActor.run { isTogglingLike = false }
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
                showDot: false
            ) {
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
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 54, height: 54)
                    Image(systemName: icon)
                        .scaledFont(size: 22, weight: .regular)
                        .foregroundStyle(tint)
                    if showDot {
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
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
                )
                .overlay(alignment: .leading) {
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
                }
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
            if isTV {
                Button {
                    showFullDetail = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet")
                            .scaledFont(size: 14)
                        Text("More episodes")
                            .scaledFont(size: 13, weight: .medium)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            } else {
                Button {
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
            }

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

    private var watchButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            // Fast path: when the sheet already resolved a Watchmode
            // source, fire the deep link from the captured URL. This
            // avoids a second ~500–1500ms Watchmode round-trip AND
            // closes a race where iOS dropped the foreground request
            // because the sheet started dismissing before open() ran.
            if let pre = preResolvedDeepLinkURL {
                StreamingDeepLinker.openResolvedURL(
                    pre,
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
                if isResolvingSource && resolvedSource == nil {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                Text(resolvedSource == nil && isResolvingSource
                     ? "Finding service…"
                     : "Watch on \(whereToWatchLabel)")
                    .scaledFont(size: 17, weight: .semibold)
                if hasResolvedPlatform, !whereToWatchLabel.isEmpty {
                    Text(whereToWatchLabel)
                        .scaledFont(size: 11, weight: .bold)
                        .foregroundStyle(Color(red: 0x5A/255, green: 0x2C/255, blue: 0x06/255))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.30)))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Capsule().fill(Color.orange))
            .shadow(color: Color.orange.opacity(0.55), radius: 22, y: 0)
        }
        .buttonStyle(.plain)
        .disabled(tmdbId == nil)
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
                .overlay(alignment: .bottom) {
                    Text(tag)
                        .scaledFont(size: 10, weight: .bold)
                        .tracking(0.8)
                        .foregroundStyle(Color.orange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.30))
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
                            Text("S5 E1 · 64min")
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

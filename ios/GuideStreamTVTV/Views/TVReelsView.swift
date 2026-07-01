//
//  TVReelsView.swift
//  GuideStreamTVTV
//
//  Living-room trailer feed. The phone app's Reels is a vertical-swipe
//  TikTok feed; on Apple TV that maps to a full-screen cinematic browser
//  the user steps through with the Siri Remote (up/down between reels,
//  left/right between sections, click to open the title sheet). tvOS can't
//  embed YouTube, so each reel presents the title's hero art with a
//  "Trailer" affordance, the streaming-service badge, rating, and a quick
//  save shortcut on the Play/Pause button.
//

import SwiftUI

// MARK: - Model

enum TVReelTab: String, CaseIterable, Hashable {
    case forYou = "for-you"
    case trending = "trending"
    case new = "new"

    var label: String {
        switch self {
        case .forYou: return "For You"
        case .trending: return "Trending"
        case .new: return "New"
        }
    }
}

struct TVReelItem: Identifiable, Hashable, Sendable {
    let id: String          // trailer key, or "tmdb-<id>" when no trailer exists
    let tmdbId: Int
    let isTV: Bool
    let title: String
    let overview: String
    let meta: String        // "DRAMA · 2024"
    let platformName: String
    let platformColor: Color
    let backdropUrl: String?
    let posterUrl: String?
    let thumbnailUrl: String?
    let trailerKey: String?
    let voteAverage: Double
    let tab: TVReelTab

    var canonicalTitleId: String {
        let kind = isTV ? "tv" : "movie"
        return "tmdb:\(kind):\(tmdbId)"
    }

    static func == (lhs: TVReelItem, rhs: TVReelItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Platform mapping

enum TVReelPlatform {
    static func recognizedKey(for raw: String?) -> String? {
        let key = (raw ?? "").lowercased()
        if key.contains("netflix") { return "netflix" }
        if key.contains("max") || key.contains("hbo") { return "hbo" }
        if key.contains("apple tv") { return "apple" }
        if key.contains("disney") { return "disney" }
        if key.contains("hulu") { return "hulu" }
        if key.contains("peacock") { return "peacock" }
        if key.contains("paramount") { return "paramount" }
        if key.contains("amazon") || key.contains("prime video") { return "prime" }
        if key.contains("starz") { return "starz" }
        if key.contains("showtime") { return "showtime" }
        if key.contains("crunchyroll") { return "crunchyroll" }
        if key.contains("youtube") { return "youtube" }
        return nil
    }

    static func info(for raw: String?) -> (name: String, color: Color) {
        let key = (raw ?? "").lowercased()
        switch key {
        case let s where s.contains("netflix"): return ("NETFLIX", Color(hex: "E50914"))
        case let s where s.contains("max") || s.contains("hbo"): return ("HBO MAX", Color(hex: "5A1FCB"))
        case let s where s.contains("apple tv"): return ("APPLE TV+", Color(hex: "1A1A1A"))
        case let s where s.contains("disney"): return ("DISNEY+", Color(hex: "113CCF"))
        case let s where s.contains("hulu"): return ("HULU", Color(hex: "1CE783"))
        case let s where s.contains("peacock"): return ("PEACOCK", Color(hex: "2A2A2A"))
        case let s where s.contains("paramount"): return ("PARAMOUNT+", Color(hex: "0064FF"))
        case let s where s.contains("amazon") || s.contains("prime video"): return ("PRIME VIDEO", Color(hex: "00A8E1"))
        case let s where s.contains("starz"): return ("STARZ", Color(hex: "1A1A1A"))
        case let s where s.contains("showtime"): return ("SHOWTIME", Color(hex: "D80000"))
        case let s where s.contains("crunchyroll"): return ("CRUNCHYROLL", Color(hex: "F47B20"))
        case let s where s.contains("youtube"): return ("YOUTUBE", Color(hex: "FF0000"))
        default: return ("STREAMING", TVTheme.orange)
        }
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class TVReelsViewModel {
    static let shared = TVReelsViewModel()

    var reels: [TVReelItem] = []
    var isLoading: Bool = true
    private var hasLoaded: Bool = false

    private let tmdb = TVTMDBService.shared

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        async let trendingTask = (try? tmdb.getTrending()) ?? []
        async let onAirTask = (try? tmdb.getOnTheAir()) ?? []
        async let popularTask = (try? tmdb.getPopularTV()) ?? []
        let (trending, onAir, popular) = await (trendingTask, onAirTask, popularTask)

        // For You is seeded from the user's saved titles, falling back to
        // trending so the section is never empty on a fresh account.
        let savedResults = savedTitleResults()

        async let forYouItems = buildItems(from: savedResults, tab: .forYou)
        async let popularItems = buildItems(from: Array(popular.prefix(20)), tab: .forYou)
        async let trendingItems = buildItems(from: Array(trending.prefix(20)), tab: .trending)
        async let newItems = buildItems(from: Array(onAir.prefix(20)), tab: .new)

        var (fy, pop, tr, nw) = await (forYouItems, popularItems, trendingItems, newItems)

        // Append popular TV to For You
        fy.append(contentsOf: pop)

        if fy.count < 6 {
            // Backfill For You with trending titles not already shown.
            let shown = Set(fy.map { $0.tmdbId })
            let extra = tr.filter { !shown.contains($0.tmdbId) }.prefix(8).map { item in
                TVReelItem(
                    id: "fy-\(item.id)", tmdbId: item.tmdbId, isTV: item.isTV,
                    title: item.title, overview: item.overview, meta: item.meta,
                    platformName: item.platformName, platformColor: item.platformColor,
                    backdropUrl: item.backdropUrl, posterUrl: item.posterUrl,
                    thumbnailUrl: item.thumbnailUrl, trailerKey: item.trailerKey,
                    voteAverage: item.voteAverage, tab: .forYou
                )
            }
            fy.append(contentsOf: extra)
        }

        var combined = fy + tr + nw
        var seen = Set<Int>()
        combined = combined.filter { seen.insert($0.tmdbId).inserted }

        self.reels = combined
        self.hasLoaded = !combined.isEmpty
    }

    /// Parses canonical `tmdb:<kind>:<id>` ids saved in the watch list into
    /// TMDB results we can enrich into reels.
    private func savedTitleResults() -> [TVTMDBResult] {
        TVStreamsViewModel.shared.userStreams.prefix(20).compactMap { stream -> TVTMDBResult? in
            let parts = stream.titleId.split(separator: ":")
            guard parts.count == 3, parts[0] == "tmdb", let id = Int(parts[2]) else { return nil }
            let kind = String(parts[1])
            return TVTMDBResult(
                id: id, mediaType: kind, name: stream.title, title: stream.title,
                posterPath: nil, backdropPath: nil, overview: nil,
                voteAverage: nil, firstAirDate: nil, releaseDate: nil
            )
        }
    }

    private func buildItems(from results: [TVTMDBResult], tab: TVReelTab) async -> [TVReelItem] {
        await withTaskGroup(of: TVReelItem?.self) { group in
            for r in results {
                group.addTask { [tmdb] in
                    async let keyTask = try? tmdb.getTrailerKey(tmdbId: r.id, isTV: r.isTV)
                    async let providerTask = try? tmdb.getTopWatchProvider(tmdbId: r.id, isTV: r.isTV)
                    async let genreTask: String? = r.isTV ? (try? tmdb.getTVGenre(tmdbId: r.id)) : nil
                    let (key, provider) = await (keyTask, providerTask)
                    let resolvedGenre = await genreTask

                    // Only surface titles we can actually point at a service.
                    guard let provider,
                          TVReelPlatform.recognizedKey(for: provider.providerName) != nil
                    else { return nil }

                    let plat = TVReelPlatform.info(for: provider.providerName)
                    let trailerKey = key ?? nil
                    let meta: String
                    if r.isTV {
                        let genreName = resolvedGenre ?? "DRAMA"
                        let yearStr = r.year.map { " · \($0)" } ?? ""
                        meta = "\(genreName.uppercased())\(yearStr)"
                    } else {
                        meta = "MOVIE\(r.year.map { " · \($0)" } ?? "")"
                    }
                    let thumb = (trailerKey).flatMap {
                        URL(string: "https://img.youtube.com/vi/\($0)/maxresdefault.jpg")?.absoluteString
                    }

                    return TVReelItem(
                        id: trailerKey ?? "tmdb-\(r.id)",
                        tmdbId: r.id,
                        isTV: r.isTV,
                        title: r.displayName,
                        overview: r.overview ?? "",
                        meta: meta,
                        platformName: plat.name,
                        platformColor: plat.color,
                        backdropUrl: r.backdropUrl,
                        posterUrl: r.posterUrl,
                        thumbnailUrl: thumb,
                        trailerKey: trailerKey,
                        voteAverage: r.voteAverage ?? 0,
                        tab: tab
                    )
                }
            }
            var out: [TVReelItem] = []
            for await item in group {
                if let item { out.append(item) }
            }
            return out
        }
    }
}

// MARK: - Reels Screen

/// Focusable destinations inside the actions overlay.
private enum TVReelAction: Hashable {
    case watch, sound, save, details
}

struct TVReelsView: View {
    @State private var vm = TVReelsViewModel.shared
    @State private var streams = TVStreamsViewModel.shared
    @State private var trailer = TVTrailerPlayer()
    @State private var index: Int = 0
    /// Direction of the last navigation, used to pick the slide transition.
    @State private var goingDown: Bool = true
    @State private var pendingDetail: TVTitleDetail?
    @State private var savedFlash: Bool = false
    @State private var showActions: Bool = false
    @FocusState private var feedFocused: Bool
    @FocusState private var actionFocus: TVReelAction?

    // Ad chip state
    @State private var adTargets: [(serviceId: String, name: String, color: Color)] = []
    @State private var adPage: Int = 0
    @State private var rotationTimer: Task<Void, Never>?

    private var current: TVReelItem? {
        vm.reels.indices.contains(index) ? vm.reels[index] : nil
    }

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()

            if vm.isLoading && vm.reels.isEmpty {
                ProgressView()
                    .scaleEffect(2.4)
                    .tint(.white)
            } else if vm.reels.isEmpty {
                emptyState
            } else if let reel = current {
                reelStage(reel)
            }

            if showActions, let reel = current {
                actionsOverlay(reel)
            }
        }
        .background(TVTheme.backgroundGradient)
        .focusable(!showActions)
        .focused($feedFocused)
        .onMoveCommand { direction in
            guard !showActions else { return }
            handleMove(direction)
        }
        .onPlayPauseCommand {
            guard !showActions else { return }
            trailer.togglePlayPause()
        }
        .onTapGesture {
            openActions()
        }
        .task {
            await streams.fetchUserStreams()
            await vm.loadIfNeeded()
            feedFocused = true
            loadCurrentTrailer()
            refreshAds()
        }
        .onChange(of: vm.reels.count) { _, count in
            if index >= count { index = max(0, count - 1) }
            loadCurrentTrailer()
            refreshAds()
        }
        .onChange(of: index) { _, _ in
            loadCurrentTrailer()
            refreshAds()
        }
        .onDisappear {
            trailer.stop()
            rotationTimer?.cancel()
        }
        .sheet(item: $pendingDetail) { detail in
            TVTitleSheet(detail: detail) { _ in
                pendingDetail = nil
                feedFocused = true
                trailer.resumeIfReady()
            }
        }
    }

    // MARK: - Stage

    @ViewBuilder
    private func reelStage(_ reel: TVReelItem) -> some View {
        ZStack {
            // Backdrop, keyed so each reel cross-fades + slides.
            TVRemoteImage(urlString: reel.backdropUrl ?? reel.posterUrl, contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()
                .id(reel.id)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: goingDown ? .bottom : .top).combined(with: .opacity),
                        removal: .opacity
                    )
                )

            // Inline trailer — crossfades in over the backdrop once the HLS
            // stream resolves and starts playing.
            if trailer.isReady, reel.trailerKey != nil {
                TVInlineVideoPlayer(player: trailer.player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            // Scrims for legibility.
            LinearGradient(
                colors: [.black.opacity(0.55), .clear, .black.opacity(0.20)],
                startPoint: .top, endPoint: .center
            )
            .ignoresSafeArea()
            LinearGradient(
                colors: [.clear, TVTheme.bg.opacity(0.6), TVTheme.bg],
                startPoint: .center, endPoint: .bottom
            )
            .ignoresSafeArea()
            LinearGradient(
                colors: [TVTheme.bg.opacity(0.85), .clear],
                startPoint: .leading, endPoint: .center
            )
            .ignoresSafeArea()

            topBar(reel)
            rightRail(reel)
            bottomContent(reel)

            if savedFlash {
                savedToast
            }

            // Ad chip — pinned bottom-right, never focusable
            if !adTargets.isEmpty {
                adChip(reel)
                    .padding(.trailing, 80)
                    .padding(.bottom, 80)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: reel.id)
    }

    // MARK: - Top bar (section tabs + position)

    private func topBar(_ reel: TVReelItem) -> some View {
        VStack {
            HStack(spacing: 28) {
                ForEach(TVReelTab.allCases, id: \.self) { tab in
                    let active = reel.tab == tab
                    Text(tab.label)
                        .font(.system(size: 24, weight: active ? .heavy : .semibold))
                        .foregroundStyle(active ? .white : TVTheme.textTertiary)
                        .overlay(alignment: .bottom) {
                            if active {
                                Capsule()
                                    .fill(TVTheme.orange)
                                    .frame(height: 4)
                                    .offset(y: 12)
                                    .shadow(color: TVTheme.orange.opacity(0.7), radius: 8)
                            }
                        }
                }

                Spacer()

                HStack(spacing: 10) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(TVTheme.orange)
                    Text("REELS")
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(.white)
                        .tracking(2)
                }
            }
            .padding(.horizontal, 80)
            .padding(.top, 50)
            Spacer()
        }
    }

    // MARK: - Right rail (rating + counter + hint)

    private func rightRail(_ reel: TVReelItem) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 26) {
                    if reel.voteAverage > 0 {
                        railChip(
                            icon: "star.fill",
                            text: String(format: "%.1f", reel.voteAverage),
                            tint: TVTheme.orange
                        )
                    }
                    railChip(
                        icon: streams.contains(titleId: reel.canonicalTitleId) ? "checkmark.circle.fill" : "plus.circle",
                        text: streams.contains(titleId: reel.canonicalTitleId) ? "Saved" : "Save",
                        tint: streams.contains(titleId: reel.canonicalTitleId) ? TVTheme.newsGreen : .white
                    )
                    railChip(
                        icon: "\(index + 1).circle",
                        text: "of \(vm.reels.count)",
                        tint: .white.opacity(0.8)
                    )
                }
                .padding(.trailing, 70)
                .padding(.bottom, 220)
            }
        }
    }

    private func railChip(icon: String, text: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Bottom content

    private func bottomContent(_ reel: TVReelItem) -> some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Text(reel.platformName)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(reel.platformColor, in: Capsule())
                    Text(reel.meta)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
                    trailerBadge(reel)
                }

                Text(reel.title)
                    .font(.system(size: 64, weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.5), radius: 14, y: 6)

                if !reel.overview.isEmpty {
                    Text(reel.overview)
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(TVTheme.textSecondary)
                        .lineLimit(3)
                        .frame(maxWidth: 980, alignment: .leading)
                }

                // Remote affordances — there is one focusable surface (the feed
                // itself) so we surface the controls as hints instead of buttons.
                HStack(spacing: 28) {
                    hint(icon: "chevron.up.chevron.down", text: "Browse")
                    hint(icon: "chevron.left.chevron.right", text: "Sections")
                    hint(icon: "playpause.fill", text: trailer.isPlaying ? "Pause" : "Play")
                    hint(icon: "circle.fill", text: "Actions")
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 80)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Shows the trailer status pill: "TRAILER" when one is available, or a
    /// muted "Trailer unavailable" affordance when none exists or the stream
    /// could not be resolved for this reel.
    @ViewBuilder
    private func trailerBadge(_ reel: TVReelItem) -> some View {
        if reel.trailerKey == nil || trailer.resolveFailed {
            HStack(spacing: 8) {
                Image(systemName: "film.slash")
                    .font(.system(size: 16, weight: .bold))
                Text("TRAILER UNAVAILABLE")
                    .font(.system(size: 16, weight: .heavy))
                    .tracking(1)
            }
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.white.opacity(0.06), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
        } else {
            HStack(spacing: 8) {
                Image(systemName: "film.fill")
                    .font(.system(size: 16, weight: .bold))
                Text("TRAILER")
                    .font(.system(size: 16, weight: .heavy))
                    .tracking(1)
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.white.opacity(0.10), in: Capsule())
        }
    }

    private func hint(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(TVTheme.orange)
            Text(text)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.white.opacity(0.06), in: Capsule())
    }

    private var savedToast: some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(TVTheme.newsGreen)
                Text("Added to Watch List")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 120)
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "film.stack")
                .font(.system(size: 70, weight: .bold))
                .foregroundStyle(TVTheme.orange)
            Text("No reels yet")
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(.white)
            Text("Trending trailers will appear here.")
                .font(.system(size: 22))
                .foregroundStyle(TVTheme.textSecondary)
        }
    }

    // MARK: - Actions overlay

    private func actionsOverlay(_ reel: TVReelItem) -> some View {
        let saved = streams.contains(titleId: reel.canonicalTitleId)
        return ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text(reel.title)
                        .font(.system(size: 40, weight: .black))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(reel.meta)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(TVTheme.textSecondary)
                }

                HStack(spacing: 26) {
                    actionTile(
                        icon: "play.tv.fill",
                        label: "Watch on\n\(reel.platformName.capitalized)",
                        tint: reel.platformColor,
                        focus: .watch,
                        action: launchStreaming
                    )
                    actionTile(
                        icon: trailer.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        label: trailer.isMuted ? "Unmute\nTrailer" : "Mute\nTrailer",
                        tint: .white.opacity(0.14),
                        focus: .sound,
                        action: { trailer.isMuted.toggle() }
                    )
                    actionTile(
                        icon: saved ? "checkmark.circle.fill" : "plus.circle.fill",
                        label: saved ? "Saved" : "Save to\nWatch List",
                        tint: saved ? TVTheme.newsGreen : .white.opacity(0.14),
                        focus: .save,
                        action: toggleSave
                    )
                    actionTile(
                        icon: "info.circle.fill",
                        label: "Full\nDetails",
                        tint: .white.opacity(0.14),
                        focus: .details,
                        action: openDetail
                    )
                }
            }
            .padding(48)
        }
        .onExitCommand { closeActions() }
        .transition(.opacity)
    }

    private func actionTile(
        icon: String,
        label: String,
        tint: Color,
        focus: TVReelAction,
        action: @escaping () -> Void
    ) -> some View {
        let isFocused = actionFocus == focus
        return Button(action: action) {
            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 96, height: 96)
                    .background(tint, in: Circle())
                Text(label)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(width: 200, height: 200)
            .background(.white.opacity(isFocused ? 0.16 : 0.06), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(TVTheme.orange, lineWidth: isFocused ? 4 : 0)
            )
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
        }
        .buttonStyle(.plain)
        .focused($actionFocus, equals: focus)
    }

    // MARK: - Interaction

    private func handleMove(_ direction: MoveCommandDirection) {
        guard !vm.reels.isEmpty else { return }
        switch direction {
        case .down:
            guard index < vm.reels.count - 1 else { return }
            goingDown = true
            withAnimation { index += 1 }
        case .up:
            guard index > 0 else { return }
            goingDown = false
            withAnimation { index -= 1 }
        case .right:
            jumpToAdjacentSection(forward: true)
        case .left:
            jumpToAdjacentSection(forward: false)
        default:
            break
        }
    }

    /// Moves to the first reel of the next/previous section so left/right on
    /// the remote behaves like switching the phone app's tab pills.
    private func jumpToAdjacentSection(forward: Bool) {
        guard let currentTab = current?.tab,
              let tabIdx = TVReelTab.allCases.firstIndex(of: currentTab) else { return }
        let order = TVReelTab.allCases
        let nextIdx = forward ? tabIdx + 1 : tabIdx - 1
        guard order.indices.contains(nextIdx) else { return }
        let targetTab = order[nextIdx]
        guard let target = vm.reels.firstIndex(where: { $0.tab == targetTab }) else { return }
        goingDown = forward
        withAnimation { index = target }
    }

    /// Resolves + plays the current reel's trailer inline, then warms up the
    /// neighbouring reels' trailers so swiping starts playback instantly.
    private func loadCurrentTrailer() {
        trailer.load(key: current?.trailerKey)
        prefetchNeighbors()
    }

    /// Pre-resolves the next two reels (and the previous one) so fast scrolling
    /// down the feed still hits warm, instantly-playable trailers.
    private func prefetchNeighbors() {
        for offset in [1, 2, -1] {
            let neighbor = index + offset
            guard vm.reels.indices.contains(neighbor) else { continue }
            trailer.prefetch(key: vm.reels[neighbor].trailerKey)
        }
    }

    private func openActions() {
        guard current != nil else { return }
        actionFocus = .watch
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showActions = true }
    }

    private func closeActions() {
        withAnimation(.easeOut(duration: 0.2)) { showActions = false }
        feedFocused = true
    }

    /// Opens the streaming app for the current reel on this Apple TV.
    private func launchStreaming() {
        guard let reel = current else { return }
        TVOSDeepLinker.open(platform: reel.platformName, title: reel.title)
        closeActions()
    }

    private func openDetail() {
        guard let reel = current else { return }
        closeActions()
        pendingDetail = TVTitleDetail(
            titleId: reel.canonicalTitleId,
            title: reel.title,
            overview: reel.overview,
            posterUrl: reel.posterUrl,
            backdropUrl: reel.backdropUrl,
            tag: reel.isTV ? "SERIES" : "MOVIE",
            accent: TVTheme.orange,
            year: nil,
            platform: reel.platformName.capitalized
        )
    }

    private func toggleSave() {
        guard let reel = current else { return }
        let wasSaved = streams.contains(titleId: reel.canonicalTitleId)
        Task {
            await streams.toggle(
                titleId: reel.canonicalTitleId,
                title: reel.title,
                posterUrl: reel.posterUrl,
                platform: reel.platformName
            )
        }
        if !wasSaved {
            withAnimation { savedFlash = true }
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation { savedFlash = false }
            }
        }
    }

    // MARK: - Ad chip

    /// Resolves eligible affiliate services for the ad carousel, mirroring the
    /// phone app's `resolveGlassAds`. Excludes the current platform and any
    /// service the user already owns, with the same fallback tiers.
    private func resolveReelAds(count: Int, tmdbId: Int, currentPlatformName: String) -> [(serviceId: String, name: String, color: Color)] {
        let pool: [(serviceId: String, name: String, color: Color)] = [
            ("netflix", "Netflix", Color(hex: "E50914")),
            ("hbo", "Max", Color(hex: "001EE0")),
            ("hulu", "Hulu", Color(hex: "1CE783")),
            ("disney", "Disney+", Color(hex: "0E293F")),
            ("apple", "Apple TV+", Color(hex: "000000")),
            ("prime", "Prime Video", Color(hex: "1A202C")),
            ("paramount", "Paramount+", Color(hex: "0064FF")),
            ("peacock", "Peacock", Color(hex: "000000")),
        ]
        let currentKey = TVReelPlatform.recognizedKey(for: currentPlatformName)

        // Preferred: exclude current platform AND services the user already owns.
        var eligible = pool.filter { ad in
            guard ad.serviceId != currentKey else { return false }
            let lower = ad.serviceId.lowercased()
            return !AuthViewModel.shared.selectedServices.contains(where: { $0.lowercased() == lower })
        }
        // Secondary: exclude only current platform.
        if eligible.isEmpty {
            eligible = pool.filter { $0.serviceId != currentKey }
        }
        // Full pool fallback.
        if eligible.isEmpty {
            eligible = pool
        }

        let rotation = abs(tmdbId) % eligible.count
        let rotated = Array(eligible[rotation...] + eligible[..<rotation])
        return Array(rotated.prefix(count))
    }

    private func refreshAds() {
        rotationTimer?.cancel()
        guard let reel = current else { return }
        adTargets = resolveReelAds(count: 5, tmdbId: reel.tmdbId, currentPlatformName: reel.platformName)
        adPage = 0

        // Log initial impression.
        if let first = adTargets.first {
            WatchIntentLogger.shared.log(
                eventType: .adImpression,
                platformId: first.serviceId,
                metadata: ["source": "reel_ad_carousel", "position": 0, "show_platform": reel.platformName]
            )
        }

        guard adTargets.count > 1 else { return }
        rotationTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5.5))
                guard !Task.isCancelled else { break }
                let targets = adTargets
                let page = adPage
                guard targets.count > 1 else { continue }
                let next = (page + 1) % targets.count
                withAnimation {
                    adPage = next
                }
                if targets.indices.contains(next) {
                    let ad = targets[next]
                    WatchIntentLogger.shared.log(
                        eventType: .adImpression,
                        platformId: ad.serviceId,
                        metadata: ["source": "reel_ad_carousel", "position": next, "show_platform": reel.platformName]
                    )
                }
            }
        }
    }

    private func adInitials(_ name: String) -> String {
        let parts = name.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(1)).uppercased()
    }

    @ViewBuilder
    private func adChip(_ reel: TVReelItem) -> some View {
        VStack(spacing: 9) {
            // Chip
            if let ad = adTargets.indices.contains(adPage) ? adTargets[adPage] : nil {
                HStack(spacing: 10) {
                    // Brand tile
                    RoundedRectangle(cornerRadius: 9)
                        .fill(ad.color)
                        .frame(width: 36, height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(.white.opacity(0.14), lineWidth: 1)
                        )
                        .overlay(
                            Text(adInitials(ad.name))
                                .font(.system(size: 14, weight: .heavy))
                                .foregroundStyle(.white)
                        )

                    Text("Stream on \(ad.name)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(height: 56)
                .padding(.horizontal, 14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .background(TVTheme.bg.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    Text("AD")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 4))
                        .padding(.leading, 4)
                        .padding(.top, 4)
                        .allowsHitTesting(false)
                }
            }

            // Dots
            HStack(spacing: 6) {
                ForEach(0..<adTargets.count, id: \.self) { i in
                    Circle()
                        .fill(i == adPage ? TVTheme.orange : .white.opacity(0.3))
                        .frame(width: 5, height: 5)
                }
            }
        }
    }
}

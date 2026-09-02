//
//  TVReelsView.swift
//  GuideStreamTVTV
//
//  Reels for Apple TV. One trailer per screen, driven by the remote rather
//  than a swipe: up and down step reels, left and right walk one action row,
//  select fires the focused action.
//
//  Ported from the iPhone screen, with four decisions taken for the TV:
//   * Watch Now deep-links straight out through TVOSDeepLinker rather than
//     opening a detail sheet first.
//   * A trailer that plays to the end advances to the next reel. The phone
//     never does this because the viewer swipes; a lean-back surface should
//     keep going.
//   * The feed carries the same four sources and the same pagination as the
//     phone, including the sponsored full-page reel after every third.
//   * The transient chrome — copy block, the three social buttons and the
//     scrubber — drops 2.5s after the last press, the same two-stage
//     choreography the phone uses in landscape at 3.0s: fade over 0.45s,
//     then out of layout 0.55s later so the persistent group settles over
//     0.50s. Persistent: the chips row, the ad carousel and Watch Now.
//

import SwiftUI
import AVFoundation

struct TVReelsView: View {
    /// When non-empty the screen plays this title-scoped feed instead of the
    /// browse feed — how the detail screen's Trailers & Clips row opens.
    /// Mirrors `ReelsScreen(injectedReels:injectedStartIndex:)` on iPhone.
    private let injectedReels: [TVReelItem]

    init(injectedReels: [TVReelItem] = [], startIndex: Int = 0) {
        self.injectedReels = injectedReels
        _index = State(initialValue: max(0, startIndex))
    }

    @State private var vm = TVReelsViewModel()
    @State private var social = TVSocialService.shared
    @State private var streams = TVStreamsViewModel.shared

    @State private var index: Int = 0
    @State private var focus: TVReelAction = .watch
    @State private var player: AVPlayer?
    @State private var videoReady: Bool = false
    @State private var adDismissed: Bool = false
    /// Bumped when the ad chip is selected. The carousel owns which page is
    /// showing, so it opens the offer rather than the screen guessing.
    @State private var adSelectSignal: Int = 0

    /// Transient chrome state, mirroring the phone's landscape pair.
    @State private var chromeVisible: Bool = true
    @State private var chromePresent: Bool = true
    @State private var chromeTask: Task<Void, Never>?

    @State private var playbackTask: Task<Void, Never>?
    @State private var endTask: Task<Void, Never>?

    @FocusState private var hasFocus: Bool
    @Namespace private var reelScope

    private static let idleSeconds: Double = 2.5
    private static let fadeSeconds: Double = 0.45
    private static let leaveDelay: Double = 0.55
    private static let settleSeconds: Double = 0.50

    private var current: TVReelItem? {
        vm.reels.indices.contains(index) ? vm.reels[index] : nil
    }

    var body: some View {
        ZStack {
            TVTheme.backgroundGradient

            if let item = current {
                reelPage(item)
            } else if vm.isLoading {
                ProgressView().scaleEffect(2).tint(.white)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .focusable()
        .focused($hasFocus)
        .focusScope(reelScope)
        .focusEffectDisabled()
        // Swipes reach this as move commands too, and Reels is the one place
        // where consuming all four directions is correct: the screen is a
        // single focusable view with nowhere for the focus engine to go.
        .onMoveCommand(perform: handleMove)
        // On tvOS a tap gesture on a focused view is the Select button.
        .onTapGesture { fire() }
        .onPlayPauseCommand { togglePlayback() }
        .task {
            if !injectedReels.isEmpty {
                vm.inject(injectedReels)
            } else {
                await vm.load()
            }
            hasFocus = true
            armChromeHide()
            await startPlayback()
        }
        .onDisappear { teardown() }
        .onChange(of: index) { _, _ in
            Task {
                await startPlayback()
                await vm.loadMoreIfNeeded(currentIndex: index)
            }
        }
    }

    // MARK: - Page

    @ViewBuilder
    private func reelPage(_ item: TVReelItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop sits under the player so the reel is never blank
            // while the stream loads, and collapses back to it on failure.
            TVRemoteImage(urlString: item.backdropUrl, contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            if let player {
                TVReelVideoLayer(player: player)
                    .opacity(videoReady ? 1 : 0)
                    .animation(.easeOut(duration: 0.4), value: videoReady)
            }

            scrims
            positionDots

            bottomBlock(item)
                .padding(.leading, TVLayout.contentLeading)
                .padding(.trailing, TVLayout.contentLeading)
                .padding(.bottom, 96)
        }
        .clipped()
    }

    private var scrims: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.55), Color.black.opacity(0.0)],
                startPoint: .top, endPoint: .center
            )
            LinearGradient(
                colors: [
                    Color(red: 0x04 / 255, green: 0x09 / 255, blue: 0x0F / 255).opacity(0.0),
                    Color(red: 0x04 / 255, green: 0x09 / 255, blue: 0x0F / 255).opacity(0.74),
                    Color(red: 0x04 / 255, green: 0x09 / 255, blue: 0x0F / 255).opacity(0.96)
                ],
                startPoint: .center, endPoint: .bottom
            )
            LinearGradient(
                colors: [
                    Color(red: 0x04 / 255, green: 0x09 / 255, blue: 0x0F / 255).opacity(0.78),
                    Color.clear
                ],
                startPoint: .leading, endPoint: .center
            )
        }
        .allowsHitTesting(false)
    }

    private var positionDots: some View {
        VStack(spacing: 12) {
            ForEach(Array(vm.reels.prefix(12).enumerated()), id: \.offset) { offset, _ in
                Capsule()
                    .fill(offset == index ? TVTheme.orange : Color.white.opacity(0.30))
                    .frame(width: 10, height: offset == index ? 34 : 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .padding(.trailing, 60)
        .animation(.easeInOut(duration: 0.28), value: index)
    }

    // MARK: - Bottom block

    @ViewBuilder
    private func bottomBlock(_ item: TVReelItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            chipsRow(item)                       // persistent

            if chromePresent {                   // transient
                copyBlock(item)
                    .opacity(chromeVisible ? 1 : 0)
                    .animation(.easeOut(duration: Self.fadeSeconds), value: chromeVisible)
            }

            if !item.isSponsored {               // persistent
                TVReelAdCarousel(
                    titleName: item.title,
                    titleId: item.canonicalTitleId,
                    providerName: item.platformName,
                    tmdbId: item.tmdbId,
                    isDismissed: $adDismissed,
                    isFocusedChip: focus == .ad,
                    isFocusedDismiss: focus == .adDismiss,
                    selectSignal: adSelectSignal
                )
            }

            actionRow(item)
        }
        .animation(.easeOut(duration: Self.settleSeconds), value: chromePresent)
    }

    private func chipsRow(_ item: TVReelItem) -> some View {
        HStack(spacing: 12) {
            if let platform = item.platformName {
                chip(platform.uppercased(), filled: true)
            }
            if let genre = item.genre {
                chip(genre, filled: false)
            }
            chip(item.isSponsored ? "SPONSORED" : (item.isTV ? "Series" : "Film"), filled: false)
        }
    }

    private func chip(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(filled ? TVTheme.orange.opacity(0.85) : Color.white.opacity(0.12))
            )
            .overlay {
                if !filled {
                    RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.22), lineWidth: 1)
                }
            }
    }

    private func copyBlock(_ item: TVReelItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.title)
                .font(.system(size: 54, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(2)
            if !item.synopsis.isEmpty {
                Text(item.synopsis)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(TVTheme.textSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: 820, alignment: .leading)
            }
            Text(metaLine(item))
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(TVTheme.textTertiary)
        }
    }

    private func metaLine(_ item: TVReelItem) -> String {
        var parts: [String] = []
        if let year = item.year { parts.append(String(year)) }
        parts.append(item.isTV ? "Series" : "Film")
        if let platform = item.platformName { parts.append(platform) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Actions

    @ViewBuilder
    private func actionRow(_ item: TVReelItem) -> some View {
        HStack(spacing: 18) {
            actionButton(
                title: item.isSponsored ? "Get the app" : "Watch Now",
                systemImage: "play.fill",
                isFocused: focus == .watch,
                tint: TVTheme.orange,
                active: true
            )

            if !item.isSponsored, chromePresent {
                HStack(spacing: 18) {
                    actionButton(
                        title: social.isLiked(item.canonicalTitleId) ? "Liked" : "Like",
                        systemImage: social.isLiked(item.canonicalTitleId) ? "heart.fill" : "heart",
                        isFocused: focus == .like,
                        tint: Color(red: 1.0, green: 0.23, blue: 0.36),
                        active: social.isLiked(item.canonicalTitleId),
                        trailing: social.likeCount(item.canonicalTitleId) > 0
                            ? Self.shortCount(social.likeCount(item.canonicalTitleId)) : nil
                    )
                    actionButton(
                        title: streams.contains(titleId: item.canonicalTitleId) ? "Saved" : "Save",
                        systemImage: streams.contains(titleId: item.canonicalTitleId)
                            ? "checkmark.circle.fill" : "plus.circle.fill",
                        isFocused: focus == .save,
                        tint: TVTheme.orange,
                        active: streams.contains(titleId: item.canonicalTitleId)
                    )
                    actionButton(
                        title: "Watched",
                        systemImage: social.isWatched(item.canonicalTitleId) ? "eye.fill" : "eye",
                        isFocused: focus == .watched,
                        tint: TVTheme.blue,
                        active: social.isWatched(item.canonicalTitleId)
                    )
                }
                .opacity(chromeVisible ? 1 : 0)
                .animation(.easeOut(duration: Self.fadeSeconds), value: chromeVisible)
            }
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        isFocused: Bool,
        tint: Color,
        active: Bool,
        trailing: String? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .bold))
            Text(title)
                .font(.system(size: 21, weight: .semibold))
            if let trailing {
                Text(trailing)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .foregroundStyle(active ? tint : Color.white)
        .padding(.horizontal, 28)
        .frame(height: 64)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(active ? tint.opacity(0.22) : Color.white.opacity(0.14))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(isFocused ? Color.white : Color.white.opacity(0.18), lineWidth: isFocused ? 4 : 1)
        }
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isFocused)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "play.slash")
                .font(.system(size: 70))
                .foregroundStyle(TVTheme.textTertiary)
            Text("No trailers right now")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(TVTheme.textPrimary)
        }
    }

    // MARK: - Remote

    private func handleMove(_ direction: MoveCommandDirection) {
        // The phone brings its chrome back on any tap without also acting on
        // it. Same here, so nothing fires while it is off screen.
        if !chromeVisible { armChromeHide(); return }
        armChromeHide()

        switch direction {
        case .up:    step(-1)
        case .down:  step(1)
        case .left:  focus = focus.previous(adAvailable: adAvailable)
        case .right: focus = focus.next(adAvailable: adAvailable)
        default:     break
        }
    }

    private var adAvailable: Bool {
        guard let item = current else { return false }
        return !item.isSponsored && !adDismissed
    }

    private func step(_ delta: Int) {
        guard !vm.reels.isEmpty else { return }
        let next = index + delta
        guard vm.reels.indices.contains(next) else { return }
        index = next
        focus = .watch
        adDismissed = false
    }

    /// Wired to the select button by the focusable container.
    private func fire() {
        guard let item = current else { return }
        armChromeHide()
        switch focus {
        case .watch:      openWatch(item)
        case .like:
            Task { await social.toggleLike(titleId: item.canonicalTitleId,
                                           mediaType: item.mediaType, tmdbId: item.tmdbId) }
        case .save:
            Task { await streams.toggle(titleId: item.canonicalTitleId, title: item.title,
                                        posterUrl: item.posterUrl, platform: item.platformName) }
        case .watched:
            Task { await social.toggleWatched(titleId: item.canonicalTitleId, titleName: item.title,
                                              mediaType: item.mediaType, tmdbId: item.tmdbId) }
        case .ad:         adSelectSignal += 1
        case .adDismiss:  adDismissed = true; focus = .watch
        }
    }

    private func openWatch(_ item: TVReelItem) {
        WatchIntentLogger.shared.log(
            eventType: .deeplinkFired,
            titleId: item.canonicalTitleId,
            platformId: item.platformId,
            metadata: ["source": "tv_reels_watch_now"]
        )
        TVOSDeepLinker.open(
            platform: item.platformId ?? "tmdb",
            title: item.title,
            contentURL: nil
        ) { _ in }
    }

    // MARK: - Transient chrome

    /// Reveals the chrome and restarts the 2.5s countdown.
    private func armChromeHide() {
        chromeTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            chromeVisible = true
            chromePresent = true
        }
        chromeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.idleSeconds))
            guard !Task.isCancelled else { return }
            // Focus cannot sit on a control that is leaving the screen.
            if focus == .like || focus == .save || focus == .watched { focus = .watch }
            withAnimation(.easeOut(duration: Self.fadeSeconds)) { chromeVisible = false }
            try? await Task.sleep(for: .seconds(Self.leaveDelay))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: Self.settleSeconds)) { chromePresent = false }
        }
    }

    // MARK: - Playback

    private func startPlayback() async {
        playbackTask?.cancel()
        endTask?.cancel()
        player?.pause()
        player = nil
        videoReady = false

        guard let item = current, !item.isSponsored else { return }
        guard let urlString = await vm.stream(for: item), let url = URL(string: urlString) else { return }
        guard currentMatches(item) else { return }

        Self.activateAudioSessionIfNeeded()
        let newPlayer = AVPlayer(playerItem: AVPlayerItem(url: url))
        newPlayer.isMuted = false
        player = newPlayer
        newPlayer.play()

        WatchIntentLogger.shared.log(
            eventType: .trailerViewed,
            titleId: item.canonicalTitleId,
            metadata: ["surface": "tv_reels"]
        )

        playbackTask = Task { @MainActor [weak newPlayer] in
            for _ in 0..<200 {
                guard !Task.isCancelled, let newPlayer else { return }
                if newPlayer.timeControlStatus == .playing {
                    withAnimation(.easeOut(duration: 0.4)) { videoReady = true }
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        // A trailer that reaches the end rolls on to the next reel.
        endTask = Task { @MainActor [weak newPlayer] in
            guard let newPlayer else { return }
            for await _ in NotificationCenter.default.notifications(
                named: .AVPlayerItemDidPlayToEndTime,
                object: newPlayer.currentItem
            ) {
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.4)) { videoReady = false }
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                step(1)
                return
            }
        }
    }

    /// Reels play with sound, and tvOS will not start playback at all while
    /// the process has no active audio session — the item reaches
    /// .readyToPlay and then sits at .paused with no error.
    private static func activateAudioSessionIfNeeded() {
        guard !audioSessionActivated else { return }
        audioSessionActivated = true
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            audioSessionActivated = false
        }
    }

    private nonisolated(unsafe) static var audioSessionActivated = false

    private func togglePlayback() {
        guard let player else { return }
        armChromeHide()
        if player.timeControlStatus == .playing { player.pause() } else { player.play() }
    }

    private func currentMatches(_ item: TVReelItem) -> Bool {
        current?.id == item.id
    }

    private func teardown() {
        chromeTask?.cancel()
        playbackTask?.cancel()
        endTask?.cancel()
        player?.pause()
        player = nil
    }

    private static func shortCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return String(n)
    }
}

// MARK: - Focus row

/// The single horizontal row of focusable actions. Up and down are reserved
/// for stepping reels, so everything selectable lives on one axis.
enum TVReelAction: Int, CaseIterable {
    case watch, like, save, watched, ad, adDismiss

    func next(adAvailable: Bool) -> TVReelAction {
        let order = TVReelAction.order(adAvailable: adAvailable)
        guard let i = order.firstIndex(of: self), i + 1 < order.count else { return self }
        return order[i + 1]
    }

    func previous(adAvailable: Bool) -> TVReelAction {
        let order = TVReelAction.order(adAvailable: adAvailable)
        guard let i = order.firstIndex(of: self), i > 0 else { return self }
        return order[i - 1]
    }

    static func order(adAvailable: Bool) -> [TVReelAction] {
        adAvailable
            ? [.watch, .like, .save, .watched, .ad, .adDismiss]
            : [.watch, .like, .save, .watched]
    }
}

// MARK: - Video layer

/// Controls-free AVPlayerLayer host, the same shape the hero uses.
private struct TVReelVideoLayer: UIViewRepresentable {
    let player: AVPlayer

    final class HostView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        view.backgroundColor = .clear
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: HostView, context: Context) {
        if uiView.playerLayer.player !== player { uiView.playerLayer.player = player }
    }
}

//
//  TVHeroCarousel.swift
//  GuideStreamTVTV
//
//  Full-screen featurette hero for Home. The embedded video or fallback
//  poster image consumes the full width of the screen and fades off into
//  the bottom of the first rail of content. Each item fills the safe area:
//  a hosted featurette (public.title_featurettes) plays muted and exactly
//  once when one resolves, otherwise the backdrop still drifts slowly
//  from 1.0 to 1.08 under the same gradients. On advance the outgoing
//  item rotates out to the left while the incoming item rotates in from
//  the right (mirrored for back-steps). The dwell ends when the
//  featurette finishes or after 10 seconds for a still; the final item
//  holds as a static poster. Left/right move commands step items while
//  the hero region holds focus — a left move at the first item falls
//  through to the side menu via TVHeroSideMenuRequestKey.
//

import SwiftUI
import AVFoundation
import UIKit

/// Preference the hero raises when a left move at the first item should
/// fall through to opening the side menu. Handled by TVMainView; the
/// value is a monotonic counter so only real requests open the menu.
struct TVHeroSideMenuRequestKey: PreferenceKey {
    static var defaultValue: Int = 0
    static func reduce(value: inout Int, nextValue: () -> Int) {
        value = max(value, nextValue())
    }
}

struct TVHeroCarousel: View {
    let items: [TVTMDBResult]
    let onToggleSave: (TVTMDBResult) -> Void
    let isSaved: (TVTMDBResult) -> Bool
    /// canonicalTitleId -> hosted featurette URL. A missing key means the
    /// item renders as a drifting still.
    let featurettes: [String: String]

    @State private var index: Int = 0
    /// +1 = forward (out left, in from right); -1 = mirrored for back-steps.
    @State private var direction: Int = 1
    @State private var dwellTask: Task<Void, Never>?
    @State private var endOfItemTask: Task<Void, Never>?
    @State private var playbackStatusTask: Task<Void, Never>?
    @State private var player: AVPlayer?
    @State private var videoReady: Bool = false
    /// The first manual move permanently stops auto-advance for this
    /// appearance of the screen; reset in onAppear.
    @State private var autoAdvanceDisabled: Bool = false
    @State private var menuRequestCount: Int = 0

    @FocusState private var isCTAFocused: Bool
    @FocusState private var heroRegionFocused: Bool
    /// Focus scope for the hero region. The Add to Watch List button is
    /// the default focus inside this scope so Home appears with the hero
    /// focused rather than the first rail card.
    @Namespace private var heroNamespace

    private var currentItem: TVTMDBResult? {
        items.indices.contains(index) ? items[index] : nil
    }

    /// The metadata block is visible while the hero region (or the CTA
    /// inside it) holds focus, and fades out when focus enters the rails.
    private var metadataVisible: Bool {
        isCTAFocused || heroRegionFocused
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop layers — only the current item is mounted; the
            // asymmetric rotate transition animates the handoff.
            ZStack {
                if let item = currentItem {
                    itemLayer(for: item)
                        .id(index)
                        .transition(.asymmetric(
                            insertion: .modifier(
                                active: TVHeroRotateModifier(
                                    angle: Double(35 * direction),
                                    offset: 240 * CGFloat(direction),
                                    opacity: 0
                                ),
                                identity: TVHeroRotateModifier(angle: 0, offset: 0, opacity: 1)
                            ),
                            removal: .modifier(
                                active: TVHeroRotateModifier(
                                    angle: Double(-35 * direction),
                                    offset: -240 * CGFloat(direction),
                                    opacity: 0
                                ),
                                identity: TVHeroRotateModifier(angle: 0, offset: 0, opacity: 1)
                            )
                        ))
                }
            }
            .animation(.easeInOut(duration: 0.65), value: index)

            metadataBlock
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .focusable()
        .focused($heroRegionFocused)
        .focusScope(heroNamespace)
        .focusEffectDisabled()
        .onMoveCommand(perform: handleMoveCommand)
        .preference(key: TVHeroSideMenuRequestKey.self, value: menuRequestCount)
        .onAppear {
            autoAdvanceDisabled = false
            startDwell()
        }
        .onDisappear {
            dwellTask?.cancel()
            endOfItemTask?.cancel()
            playbackStatusTask?.cancel()
            teardownPlayer()
        }
        .onChange(of: index) { _, _ in
            startDwell()
        }
        .onChange(of: items.count) { _, _ in
            index = 0
            startDwell()
        }
    }

    // MARK: - Layers

    /// One item's background: the drifting still always renders, with the
    /// muted featurette layer fading in above it once playback actually
    /// starts (so a failed load or stall simply leaves the still). The
    /// hero art fills the full width and fades off at the bottom into the
    /// first rail of content.
    @ViewBuilder
    private func itemLayer(for item: TVTMDBResult) -> some View {
        ZStack {
            TVHeroStillBackdrop(urlString: item.backdropUrl)
            if let player {
                TVFeaturetteLayer(player: player)
                    .opacity(videoReady ? 1 : 0)
                    .animation(.easeOut(duration: 0.6), value: videoReady)
            }
        }
        .overlay {
            LinearGradient(
                colors: [
                    Color(red: 0x04 / 255, green: 0x09 / 255, blue: 0x0F / 255).opacity(0.0),
                    Color(red: 0x04 / 255, green: 0x09 / 255, blue: 0x0F / 255).opacity(0.35),
                    Color(red: 0x04 / 255, green: 0x09 / 255, blue: 0x0F / 255).opacity(0.72),
                    Color(red: 0x04 / 255, green: 0x09 / 255, blue: 0x0F / 255).opacity(0.92)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .overlay {
            LinearGradient(
                colors: [
                    Color(red: 0x04 / 255, green: 0x09 / 255, blue: 0x0F / 255).opacity(0.75),
                    Color.clear
                ],
                startPoint: .leading,
                endPoint: .center
            )
        }
    }

    /// Metadata block, bottom-leading, sitting above the peeking first
    /// rail. All four elements (eyebrow, title, overview, CTA) are
    /// preserved per item.
    @ViewBuilder
    private var metadataBlock: some View {
        if let item = currentItem {
            VStack(alignment: .leading, spacing: 18) {
                Text(item.isTV ? "TRENDING SHOW" : "TRENDING MOVIE")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(TVTheme.orange)
                    .tracking(2)
                Text(item.displayName)
                    .font(.system(size: 54, weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(TVTheme.textSecondary)
                        .lineLimit(3)
                        .frame(maxWidth: 820, alignment: .leading)
                }

                Button {
                    onToggleSave(item)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: isSaved(item) ? "checkmark.circle.fill" : "plus.circle.fill")
                            .font(.system(size: 28, weight: .bold))
                        Text(isSaved(item) ? "Saved to Watch List" : "Add to Watch List")
                            .font(.system(size: 22, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 18)
                }
                .buttonStyle(.card)
                .focused($isCTAFocused)
                .prefersDefaultFocus(true, in: heroNamespace)
                .padding(.top, 6)
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 120)
            .opacity(metadataVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: metadataVisible)
            .animation(.easeOut(duration: 0.35), value: index)
        }
    }

    // MARK: - Dwell & rotation

    /// Starts the current item's dwell: a hosted featurette plays once and
    /// advances on its end; a still (or a featurette that never starts)
    /// advances after 10 seconds. The last item holds as a static poster.
    private func startDwell() {
        dwellTask?.cancel()
        endOfItemTask?.cancel()
        playbackStatusTask?.cancel()
        teardownPlayer()

        guard let item = currentItem, items.count > 1, index < items.count - 1 else {
            return
        }

        if let urlString = featurettes[item.canonicalTitleId], let url = URL(string: urlString) {
            setUpPlayer(for: item, url: url)
            dwellTask = Task { @MainActor in
                // 10-second fallback while the featurette never starts
                // (failed load or stall) — the still stays visible.
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                guard videoReady else {
                    advance()
                    return
                }
                // Playing — the end-of-item observer owns advancing, but a
                // mid-playback stall still needs an out: advance after the
                // player sits idle well past any plausible rebuffer.
                var idleChecks = 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    if player?.timeControlStatus == .playing {
                        idleChecks = 0
                    } else {
                        idleChecks += 1
                        if idleChecks >= 3 {
                            advance()
                            return
                        }
                    }
                }
            }
        } else {
            dwellTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                advance()
            }
        }
    }

    private func setUpPlayer(for item: TVTMDBResult, url: URL) {
        let playerItem = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.isMuted = true
        player = newPlayer
        newPlayer.play()

        // Fade the layer in and log the view the moment playback actually
        // starts; until then the drifting still stays visible underneath.
        playbackStatusTask = Task { @MainActor [weak newPlayer] in
            guard let newPlayer else { return }
            if newPlayer.timeControlStatus == .playing {
                markVideoReady(for: item)
                return
            }
            for await status in newPlayer.publisher(for: \.timeControlStatus).values {
                guard !Task.isCancelled else { return }
                guard status == .playing else { continue }
                markVideoReady(for: item)
                return
            }
        }

        endOfItemTask = Task { @MainActor [weak newPlayer] in
            guard let newPlayer else { return }
            for await _ in NotificationCenter.default.notifications(
                named: .AVPlayerItemDidPlayToEndTime,
                object: newPlayer.currentItem
            ) {
                guard !Task.isCancelled else { return }
                advance()
                return
            }
        }
    }

    private func markVideoReady(for item: TVTMDBResult) {
        withAnimation(.easeOut(duration: 0.6)) {
            videoReady = true
        }
        WatchIntentLogger.shared.log(
            eventType: .trailerViewed,
            titleId: item.canonicalTitleId,
            metadata: ["surface": "tv_home_hero"]
        )
    }

    private func teardownPlayer() {
        player?.pause()
        player = nil
        videoReady = false
    }

    /// Auto-advance to the next item. Manual moves disable auto-advance;
    /// the current item is held while the hero holds focus so the
    /// highlight never changes under the user, retrying on the still timer.
    private func advance() {
        dwellTask?.cancel()
        endOfItemTask?.cancel()
        guard !autoAdvanceDisabled else { return }
        guard items.count > 1, index < items.count - 1 else { return }
        if isCTAFocused || heroRegionFocused {
            dwellTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                advance()
            }
            return
        }
        direction = 1
        index += 1
    }

    // MARK: - Move commands

    /// Left/right stepping while the hero region (or the CTA inside it)
    /// holds focus. Clamps at both ends, no wrapping; the first manual
    /// move permanently stops auto-advance. A left move at the first item
    /// falls through to opening the side menu instead of being swallowed.
    private func handleMoveCommand(_ move: MoveCommandDirection) {
        switch move {
        case .right:
            guard items.count > 1, index < items.count - 1 else { return }
            autoAdvanceDisabled = true
            direction = 1
            index += 1
        case .left:
            guard items.count > 1, index > 0 else {
                menuRequestCount += 1
                return
            }
            autoAdvanceDisabled = true
            direction = -1
            index -= 1
        default:
            break
        }
    }
}

// MARK: - Still backdrop

/// Backdrop still with a slow 1.0 -> 1.08 scale drift across the item's
/// dwell. The drift restarts with each item layer (new view identity).
private struct TVHeroStillBackdrop: View {
    let urlString: String?
    @State private var drift: CGFloat = 1.0

    var body: some View {
        TVRemoteImage(urlString: urlString, contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .scaleEffect(drift)
            .onAppear {
                drift = 1.0
                withAnimation(.linear(duration: 10)) {
                    drift = 1.08
                }
            }
    }
}

// MARK: - Featurette layer

/// Controls-free, muted AVPlayerLayer host. The player never loops and
/// never registers with Now Playing — no audio session or remote-command
/// wiring, so ambient hero playback cannot interfere with
/// TVPlayCommandListener.
private struct TVFeaturetteLayer: UIViewRepresentable {
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
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}

// MARK: - Rotate transition

/// Rotation/offset/opacity values for the hero's directional handoff
/// transition, applied via `.modifier(active:identity:)` so insertion and
/// removal animate to and from the same identity. Forward moves: the
/// outgoing item rotates out left (y-axis 0 -> -35, leading anchor,
/// x -> -240) while the incoming item rotates in from the right
/// (y-axis +35 -> 0, x +240 -> 0); back-steps mirror both.
private struct TVHeroRotateModifier: ViewModifier {
    let angle: Double
    let offset: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(angle),
                axis: (x: 0, y: 1, z: 0),
                anchor: .leading
            )
            .offset(x: offset)
            .opacity(opacity)
    }
}

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
import Supabase
import UIKit

/// What the hero's CTA offers for a title the viewer has already started.
struct TVHeroContinueState {
    /// The service they were watching on; nil when it did not resolve.
    let serviceName: String?
}

/// Preference the hero raises when a left move at the first item should
/// fall through to opening the side menu. Handled by TVMainView; the
/// value is a monotonic counter so only real requests open the menu.
struct TVHeroSideMenuRequestKey: PreferenceKey {
    static var defaultValue: Int = 0
    static func reduce(value: inout Int, nextValue: () -> Int) {
        value = max(value, nextValue())
    }
}

/// Raised while the hero holds the left direction for itself — that is,
/// while its CTA has focus and the carousel is past its first item.
///
/// Left has to do two different things from the same button: step back
/// through the heroes, and open the side menu once there is nothing left to
/// step back to. `.onMoveCommand` cannot express that, because it consumes
/// all four directions and traps focus in the hero. So the hero states its
/// claim here and the rail makes itself unfocusable for as long as it holds:
/// the focus engine finds no target to the left and focus stays put, which
/// is what lets the hero step instead. On the first item the claim drops,
/// the rail becomes focusable again, and left moves focus into the menu the
/// ordinary way.
struct TVHeroHoldsLeftKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

struct TVHeroCarousel: View {
    let items: [TVTMDBResult]
    /// Bound from TVHomeView so the scroll content can declare the CTA the
    /// default focus for the scene, preventing launch focus from landing on
    /// a rail card and scrolling the hero off screen.
    @FocusState.Binding var ctaFocused: Bool
    /// Non-nil when this title is already in the Continue Watching rail —
    /// the viewer has started it. `serviceName` is what they started it on,
    /// and is nil when the stored platform id maps to no catalogue entry,
    /// which the rail treats as expected rather than an error.
    let continueState: (TVTMDBResult) -> TVHeroContinueState?
    /// Resume: open the service they were watching on.
    let onContinue: (TVTMDBResult, String?) -> Void
    /// Not started: open the title screen.
    let onWatchNow: (TVTMDBResult) -> Void
    /// canonicalTitleId -> hosted featurette URL. A missing key means the
    /// item renders as a drifting still.
    let featurettes: [String: String]
    /// Leading inset for the metadata block only. The art runs full bleed,
    /// so the copy has to be told where the rail titles below it start —
    /// TVMainView's inset plus the measured title-safe margin plus the
    /// rail's own gutter.
    let metadataInset: CGFloat

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
    /// False until focus has actually left the hero once. tvOS will not move
    /// focus onto a fully transparent view, so gating the metadata block
    /// purely on hero focus made the CTA unfocusable.
    @State private var heroFocusEverLeft: Bool = false
    /// Alternative streams tried for the current item. A resolved URL can
    /// still refuse to play, so the next key gets a turn — bounded, or a
    /// title with five dead keys would hold the hero for its whole dwell.
    @State private var streamRetries: Int = 0
    /// A player built ahead of time for the item after this one, so its
    /// asset is loaded and buffered before the carousel reaches it. Reels on
    /// iPhone and Android deliberately never do this — they only ever hold
    /// one live player, because the user swipes and the app cannot know what
    /// is next. The hero auto-advances, so it does know, and the first frame
    /// is the whole point of the surface.
    @State private var prerolledPlayer: AVPlayer?
    @State private var prerolledIndex: Int?

    @FocusState private var heroRegionFocused: Bool
    /// Focus scope for the hero region. The CTA is the default focus inside
    /// this scope so Home appears with the hero focused rather than the
    /// first rail card.
    @Namespace private var heroNamespace

    private var currentItem: TVTMDBResult? {
        items.indices.contains(index) ? items[index] : nil
    }

    /// The metadata block is visible while the hero region (or the CTA
    /// inside it) holds focus, and fades out when focus enters the rails.
    private var metadataVisible: Bool {
        ctaFocused || heroRegionFocused || !heroFocusEverLeft
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
            // tvOS keeps everything inside a title-safe margin by default,
            // which left a band of background down the leading edge and
            // across the top. The art opts out; the metadata below does not.
            .ignoresSafeArea()

            metadataBlock
            pageIndicator
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        // The art is deliberately not focusable. It used to be, which put a
        // focus stop on the hero region *containing* the CTA — focus landed
        // there instead of on Add to Watch List, and the button was awkward
        // to reach. The CTA is now the hero's only stop.
        .focusScope(heroNamespace)
        .focusEffectDisabled()
        // Deliberately NOT .onMoveCommand: it consumes all four directions
        // while the hero holds focus, which trapped focus here — down never
        // reached the focus engine, so the rails were unreachable, and left
        // never reached the side menu. This observes instead, so up, down and
        // left stay ordinary focus movement and only right is acted on.
        .onRemoteDirection(isEnabled: ctaFocused) {
            handleMove($0, source: "remote")
        }
        .preference(key: TVHeroHoldsLeftKey.self, value: ctaFocused && index > 0)
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
            discardPreroll()
        }
        .onChange(of: ctaFocused) { wasFocused, isFocused in
            if wasFocused && !isFocused { heroFocusEverLeft = true }
        }
        .onChange(of: heroRegionFocused) { wasFocused, isFocused in
            if wasFocused && !isFocused { heroFocusEverLeft = true }
        }
        .onChange(of: ctaFocused) { wasFocused, isFocused in
            if wasFocused && !isFocused { heroFocusEverLeft = true }
        }
        .onChange(of: heroRegionFocused) { wasFocused, isFocused in
            if wasFocused && !isFocused { heroFocusEverLeft = true }
        }
        .onChange(of: index) { _, _ in
            startDwell()
        }
        .onChange(of: items.count) { _, _ in
            index = 0
            startDwell()
        }
        .onChange(of: featurettes.count) { _, _ in
            // The pool is built before its video URLs resolve, so the first
            // item's dwell starts on the still path. Re-arm once the map
            // lands or item one can never play.
            startDwell()
            prerollNext()
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
                    .animation(.easeOut(duration: 0.4), value: videoReady)
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
            VStack(alignment: .leading, spacing: 14) {
                Text(item.isTV ? "TRENDING SHOW" : "TRENDING MOVIE")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(TVTheme.orange)
                    .tracking(2)
                Text(item.displayName)
                    .font(.system(size: 44, weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(TVTheme.textSecondary)
                        .lineLimit(2)
                        .frame(maxWidth: 700, alignment: .leading)
                }

                // The CTA reads the viewer's own history: a title they have
                // started resumes on the service they started it on, and one
                // they have not opens the title screen. Add to Watch List
                // moved off the hero with this — it is on the title screen,
                // and asking someone to file a title they are mid-way
                // through was the wrong offer on the app's front page.
                let resume = continueState(item)
                Button {
                    if let resume {
                        onContinue(item, resume.serviceName)
                    } else {
                        onWatchNow(item)
                    }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 26, weight: .bold))
                        if let resume {
                            if let service = resume.serviceName {
                                Text("Continue on")
                                    .font(.system(size: 22, weight: .semibold))
                                TVServiceBrandMark(providerName: service, size: 40)
                            } else {
                                // In the rail, but the stored platform id
                                // named no service we know. Still a resume.
                                Text("Continue Watching")
                                    .font(.system(size: 22, weight: .semibold))
                            }
                        } else {
                            Text("Watch Now")
                                .font(.system(size: 22, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 18)
                }
                .buttonStyle(.card)
                .focused($ctaFocused)
                // The CTA holds focus on arrival, so left/right land here
                // rather than on the hero region behind it. Without this the
                // carousel cannot be stepped through at all.
                .prefersDefaultFocus(true, in: heroNamespace)
                .padding(.top, 6)
            }
            .padding(.leading, metadataInset)
            .padding(.trailing, 80)
            // Clears the first rail, which peeks over the hero at the fold.
            // The hero grew by the title-safe margin when it opted out, so
            // this has to clear more than it used to.
            .padding(.bottom, 290)
            .opacity(metadataVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: metadataVisible)
            .animation(.easeOut(duration: 0.35), value: index)
        }
    }

    /// Dotted position control for the carousel, centred on the same line
    /// as the CTA. The current item reads as an orange capsule; the rest
    /// are dim dots. Purely indicative — stepping is the remote's job.
    @ViewBuilder
    private var pageIndicator: some View {
        if items.count > 1 {
            HStack(spacing: 12) {
                ForEach(items.indices, id: \.self) { position in
                    Capsule()
                        .fill(position == index ? TVTheme.orange : Color.white.opacity(0.32))
                        .frame(width: position == index ? 34 : 10, height: 10)
                }
            }
            .animation(.easeInOut(duration: 0.28), value: index)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 300)
            .opacity(metadataVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: metadataVisible)
        }
    }

    // MARK: - Dwell & rotation

    /// How long a title is given to actually start playing before the
    /// carousel gives up on it and moves on. Extraction, then the asset
    /// load, then the first frame — ten seconds was not enough on a real
    /// Apple TV, so the item lost its turn to the next poster while its
    /// video was still on the way.
    private static let videoStartGrace: Int = 22
    /// How long a still holds when the title has no video at all.
    private static let stillDwell: Int = 10
    /// Longest any one item holds the hero, measured from the moment its
    /// video starts playing rather than from when the item appeared.
    private static let maxVideoDwell: Int = 26

    /// Starts the current item's dwell: a hosted featurette plays once and
    /// advances on its end; a still (or a featurette that never starts)
    /// advances after 10 seconds. The last item holds as a static poster.
    private func startDwell() {
        dwellTask?.cancel()
        endOfItemTask?.cancel()
        playbackStatusTask?.cancel()
        teardownPlayer()
        resetVideoReady()
        streamRetries = 0

        guard let item = currentItem, items.count > 1, index < items.count - 1 else {
            return
        }

        if let urlString = featurettes[item.canonicalTitleId], let url = URL(string: urlString) {
            setUpPlayer(for: item, url: url)
            dwellTask = Task { @MainActor in
                // Wait for playback to actually begin rather than counting
                // down regardless. The old fixed timer is what made the
                // carousel rotate to the next poster while this title's
                // video was still loading.
                var waited = 0
                while !videoReady, waited < Self.videoStartGrace * 1000 {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled else { return }
                    waited += 200
                }
                guard !Task.isCancelled else { return }
                guard videoReady else {
                    advance()
                    return
                }

                // Playing, so the next title's video can start loading now
                // and be ready by the time the carousel reaches it.
                prerollNext()

                // The end-of-item observer advances when a clip actually
                // finishes, but an extracted YouTube trailer runs two or
                // three minutes — long enough that the carousel looks stuck
                // on one title — so cap the turn. Counted from playback
                // start, so a slow-loading title still gets its full watch
                // time rather than the remainder of a shared clock. A stall
                // needs its own out: advance once the player sits idle well
                // past any plausible rebuffer.
                var idleChecks = 0
                var elapsed = 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    elapsed += 3
                    if elapsed >= Self.maxVideoDwell {
                        advance()
                        return
                    }
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
                // No video for this title, but the next one may have one —
                // warm it while the still holds.
                prerollNext()
                try? await Task.sleep(for: .seconds(Self.stillDwell))
                guard !Task.isCancelled else { return }
                advance()
            }
        }
    }

    /// tvOS will not start playback while the process has no active audio
    /// session, even for a muted player: the item reaches .readyToPlay and
    /// then sits at .paused with no error, which is exactly how this looked
    /// on device. .mixWithOthers so a silent hero never interrupts whatever
    /// the viewer already has playing.
    private static func activateAudioSessionIfNeeded() {
        guard !audioSessionActivated else { return }
        audioSessionActivated = true
        do {
            // .mixWithOthers was right for a silent backdrop and wrong now
            // that the hero has sound: it would play under whatever else is
            // making noise instead of owning the room. Same category Reels
            // uses.
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            audioSessionActivated = false
        }
    }

    private nonisolated(unsafe) static var audioSessionActivated = false

    /// Builds the player for the item after this one and lets it load in the
    /// background. Nothing is displayed and nothing plays — the point is
    /// only that the asset and its first frames are already in hand when the
    /// carousel rotates.
    private func prerollNext() {
        let next = index + 1
        guard items.indices.contains(next) else { return }
        guard prerolledIndex != next else { return }
        let nextItem = items[next]
        guard let urlString = featurettes[nextItem.canonicalTitleId],
              let url = URL(string: urlString) else { return }

        prerolledPlayer?.pause()
        let warm = AVPlayer(playerItem: AVPlayerItem(url: url))
        // Audio on, every surface. The hero used to be a silent backdrop;
        // it is the app's front page and it plays with sound like Apple's TV
        // app and every service's own home screen.
        warm.isMuted = false
        // Waiting to minimise stalling is the wrong trade for a hero that
        // holds the screen for 26 seconds: AVPlayer sits at .paused with a
        // ready item while it decides, the layer never fades in, and the
        // item loses its turn. Start on demand and let it rebuffer if it
        // must — the dwell already advances on a real stall.
        warm.automaticallyWaitsToMinimizeStalling = false
        prerolledPlayer = warm
        prerolledIndex = next
    }

    private func discardPreroll() {
        prerolledPlayer?.pause()
        prerolledPlayer = nil
        prerolledIndex = nil
    }

    private func setUpPlayer(for item: TVTMDBResult, url: URL) {
        Self.activateAudioSessionIfNeeded()

        let newPlayer: AVPlayer
        if let warm = prerolledPlayer, prerolledIndex == index,
           (warm.currentItem?.asset as? AVURLAsset)?.url == url {
            newPlayer = warm
            prerolledPlayer = nil
            prerolledIndex = nil
        } else {
            discardPreroll()
            newPlayer = AVPlayer(playerItem: AVPlayerItem(url: url))
        }
        guard let playerItem = newPlayer.currentItem else { return }
        newPlayer.isMuted = false
        newPlayer.automaticallyWaitsToMinimizeStalling = false
        player = newPlayer
        newPlayer.play()

        // play() before the item is ready can be dropped, so ask again the
        // moment it becomes playable.
        Task { @MainActor [weak newPlayer, weak playerItem] in
            guard let newPlayer, let playerItem else { return }
            for await status in playerItem.publisher(for: \.status).values {
                guard !Task.isCancelled else { return }
                guard status == .readyToPlay else { continue }
                if newPlayer.timeControlStatus != .playing { newPlayer.play() }
                return
            }
        }

        // Fade the layer in and log the view the moment playback actually
        // starts; until then the drifting still stays visible underneath.
        // Polled rather than observed. The KVO publisher for
        // timeControlStatus did not deliver on device — players reported
        // time=playing while this never fired, so the layer stayed at
        // opacity 0 and the video was invisible even when it was running.
        playbackStatusTask = Task { @MainActor [weak newPlayer] in
            // 100ms ticks over the same 20s budget: the poster gives way the
            // moment the stream is genuinely playing, with no hold in front
            // of it, so the only thing between still and video is the fade.
            var readyButStalled = 0
            for _ in 0..<200 {
                guard !Task.isCancelled else { return }
                guard let newPlayer else { return }
                if newPlayer.timeControlStatus == .playing {
                    markVideoReady(for: item)
                    return
                }
                if newPlayer.currentItem?.status == .failed {
                    await retryWithNextStream(for: item)
                    return
                }
                // An item that reaches .readyToPlay and still will not play
                // never reaches .failed either, so it used to sit here for
                // the whole 22s grace and the carousel rotated on the still.
                // Nudge it once at 3s, then move to the next stream at 6s.
                if newPlayer.currentItem?.status == .readyToPlay {
                    readyButStalled += 1
                    if readyButStalled == 30 {
                        newPlayer.play()
                    } else if readyButStalled >= 60 {
                        await retryWithNextStream(for: item)
                        return
                    }
                } else {
                    readyButStalled = 0
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        #if DEBUG
        // Unconditional snapshot a few seconds in. A player stuck at
        // .unknown never reaches .failed either, so only reporting failures
        // leaves the common case invisible.
        Task { @MainActor [weak newPlayer, weak playerItem] in
            try? await Task.sleep(for: .seconds(8))
            guard let newPlayer, let playerItem else { return }
            let itemStatus: String
            switch playerItem.status {
            case .readyToPlay: itemStatus = "readyToPlay"
            case .failed: itemStatus = "failed"
            default: itemStatus = "unknown"
            }
            let timeStatus: String
            switch newPlayer.timeControlStatus {
            case .playing: timeStatus = "playing"
            case .paused: timeStatus = "paused"
            case .waitingToPlayAtSpecifiedRate: timeStatus = "waiting"
            @unknown default: timeStatus = "?"
            }
            let last = playerItem.errorLog()?.events.last
            let detail = "item=\(itemStatus) time=\(timeStatus) ready=\(videoReady)"
                + " likelyKeepUp=\(playerItem.isPlaybackLikelyToKeepUp)"
                + " err=\(playerItem.error?.localizedDescription ?? "none")"
                + " httpStatus=\(last?.errorStatusCode ?? 0)"
                + " comment=\(last?.errorComment ?? "none")"
            try? await SupabaseManager.shared.client
                .from("debug_logs")
                .insert([
                    "event": .string("tv_hero_player_status"),
                    "platform": .string("tvos"),
                    "title": .string(item.canonicalTitleId),
                    "target_name": .string(String(detail.prefix(300))),
                    "matched": .bool(newPlayer.timeControlStatus == .playing)
                ] as [String: AnyJSON])
                .execute()
        }

        // A failed load never reaches .playing, so without this the video
        // simply never appears and nothing says why.
        Task { @MainActor [weak playerItem] in
            guard let playerItem else { return }
            for await status in playerItem.publisher(for: \.status).values {
                guard !Task.isCancelled else { return }
                guard status == .failed else { continue }
                let message = (playerItem.error?.localizedDescription ?? "unknown")
                    + " | log=" + (playerItem.errorLog()?.events.last?.errorComment ?? "none")
                    + " | status=" + String(playerItem.errorLog()?.events.last?.errorStatusCode ?? 0)
                try? await SupabaseManager.shared.client
                    .from("debug_logs")
                    .insert([
                        "event": .string("tv_hero_player_failed"),
                        "platform": .string("tvos"),
                        "title": .string(item.canonicalTitleId),
                        "target_name": .string(String(message.prefix(300))),
                        "matched": .bool(false)
                    ] as [String: AnyJSON])
                    .execute()
                return
            }
        }
        #endif

        endOfItemTask = Task { @MainActor [weak newPlayer] in
            guard let newPlayer else { return }
            for await _ in NotificationCenter.default.notifications(
                named: .AVPlayerItemDidPlayToEndTime,
                object: newPlayer.currentItem
            ) {
                guard !Task.isCancelled else { return }
                // Fade back to the poster before rotating, so the item ends
                // on the same image it began with.
                withAnimation(.easeOut(duration: 0.6)) { videoReady = false }
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { return }
                advance()
                return
            }
        }
    }

    /// Swaps in the next candidate stream for this title — another rendition
    /// of the same trailer first, then another key. Bounded so a title whose
    /// candidates are all dead falls back to its still rather than churning
    /// for the whole dwell.
    private func retryWithNextStream(for item: TVTMDBResult) async {
        guard streamRetries < 4 else { return }
        streamRetries += 1
        guard let next = await TVTrailerStreamService.shared.nextStreamURL(for: item.canonicalTitleId),
              let url = URL(string: next) else { return }
        guard !Task.isCancelled, currentItem?.id == item.id else { return }
        teardownPlayer()
        setUpPlayer(for: item, url: url)
    }

    private func markVideoReady(for item: TVTMDBResult) {
        withAnimation(.easeOut(duration: 0.4)) {
            videoReady = true
        }
        WatchIntentLogger.shared.log(
            eventType: .trailerViewed,
            titleId: item.canonicalTitleId,
            metadata: ["surface": "tv_home_hero"]
        )
    }

    private func resetVideoReady() {
        videoReady = false
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
        // Deliberately does NOT pause because the hero holds focus. It used
        // to, back when the CTA was only focused if the viewer moved to it —
        // now the CTA is the screen's default focus, so that rule re-armed
        // the timer forever and the carousel never left the first item.
        // autoAdvanceDisabled, set by any manual left/right, is the pause.
        direction = 1
        index += 1
    }

    // MARK: - Move commands

    /// Left/right stepping while the hero region (or the CTA inside it)
    /// holds focus. Clamps at both ends, no wrapping; the first manual
    /// move permanently stops auto-advance. A left move at the first item
    /// falls through to opening the side menu instead of being swallowed.
    private func handleMove(_ move: MoveCommandDirection, source: String) {
        TVNavLog.log("hero \(source) \(move) index=\(index)/\(items.count) "
                     + "cta=\(ctaFocused) region=\(heroRegionFocused)")
        handleMoveCommand(move)
    }

    private func handleMoveCommand(_ move: MoveCommandDirection) {
        switch move {
        case .right:
            // The one direction the hero claims. Right is a dead end for the
            // focus engine here anyway — nothing sits to the right of the CTA.
            guard items.count > 1, index < items.count - 1 else { return }
            autoAdvanceDisabled = true
            direction = 1
            index += 1
        case .left:
            // While the carousel has somewhere to step back to, the rail is
            // unfocusable (TVHeroHoldsLeftKey), so the focus engine leaves
            // focus here and this is the only thing that acts on left.
            guard items.count > 1, index > 0 else {
                // First item: the rail is focusable again and the focus
                // engine is moving into it. Asking as well costs nothing and
                // keeps the hero from being a dead end if that move finds no
                // target; TVMainView ignores a request while the menu is open.
                TVNavLog.log("hero requests side menu (count \(menuRequestCount + 1))")
                menuRequestCount += 1
                return
            }
            autoAdvanceDisabled = true
            direction = -1
            index -= 1
        default:
            // Up and down belong to the focus engine — this is what lets the
            // rails be reached from the hero.
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

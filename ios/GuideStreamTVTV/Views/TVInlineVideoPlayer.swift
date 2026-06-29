//
//  TVInlineVideoPlayer.swift
//  GuideStreamTVTV
//
//  Inline trailer playback for the Reels feed. Since tvOS can't embed YouTube,
//  we resolve each trailer key to a native HLS stream (TVTrailerResolver) and
//  play it with AVPlayer inside an AVPlayerLayer-backed view that fills the
//  reel. The controller owns a single AVPlayer reused across reels, loops the
//  trailer, and exposes mute / play state to the SwiftUI surface.
//

import SwiftUI
import AVFoundation

// MARK: - Player controller

@MainActor
@Observable
final class TVTrailerPlayer {
    /// The underlying player surfaced to the representable view.
    let player: AVPlayer = {
        let p = AVPlayer()
        p.automaticallyWaitsToMinimizeStalling = true
        p.actionAtItemEnd = .none
        return p
    }()

    private(set) var isReady: Bool = false
    private(set) var isPlaying: Bool = false
    var isMuted: Bool = true {
        didSet { player.isMuted = isMuted }
    }

    /// The trailer key currently loaded (or being loaded).
    private var activeKey: String?
    /// Token incremented on every load so stale async resolves are ignored.
    private var loadToken: Int = 0
    private var endObserver: NSObjectProtocol?
    /// Session cache of resolved stream URLs to avoid re-hitting the resolver.
    private var urlCache: [String: URL] = [:]

    init() {
        player.isMuted = true
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// Loads + plays the trailer for the given key. No-op if it's already the
    /// active key. Pass nil to stop and clear the current item.
    func load(key: String?) {
        guard activeKey != key else { return }
        activeKey = key
        loadToken += 1
        let token = loadToken

        isReady = false
        isPlaying = false
        teardownItem()

        guard let key, !key.isEmpty else { return }

        if let cached = urlCache[key] {
            startPlayback(url: cached, token: token)
            return
        }

        Task {
            let resolved = await TVTrailerResolver.shared.streamURL(for: key)
            guard token == loadToken else { return }   // a newer reel took over
            guard let resolved else { return }          // no playable stream
            urlCache[key] = resolved
            startPlayback(url: resolved, token: token)
        }
    }

    private func startPlayback(url: URL, token: Int) {
        guard token == loadToken else { return }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.isMuted = isMuted

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.player.seek(to: .zero)
                self.player.play()
            }
        }

        player.seek(to: .zero)
        player.play()
        isReady = true
        isPlaying = true
    }

    func togglePlayPause() {
        guard isReady else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func resumeIfReady() {
        guard isReady, !isPlaying else { return }
        player.play()
        isPlaying = true
    }

    /// Fully stops and detaches the current item (used when leaving the tab).
    func stop() {
        activeKey = nil
        loadToken += 1
        teardownItem()
        isReady = false
        isPlaying = false
    }

    private func teardownItem() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}

// MARK: - AVPlayerLayer host

/// Fills the reel with the player's video, cropping to aspect-fill so the
/// trailer behaves like the backdrop it replaces.
struct TVInlineVideoPlayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }

    final class PlayerContainerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

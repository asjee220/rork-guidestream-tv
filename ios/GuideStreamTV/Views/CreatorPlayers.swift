//
//  CreatorPlayers.swift
//  GuideStreamTV
//
//  Reusable media player views for non-TMDB creators:
//  – YouTubeEmbedPlayer: WKWebView IFrame embed (iOS only)
//  – PodcastAudioPlayer: AVPlayer-backed audio with scrubber & skip controls
//

import SwiftUI
#if os(iOS)
import WebKit
import AVFoundation
import AVKit
#endif

// MARK: - YouTube embed player (iOS only)

#if os(iOS)
/// Embedded YouTube player that gracefully falls back to an "Open in YouTube"
/// CTA when the IFrame player reports an embed restriction (errors 150/152/153)
/// or fails to load — instead of showing YouTube's raw grey error card.
struct YouTubeEmbedPlayer: View {
    let videoId: String

    @State private var didError: Bool = false
    @Environment(\.openURL) private var openURL

    private var watchURL: URL? {
        URL(string: "https://www.youtube.com/watch?v=\(videoId)")
    }

    var body: some View {
        ZStack {
            Color.black
            if didError {
                fallbackOverlay
            } else {
                YouTubeWebView(videoId: videoId) {
                    didError = true
                }
            }
        }
        .onChange(of: videoId) { _, _ in
            didError = false
        }
    }

    private var fallbackOverlay: some View {
        VStack(spacing: 14) {
            Image(systemName: "play.rectangle.fill")
                .scaledFont(size: 40, weight: .semibold)
                .foregroundStyle(Color(red: 0xFF/255, green: 0x00/255, blue: 0x00/255))
            Text("This video can't play here")
                .scaledFont(size: 15, weight: .semibold)
                .foregroundStyle(.white)
            Text("The owner has restricted embedded playback.")
                .scaledFont(size: 12)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                if let watchURL { openURL(watchURL) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.forward.square.fill")
                        .scaledFont(size: 15, weight: .semibold)
                    Text("Open in YouTube")
                        .scaledFont(size: 14, weight: .semibold)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .frame(height: 44)
                .background(Capsule().fill(Color(red: 0xFF/255, green: 0x00/255, blue: 0x00/255)))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(24)
    }
}

/// Internal IFrame Player API web view that signals embed/playback errors back
/// to SwiftUI via the `onError` closure.
private struct YouTubeWebView: UIViewRepresentable {
    let videoId: String
    let onError: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onError: onError) }

    private func html(for videoId: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
        <style>
        body{margin:0;background:#000;height:100vh;}
        #player{width:100%;height:100%;}
        </style>
        </head>
        <body>
        <div id="player"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
        function notifyError(){
          if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.ytError){
            window.webkit.messageHandlers.ytError.postMessage(1);
          }
        }
        function onYouTubeIframeAPIReady(){
          new YT.Player('player',{
            width:'100%',height:'100%',videoId:'\(videoId)',
            playerVars:{playsinline:1,rel:0,modestbranding:1},
            events:{ 'onError': notifyError }
          });
        }
        </script>
        </body>
        </html>
        """
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "ytError")

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(html(for: videoId), baseURL: URL(string: "https://www.youtube.com"))
        context.coordinator.loadedVideoId = videoId
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard context.coordinator.loadedVideoId != videoId else { return }
        context.coordinator.loadedVideoId = videoId
        uiView.loadHTMLString(html(for: videoId), baseURL: URL(string: "https://www.youtube.com"))
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "ytError")
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onError: () -> Void
        var loadedVideoId: String?

        init(onError: @escaping () -> Void) {
            self.onError = onError
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "ytError" else { return }
            print("[YouTubeEmbedPlayer] IFrame player reported an embed error")
            onError()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("[YouTubeEmbedPlayer] navigation failed: \(error.localizedDescription)")
            onError()
        }
    }
}
#endif

// MARK: - Podcast audio player

#if os(iOS)
struct PodcastAudioPlayer: View {
    let audioUrl: String
    let episodeTitle: String
    let podcastName: String
    let artworkUrl: String?

    @State private var player: AVPlayer?
    @State private var isPlaying: Bool = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 1
    @State private var isSeeking: Bool = false
    @State private var seekTarget: TimeInterval = 0

    var body: some View {
        VStack(spacing: 0) {
            // Artwork
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0x7C/255, green: 0x3A/255, blue: 0xED/255).opacity(0.15))
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: min(UIScreen.main.bounds.width * 0.65, 280))

                if let artworkUrl {
                    RemoteImage(urlString: artworkUrl, contentMode: .fill, fallbackColors: [
                        Color(red: 0x7C/255, green: 0x3A/255, blue: 0xED/255),
                        Color(red: 0x7C/255, green: 0x3A/255, blue: 0xED/255).opacity(0.4)
                    ])
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: min(UIScreen.main.bounds.width * 0.65, 280))
                    .clipShape(.rect(cornerRadius: 12))
                    .allowsHitTesting(false)
                } else {
                    Image(systemName: "mic.fill")
                        .scaledFont(size: 48, weight: .semibold)
                        .foregroundStyle(Color(red: 0x7C/255, green: 0x3A/255, blue: 0xED/255).opacity(0.5))
                }
            }
            .padding(.top, 16)

            // Title + Podcast name
            VStack(spacing: 4) {
                Text(episodeTitle)
                    .scaledFont(size: 18, weight: .bold)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 20)
                Text(podcastName)
                    .scaledFont(size: 14)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            .padding(.top, 16)

            // Scrubber
            VStack(spacing: 8) {
                Slider(
                    value: Binding<Double>(
                        get: { isSeeking ? seekTarget : currentTime },
                        set: { v in
                            isSeeking = true
                            seekTarget = v
                        }
                    ),
                    in: 0...max(duration, 1)
                ) { editing in
                    if !editing, let player {
                        isSeeking = false
                        let target = CMTime(seconds: seekTarget, preferredTimescale: 600)
                        player.seek(to: target)
                    }
                }
                .tint(Color(red: 0x7C/255, green: 0x3A/255, blue: 0xED/255))
                .padding(.horizontal, 20)

                HStack {
                    Text(formatTime(currentTime))
                        .scaledFont(size: 11, weight: .medium)
                        .foregroundStyle(Color.textTertiary)
                        .monospacedDigit()
                    Spacer()
                    Text("-\(formatTime(max(duration - currentTime, 0)))")
                        .scaledFont(size: 11, weight: .medium)
                        .foregroundStyle(Color.textTertiary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 20)

            // Controls
            HStack(spacing: 28) {
                // Skip back 15
                Button {
                    skip(by: -15)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "gobackward.15")
                            .scaledFont(size: 22, weight: .medium)
                            .foregroundStyle(.white)
                        Text("15")
                            .scaledFont(size: 9, weight: .semibold)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .buttonStyle(.plain)

                // Play / Pause
                Button {
                    togglePlayback()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0x7C/255, green: 0x3A/255, blue: 0xED/255))
                            .frame(width: 64, height: 64)
                            .shadow(color: Color(red: 0x7C/255, green: 0x3A/255, blue: 0xED/255).opacity(0.4), radius: 16)
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .scaledFont(size: 26, weight: .bold)
                            .foregroundStyle(.white)
                            .offset(x: isPlaying ? 0 : 2)
                    }
                }
                .buttonStyle(.plain)

                // Skip forward 30
                Button {
                    skip(by: 30)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "goforward.30")
                            .scaledFont(size: 22, weight: .medium)
                            .foregroundStyle(.white)
                        Text("30")
                            .scaledFont(size: 9, weight: .semibold)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
        .onAppear { setupAudio() }
        .onDisappear { tearDown() }
    }

    private func setupAudio() {
        guard let url = URL(string: audioUrl) else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[PodcastAudioPlayer] AVAudioSession error: \(error.localizedDescription)")
        }
        let p = AVPlayer(url: url)
        player = p

        // Periodic time observer
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard !isSeeking else { return }
            currentTime = time.seconds
            if let d = p.currentItem?.duration, d.isNumeric {
                duration = d.seconds
            }
        }
    }

    private func tearDown() {
        player?.pause()
        player = nil
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying = (player.rate > 0)
    }

    private func skip(by seconds: Double) {
        guard let player else { return }
        let newTime = max(0, currentTime + seconds)
        let target = CMTime(seconds: newTime, preferredTimescale: 600)
        player.seek(to: target)
        currentTime = newTime
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let total = Int(max(t, 0))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
#endif

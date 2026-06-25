//
//  CreatorDetailView.swift
//  GuideStreamTV
//
//  Full destination for non-TMDB entities (YouTube, podcasts, Twitch, Kick).
//  Renders metadata from content_sources and live_status plus media playback:
//  YouTube → WKWebView IFrame embed, Podcast → AVPlayer audio, Twitch → external app.
//

import SwiftUI
#if os(iOS)
import WebKit
import AVFoundation
import AVKit
#endif

// MARK: - Cross-file routing types

/// Episode payload carried from the New Episodes rail into CreatorDetailView.
struct CreatorInitialEpisode: Hashable {
    let episodeId: String?
    let deepLinkUrl: String?
    let title: String?
    let posterUrl: String?
}

/// Wrapper that carries a creator titleId and an optional specific episode to play.
/// Used as the state behind `fullScreenCover(item:)` so both "open a creator"
/// and "play this exact episode" share the same routing target.
struct CreatorDetailTarget: Identifiable, Hashable {
    let titleId: String
    let initialEpisode: CreatorInitialEpisode?
    var id: String { titleId }
}

struct CreatorDetailView: View {
    let titleId: String
    var initialEpisode: CreatorInitialEpisode? = nil
    let onBack: () -> Void

    @State private var source: ContentSource?
    @State private var liveStatus: LiveStatus?
    @State private var isLoading: Bool = true
    @State private var streams = StreamsViewModel.shared

    // Episodes list for YouTube / Podcast creators
    @State private var episodes: [NewEpisodeRow] = []
    @State private var currentEpisodeId: String? = nil
    @State private var currentDeepLinkUrl: String? = nil
    @State private var isPlayerReady: Bool = false

    private var kind: SourceKind { SourceKind.from(titleId: titleId) }

    var body: some View {
        ZStack {
            BrandBackground()

            if isLoading {
                ProgressView().tint(Color.orange)
            } else if let source {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        // MARK: Media area
                        mediaArea(source: source)

                        // MARK: Header
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(sourceColor.opacity(0.15))
                                    .frame(width: 88, height: 88)
                                if let url = CreatorImageOverrides.resolve(titleId: titleId, stored: source.imageUrl) {
                                    RemoteImage(urlString: url, contentMode: .fill, fallbackColors: [sourceColor, sourceColor.opacity(0.5)])
                                        .frame(width: 88, height: 88)
                                        .clipShape(Circle())
                                        .allowsHitTesting(false)
                                } else {
                                    Image(systemName: kindIcon)
                                        .scaledFont(size: 36, weight: .semibold)
                                        .foregroundStyle(sourceColor)
                                }
                            }

                            Text(source.displayName)
                                .scaledFont(size: 24, weight: .bold)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)

                            HStack(spacing: 8) {
                                SourceTypeBadge(kind: kind)
                                if let handle = source.handle {
                                    let cleanHandle = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
                                    Text("@\(cleanHandle)")
                                        .scaledFont(size: 14)
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }

                            if let liveStatus, liveStatus.isLive {
                                HStack(spacing: 8) {
                                    LivePill()
                                    Text("Live now")
                                        .scaledFont(size: 14, weight: .semibold)
                                        .foregroundStyle(Color.textSecondary)
                                    if let viewers = liveStatus.viewerCount {
                                        Text("·")
                                        Text(formatViewers(viewers))
                                            .scaledFont(size: 13)
                                            .foregroundStyle(Color.textTertiary)
                                    }
                                }
                            }

                            // Follow button
                            Button {
                                toggleFollow()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: isFollowed ? "checkmark" : "plus")
                                        .scaledFont(size: 14, weight: .bold)
                                    Text(isFollowed ? "Following" : "Follow")
                                        .scaledFont(size: 15, weight: .bold)
                                }
                                .foregroundStyle(isFollowed ? Color.textSecondary : .white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(
                                    Capsule()
                                        .fill(isFollowed ? Color.white.opacity(0.10) : Color.orange)
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 40)
                        }
                        .padding(.top, 20)
                        .padding(.bottom, 28)

                        Divider().overlay(Color.white.opacity(0.08)).padding(.horizontal, 20)

                        // MARK: Info
                        VStack(alignment: .leading, spacing: 20) {
                            if let desc = source.description {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("ABOUT")
                                        .scaledFont(size: 12, weight: .heavy)
                                        .tracking(1.4)
                                        .foregroundStyle(Color.white.opacity(0.45))
                                    Text(desc)
                                        .scaledFont(size: 15)
                                        .foregroundStyle(Color.white.opacity(0.85))
                                        .lineSpacing(4)
                                }
                            }

                            if let liveStatus, liveStatus.isLive, let streamTitle = liveStatus.streamTitle {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("CURRENTLY STREAMING")
                                        .scaledFont(size: 12, weight: .heavy)
                                        .tracking(1.4)
                                        .foregroundStyle(Color.white.opacity(0.45))
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 8, height: 8)
                                        Text(streamTitle)
                                            .scaledFont(size: 16, weight: .semibold)
                                            .foregroundStyle(.white)
                                    }
                                    if let cat = liveStatus.category {
                                        Text(cat)
                                            .scaledFont(size: 13)
                                            .foregroundStyle(Color.textSecondary)
                                    }
                                }
                            }

                            if let url = source.channelUrl ?? source.feedUrl {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("LINK")
                                        .scaledFont(size: 12, weight: .heavy)
                                        .tracking(1.4)
                                        .foregroundStyle(Color.white.opacity(0.45))
#if os(iOS)
                                    Button {
                                        if let u = URL(string: url) {
                                            UIApplication.shared.open(u)
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text(url)
                                                .scaledFont(size: 13)
                                                .foregroundStyle(Color.orange)
                                                .lineLimit(1)
                                            Image(systemName: "arrow.up.right")
                                                .scaledFont(size: 11, weight: .semibold)
                                                .foregroundStyle(Color.orange)
                                        }
                                    }
                                    .buttonStyle(.plain)
#else
                                    Text(url)
                                        .scaledFont(size: 13)
                                        .foregroundStyle(Color.textSecondary)
                                        .lineLimit(1)
#endif
                                }
                            }

                            if let cat = source.category {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("CATEGORY")
                                        .scaledFont(size: 12, weight: .heavy)
                                        .tracking(1.4)
                                        .foregroundStyle(Color.white.opacity(0.45))
                                    Text(cat)
                                        .scaledFont(size: 14)
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }

                            // Episodes list (YouTube & Podcast)
                            if (kind == .youtube || kind == .podcast), !episodes.isEmpty {
                                Divider().overlay(Color.white.opacity(0.08)).padding(.vertical, 8)
                                episodeListSection
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 60)
                    }
                }
#if os(iOS)
                // Back button overlay
                .overlay(alignment: .topLeading) {
                    Button(action: onBack) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 36, height: 36)
                            Image(systemName: "xmark")
                                .scaledFont(size: 13, weight: .bold)
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 56)
                    .padding(.leading, 16)
                }
#endif
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "questionmark.circle")
                        .scaledFont(size: 36, weight: .regular)
                        .foregroundStyle(Color.textTertiary)
                    Text("Creator not found")
                        .scaledFont(size: 16, weight: .semibold)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
#if os(tvOS)
        .overlay(alignment: .topLeading) {
            Button(action: onBack) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 36, height: 36)
                    Image(systemName: "xmark")
                        .scaledFont(size: 13, weight: .bold)
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 56)
            .padding(.leading, 16)
        }
#endif
        .task { await load() }
    }

    // MARK: - Media area

    @ViewBuilder
    private func mediaArea(source: ContentSource) -> some View {
        switch kind {
        case .youtube:
            youtubePlayerSection(source: source)
        case .podcast:
            podcastPlayerSection(source: source)
        case .twitch:
            twitchSection
        case .kick:
            kickSection
        case .tmdb:
            EmptyView()
        }
    }

    // MARK: - YouTube section

    @ViewBuilder
    private func youtubePlayerSection(source: ContentSource) -> some View {
#if os(iOS)
        if let videoId = currentEpisodeId {
            // Player
            ZStack {
                Color.black
                YouTubeEmbedPlayer(videoId: videoId)
            }
            .aspectRatio(16/9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 0))
            .padding(.top, 0)
        } else if !episodes.isEmpty {
            // Fallback: no video loaded but episodes exist — show most recent
            Color.black
                .frame(height: 220)
                .overlay {
                    VStack(spacing: 12) {
                        ProgressView().tint(Color.white)
                        Text("Loading player…")
                            .scaledFont(size: 13)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
        } else {
            // No episodes at all — show metadata only
            Color.clear.frame(height: 0)
        }
#else
        // tvOS fallback
        if let videoId = currentEpisodeId {
            Button {
                // Fallback: open externally via the app delegate or nothing
            } label: {
                HStack {
                    Image(systemName: "play.rectangle.fill")
                        .scaledFont(size: 16, weight: .semibold)
                    Text("Watch on YouTube")
                        .scaledFont(size: 15, weight: .semibold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Capsule().fill(Color(red: 0xFF/255, green: 0x00/255, blue: 0x00/255)))
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        } else {
            EmptyView()
        }
#endif
    }

    // MARK: - Podcast section

    @ViewBuilder
    private func podcastPlayerSection(source: ContentSource) -> some View {
#if os(iOS)
        if let audioUrl = currentDeepLinkUrl {
            PodcastAudioPlayer(
                audioUrl: audioUrl,
                episodeTitle: currentEpisodeTitle ?? "Episode",
                podcastName: source.displayName,
                artworkUrl: currentEpisodePosterUrl ?? source.imageUrl
            )
            .padding(.horizontal, 20)
        } else if !episodes.isEmpty {
            Color.black.opacity(0.3)
                .frame(height: 320)
                .overlay {
                    VStack(spacing: 12) {
                        ProgressView().tint(Color.white)
                        Text("Loading player…")
                            .scaledFont(size: 13)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
        } else {
            Color.clear.frame(height: 0)
        }
#else
        // tvOS fallback — metadata only for podcasts
        Color.clear.frame(height: 0)
#endif
    }

    // MARK: - Twitch section

    private var twitchSection: some View {
        VStack(spacing: 12) {
            if let liveStatus, liveStatus.isLive {
                HStack(spacing: 8) {
                    LivePill()
                    Text("Live now")
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(.white)
                    if let viewers = liveStatus.viewerCount {
                        Text("· \(formatViewers(viewers))")
                            .scaledFont(size: 13)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.red.opacity(0.12))
                )
                .padding(.horizontal, 20)
            }

            watchOnTwitchButton
                .padding(.horizontal, 20)
        }
        .padding(.top, 16)
    }

    private var watchOnTwitchButton: some View {
#if os(iOS)
        Button {
            openTwitch()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.rectangle.fill")
                    .scaledFont(size: 16, weight: .semibold)
                Text("Watch on Twitch")
                    .scaledFont(size: 16, weight: .bold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                Capsule()
                    .fill(Color(red: 0x91/255, green: 0x46/255, blue: 0xFF/255))
            )
            .shadow(color: Color(red: 0x91/255, green: 0x46/255, blue: 0xFF/255).opacity(0.35), radius: 16)
        }
        .buttonStyle(.plain)
#else
        Button {} label: {
            HStack(spacing: 8) {
                Image(systemName: "play.rectangle.fill")
                    .scaledFont(size: 16, weight: .semibold)
                Text("Watch on Twitch")
                    .scaledFont(size: 16, weight: .bold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule().fill(Color(red: 0x91/255, green: 0x46/255, blue: 0xFF/255)))
        }
#endif
    }

    // MARK: - Kick section

    private var kickSection: some View {
#if os(iOS)
        Button {
            openKick()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .scaledFont(size: 16, weight: .semibold)
                Text("Watch on Kick")
                    .scaledFont(size: 16, weight: .bold)
            }
            .foregroundStyle(Color(red: 0.05, green: 0.05, blue: 0.05))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                Capsule()
                    .fill(Color(red: 0x53/255, green: 0xFC/255, blue: 0x18/255))
            )
            .shadow(color: Color(red: 0x53/255, green: 0xFC/255, blue: 0x18/255).opacity(0.3), radius: 16)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 16)
#else
        Color.clear.frame(height: 0)
#endif
    }

    // MARK: - Episode list

    private var episodeListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kind == .youtube ? "RECENT UPLOADS" : "RECENT EPISODES")
                .scaledFont(size: 12, weight: .heavy)
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.45))
                .padding(.bottom, 4)

            ForEach(episodes) { ep in
                Button {
                    selectEpisode(ep)
                } label: {
                    HStack(spacing: 10) {
                        // Mini thumbnail
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(sourceColor.opacity(0.15))
                                .frame(width: 44, height: 44)
                            if let poster = ep.posterUrl {
                                RemoteImage(urlString: poster, contentMode: .fill, fallbackColors: [sourceColor, sourceColor.opacity(0.4)])
                                    .frame(width: 44, height: 44)
                                    .clipShape(.rect(cornerRadius: 6))
                                    .allowsHitTesting(false)
                            } else {
                                Image(systemName: kind == .podcast ? "mic.fill" : "play.rectangle.fill")
                                    .scaledFont(size: 16, weight: .semibold)
                                    .foregroundStyle(sourceColor.opacity(0.5))
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(ep.title ?? "Episode")
                                .scaledFont(size: 14, weight: isEpisodeActive(ep) ? .bold : .medium)
                                .foregroundStyle(isEpisodeActive(ep) ? sourceColor : Color.textPrimary)
                                .lineLimit(2)
                            if let date = ep.releasedAt {
                                Text(episodeDateFormatter.localizedString(for: date, relativeTo: Date()))
                                    .scaledFont(size: 11)
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }

                        Spacer(minLength: 8)

                        if isEpisodeActive(ep) {
                            Image(systemName: kind == .youtube ? "play.fill" : "speaker.wave.3.fill")
                                .scaledFont(size: 12, weight: .bold)
                                .foregroundStyle(sourceColor)
                        }
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if ep.id != episodes.last?.id {
                    Divider().overlay(Color.white.opacity(0.05))
                }
            }
        }
    }

    private func isEpisodeActive(_ ep: NewEpisodeRow) -> Bool {
        if kind == .youtube {
            return currentEpisodeId == ep.episodeId
        }
        return currentDeepLinkUrl == ep.deepLinkUrl
    }

    private func selectEpisode(_ ep: NewEpisodeRow) {
        WatchIntentLogger.shared.log(
            eventType: .cardTapped,
            titleId: titleId,
            metadata: ["section": "creator_detail", "kind": kind.sourceType, "action": "select_episode"]
        )
        currentEpisodeId = ep.episodeId
        currentDeepLinkUrl = ep.deepLinkUrl
    }

    // MARK: - Computed episode info

    private var currentEpisodeTitle: String? {
        episodes.first(where: { ep in
            if kind == .youtube { return ep.episodeId == currentEpisodeId }
            return ep.deepLinkUrl == currentDeepLinkUrl
        })?.title
    }

    private var currentEpisodePosterUrl: String? {
        episodes.first(where: { ep in
            if kind == .youtube { return ep.episodeId == currentEpisodeId }
            return ep.deepLinkUrl == currentDeepLinkUrl
        })?.posterUrl
    }

    // MARK: - Twitch / Kick external open

#if os(iOS)
    private func openTwitch() {
        let slug: String
        if let handle = source?.handle {
            slug = handle.hasPrefix("@") ? String(handle.dropFirst()).lowercased() : handle.lowercased()
        } else if let url = source?.channelUrl, let lastComponent = url.split(separator: "/").last {
            slug = String(lastComponent).lowercased()
        } else {
            slug = titleId.replacingOccurrences(of: "tw:", with: "")
        }

        let twitchAppUrl = URL(string: "twitch://stream/\(slug)")!
        if UIApplication.shared.canOpenURL(twitchAppUrl) {
            UIApplication.shared.open(twitchAppUrl)
        } else {
            UIApplication.shared.open(URL(string: "https://www.twitch.tv/\(slug)")!)
        }
    }

    private func openKick() {
        let slug: String
        if let handle = source?.handle {
            slug = handle.hasPrefix("@") ? String(handle.dropFirst()).lowercased() : handle.lowercased()
        } else if let url = source?.channelUrl, let lastComponent = url.split(separator: "/").last {
            slug = String(lastComponent).lowercased()
        } else {
            slug = titleId.replacingOccurrences(of: "kick:", with: "")
        }
        UIApplication.shared.open(URL(string: "https://kick.com/\(slug)")!)
    }
#endif

    // MARK: - Follow logic

    private var isFollowed: Bool {
        streams.userStreams.contains { $0.titleId == titleId }
    }

    private var sourceColor: Color {
        switch kind {
        case .youtube: return Color(red: 0xFF/255, green: 0x00/255, blue: 0x00/255)
        case .podcast: return Color(red: 0x7C/255, green: 0x3A/255, blue: 0xED/255)
        case .twitch: return Color(red: 0x91/255, green: 0x46/255, blue: 0xFF/255)
        case .kick: return Color(red: 0x53/255, green: 0xFC/255, blue: 0x18/255)
        case .tmdb: return Color.orange
        }
    }

    private var kindIcon: String {
        switch kind {
        case .youtube: return "play.rectangle.fill"
        case .podcast: return "mic.fill"
        case .twitch: return "gamecontroller.fill"
        case .kick: return "bolt.fill"
        case .tmdb: return "tv.fill"
        }
    }

    // MARK: - Data loading

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let sources = try await ContentSourcesService.shared.fetchSources()
            source = sources.first { $0.titleId == titleId }
            if let src = source, kind.isLivestream {
                let statuses = try? await ContentSourcesService.shared.fetchLiveStatus(for: [titleId])
                liveStatus = statuses?.first
            }

            // Fetch episodes for YouTube / Podcast creators
            if kind == .youtube || kind == .podcast {
                if let fetched = try? await ContentSourcesService.shared.fetchEpisodes(forTitleId: titleId) {
                    episodes = fetched
                    // Determine current episode
                    if let initial = initialEpisode {
                        // Route to the specific episode tapped
                        currentEpisodeId = initial.episodeId
                        currentDeepLinkUrl = initial.deepLinkUrl
                    } else if let first = fetched.first {
                        // Default to most recent
                        currentEpisodeId = first.episodeId
                        currentDeepLinkUrl = first.deepLinkUrl
                    }
                    isPlayerReady = true
                }
            }
        } catch {
            source = nil
        }
    }

    private func toggleFollow() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            if isFollowed {
                await streams.removeFromMyStreams(titleId: titleId)
            } else {
                await streams.addToMyStreams(
                    titleId: titleId,
                    title: source?.displayName ?? titleId,
                    posterUrl: source?.imageUrl,
                    platform: kind.sourceType
                )
            }
        }
    }

    private func formatViewers(_ count: Int) -> String {
        if count >= 1000 { return String(format: "%.1fK viewers", Double(count) / 1000) }
        return "\(count) viewers"
    }

    private let episodeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}

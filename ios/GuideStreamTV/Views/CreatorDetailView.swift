//
//  CreatorDetailView.swift
//  GuideStreamTV
//
//  Full destination for non-TMDB entities (YouTube, podcasts, Twitch, Kick).
//  Renders metadata from content_sources and live_status plus media playback:
//  YouTube → WKWebView IFrame embed, Podcast → AVPlayer audio, Twitch → external app.
//

import SwiftUI
import Supabase
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
    /// Creator metadata captured at tap time (e.g. from live search) so the
    /// detail screen can render even when no `content_sources` row exists yet.
    var fallbackCreator: DiscoverableCreator? = nil
    var id: String { titleId }
}

struct CreatorDetailView: View {
    let titleId: String
    var initialEpisode: CreatorInitialEpisode? = nil
    var fallbackCreator: DiscoverableCreator? = nil
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

    // Channel statistics + bio loaded via the `youtube_channel_meta` edge function.
    @State private var channelMeta: ChannelMeta? = nil
    // Recent uploads loaded from the same edge function (YouTube only).
    @State private var channelUploads: [ChannelMetaResponse.Upload] = []
    // True while the channel-meta edge function call is in flight.
    @State private var isLoadingMeta: Bool = false

    // Per-creator upload-alert preference (synced to creator_notification_preferences).
    @State private var uploadAlertsOn: Bool = false

    // Social (likes / comments) — keyed off the creator's titleId
    @State private var social = SocialViewModel.shared
    @State private var showComments: Bool = false
    @State private var isTogglingLike: Bool = false

    private var kind: SourceKind { SourceKind.from(titleId: titleId) }

    /// Channel statistics + bio sourced from the YouTube Data API
    /// `channels.list` endpoint (parts: snippet,statistics).
    private struct ChannelMeta: Sendable {
        let subscribers: Int?
        let videoCount: Int?
        let viewCount: Int?
        let description: String?
    }

    var body: some View {
        ZStack {
            BrandBackground()

            if isLoading {
                ProgressView().tint(Color.orange)
            } else if let source {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        // MARK: 1–2. Header (banner + avatar + name + badge)
                        creatorHeader(source: source)

                        // MARK: 3. Primary action row (Follow + upload-alert bell)
                        primaryActionRow(source: source)
                            .padding(.horizontal, 20)
                            .padding(.top, 4)

                        // MARK: 4. Channel stat row (subs / videos / views)
                        if kind == .youtube {
                            channelStatRow
                                .padding(.horizontal, 20)
                                .padding(.top, 22)
                        }

                        // MARK: Inline media player (kept for playback)
                        mediaArea(source: source)
                            .padding(.top, 16)

                        // MARK: 5. Social action bar (like / comment / share)
                        Divider().overlay(Color.white.opacity(0.08)).padding(.horizontal, 20).padding(.top, 20)

                        socialActionsRow(source: source)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 18)

                        Divider().overlay(Color.white.opacity(0.08)).padding(.horizontal, 20)

                        // MARK: 6. Tile ad slot
                        adTileSlot
                            .padding(.top, 18)

                        // MARK: 7–8. Info + recent uploads
                        VStack(alignment: .leading, spacing: 20) {
                            if let desc = bioText(source: source) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("ABOUT")
                                        .scaledFont(size: 12, weight: .heavy)
                                        .tracking(1.4)
                                        .foregroundStyle(Color.white.opacity(0.45))
                                    Text(desc)
                                        .scaledFont(size: 15)
                                        .foregroundStyle(Color.white.opacity(0.85))
                                        .lineSpacing(4)
                                        .lineLimit(4)
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

                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 24)

                        // MARK: 8. Recent uploads (YouTube via edge function, Podcast via episodes)
                        if kind == .youtube {
                            if isLoadingMeta && channelUploads.isEmpty {
                                uploadsLoadingPlaceholder
                                    .padding(.horizontal, 20)
                                    .padding(.top, 26)
                            } else if !channelUploads.isEmpty {
                                youtubeUploadsSection(source: source)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 26)
                            }
                        } else if kind == .podcast, !episodes.isEmpty {
                            recentUploadsSection(source: source)
                                .padding(.horizontal, 20)
                                .padding(.top, 26)
                        }

                        Color.clear.frame(height: 60)
                    }
                }
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
#if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .sheet(isPresented: $showComments) {
            if let source {
                TitleCommentsSheet(
                    titleId: titleId,
                    title: source.displayName,
                    subtitle: kind.displayLabel,
                    posterUrl: CreatorImageOverrides.resolve(titleId: titleId, stored: source.imageUrl),
                    posterColors: [sourceColor, sourceColor.opacity(0.5)],
                    accent: Color.orange
                )
            }
        }
#endif
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
        .task(id: titleId) { await social.refreshCounts(titleId: titleId) }
    }

    // MARK: - Social actions row

    @ViewBuilder
    private func socialActionsRow(source: ContentSource) -> some View {
        let isLiked = social.isLiked(titleId)
        HStack(spacing: 0) {
            socialCircleAction(
                icon: isLiked ? "heart.fill" : "heart",
                label: "Like",
                count: social.likes(titleId),
                tint: isLiked ? Color.orange : .white
            ) {
#if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
                guard !isTogglingLike else { return }
                isTogglingLike = true
                Task {
                    await social.toggleLike(titleId: titleId)
                    await MainActor.run { isTogglingLike = false }
                }
            }
            .frame(maxWidth: .infinity)

            socialCircleAction(
                icon: "bubble.left.fill",
                label: "Comments",
                count: social.commentTotal(titleId),
                tint: .white
            ) {
#if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
                showComments = true
                WatchIntentLogger.shared.log(
                    eventType: .commentsOpened,
                    titleId: titleId,
                    metadata: ["source": "creator_detail"]
                )
            }
            .frame(maxWidth: .infinity)

#if os(iOS)
            ShareLink(
                item: shareURL(source: source),
                subject: Text(source.displayName),
                message: Text("Follow \(source.displayName) on GuideStream TV")
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
#endif
        }
    }

    private func socialCircleAction(
        icon: String,
        label: String,
        count: Int,
        tint: Color,
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
                }
                Text(count > 0 ? "\(formatSocialCount(count)) \(label)" : label)
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private func formatSocialCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

#if os(iOS)
    private func shareURL(source: ContentSource) -> URL {
        if let url = source.channelUrl ?? source.feedUrl, let u = URL(string: url) {
            return u
        }
        return URL(string: "https://guidestream.tv")!
    }
#endif

    // MARK: - Header

    @ViewBuilder
    private func creatorHeader(source: ContentSource) -> some View {
        let avatarUrl = CreatorImageOverrides.resolve(titleId: titleId, stored: source.imageUrl)

        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                // Blurred backdrop built from the creator's avatar for depth
                if let avatarUrl {
                    RemoteImage(urlString: avatarUrl, contentMode: .fill, fallbackColors: [sourceColor, sourceColor.opacity(0.4)])
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .blur(radius: 32)
                        .opacity(0.55)
                        .allowsHitTesting(false)
                } else {
                    LinearGradient(
                        colors: [sourceColor.opacity(0.45), sourceColor.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 180)
                }

                LinearGradient(colors: [.clear, Color.navy], startPoint: .top, endPoint: .bottom)
                    .frame(height: 180)
                    .allowsHitTesting(false)

                // Avatar ring sitting on the backdrop
                ZStack {
                    Circle()
                        .fill(Color.navy)
                        .frame(width: 104, height: 104)
                    Circle()
                        .fill(sourceColor.opacity(0.15))
                        .frame(width: 96, height: 96)
                    if let avatarUrl {
                        RemoteImage(urlString: avatarUrl, contentMode: .fill, fallbackColors: [sourceColor, sourceColor.opacity(0.5)])
                            .frame(width: 96, height: 96)
                            .clipShape(Circle())
                            .allowsHitTesting(false)
                    } else {
                        Image(systemName: kindIcon)
                            .scaledFont(size: 38, weight: .semibold)
                            .foregroundStyle(sourceColor)
                    }
                }
                .overlay(
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 1)
                        .frame(width: 96, height: 96)
                )
                .offset(y: 30)
            }
            .frame(height: 180)
            // Close (top-left) + share (top-right) chrome over the banner.
            .overlay(alignment: .top) {
                HStack {
                    glassCircleButton(symbol: "xmark", action: onBack)
#if os(iOS)
                    Spacer()
                    ShareLink(
                        item: shareURL(source: source),
                        subject: Text(source.displayName),
                        message: Text("Follow \(source.displayName) on GuideStream TV")
                    ) {
                        glassCircleLabel(symbol: "square.and.arrow.up")
                    }
#endif
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
            }
            .padding(.bottom, 30)

            VStack(spacing: 12) {
                Text(source.displayName)
                    .scaledFont(size: 25, weight: .bold)
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
            }
            .padding(.bottom, 4)
        }
    }

#if os(iOS)
    /// Best external URL to open the creator's channel/page in its native app or web.
    private func externalChannelUrl(source: ContentSource) -> URL? {
        if let url = source.channelUrl ?? source.feedUrl, let u = URL(string: url) {
            return u
        }
        return nil
    }
#endif

    // MARK: - Glass chrome buttons

    private func glassCircleButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            glassCircleLabel(symbol: symbol)
        }
        .buttonStyle(.plain)
    }

    private func glassCircleLabel(symbol: String) -> some View {
        ZStack {
            Circle()
                .fill(Color.navy.opacity(0.55))
                .background(.ultraThinMaterial, in: Circle())
            Image(systemName: symbol)
                .scaledFont(size: 14, weight: .bold)
                .foregroundStyle(.white)
        }
        .frame(width: 38, height: 38)
        .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
    }

    // MARK: - 3. Primary action row (Follow + upload-alert bell)

    @ViewBuilder
    private func primaryActionRow(source: ContentSource) -> some View {
        HStack(spacing: 10) {
            Button {
                toggleFollow()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isFollowed ? "checkmark" : "plus")
                        .scaledFont(size: 14, weight: .bold)
                    Text(isFollowed ? "Following" : "Follow")
                        .scaledFont(size: 15, weight: .bold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    Capsule()
                        .fill(isFollowed ? Color.blue.opacity(0.35) : Color.blue)
                )
                .overlay(
                    Capsule().stroke(isFollowed ? Color.blue.opacity(0.6) : .clear, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // Per-creator upload-alert bell.
            Button {
                toggleUploadAlerts()
            } label: {
                Image(systemName: uploadAlertsOn ? "bell.fill" : "bell")
                    .scaledFont(size: 18, weight: .semibold)
                    .foregroundStyle(uploadAlertsOn ? Color.orange : .white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .overlay(Circle().stroke(uploadAlertsOn ? Color.orange.opacity(0.6) : Color.white.opacity(0.14), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 4. Channel stat row

    private var channelStatRow: some View {
        HStack(spacing: 0) {
            statColumn(value: channelMeta?.subscribers, label: "Subscribers")
            statDivider
            statColumn(value: channelMeta?.videoCount, label: "Videos")
            statDivider
            statColumn(value: channelMeta?.viewCount, label: "Views")
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .glassCard()
        .redacted(reason: (isLoadingMeta && channelMeta == nil) ? .placeholder : [])
    }

    private func statColumn(value: Int?, label: String) -> some View {
        VStack(spacing: 4) {
            // While the edge function is in flight we show a redacted placeholder
            // figure (a shimmer bar); once settled, real numbers or "—" (pending/error).
            Text(value.map { formatStat($0) } ?? (isLoadingMeta ? "0.0M" : "—"))
                .scaledFont(size: 18, weight: .heavy)
                .foregroundStyle(.white)
            Text(label.uppercased())
                .scaledFont(size: 10, weight: .heavy)
                .tracking(0.8)
                .foregroundStyle(Color.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 30)
    }

    private func formatStat(_ n: Int) -> String {
        if n >= 1_000_000_000 { return String(format: "%.1fB", Double(n) / 1_000_000_000) }
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    // MARK: - 6. Tile ad slot

    /// ~320×90 tile ad with an "AD" compliance label, guarded for the cloud
    /// simulator exactly like the Reels banner. The real banner integration
    /// (AdManager's GADBannerView) is currently a no-op stub, so this renders
    /// a labelled placeholder that keeps the layout intact on device.
    @ViewBuilder
    private var adTileSlot: some View {
#if targetEnvironment(simulator)
        EmptyView()
#else
        // TODO(ads): Replace this placeholder with the shared banner view once
        // AdManager's Google Mobile Ads SDK is restored for device builds.
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            Text("Advertisement")
                .scaledFont(size: 12, weight: .medium)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: 320)
        .frame(height: 90)
        .overlay(alignment: .topLeading) {
            Text("AD")
                .scaledFont(size: 8, weight: .heavy)
                .foregroundStyle(Color.white.opacity(0.7))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.12)))
                .padding(6)
        }
        .frame(maxWidth: .infinity)
#endif
    }

    // MARK: - 7. Bio

    /// Truncated channel description (from channels.list snippet.description
    /// when available, otherwise the stored content_sources description).
    private func bioText(source: ContentSource) -> String? {
        let raw = channelMeta?.description ?? source.description
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return raw
    }

    // MARK: - 8. Recent uploads

    private func recentUploadsSection(source: ContentSource) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(kind == .youtube ? "Recent uploads" : "Recent episodes")
                    .scaledFont(size: 17, weight: .semibold)
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
#if os(iOS)
                if let openUrl = externalChannelUrl(source: source) {
                    Button {
                        UIApplication.shared.open(openUrl)
                    } label: {
                        Text("See all")
                            .scaledFont(size: 13, weight: .semibold)
                            .foregroundStyle(Color.orange)
                    }
                    .buttonStyle(.plain)
                }
#endif
            }

            ForEach(episodes) { ep in
                Button {
                    selectEpisode(ep)
                } label: {
                    uploadRow(ep)
                }
                .buttonStyle(.plain)
                if ep.id != episodes.last?.id {
                    Divider().overlay(Color.white.opacity(0.05))
                }
            }
        }
    }

    private func uploadRow(_ ep: NewEpisodeRow) -> some View {
        HStack(spacing: 12) {
            // 16:9 thumbnail with duration badge
            Color(.sRGB, white: 0.1, opacity: 1)
                .frame(width: 120, height: 68)
                .overlay {
                    if let poster = ep.posterUrl ?? ep.thumbnailUrl {
                        RemoteImage(urlString: poster, contentMode: .fill, fallbackColors: [sourceColor, sourceColor.opacity(0.4)])
                            .allowsHitTesting(false)
                    } else {
                        Image(systemName: kind == .podcast ? "mic.fill" : "play.rectangle.fill")
                            .scaledFont(size: 20, weight: .semibold)
                            .foregroundStyle(sourceColor.opacity(0.5))
                    }
                }
                .clipShape(.rect(cornerRadius: 8))
                .overlay(alignment: .bottomTrailing) {
                    if let mins = ep.durationMinutes, mins > 0 {
                        Text(durationLabel(minutes: mins))
                            .scaledFont(size: 10, weight: .bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.75)))
                            .padding(5)
                    }
                }
                .overlay(alignment: .center) {
                    if isEpisodeActive(ep) {
                        Image(systemName: kind == .youtube ? "play.circle.fill" : "speaker.wave.3.fill")
                            .scaledFont(size: 22, weight: .bold)
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                    }
                }

            VStack(alignment: .leading, spacing: 5) {
                Text(ep.title ?? "Episode")
                    .scaledFont(size: 14, weight: isEpisodeActive(ep) ? .bold : .semibold)
                    .foregroundStyle(isEpisodeActive(ep) ? sourceColor : Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let meta = uploadMetaLine(ep) {
                    Text(meta)
                        .scaledFont(size: 12)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    /// "3 days ago" plus a view-count tail when available. View counts are not
    /// in `new_episodes`; they require the pending channel edge function, so
    /// this currently surfaces only the relative date for most rows.
    private func uploadMetaLine(_ ep: NewEpisodeRow) -> String? {
        guard let date = ep.releasedAt else { return nil }
        return episodeDateFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func durationLabel(minutes: Int) -> String {
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
        return "\(minutes) min"
    }

    // MARK: - Upload-alert preference (creator_notification_preferences)

    /// Local cache key so the bell reflects the last known value instantly on
    /// cold open, before the table read settles.
    private var uploadAlertsKey: String { "gs.creator.uploadAlerts.\(titleId)" }

    /// Loads the per-creator upload-alert preference. Uses the UserDefaults
    /// cache for an instant UI value, then reconciles against
    /// `creator_notification_preferences` (the source of truth) using the same
    /// dual-ownership resolution as the like/watchlist code.
    private func loadUploadAlertsPref() async {
        uploadAlertsOn = UserDefaults.standard.bool(forKey: uploadAlertsKey)
        let deviceId = DeviceIdentity.shared.deviceId
        let userId = AuthViewModel.shared.currentUser?.id.uuidString
        do {
            var query = SupabaseManager.shared.client
                .from("creator_notification_preferences")
                .select("notify_uploads")
                .eq("title_id", value: titleId)
            if let userId {
                query = query.or("user_id.eq.\(userId),device_id.eq.\(deviceId)")
            } else {
                query = query.eq("device_id", value: deviceId)
            }
            let rows: [CreatorNotifPrefRow] = try await query.limit(1).execute().value
            if let pref = rows.first?.notify_uploads {
                uploadAlertsOn = pref
                UserDefaults.standard.set(pref, forKey: uploadAlertsKey)
            }
        } catch {
            print("[Creator] upload-alert pref load failed: \(error.localizedDescription)")
        }
    }

    /// Flips the per-creator upload-alert toggle. Local state + cache update
    /// immediately for a responsive UI; the table write is best-effort and
    /// upserts on the matching unique index (user_id+title_id signed-in,
    /// device_id+title_id guest).
    private func toggleUploadAlerts() {
#if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
        uploadAlertsOn.toggle()
        let newValue = uploadAlertsOn
        UserDefaults.standard.set(newValue, forKey: uploadAlertsKey)
        WatchIntentLogger.shared.log(
            eventType: .cardTapped,
            titleId: titleId,
            metadata: ["source": "creator_detail", "action": "upload_alerts", "enabled": newValue]
        )
        Task { await persistUploadAlerts(newValue) }
    }

    private func persistUploadAlerts(_ enabled: Bool) async {
        let deviceId = DeviceIdentity.shared.deviceId
        let userId = AuthViewModel.shared.currentUser?.id.uuidString
        var payload: [String: AnyJSON] = [
            "title_id": .string(titleId),
            "device_id": .string(deviceId),
            "notify_uploads": .bool(enabled)
        ]
        if let userId { payload["user_id"] = .string(userId) }
        let onConflict = userId != nil ? "user_id,title_id" : "device_id,title_id"
        do {
            try await SupabaseManager.shared.client
                .from("creator_notification_preferences")
                .upsert(payload, onConflict: onConflict)
                .execute()
        } catch {
            print("[Creator] upload-alert pref upsert failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Channel meta loader (youtube_channel_meta edge function)

    /// Loads channel statistics, bio, and recent uploads via the deployed
    /// `youtube_channel_meta` Supabase edge function. The function proxies the
    /// YouTube Data API server-side, so no API key ships in the client.
    ///
    /// Behaviour:
    /// - `ok:false` or a thrown error → keep whatever the header already shows,
    ///   render the stat row as "—", and leave uploads empty (never crash, never
    ///   show fake numbers).
    /// - `pending:true` → channel id not yet resolved server-side: enrich the
    ///   header + bio from `channel`, show stats as "—", uploads empty.
    /// - otherwise → populate stats, bio, and the recent-uploads list.
    private func loadChannelMeta() async {
        isLoadingMeta = true
        defer { isLoadingMeta = false }
        do {
            let response: ChannelMetaResponse = try await SupabaseManager.shared.client.functions
                .invoke(
                    "youtube_channel_meta",
                    options: FunctionInvokeOptions(body: ["title_id": titleId])
                )
            guard response.ok else { return }

            // Header enrichment — prefer the channel name/avatar from the API,
            // falling back to whatever the sheet was already showing.
            if let channel = response.channel {
                applyChannelToSource(channel)
            }

            // Stats are null while pending; render "—" in that case.
            channelMeta = ChannelMeta(
                subscribers: response.stats.map { Int($0.subscribers) },
                videoCount: response.stats.map { Int($0.videos) },
                viewCount: response.stats.map { Int($0.views) },
                description: response.channel?.description
            )

            channelUploads = response.uploads

            // Default the inline player to the most recent upload when nothing
            // was explicitly routed (e.g. from the New Episodes rail).
            if currentEpisodeId == nil, initialEpisode == nil, let first = response.uploads.first {
                currentEpisodeId = first.videoId
                currentDeepLinkUrl = first.deepLink
            }
        } catch {
            print("[Creator] channel meta load failed: \(error.localizedDescription)")
        }
    }

    /// Merges the edge function's channel name/avatar/description into the
    /// loaded `ContentSource` so the header + bio prefer the live values.
    private func applyChannelToSource(_ channel: ChannelMetaResponse.Channel) {
        guard let existing = source else { return }
        let name = (channel.name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        let avatar = (channel.avatar?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        let desc = (channel.description?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        let link = (channel.channelUrl?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        source = ContentSource(
            titleId: existing.titleId,
            sourceType: existing.sourceType,
            displayName: name ?? existing.displayName,
            handle: existing.handle,
            imageUrl: avatar ?? existing.imageUrl,
            externalId: existing.externalId,
            feedUrl: existing.feedUrl,
            channelUrl: existing.channelUrl ?? link,
            websubTopic: existing.websubTopic,
            category: existing.category,
            description: desc ?? existing.description,
            createdAt: existing.createdAt,
            updatedAt: existing.updatedAt
        )
    }

    // MARK: - YouTube recent uploads (edge function)

    private var uploadsLoadingPlaceholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent uploads")
                .scaledFont(size: 17, weight: .semibold)
                .foregroundStyle(.white)
            HStack(spacing: 10) {
                ProgressView().tint(Color.white.opacity(0.6))
                Text("Loading uploads…")
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func youtubeUploadsSection(source: ContentSource) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent uploads")
                    .scaledFont(size: 17, weight: .semibold)
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
#if os(iOS)
                if let openUrl = externalChannelUrl(source: source) {
                    Button {
                        UIApplication.shared.open(openUrl)
                    } label: {
                        Text("See all")
                            .scaledFont(size: 13, weight: .semibold)
                            .foregroundStyle(Color.orange)
                    }
                    .buttonStyle(.plain)
                }
#endif
            }

            ForEach(channelUploads) { upload in
                Button {
                    selectUpload(upload)
                } label: {
                    youtubeUploadRow(upload)
                }
                .buttonStyle(.plain)
                if upload.id != channelUploads.last?.id {
                    Divider().overlay(Color.white.opacity(0.05))
                }
            }
        }
    }

    private func youtubeUploadRow(_ upload: ChannelMetaResponse.Upload) -> some View {
        let isActive = currentEpisodeId == upload.videoId
        return HStack(spacing: 12) {
            Color(.sRGB, white: 0.1, opacity: 1)
                .frame(width: 120, height: 68)
                .overlay {
                    if let thumb = upload.thumbnail {
                        RemoteImage(urlString: thumb, contentMode: .fill, fallbackColors: [sourceColor, sourceColor.opacity(0.4)])
                            .allowsHitTesting(false)
                    } else {
                        Image(systemName: "play.rectangle.fill")
                            .scaledFont(size: 20, weight: .semibold)
                            .foregroundStyle(sourceColor.opacity(0.5))
                    }
                }
                .clipShape(.rect(cornerRadius: 8))
                .overlay(alignment: .bottomTrailing) {
                    let badge = durationBadge(seconds: upload.durationSeconds)
                    if !badge.isEmpty {
                        Text(badge)
                            .scaledFont(size: 10, weight: .bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.75)))
                            .padding(5)
                    }
                }
                .overlay(alignment: .center) {
                    if isActive {
                        Image(systemName: "play.circle.fill")
                            .scaledFont(size: 22, weight: .bold)
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                    }
                }

            VStack(alignment: .leading, spacing: 5) {
                Text(upload.title.isEmpty ? "Video" : upload.title)
                    .scaledFont(size: 14, weight: isActive ? .bold : .semibold)
                    .foregroundStyle(isActive ? sourceColor : Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                let meta = uploadMetaLine(upload)
                if !meta.isEmpty {
                    Text(meta)
                        .scaledFont(size: 12)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    /// Opens an upload through the existing inline YouTube player path by
    /// selecting its video id (the same mechanism episode rows use). No raw
    /// stream URL is extracted.
    private func selectUpload(_ upload: ChannelMetaResponse.Upload) {
        WatchIntentLogger.shared.log(
            eventType: .cardTapped,
            titleId: titleId,
            metadata: ["section": "creator_detail", "kind": kind.sourceType, "action": "select_upload", "video_id": upload.videoId]
        )
        currentEpisodeId = upload.videoId
        currentDeepLinkUrl = upload.deepLink
    }

    /// "mm:ss" (or "h:mm:ss") duration badge from a raw seconds count.
    private func durationBadge(seconds: Int) -> String {
        guard seconds > 0 else { return "" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    /// "3 days ago · 1.4M views" — relative date from `published_at` plus a
    /// compact view count. Either part is omitted when unavailable.
    private func uploadMetaLine(_ upload: ChannelMetaResponse.Upload) -> String {
        var parts: [String] = []
        if let date = parseISODate(upload.publishedAt) {
            parts.append(episodeDateFormatter.localizedString(for: date, relativeTo: Date()))
        }
        if upload.views > 0 {
            parts.append("\(formatStat(Int(upload.views))) views")
        }
        return parts.joined(separator: " · ")
    }

    private func parseISODate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFractional.date(from: raw) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
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

    // MARK: - Episode helpers

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
        await loadUploadAlertsPref()
        do {
            let sources = try await ContentSourcesService.shared.fetchSources()
            source = sources.first { $0.titleId == titleId } ?? fallbackSource()
            if let src = source, kind.isLivestream {
                let statuses = try? await ContentSourcesService.shared.fetchLiveStatus(for: [titleId])
                liveStatus = statuses?.first
            }

            // Honor a specific episode routed from the New Episodes rail so the
            // inline player opens straight to it (YouTube + Podcast).
            if let initial = initialEpisode {
                currentEpisodeId = initial.episodeId
                currentDeepLinkUrl = initial.deepLinkUrl
            }

            // Podcasts still source their recent episodes from new_episodes;
            // YouTube uploads now come from the youtube_channel_meta edge function.
            if kind == .podcast {
                if let fetched = try? await ContentSourcesService.shared.fetchEpisodes(forTitleId: titleId) {
                    episodes = fetched
                    if initialEpisode == nil, let first = fetched.first {
                        currentEpisodeId = first.episodeId
                        currentDeepLinkUrl = first.deepLinkUrl
                    }
                    isPlayerReady = true
                }
            }
        } catch {
            // Network/db failure shouldn't dead-end a creator the user already
            // saved — fall back to the watch-list entry so the screen still opens.
            source = fallbackSource()
        }

        // Channel statistics, bio, and recent uploads via the edge function
        // (YouTube only). Runs after `source` is set so the header can be
        // enriched with the live channel name/avatar.
        if kind == .youtube {
            await loadChannelMeta()
        }
    }

    /// Builds a minimal ContentSource so creators discovered via live search
    /// (whose content_sources upsert may not have persisted) still open instead
    /// of showing "Creator not found". Prefers the metadata captured at tap time
    /// (search/discovery), then falls back to the user's saved watch-list entry.
    private func fallbackSource() -> ContentSource? {
        if let creator = fallbackCreator {
            let cleanName = creator.displayName.isEmpty ? kind.displayLabel : creator.displayName
            return ContentSource(
                titleId: titleId,
                sourceType: creator.sourceType,
                displayName: cleanName,
                handle: creator.handle,
                imageUrl: creator.imageUrl,
                externalId: nil,
                feedUrl: nil,
                channelUrl: nil,
                websubTopic: nil,
                category: creator.category,
                description: creator.description,
                createdAt: nil,
                updatedAt: nil
            )
        }
        guard let saved = streams.userStreams.first(where: { $0.titleId == titleId }) else {
            return nil
        }
        let cleanName = (saved.title?.isEmpty ?? true) ? kind.displayLabel : (saved.title ?? kind.displayLabel)
        return ContentSource(
            titleId: titleId,
            sourceType: kind.sourceType,
            displayName: cleanName,
            handle: nil,
            imageUrl: saved.posterUrl,
            externalId: nil,
            feedUrl: nil,
            channelUrl: nil,
            websubTopic: nil,
            category: nil,
            description: nil,
            createdAt: nil,
            updatedAt: nil
        )
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

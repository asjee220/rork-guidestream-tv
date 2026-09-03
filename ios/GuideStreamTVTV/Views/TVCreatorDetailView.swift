//
//  TVCreatorDetailView.swift
//  GuideStreamTVTV
//
//  The creator screen: YouTube channels, podcasts, Twitch and Kick.
//
//  Until now every non-TMDB title opened TVTitleSheet, which is built around
//  a TMDB id — so a creator got a stretched avatar, a "Series" meta line and
//  five empty sections, because loadSections() returns immediately when
//  there is no tmdbId. This screen carries what the phone's
//  CreatorDetailView carries: the channel's own name and bio, its
//  subscriber/video (or follower/VOD) counts, live state and what is
//  streaming right now, recent uploads or episodes, and the follow, watched
//  and like actions.
//
//  Not ported, because they are phone affordances rather than missing
//  content: the share sheet (no UIActivityViewController on tvOS), Send to
//  TV (this *is* the TV), and the sticky compact header (there is no
//  scroll-to-shrink idiom on a 10-foot screen).
//

import SwiftUI
import AVKit

struct TVCreatorDetailView: View {
    let detail: TVTitleDetail
    /// Called when the viewer backs out, mirroring TVTitleSheet's contract so
    /// the shell owns the route either way.
    let onDismiss: (Bool) -> Void

    @State private var source: TVCreatorSource?
    @State private var live: TVLiveStatus?
    @State private var episodes: [TVCreatorEpisode] = []
    @State private var meta: TVChannelMetaResponse?
    @State private var isLoadingMeta = false

    @State private var streams = TVStreamsViewModel.shared
    @State private var social = SocialViewModel.shared

    /// The podcast episode currently playing, if any. tvOS has no mini
    /// player, so playback is a full-screen AVKit presentation.
    @State private var playingEpisode: TVCreatorEpisode?

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case watch, follow, watched, like
        case upload(String)
        case episode(String)
    }

    private var kind: TVCreatorKind { TVCreatorKind.from(titleId: detail.titleId) ?? .youtube }

    /// The channel's own name wins over whatever the caller passed: a saved
    /// row can be years stale, and the edge function is reading the channel
    /// as it stands today.
    private var displayName: String {
        meta?.channel?.name ?? source?.displayName ?? detail.title
    }

    private var avatarUrl: String? {
        meta?.channel?.avatar ?? source?.imageUrl ?? detail.posterUrl
    }

    private var bio: String? {
        let raw = meta?.channel?.description ?? source?.description
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return raw
    }

    private var isLive: Bool { live?.isLive ?? false }

    private var accent: Color {
        switch kind {
        case .youtube: return Color(red: 1.0, green: 0.0, blue: 0.0)
        case .podcast: return Color(red: 0.49, green: 0.23, blue: 0.93)
        case .twitch: return Color(red: 0.57, green: 0.27, blue: 1.0)
        case .kick: return Color(red: 0.33, green: 0.99, blue: 0.09)
        }
    }

    var body: some View {
        ZStack {
            backdropLayer

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 56) {
                    heroSection
                    infoSection
                    uploadsSection
                    Color.clear.frame(height: 60)
                }
                .padding(.top, 80)
                // Clear of the collapsed rail, like every other surface. The
                // backdrop is a layer behind this stack, so it still bleeds.
                .padding(.leading, TVLayout.contentLeadingInset)
            }
            .ignoresSafeArea()
        }
        // Close is the Menu button, matching the title screen.
        .onExitCommand { onDismiss(streams.contains(titleId: detail.titleId)) }
        .task { await load() }
        .fullScreenCover(item: $playingEpisode) { episode in
            TVPodcastPlayer(episode: episode, title: displayName)
        }
    }

    // MARK: - Backdrop

    /// The avatar, blurred and dimmed. A channel avatar is a square headshot
    /// or logo, not a 16:9 key art, so it is atmosphere here rather than the
    /// subject — stretched full-screen sharp (which is what TVTitleSheet did
    /// with it) it reads as a mistake.
    private var backdropLayer: some View {
        GeometryReader { proxy in
            ZStack {
                TVTheme.bg
                if let avatarUrl {
                    TVRemoteImage(urlString: avatarUrl, contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .blur(radius: 60)
                        .opacity(0.5)
                }
                LinearGradient(
                    colors: [TVTheme.bg.opacity(0.2), TVTheme.bg.opacity(0.95)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Hero

    private var heroSection: some View {
        HStack(alignment: .top, spacing: 44) {
            // The avatar at its own aspect ratio. Channel art is square.
            TVRemoteImage(urlString: avatarUrl, contentMode: .fill)
                .frame(width: 260, height: 260)
                .clipShape(.circle)
                .overlay {
                    Circle().stroke(Color.white.opacity(0.15), lineWidth: 2)
                }
                .shadow(color: .black.opacity(0.6), radius: 30, y: 12)

            VStack(alignment: .leading, spacing: 20) {
                metadataLine

                Text(displayName)
                    .font(.system(size: 64, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)

                if let handle = handleText {
                    Text(handle)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(TVTheme.textSecondary)
                }

                socialCounterRow

                actionsRow
                    .padding(.top, 8)
                    .focusSection()
            }

            Spacer(minLength: 0)
        }
        .padding(.trailing, 80)
    }

    /// Platform badge, then the counts the platform actually reports —
    /// subscribers and videos for YouTube, followers and VODs for Twitch —
    /// then the live pill. "—" while the channel id is still resolving
    /// server-side, which is what `pending` means.
    private var metadataLine: some View {
        HStack(spacing: 14) {
            Text(kind.displayLabel.uppercased())
                .font(.system(size: 18, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(accent.opacity(0.85), in: Capsule())

            if kind == .youtube {
                Text("\(statText(meta?.stats?.subscribers)) subscribers · \(statText(meta?.stats?.videos)) videos")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(TVTheme.textSecondary)
            } else if kind == .twitch {
                Text("\(statText(meta?.stats?.subscribers)) followers · \(statText(meta?.stats?.videos)) VODs")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(TVTheme.textSecondary)
            }

            if isLive {
                HStack(spacing: 8) {
                    Circle().fill(Color.red).frame(width: 10, height: 10)
                    Text("LIVE")
                        .font(.system(size: 18, weight: .heavy))
                        .tracking(1.2)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.28), in: Capsule())
                .overlay(Capsule().stroke(Color.red.opacity(0.8), lineWidth: 1))
            }
        }
    }

    private var handleText: String? {
        guard kind == .podcast || kind == .kick, let handle = source?.handle else { return nil }
        return handle.hasPrefix("@") ? handle : "@\(handle)"
    }

    private var socialCounterRow: some View {
        HStack(spacing: 26) {
            Label("\(social.likes(detail.titleId))", systemImage: "heart.fill")
            if social.commentTotal(detail.titleId) > 0 {
                Label("\(social.commentTotal(detail.titleId))", systemImage: "bubble.left.fill")
            }
        }
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(TVTheme.textSecondary)
    }

    // MARK: - Actions

    private var actionsRow: some View {
        HStack(alignment: .top, spacing: 26) {
            watchButton
            circleAction(
                systemImage: streams.contains(titleId: detail.titleId) ? "checkmark" : "plus",
                caption: streams.contains(titleId: detail.titleId) ? "Following" : "Follow",
                field: .follow
            ) {
                Task {
                    if streams.contains(titleId: detail.titleId) {
                        await streams.remove(titleId: detail.titleId)
                    } else {
                        await streams.add(
                            titleId: detail.titleId,
                            title: displayName,
                            posterUrl: avatarUrl,
                            platform: kind.displayLabel
                        )
                    }
                }
            }
            circleAction(
                systemImage: social.isWatched(detail.titleId) ? "eye.fill" : "eye",
                caption: "Watched?",
                field: .watched
            ) {
                Task { await social.toggleWatched(titleId: detail.titleId, titleName: displayName) }
            }
            circleAction(
                systemImage: social.isLiked(detail.titleId) ? "heart.fill" : "heart",
                caption: "Like",
                field: .like
            ) {
                Task { await social.toggleLike(titleId: detail.titleId) }
            }
        }
    }

    /// The one orange pill: opens the channel in its own app. Every kind has
    /// a chain — YouTube's is the existing channel opener, the rest are built
    /// from the id's slug — so this button is never dead, which is what it
    /// was for podcasts, Twitch and Kick on the old screen.
    private var watchButton: some View {
        Button {
            openChannel()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isLive ? "dot.radiowaves.left.and.right" : "play.fill")
                    .font(.system(size: 26, weight: .bold))
                Text(isLive ? "Watch live on \(kind.displayLabel)" : "Watch on \(kind.displayLabel)")
                    .font(.system(size: 24, weight: .bold))
            }
            .foregroundStyle(focusedField == .watch ? Color.black : Color.white)
            .padding(.horizontal, 40)
            .padding(.vertical, 22)
            .background(
                Capsule().fill(focusedField == .watch ? Color.white : Color.white.opacity(0.16))
            )
            .scaleEffect(focusedField == .watch ? 1.04 : 1.0)
            .animation(.easeOut(duration: 0.15), value: focusedField)
        }
        .buttonStyle(TVFlatButtonStyle())
        .focusEffectDisabled()
        .focused($focusedField, equals: .watch)
    }

    private func circleAction(
        systemImage: String,
        caption: String,
        field: Field,
        action: @escaping () -> Void
    ) -> some View {
        let focused = focusedField == field
        return VStack(spacing: 10) {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(focused ? Color.black : Color.white)
                    .frame(width: 76, height: 76)
                    .background(
                        Circle().fill(focused ? Color.white : Color.white.opacity(0.16))
                    )
                    .scaleEffect(focused ? 1.06 : 1.0)
                    .animation(.easeOut(duration: 0.15), value: focused)
            }
            .buttonStyle(TVFlatButtonStyle())
            .focusEffectDisabled()
            .focused($focusedField, equals: field)

            Text(caption)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(TVTheme.textSecondary)
        }
    }

    // MARK: - Currently streaming + About

    @ViewBuilder
    private var infoSection: some View {
        let liveTitle: String? = isLive ? live?.streamTitle : nil
        if liveTitle != nil || bio != nil {
            VStack(alignment: .leading, spacing: 32) {
                if let liveTitle {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("CURRENTLY STREAMING")
                            .font(.system(size: 18, weight: .heavy))
                            .tracking(1.6)
                            .foregroundStyle(Color.white.opacity(0.45))
                        HStack(spacing: 12) {
                            Circle().fill(Color.red).frame(width: 12, height: 12)
                            Text(liveTitle)
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        HStack(spacing: 16) {
                            if let category = live?.category {
                                Text(category)
                                    .font(.system(size: 22))
                                    .foregroundStyle(TVTheme.textSecondary)
                            }
                            if let viewers = live?.viewerCount, viewers > 0 {
                                Text("\(formatStat(Int64(viewers))) watching")
                                    .font(.system(size: 22))
                                    .foregroundStyle(TVTheme.textSecondary)
                            }
                        }
                    }
                }

                if let bio {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionHeader("About")
                        Text(bio)
                            .font(.system(size: 24))
                            .foregroundStyle(TVTheme.textSecondary)
                            .lineSpacing(6)
                            .lineLimit(6)
                            .frame(maxWidth: 1100, alignment: .leading)
                    }
                }
            }
            .padding(.trailing, 80)
        }
    }

    // MARK: - Recent uploads / episodes

    @ViewBuilder
    private var uploadsSection: some View {
        if kind == .youtube || kind == .twitch {
            if let uploads = meta?.uploads, !uploads.isEmpty {
                VStack(alignment: .leading, spacing: 24) {
                    sectionHeader(kind == .twitch ? "Recent VODs" : "Recent uploads")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 32) {
                            ForEach(uploads) { upload in
                                uploadCard(upload)
                            }
                        }
                        .padding(.trailing, 80)
                        .padding(.vertical, 24)
                    }
                    .focusSection()
                }
            } else if isLoadingMeta {
                VStack(alignment: .leading, spacing: 24) {
                    sectionHeader(kind == .twitch ? "Recent VODs" : "Recent uploads")
                    ProgressView().tint(.white).scaleEffect(1.6)
                        .padding(.vertical, 40)
                }
            }
        } else if kind == .podcast, !episodes.isEmpty {
            VStack(alignment: .leading, spacing: 24) {
                sectionHeader("Recent episodes")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 32) {
                        ForEach(episodes) { episode in
                            episodeCard(episode)
                        }
                    }
                    .padding(.trailing, 80)
                    .padding(.vertical, 24)
                }
                .focusSection()
            }
        }
    }

    /// One upload: 16:9 still, duration badge, title, then "3 days ago ·
    /// 1.4M views" — the same line the phone builds. Selecting it opens that
    /// video in the platform's app rather than trying to play it here; tvOS
    /// has no WebKit, so there is no embed to fall back on.
    private func uploadCard(_ upload: TVChannelMetaResponse.Upload) -> some View {
        let focused = focusedField == .upload(upload.videoId)
        return Button {
            openUpload(upload)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    Color(white: 0.05)
                        .overlay {
                            TVRemoteImage(urlString: upload.thumbnail, contentMode: .fill)
                                .allowsHitTesting(false)
                        }
                    let badge = durationBadge(seconds: upload.durationSeconds)
                    if !badge.isEmpty {
                        Text(badge)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6))
                            .padding(12)
                    }
                }
                .frame(width: 420, height: 236)
                .clipShape(.rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(focused ? TVTheme.orange.opacity(0.95) : Color.white.opacity(0.06),
                                lineWidth: focused ? 4 : 1)
                }

                Text(upload.title.isEmpty ? "Video" : upload.title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                let line = uploadMetaLine(upload)
                if !line.isEmpty {
                    Text(line)
                        .font(.system(size: 20))
                        .foregroundStyle(TVTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(width: 420, alignment: .leading)
            .scaleEffect(focused ? 1.05 : 1.0)
            .shadow(color: focused ? TVTheme.orange.opacity(0.55) : .black.opacity(0.45),
                    radius: focused ? 36 : 14, y: focused ? 24 : 8)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: focused)
        }
        .buttonStyle(TVFlatButtonStyle())
        .focusEffectDisabled()
        .focused($focusedField, equals: .upload(upload.videoId))
    }

    /// A podcast episode. Audio plays here rather than handing off — there is
    /// no podcast app to hand off to on tvOS, and AVKit plays the enclosure
    /// URL directly.
    private func episodeCard(_ episode: TVCreatorEpisode) -> some View {
        let focused = focusedField == .episode(episode.id)
        return Button {
            playingEpisode = episode
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    Color(white: 0.05)
                        .overlay {
                            if let art = episode.posterUrl ?? episode.thumbnailUrl {
                                TVRemoteImage(urlString: art, contentMode: .fill)
                                    .allowsHitTesting(false)
                            } else {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 44, weight: .semibold))
                                    .foregroundStyle(accent.opacity(0.5))
                            }
                        }
                    if let mins = episode.durationMinutes, mins > 0 {
                        Text(durationLabel(minutes: mins))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6))
                            .padding(12)
                    }
                }
                .frame(width: 420, height: 236)
                .clipShape(.rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(focused ? TVTheme.orange.opacity(0.95) : Color.white.opacity(0.06),
                                lineWidth: focused ? 4 : 1)
                }

                Text(episode.title ?? "Episode")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let released = episode.releasedAt {
                    Text(Self.relativeFormatter.localizedString(for: released, relativeTo: Date()))
                        .font(.system(size: 20))
                        .foregroundStyle(TVTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(width: 420, alignment: .leading)
            .scaleEffect(focused ? 1.05 : 1.0)
            .shadow(color: focused ? TVTheme.orange.opacity(0.55) : .black.opacity(0.45),
                    radius: focused ? 36 : 14, y: focused ? 24 : 8)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: focused)
        }
        .buttonStyle(TVFlatButtonStyle())
        .focusEffectDisabled()
        .focused($focusedField, equals: .episode(episode.id))
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 14) {
            Capsule()
                .fill(TVTheme.orange)
                .frame(width: 6, height: 30)
                .shadow(color: TVTheme.orange.opacity(0.65), radius: 10)
            Text(title)
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Launch

    private func openChannel() {
        WatchIntentLogger.shared.log(
            eventType: .deeplinkFired,
            titleId: detail.titleId,
            platformId: kind.rawValue,
            metadata: ["source": "tv_creator_detail", "kind": kind.rawValue]
        )
        let external = kind.externalId(from: detail.titleId)
        switch kind {
        case .youtube:
            TVOSDeepLinker.openYouTubeChannel(channelId: external, name: displayName)
        case .twitch, .kick, .podcast:
            // Built from the id's slug, then the row's own channel URL, then
            // the app's home — the same shape openYouTubeChannel uses.
            let chain: [URL] = channelChain(external: external).compactMap { URL(string: $0) }
            TVOSDeepLinker.openURLChain(chain)
        }
    }

    /// Scheme chains per platform. Kept here rather than in TVOSDeepLinker's
    /// resolve(), which is keyed on streaming-service names and has no notion
    /// of a creator slug.
    private func channelChain(external: String) -> [String] {
        let encoded = external.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? external
        switch kind {
        case .twitch:
            return [
                "twitch://stream/\(encoded)",
                "twitch://open?channel=\(encoded)",
                source?.channelUrl ?? "https://www.twitch.tv/\(encoded)",
                "twitch://"
            ]
        case .kick:
            return [
                "kick://\(encoded)",
                source?.channelUrl ?? "https://kick.com/\(encoded)",
                "kick://"
            ]
        case .podcast:
            return [
                source?.feedUrl,
                source?.channelUrl,
                "podcasts://"
            ].compactMap { $0 }
        case .youtube:
            return []
        }
    }

    private func openUpload(_ upload: TVChannelMetaResponse.Upload) {
        WatchIntentLogger.shared.log(
            eventType: .deeplinkFired,
            titleId: detail.titleId,
            platformId: kind.rawValue,
            metadata: [
                "source": "tv_creator_detail",
                "kind": kind.rawValue,
                "video_id": upload.videoId
            ]
        )
        var chain: [URL] = []
        if let link = URL(string: upload.deepLink) { chain.append(link) }
        if kind == .youtube {
            chain.append(contentsOf: [
                URL(string: "youtube://www.youtube.com/watch?v=\(upload.videoId)"),
                URL(string: "youtube://")
            ].compactMap { $0 })
        }
        TVOSDeepLinker.openURLChain(chain)
    }

    // MARK: - Load

    private func load() async {
        async let sourceTask = TVCreatorService.fetchSource(titleId: detail.titleId)
        async let liveTask = TVCreatorService.fetchLiveStatus(titleId: detail.titleId)
        source = await sourceTask
        live = await liveTask

        await social.refreshCounts(titleId: detail.titleId)

        if kind == .podcast {
            episodes = await TVCreatorService.fetchEpisodes(titleId: detail.titleId)
        } else {
            isLoadingMeta = true
            meta = await TVCreatorService.fetchChannelMeta(titleId: detail.titleId)
            isLoadingMeta = false
        }
    }

    // MARK: - Formatting

    private func statText(_ value: Int64?) -> String {
        value.map { formatStat($0) } ?? "—"
    }

    private func formatStat(_ n: Int64) -> String {
        if n >= 1_000_000_000 { return String(format: "%.1fB", Double(n) / 1_000_000_000) }
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    private func durationBadge(seconds: Int) -> String {
        guard seconds > 0 else { return "" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private func durationLabel(minutes: Int) -> String {
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
        return "\(minutes) min"
    }

    private func uploadMetaLine(_ upload: TVChannelMetaResponse.Upload) -> String {
        var parts: [String] = []
        if let date = Self.parseISODate(upload.publishedAt) {
            parts.append(Self.relativeFormatter.localizedString(for: date, relativeTo: Date()))
        }
        if upload.views > 0 {
            parts.append("\(formatStat(upload.views)) views")
        }
        return parts.joined(separator: " · ")
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    /// Published dates arrive with and without fractional seconds depending on
    /// the platform, so both are tried before giving up.
    private static func parseISODate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }
}

// MARK: - Podcast playback

/// Full-screen AVKit playback for a podcast episode. Audio-only media plays
/// through the same player; tvOS shows its own now-playing chrome over the
/// artwork, so there is nothing to build here beyond handing it the URL.
private struct TVPodcastPlayer: View {
    let episode: TVCreatorEpisode
    let title: String

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60, weight: .bold))
                        .foregroundStyle(TVTheme.orange)
                    Text("This episode has no playable audio")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .onAppear {
            guard let raw = episode.deepLinkUrl, let url = URL(string: raw) else { return }
            let item = AVPlayer(url: url)
            player = item
            item.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .onExitCommand { dismiss() }
    }
}

// MARK: - Focus style


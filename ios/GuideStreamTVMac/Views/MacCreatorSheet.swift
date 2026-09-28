//
//  MacCreatorSheet.swift
//  GuideStreamTVMac
//
//  The creator screen, laid out like tvOS TVCreatorDetailView and the phone's
//  CreatorDetailView: blurred avatar backdrop, round avatar hero with the
//  platform badge, subscriber/video (or follower/VOD) counts and live pill,
//  like/comment counters, the latest upload named above an orange
//  "Watch on <brand>" pill, Follow / Watched? / Like circle actions,
//  Currently streaming, About, then Recent uploads / VODs / episodes.
//
//  Mac-only difference: YouTube uploads and podcast episodes play inside the
//  sheet (WKWebView / AVKit) instead of handing off, like tvOS podcasts.
//

import SwiftUI
import AVKit

struct MacCreatorSheet: View {
    let ref: MacCreatorRef
    @Environment(\.dismiss) private var dismiss

    @State private var source: TVCreatorSource?
    @State private var live: TVLiveStatus?
    @State private var episodes: [TVCreatorEpisode] = []
    @State private var meta: TVChannelMetaResponse?
    @State private var isLoadingMeta = false
    @State private var loaded = false

    @State private var playingVideo: String?
    @State private var playingEpisode: TVCreatorEpisode?
    @State private var episodePlayer: AVPlayer?

    @State private var streams = TVStreamsViewModel.shared
    @State private var social = SocialViewModel.shared

    private var titleId: String { ref.titleId }
    private var kind: TVCreatorKind { TVCreatorKind.from(titleId: titleId) ?? .youtube }
    private var displayName: String { meta?.channel?.name ?? source?.displayName ?? "Creator" }
    private var avatarUrl: String? { meta?.channel?.avatar ?? source?.imageUrl }
    private var isLive: Bool { live?.isLive ?? false }
    private var isFollowing: Bool { streams.contains(titleId: titleId) }

    private var bio: String? {
        let raw = meta?.channel?.description ?? source?.description
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return raw
    }

    private var accent: Color {
        switch kind {
        case .youtube: return Color(red: 1.0, green: 0.0, blue: 0.0)
        case .podcast: return Color(red: 0.49, green: 0.23, blue: 0.93)
        case .twitch: return Color(red: 0.57, green: 0.27, blue: 1.0)
        case .kick: return Color(red: 0.33, green: 0.99, blue: 0.09)
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            backdrop
            if !loaded && source == nil {
                ProgressView().tint(MacColor.orange).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 32) {
                        hero
                        if let playingVideo { inlineVideo(playingVideo) }
                        if let playingEpisode { inlineEpisode(playingEpisode) }
                        infoSection
                        uploadsSection
                    }
                    .padding(.horizontal, 36)
                    .padding(.top, 44)
                    .padding(.bottom, 36)
                }
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .padding(16)
        }
        .frame(width: 980, height: 760)
        .background(MacColor.navy)
        .task { await load() }
        .onDisappear { episodePlayer?.pause() }
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        GeometryReader { proxy in
            ZStack {
                MacColor.navy
                if let avatarUrl {
                    TVRemoteImage(urlString: avatarUrl, contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .blur(radius: 50)
                        .opacity(0.45)
                }
                LinearGradient(colors: [MacColor.navy.opacity(0.2), MacColor.navy.opacity(0.96)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .top, spacing: 30) {
            TVRemoteImage(urlString: avatarUrl, contentMode: .fill)
                .frame(width: 170, height: 170)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.6), radius: 20, y: 8)

            VStack(alignment: .leading, spacing: 12) {
                metadataLine
                Text(displayName)
                    .font(.system(size: 36, weight: .heavy))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                if let handle = handleText {
                    Text(handle).font(.system(size: 14, weight: .semibold)).foregroundStyle(MacColor.text2)
                }
                socialCounterRow
                latestDropBlock
                actionsRow.padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
    }

    private var metadataLine: some View {
        HStack(spacing: 10) {
            Text(kind.displayLabel.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.2)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(accent.opacity(0.85), in: Capsule())
            if kind == .youtube {
                Text("\(statText(meta?.stats?.subscribers)) subscribers · \(statText(meta?.stats?.videos)) videos")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(MacColor.text2)
            } else if kind == .twitch {
                Text("\(statText(meta?.stats?.subscribers)) followers · \(statText(meta?.stats?.videos)) VODs")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(MacColor.text2)
            }
            if isLive {
                HStack(spacing: 6) {
                    Circle().fill(Color.red).frame(width: 7, height: 7)
                    Text("LIVE").font(.system(size: 11, weight: .heavy)).tracking(1)
                }
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Color.red.opacity(0.28), in: Capsule())
                .overlay(Capsule().stroke(Color.red.opacity(0.8), lineWidth: 1))
            }
        }
    }

    private var handleText: String? {
        guard kind == .podcast || kind == .kick, let handle = source?.handle, !handle.isEmpty else { return nil }
        return handle.hasPrefix("@") ? handle : "@\(handle)"
    }

    private var socialCounterRow: some View {
        HStack(spacing: 18) {
            Button { Task { await social.toggleLike(titleId: titleId) } } label: {
                Label("\(social.likes(titleId))", systemImage: social.isLiked(titleId) ? "heart.fill" : "heart")
                    .foregroundStyle(social.isLiked(titleId) ? MacColor.orange : MacColor.text2)
            }
            .buttonStyle(.plain)
            if social.commentTotal(titleId) > 0 {
                Label("\(social.commentTotal(titleId))", systemImage: "bubble.left.fill")
                    .foregroundStyle(MacColor.text2)
            }
        }
        .font(.system(size: 13, weight: .semibold))
    }

    // MARK: - Latest drop + actions

    private struct LatestDrop {
        let title: String
        let synopsis: String?
        let meta: String
        let upload: TVChannelMetaResponse.Upload?
        let episode: TVCreatorEpisode?
    }

    private var latestDrop: LatestDrop? {
        if kind == .podcast {
            guard let ep = episodes.first else { return nil }
            return LatestDrop(title: ep.title ?? "Episode", synopsis: Self.synopsis(from: ep.synopsis),
                              meta: ep.releasedAt.map { Self.relative.localizedString(for: $0, relativeTo: Date()) } ?? "",
                              upload: nil, episode: ep)
        }
        guard let u = meta?.uploads.first else { return nil }
        return LatestDrop(title: u.title.isEmpty ? "Video" : u.title, synopsis: Self.synopsis(from: u.description),
                          meta: uploadMetaLine(u), upload: u, episode: nil)
    }

    private var latestLabel: String {
        switch kind {
        case .podcast: return "LATEST EPISODE"
        case .twitch: return "LATEST VOD"
        case .kick, .youtube: return "LATEST UPLOAD"
        }
    }

    @ViewBuilder private var latestDropBlock: some View {
        if let drop = latestDrop {
            VStack(alignment: .leading, spacing: 6) {
                Text(latestLabel).font(.system(size: 11, weight: .heavy)).tracking(1.2).foregroundStyle(MacColor.text3)
                Text(drop.title).font(.system(size: 17, weight: .bold)).lineLimit(2)
                if let s = drop.synopsis {
                    Text(s).font(.system(size: 13)).foregroundStyle(MacColor.text2).lineLimit(3)
                }
                if !drop.meta.isEmpty {
                    Text(drop.meta).font(.system(size: 12)).foregroundStyle(MacColor.text3)
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.top, 2)
        }
    }

    private var actionsRow: some View {
        HStack(alignment: .top, spacing: 18) {
            Button(action: launchWatch) {
                HStack(spacing: 9) {
                    Image(systemName: isLive ? "dot.radiowaves.left.and.right" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text(isLive ? "Watch live on" : "Watch on").font(.system(size: 15, weight: .bold))
                    TVServiceBrandMark(providerName: kind.displayLabel, size: 24, catalogId: kind.brandCatalogId)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .frame(height: 46)
                .background(Capsule().fill(MacColor.orange))
                .shadow(color: MacColor.orange.opacity(0.35), radius: 12, y: 5)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)

            circleAction(isFollowing ? "bookmark.fill" : "bookmark", isFollowing ? "Following" : "Follow",
                         tint: isFollowing ? MacColor.orange : .white) {
                Task {
                    if isFollowing { await streams.remove(titleId: titleId) }
                    else { await streams.add(titleId: titleId, title: displayName, posterUrl: avatarUrl, platform: kind.displayLabel) }
                }
            }
            .disabled(!AuthViewModel.shared.isAuthenticated && !AuthViewModel.shared.isGuest)

            circleAction(social.isWatched(titleId) ? "eye.fill" : "eye", social.isWatched(titleId) ? "Watched" : "Watched?",
                         tint: social.isWatched(titleId) ? MacColor.blue : .white) {
                Task { await social.toggleWatched(titleId: titleId, titleName: displayName) }
            }

            circleAction(social.isLiked(titleId) ? "heart.fill" : "heart", "Like",
                         tint: social.isLiked(titleId) ? MacColor.orange : .white) {
                Task { await social.toggleLike(titleId: titleId) }
            }
        }
    }

    private func circleAction(_ icon: String, _ label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(tint)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                Text(label).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.7))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Live wins; otherwise the newest upload (played here for YouTube and
    /// podcasts), then the channel.
    private func launchWatch() {
        guard !isLive, let drop = latestDrop else { openChannel(); return }
        if let u = drop.upload { openUpload(u) }
        else if let ep = drop.episode { play(ep) }
        else { openChannel() }
    }

    // MARK: - Inline players

    private func inlineVideo(_ id: String) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            MacYouTubePlayer(videoId: id, onUnplayable: {
                if let u = meta?.uploads.first(where: { $0.videoId == id }), let url = URL(string: u.deepLink) {
                    MacLinkOpener.open(url)
                }
            })
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: MacLayout.cardRadius))
            .id(id)
            Button("Close player") { playingVideo = nil }
                .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(MacColor.text2)
        }
    }

    private func inlineEpisode(_ ep: TVCreatorEpisode) -> some View {
        HStack(spacing: 14) {
            TVRemoteImage(urlString: ep.posterUrl ?? ep.thumbnailUrl ?? avatarUrl, contentMode: .fill)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 6) {
                Text(ep.title ?? "Episode").font(.system(size: 14, weight: .semibold)).lineLimit(1)
                if let episodePlayer {
                    VideoPlayer(player: episodePlayer).frame(height: 40)
                } else {
                    Text("This episode has no playable audio").font(.system(size: 12)).foregroundStyle(MacColor.text2)
                }
            }
            Button {
                episodePlayer?.pause(); episodePlayer = nil; playingEpisode = nil
            } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 18)) }
                .buttonStyle(.plain).foregroundStyle(MacColor.text2)
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: MacLayout.cardRadius))
    }

    private func play(_ ep: TVCreatorEpisode) {
        episodePlayer?.pause()
        playingVideo = nil
        playingEpisode = ep
        if let raw = ep.deepLinkUrl, let url = URL(string: raw) {
            let p = AVPlayer(url: url)
            episodePlayer = p
            p.play()
        } else {
            episodePlayer = nil
        }
    }

    // MARK: - Currently streaming + About

    @ViewBuilder private var infoSection: some View {
        let liveTitle: String? = isLive ? live?.streamTitle : nil
        if liveTitle != nil || bio != nil {
            VStack(alignment: .leading, spacing: 22) {
                if let liveTitle {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CURRENTLY STREAMING").font(.system(size: 11, weight: .heavy)).tracking(1.4)
                            .foregroundStyle(Color.white.opacity(0.45))
                        HStack(spacing: 8) {
                            Circle().fill(Color.red).frame(width: 8, height: 8)
                            Text(liveTitle).font(.system(size: 16, weight: .semibold))
                        }
                        HStack(spacing: 12) {
                            if let c = live?.category { Text(c) }
                            if let v = live?.viewerCount, v > 0 { Text("\(formatStat(Int64(v))) watching") }
                        }
                        .font(.system(size: 13)).foregroundStyle(MacColor.text2)
                    }
                }
                if let bio {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader("About")
                        Text(bio).font(.system(size: 13.5)).foregroundStyle(MacColor.text2)
                            .lineSpacing(3).lineLimit(6).frame(maxWidth: 760, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    // MARK: - Recent uploads / episodes

    @ViewBuilder private var uploadsSection: some View {
        if kind == .youtube || kind == .twitch {
            if let uploads = meta?.uploads, !uploads.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    sectionHeader(kind == .twitch ? "Recent VODs" : "Recent uploads")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(uploads) { u in uploadCard(u) }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } else if isLoadingMeta {
                VStack(alignment: .leading, spacing: 14) {
                    sectionHeader(kind == .twitch ? "Recent VODs" : "Recent uploads")
                    ProgressView().padding(.vertical, 20)
                }
            }
        } else if kind == .podcast, !episodes.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader("Recent episodes")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(episodes) { ep in episodeCard(ep) }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func uploadCard(_ u: TVChannelMetaResponse.Upload) -> some View {
        MacMediaCard(title: u.title.isEmpty ? "Video" : u.title, image: u.thumbnail,
                     badge: durationBadge(u.durationSeconds), meta: uploadMetaLine(u),
                     selected: playingVideo == u.videoId, placeholderIcon: "play.fill", accent: accent) {
            openUpload(u)
        }
    }

    private func episodeCard(_ ep: TVCreatorEpisode) -> some View {
        MacMediaCard(title: ep.title ?? "Episode", image: ep.posterUrl ?? ep.thumbnailUrl,
                     badge: ep.durationMinutes.map(durationLabel) ?? "",
                     meta: ep.releasedAt.map { Self.relative.localizedString(for: $0, relativeTo: Date()) } ?? "",
                     selected: playingEpisode?.id == ep.id, placeholderIcon: "mic.fill", accent: accent) {
            play(ep)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 10) {
            Capsule().fill(MacColor.orange).frame(width: 4, height: 20)
                .shadow(color: MacColor.orange.opacity(0.6), radius: 6)
            Text(title).font(.system(size: 18, weight: .heavy))
        }
    }

    // MARK: - Launch

    private func openUpload(_ u: TVChannelMetaResponse.Upload) {
        WatchIntentLogger.shared.log(eventType: .deeplinkFired, titleId: titleId, platformId: kind.rawValue,
                                     metadata: ["source": "mac_creator_detail", "kind": kind.rawValue, "video_id": u.videoId])
        if kind == .youtube {
            episodePlayer?.pause(); episodePlayer = nil; playingEpisode = nil
            playingVideo = u.videoId
        } else if let url = URL(string: u.deepLink) {
            MacLinkOpener.open(url)
        }
    }

    private func openChannel() {
        WatchIntentLogger.shared.log(eventType: .deeplinkFired, titleId: titleId, platformId: kind.rawValue,
                                     metadata: ["source": "mac_creator_detail", "kind": kind.rawValue])
        let url = source?.channelUrl.flatMap(URL.init(string:))
            ?? MacCreatorLinks.url(for: titleId)
            ?? source?.feedUrl.flatMap(URL.init(string:))
        if let url { MacLinkOpener.open(url) }
    }

    // MARK: - Load

    private func load() async {
        async let s = TVCreatorService.fetchSource(titleId: titleId)
        async let l = TVCreatorService.fetchLiveStatus(titleId: titleId)
        source = await s
        live = await l
        loaded = true
        await social.refreshCounts(titleId: titleId)
        if kind == .podcast {
            episodes = await TVCreatorService.fetchEpisodes(titleId: titleId)
        } else {
            isLoadingMeta = true
            meta = await TVCreatorService.fetchChannelMeta(titleId: titleId)
            isLoadingMeta = false
        }
    }

    // MARK: - Formatting

    private func statText(_ v: Int64?) -> String { v.map(formatStat) ?? "—" }

    private func formatStat(_ n: Int64) -> String {
        if n >= 1_000_000_000 { return String(format: "%.1fB", Double(n) / 1_000_000_000) }
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    private func durationBadge(_ s: Int) -> String {
        guard s > 0 else { return "" }
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }

    private func durationLabel(_ minutes: Int) -> String {
        guard minutes > 0 else { return "" }
        if minutes >= 60 { let m = minutes % 60; return m > 0 ? "\(minutes / 60)h \(m)m" : "\(minutes / 60)h" }
        return "\(minutes) min"
    }

    private func uploadMetaLine(_ u: TVChannelMetaResponse.Upload) -> String {
        var parts: [String] = []
        if let d = Self.parseISO(u.publishedAt) { parts.append(Self.relative.localizedString(for: d, relativeTo: Date())) }
        if u.views > 0 { parts.append("\(formatStat(u.views)) views") }
        return parts.joined(separator: " · ")
    }

    /// Same cleanup as tvOS: drop link, chapter and hashtag lines, trim to ~220.
    static func synopsis(from raw: String?) -> String? {
        guard let raw else { return nil }
        let kept = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                guard !line.isEmpty else { return false }
                let lower = line.lowercased()
                if lower.contains("http://") || lower.contains("https://") || lower.contains("www.") { return false }
                if line.range(of: "^\\d{1,2}:\\d{2}", options: .regularExpression) != nil { return false }
                if line.hasPrefix("#") || line.hasPrefix("@") { return false }
                return true
            }
        guard !kept.isEmpty else { return nil }
        let joined = kept.joined(separator: " ")
        guard joined.count > 220 else { return joined }
        let cut = joined.prefix(220)
        if let space = cut.lastIndex(of: " ") { return cut[..<space].trimmingCharacters(in: .whitespaces) + "…" }
        return String(cut) + "…"
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .full; return f
    }()

    private static func parseISO(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
}

/// 16:9 upload / episode card with a duration badge and hover outline.
private struct MacMediaCard: View {
    let title: String
    let image: String?
    let badge: String
    let meta: String
    let selected: Bool
    let placeholderIcon: String
    let accent: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    Color(white: 0.06).overlay {
                        if let image {
                            TVRemoteImage(urlString: image, contentMode: .fill).allowsHitTesting(false)
                        } else {
                            Image(systemName: placeholderIcon).font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(accent.opacity(0.5))
                        }
                    }
                    if !badge.isEmpty {
                        Text(badge).font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
                            .padding(8)
                    }
                }
                .frame(width: 280, height: 158)
                .clipShape(RoundedRectangle(cornerRadius: MacLayout.cardRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: MacLayout.cardRadius)
                        .strokeBorder(selected || hovering ? MacColor.orange : Color.white.opacity(0.06),
                                      lineWidth: selected || hovering ? 2 : 1)
                }
                Text(title).font(.system(size: 13.5, weight: .semibold)).lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !meta.isEmpty {
                    Text(meta).font(.system(size: 11.5)).foregroundStyle(MacColor.text3).lineLimit(1)
                }
            }
            .frame(width: 280, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

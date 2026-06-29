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

    // Dismiss state for the sponsored affiliate banner.
    @State private var adDismissed: Bool = false

    // Social (likes / comments) — keyed off the creator's titleId
    @State private var social = SocialViewModel.shared
    @State private var showComments: Bool = false
    @State private var isTogglingLike: Bool = false

    // Sticky compact header offset + share-sheet presentation.
    @State private var scrollOffset: CGFloat = 0
    @State private var showShareSheet: Bool = false

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
        ZStack(alignment: .top) {
            BrandBackground()

            if isLoading {
                ProgressView().tint(Color.orange)
            } else if let source {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        // MARK: Hero (full-bleed, matching ShowDetailScreen)
                        DetailHeroHeader(
                            heroImageUrl: CreatorImageOverrides.resolve(titleId: titleId, stored: source.imageUrl),
                            title: source.displayName,
                            metadata: { creatorMetadata(source: source) },
                            onBack: onBack,
                            onShare: { triggerShare() }
                        )

                        // MARK: Fan Activity card (like / comment / save / notify)
                        FanActivityCard(
                            liked: social.isLiked(titleId),
                            likeLabel: social.likes(titleId) > 0 ? formatSocialCount(social.likes(titleId)) : "Like",
                            onLike: { toggleLikeAction() },
                            commentLabel: social.commentTotal(titleId) > 0 ? formatSocialCount(social.commentTotal(titleId)) : "Comment",
                            onComment: { openComments() },
                            isSaved: isFollowed,
                            saveLabel: isFollowed ? "Following" : "Follow",
                            onSave: { toggleFollow() },
                            notifyOn: uploadAlertsOn,
                            onNotify: { toggleUploadAlerts() }
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 24)

                        // MARK: Currently streaming + About
                        creatorInfoSection(source: source)

                        // MARK: Inline media (podcast audio on iOS; all kinds on tvOS)
#if os(tvOS)
                        mediaArea(source: source)
                            .padding(.top, 16)
#else
                        if kind == .podcast {
                            mediaArea(source: source)
                                .padding(.top, 16)
                        }
#endif

                        // MARK: Recent uploads
                        recentUploadsContainer(source: source)

                        // MARK: Sponsored affiliate banner (live Rakuten card)
                        affiliateBanner
                            .padding(.top, 24)

                        Color.clear.frame(height: 140)
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: ScrollOffsetKey.self,
                                value: -geo.frame(in: .named("creatorDetailScroll")).minY
                            )
                        }
                    )
                }
                .coordinateSpace(name: "creatorDetailScroll")
                .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = $0 }

#if os(iOS)
                DetailCompactHeader(title: source.displayName, onBack: onBack) {
                    Button { triggerShare() } label: {
                        Image(systemName: "square.and.arrow.up")
                            .scaledFont(size: 14, weight: .semibold)
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
                .opacity(scrollOffset > 220 ? 1 : 0)
                .offset(y: scrollOffset > 220 ? 0 : -8)
                .animation(.easeOut(duration: 0.18), value: scrollOffset > 220)
                .allowsHitTesting(scrollOffset > 220)

                if kind != .podcast {
                    creatorBottomBar(source: source)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .ignoresSafeArea(edges: .bottom)
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
#if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
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
        .sheet(isPresented: $showShareSheet) {
            if let source {
                CreatorShareSheet(items: [shareURL(source: source)])
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

    // MARK: - Like / comment actions (wired into FanActivityCard)

    /// Toggles the creator like via `SocialViewModel.shared`, guarding against
    /// double-taps while the network round-trip is in flight.
    private func toggleLikeAction() {
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

    /// Opens the existing comment composer/viewer sheet for this creator.
    private func openComments() {
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

    /// Triggers the system share sheet (presented from `body`).
    private func triggerShare() {
#if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showShareSheet = true
#endif
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

    // MARK: - Hero metadata slot

    /// Hero metadata line: the platform badge followed by compact subscriber /
    /// video counts for YouTube ("—" while pending), or the @handle otherwise.
    @ViewBuilder
    private func creatorMetadata(source: ContentSource) -> some View {
        HStack(spacing: 8) {
            SourceTypeBadge(kind: kind)
            if kind == .youtube {
                Text("· \(statText(channelMeta?.subscribers)) subscribers · \(statText(channelMeta?.videoCount)) videos")
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            } else if kind == .twitch {
                Text("· \(statText(channelMeta?.subscribers)) followers · \(statText(channelMeta?.videoCount)) VODs")
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            } else if let handle = source.handle {
                let cleanHandle = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
                Text("@\(cleanHandle)")
                    .scaledFont(size: 14)
                    .foregroundStyle(Color.textSecondary)
            }
            if let liveStatus, liveStatus.isLive {
                LivePill()
            }
        }
    }

    /// Compact-formatted stat figure, or "—" when the value is unavailable
    /// (stats pending server-side or the edge call failed).
    private func statText(_ value: Int?) -> String {
        value.map { formatStat($0) } ?? "—"
    }

    // MARK: - Currently streaming + About

    @ViewBuilder
    private func creatorInfoSection(source: ContentSource) -> some View {
        let bio = bioText(source: source)
        let liveTitle: String? = (liveStatus?.isLive ?? false) ? liveStatus?.streamTitle : nil
        if bio != nil || liveTitle != nil {
            VStack(alignment: .leading, spacing: 18) {
                if let liveTitle {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CURRENTLY STREAMING")
                            .scaledFont(size: 12, weight: .heavy)
                            .tracking(1.4)
                            .foregroundStyle(Color.white.opacity(0.45))
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text(liveTitle)
                                .scaledFont(size: 16, weight: .semibold)
                                .foregroundStyle(.white)
                        }
                        if let cat = liveStatus?.category {
                            Text(cat)
                                .scaledFont(size: 13)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }

                if let bio {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("About")
                            .scaledFont(size: 17, weight: .semibold)
                            .foregroundStyle(.white)
                        Text(bio)
                            .scaledFont(size: 14)
                            .foregroundStyle(Color.textSecondary)
                            .lineSpacing(4)
                            .lineLimit(6)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
        }
    }

    // MARK: - Recent uploads container

    @ViewBuilder
    private func recentUploadsContainer(source: ContentSource) -> some View {
        if kind == .youtube || kind == .twitch {
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

    private func formatStat(_ n: Int) -> String {
        if n >= 1_000_000_000 { return String(format: "%.1fB", Double(n) / 1_000_000_000) }
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    // MARK: - 6. Sponsored affiliate banner

    /// Live "Stream more on …" affiliate card, identical to the one shown in
    /// the show/episode detail sheet. Drives the Rakuten affiliate link path
    /// and is dismissable. Picks a streaming service the user doesn't already
    /// own from the pool. iOS only (the affiliate/Rakuten stack is iOS-bound).
    @ViewBuilder
    private var affiliateBanner: some View {
#if os(iOS)
        if !adDismissed, let ad = affiliateAdData,
           let service = StreamingCatalog.all.first(where: { $0.id == ad.serviceId }) {
            SponsoredAffiliateCard(
                service: service,
                fallbackName: ad.headline,
                fallbackColor: .white,
                headline: ad.headline,
                subtitle: ad.subtext,
                onTap: {
                    RakutenManager.shared.openAffiliateLink(
                        serviceId: ad.serviceId,
                        metadata: [
                            "source": "creator_detail_sheet",
                            "title": source?.displayName ?? titleId
                        ]
                    )
                },
                onDismiss: { adDismissed = true }
            )
            .padding(.horizontal, 20)
        }
#else
        EmptyView()
#endif
    }

    /// Chooses the first streaming service from the pool that the user doesn't
    /// already own so the affiliate prompt is for something new.
    private var affiliateAdData: (serviceId: String, headline: String, subtext: String)? {
        let owned = AuthViewModel.shared.selectedServices.map { normalisedServiceKey($0) }
        let pool: [(String, String, String)] = [
            ("netflix", "Stream more on Netflix", "Unlimited shows & movies · Try free"),
            ("hbo", "Watch more on Max", "HBO, Max Originals & more · Try free"),
            ("hulu", "Live TV + streaming on Hulu", "Starting at $7.99/mo · Try free"),
            ("disney", "Disney+, Hulu & ESPN+ bundle", "Disney Bundle · Try free"),
            ("appletv", "Award-winning originals", "Apple TV+ · First month free"),
            ("prime", "Included with Prime", "Prime Video · Try free"),
            ("paramount", "NFL on CBS & live sports", "Paramount+ · Try free"),
            ("peacock", "Stream free on Peacock", "NBC shows & live sports · Free tier")
        ]
        if let preferred = pool.first(where: { !owned.contains($0.0) }) {
            return (preferred.0, preferred.1, preferred.2)
        }
        return pool.first.map { ($0.0, $0.1, $0.2) }
    }

    private func normalisedServiceKey(_ raw: String) -> String {
        let k = raw.lowercased()
        if k.contains("netflix") { return "netflix" }
        if k.contains("max") || k.contains("hbo") { return "hbo" }
        if k.contains("hulu") { return "hulu" }
        if k.contains("disney") { return "disney" }
        if k.contains("apple") { return "appletv" }
        if k.contains("prime") || k.contains("amazon") { return "prime" }
        if k.contains("paramount") { return "paramount" }
        if k.contains("peacock") { return "peacock" }
        return k
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
    /// `youtube_channel_meta` or `twitch_channel_meta` Supabase edge function.
    /// The correct function is selected by the creator's title_id prefix
    /// (`yt:` → YouTube, `tw:` → Twitch). Both functions return the identical
    /// `ChannelMetaResponse` shape, so no rendering changes are needed.
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
            let functionName: String = titleId.hasPrefix("tw:") ? "twitch_channel_meta" : "youtube_channel_meta"
            let response: ChannelMetaResponse = try await SupabaseManager.shared.client.functions
                .invoke(
                    functionName,
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
#if os(iOS)
        // Open the tapped upload straight in YouTube — no inline embed.
        if let u = URL(string: upload.deepLink) {
            UIApplication.shared.open(u)
        }
#endif
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

    /// "Watch on YOUTUBE" CTA (mirroring the show-detail watch button). We no
    /// longer embed the player inline — embedded playback is widely restricted
    /// by channel owners, so we deep-link straight into the YouTube app/site
    /// for the currently-selected upload (or the channel when none is chosen).
    @ViewBuilder
    private func youtubePlayerSection(source: ContentSource) -> some View {
        watchOnButton(chip: "YouTube", chipColor: sourceColor) {
#if os(iOS)
            openYouTube()
#endif
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Shared "Watch on [chip]" CTA

    /// Orange capsule + branded service chip, matching the show-detail sheet's
    /// primary watch button. Used by every external creator platform so the
    /// call-to-action reads consistently across the app.
    private func watchOnButton(chip: String, chipColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .scaledFont(size: 15, weight: .bold)
                Text("Watch on")
                    .scaledFont(size: 16, weight: .bold)
                    .lineLimit(1)
                Text(chip.uppercased())
                    .scaledFont(size: 10, weight: .heavy)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(chipColor)
                    )
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule().fill(Color.orange))
            .shadow(color: Color.orange.opacity(0.35), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
    }

#if os(iOS)
    /// Deep-links into YouTube for the currently-selected upload, falling back
    /// to the channel page. iOS routes the https URL into the YouTube app via
    /// universal links. No raw stream URL is extracted (YouTube ToS).
    private func openYouTube() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let deep = currentDeepLinkUrl, let u = URL(string: deep) {
            UIApplication.shared.open(u)
            return
        }
        if let videoId = currentEpisodeId, let u = URL(string: "https://www.youtube.com/watch?v=\(videoId)") {
            UIApplication.shared.open(u)
            return
        }
        if let ch = source?.channelUrl ?? source?.feedUrl, let u = URL(string: ch) {
            UIApplication.shared.open(u)
        }
    }
#endif

#if os(iOS)
    // MARK: - Bottom action bar (matches ShowDetailScreen)

    /// Bottom bar mirroring the show-detail screen: a "most recent upload" strip
    /// (YouTube only) above the orange "Watch on <CHIP>" capsule and a circular
    /// follow toggle, over a navy ultraThinMaterial background.
    @ViewBuilder
    private func creatorBottomBar(source: ContentSource) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)

            VStack(spacing: 10) {
                if (kind == .youtube || kind == .twitch), let latest = channelUploads.first {
                    latestUploadStrip(latest)
                }

                HStack(spacing: 8) {
                    watchOnButton(chip: watchChipName, chipColor: sourceColor) {
                        openExternalWatch()
                    }

                    Button(action: toggleFollow) {
                        Image(systemName: isFollowed ? "checkmark" : "plus")
                            .scaledFont(size: 20, weight: .bold)
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(isFollowed ? Color.orange.opacity(0.20) : Color.white.opacity(0.08)))
                            .overlay(Circle().stroke(isFollowed ? Color.orange : Color.white.opacity(0.14), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .background(
                Color.navy.opacity(0.90)
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
    }

    private func latestUploadStrip(_ upload: ChannelMetaResponse.Upload) -> some View {
        HStack(spacing: 8) {
            Color.white.opacity(0.08)
                .frame(width: 38, height: 26)
                .overlay {
                    if let thumb = upload.thumbnail {
                        RemoteImage(urlString: thumb, contentMode: .fill, fallbackColors: [sourceColor, sourceColor.opacity(0.4)])
                            .allowsHitTesting(false)
                    } else {
                        Image(systemName: "play.fill")
                            .scaledFont(size: 8, weight: .bold)
                            .foregroundStyle(Color.white.opacity(0.45))
                    }
                }
                .clipShape(.rect(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 1) {
                Text("Latest upload")
                    .scaledFont(size: 9, weight: .semibold)
                    .foregroundStyle(Color.white.opacity(0.38))
                Text(upload.title.isEmpty ? "New video" : upload.title)
                    .scaledFont(size: 11, weight: .semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text("NEW")
                .scaledFont(size: 7, weight: .heavy)
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.orange)
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.09), lineWidth: 1)
                )
        )
    }

    /// Branded chip label inside the bottom "Watch on" capsule, per platform.
    private var watchChipName: String {
        switch kind {
        case .youtube: return "YouTube"
        case .twitch: return "Twitch"
        case .kick: return "Kick"
        case .podcast: return "Podcast"
        case .tmdb: return "TV"
        }
    }

    /// Routes the bottom CTA to the correct external-app deep link for the kind.
    private func openExternalWatch() {
        switch kind {
        case .youtube: openYouTube()
        case .twitch: openTwitch()
        case .kick: openKick()
        default: break
        }
    }
#endif

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

            watchOnButton(chip: "Twitch", chipColor: sourceColor) {
#if os(iOS)
                openTwitch()
#endif
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 16)
    }

    // MARK: - Kick section

    private var kickSection: some View {
        watchOnButton(chip: "Kick", chipColor: sourceColor) {
#if os(iOS)
            openKick()
#endif
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
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
        // (YouTube + Twitch, selected by title_id prefix inside the loader).
        // Runs after `source` is set so the header can be enriched with the
        // live channel name/avatar.
        if kind == .youtube || kind == .twitch {
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

#if os(iOS)
// MARK: - System share sheet

/// Lightweight wrapper around `UIActivityViewController` so the hero / compact
/// header share buttons can present the system share sheet via a state-driven
/// `.sheet` (instead of an inline `ShareLink`).
private struct CreatorShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

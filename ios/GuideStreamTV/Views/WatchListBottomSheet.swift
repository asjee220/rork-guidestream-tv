//
//  WatchListBottomSheet.swift
//  GuideStreamTV
//
//  Two surfaces that share the same content view (`WatchListContent`):
//
//  * `WatchListBottomSheet` — modal sheet presented from the home feed's
//    "See all" link on the Watch List section.
//  * `WatchListView` — pushed onto the Profile stack so users can manage
//    their saved titles from the Profile tab as well.
//
//  Both surfaces pull the same `user_streams` Supabase rows, support
//  swipe-to-delete, and open the existing `EpisodeDetailSheet` so the user
//  can pick up where they left off.
//

import SwiftUI
import UIKit
import Supabase

// MARK: - Bottom sheet

struct WatchListBottomSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GsSheetHeader(title: "My Watch List") {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
                WatchListContent()
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .sheetSurface(.base)
    }
}

// MARK: - Pushable destination (Profile tab)

struct WatchListView: View {
    var body: some View {
        WatchListContent()
            .navigationTitle("My Watch List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.navy, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .background(BrandBackground())
    }
}

// MARK: - Shared content

/// Renders the watch list itself — list, empty state, or guest prompt — plus
/// background atmosphere and the detail-sheet plumbing. Wrap this view in
/// whatever navigation chrome the surface needs (sheet vs. push).
private struct WatchListContent: View {
    @State private var streams = StreamsViewModel.shared
    @State private var social = SocialViewModel.shared
    @State private var auth = AuthViewModel.shared
    @State private var detailSubject: DetailSubject?
    @State private var showFollowCreators: Bool = false
    /// Full-screen detail for non-TMDB creator/ podcast entities.
    @State private var creatorDetailTarget: CreatorDetailTarget?
    /// Maps prefixed title_ids to their live status for in-list LIVE/OFFLINE pills.
    @State private var liveStatusMap: [String: LiveStatus] = [:]
    /// Maps prefixed title_ids to their content_sources.image_url, used as a
    /// poster fallback so every creator/podcast/streamer always shows an image.
    @State private var sourceImageMap: [String: String] = [:]
    /// Watch-list filter toggles — both default off, and both operate only on
    /// data already in hand (subscriptions + the expiring-titles cache).
    @State private var filterOnMyServices: Bool = false
    @State private var filterLeavingSoon: Bool = false
    @State private var reminders = ReleaseReminderService.shared

    var body: some View {
        ZStack {
            // Atmosphere — keeps the surface feeling like the rest of the app.
            GeometryReader { geo in
                Circle()
                    .fill(Color.blue.opacity(0.14))
                    .frame(width: geo.size.width * 0.9)
                    .blur(radius: 90)
                    .offset(x: -geo.size.width * 0.35, y: -geo.size.height * 0.35)
                Circle()
                    .fill(Color.orange.opacity(0.10))
                    .frame(width: geo.size.width * 0.7)
                    .blur(radius: 80)
                    .offset(x: geo.size.width * 0.4, y: geo.size.height * 0.4)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            content
        }
        .sheet(item: $detailSubject) { subject in
            EpisodeDetailSheet(subject: subject, level: .raised)
        }
        .fullScreenCover(isPresented: $showFollowCreators) {
            FollowCreatorsView()
        }
        .sheet(item: $creatorDetailTarget) { target in
            CreatorDetailView(
                titleId: target.titleId,
                initialEpisode: target.initialEpisode,
                onBack: { creatorDetailTarget = nil }
            )
        }
        .task {
            await streams.fetchUserStreams()
            await streams.fetchLatestContentDates()
            await streams.fetchWatchlistSeen()
            await social.loadAllWatched()
            await hydrateLiveStatus()
            await hydrateSourceImages()
            await refreshDepartureReminders()
        }
        .task {
            await subscribeToLiveStatus()
        }
        .refreshable {
            await streams.fetchUserStreams()
            await streams.fetchLatestContentDates()
            await streams.fetchWatchlistSeen()
            await social.loadAllWatched()
            await hydrateLiveStatus()
            await hydrateSourceImages()
            await refreshDepartureReminders()
        }
    }

    @ViewBuilder
    private var content: some View {
        if streams.userStreams.isEmpty {
            VStack(spacing: 16) {
                followCreatorsEntryCard
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                emptyState
            }
        } else {
            VStack(spacing: 0) {
                if !auth.isAuthenticated {
                    guestSyncBanner
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
                // Follow creators entry card — pinned above the saved list
                followCreatorsEntryCard
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                filterBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                if filteredStreams.isEmpty {
                    filteredEmptyState
                } else {
                List {
                    ForEach(filteredStreams) { item in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            let kind = SourceKind.from(titleId: item.titleId)
                            if kind.isNonTMDB {
                                creatorDetailTarget = CreatorDetailTarget(titleId: item.titleId, initialEpisode: nil)
                            } else {
                                detailSubject = .show(posterShow(from: item))
                            }
                        } label: {
                            WatchListRow(
                                item: item,
                                isLive: liveStatusMap[item.titleId]?.isLive ?? false,
                                isStreamer: SourceKind.from(titleId: item.titleId).isLivestream,
                                streamTitle: liveStatusMap[item.titleId]?.streamTitle,
                                effectivePosterUrl: CreatorImageOverrides.resolve(titleId: item.titleId, stored: item.posterUrl ?? sourceImageMap[item.titleId]),
                                isWatched: social.isWatched(item.titleId),
                                badgeText: streams.newBadgeText(for: item),
                                expiryText: expiryBadgeText(for: item),
                                isDepartureReminded: departureReminderKey(for: item)
                                    .map { reminders.isReminded($0, kind: .departure) } ?? false,
                                onToggleDepartureReminder: departureReminderAction(for: item)
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Color.white.opacity(0.06))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                remove(item)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                }
            }
        }
    }

    /// Entry card styled with orange-tinted glass that opens the Follow Creators
    /// discovery screen on tap.
    private var followCreatorsEntryCard: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            WatchIntentLogger.shared.log(
                eventType: .cardTapped,
                metadata: ["section": "follow_creators_entry", "source": "watch_list"]
            )
            showFollowCreators = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.orange.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: "person.2.badge.plus")
                        .scaledFont(size: 18, weight: .semibold)
                        .foregroundStyle(Color.orange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Follow creators & podcasts")
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(Color.textPrimary)
                    Text("YouTube, Twitch, Kick, and more")
                        .scaledFont(size: 12)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.orange.opacity(0.08))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.orange.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.14))
                    .frame(width: 88, height: 88)
                Image(systemName: "bookmark.fill")
                    .scaledFont(size: 32, weight: .semibold)
                    .foregroundStyle(Color.orange)
            }
            Text("Your watch list is empty")
                .scaledFont(size: 17, weight: .bold)
                .foregroundStyle(.white)
            Text("Tap the + on any show, movie, or creator to save it here. We'll keep them ready for tonight.")
                .scaledFont(size: 13)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Small inline banner shown above a guest's watch list so they know the
    /// list lives on this device until they sign in. We deliberately do NOT
    /// gate the list behind a sign-in wall — guests can save and manage
    /// items locally; signing in later syncs everything up to Supabase.
    private var guestSyncBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "icloud.slash")
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(Color.orange)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text("Saved on this device")
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(.white)
                Text("Sign in to sync your watch list across devices.")
                    .scaledFont(size: 12)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                )
        )
    }

    /// User streams sorted with live items first, then by recency
    /// (newest content first, falling back to date-added order).
    private var sortedStreams: [UserStream] {
        let recencyMap = streams.latestContentAt
        return streams.userStreams.sorted { a, b in
            let aLive = liveStatusMap[a.titleId]?.isLive ?? false
            let bLive = liveStatusMap[b.titleId]?.isLive ?? false
            if aLive != bLive { return aLive }
            let aDate = recencyMap[a.titleId]
            let bDate = recencyMap[b.titleId]
            if let aD = aDate, let bD = bDate, aD != bD {
                return aD > bD
            }
            // Titles with a recency entry come before those without.
            if aDate != nil && bDate == nil { return true }
            if aDate == nil && bDate != nil { return false }
            let aAdded = a.addedAt ?? Date.distantPast
            let bAdded = b.addedAt ?? Date.distantPast
            return aAdded > bAdded
        }
    }

    /// Two toggle chips above the saved list.
    private var filterBar: some View {
        HStack(spacing: 10) {
            WatchListFilterChip(label: "On my services", isOn: filterOnMyServices) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                filterOnMyServices.toggle()
            }
            WatchListFilterChip(label: "Leaving soon", isOn: filterLeavingSoon) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                filterLeavingSoon.toggle()
            }
            Spacer(minLength: 0)
        }
    }

    /// Empty state shown when the active filters exclude every saved title.
    private var filteredEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .scaledFont(size: 34, weight: .semibold)
                .foregroundStyle(Color.white.opacity(0.35))
            Text("No titles match these filters")
                .scaledFont(size: 15, weight: .semibold)
                .foregroundStyle(.white)
            Text("Try turning a filter off.")
                .scaledFont(size: 12)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Expiry cross-reference & filters

    /// One matched expiring-titles row, reduced to what the badge needs.
    private struct ExpiryInfo {
        let leavingDate: String?
        let serviceName: String?
    }

    /// Expiring rows keyed by tmdb id, taken from the data the Home rail
    /// already fetched (ExpiringTitlesService cache) — never a new network
    /// call and never a write to expiring_titles.
    private var expiryByTmdbId: [Int: ExpiryInfo] {
        Dictionary(
            ExpiringTitlesService.shared.cachedRows.map {
                ($0.tmdbId, ExpiryInfo(leavingDate: $0.leavingDate, serviceName: $0.serviceName))
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func expiryInfo(for item: UserStream) -> ExpiryInfo? {
        guard let id = TitleID.tmdbId(from: item.titleId) else { return nil }
        return expiryByTmdbId[id]
    }

    private func isOnMyServices(_ item: UserStream) -> Bool {
        guard let platform = item.platform, !platform.isEmpty else { return false }
        return AuthViewModel.shared.subscribesToService(named: platform)
    }

    /// Saved titles after the active filters. Both filters on intersect;
    /// neither on returns the unchanged sort order.
    private var filteredStreams: [UserStream] {
        guard filterOnMyServices || filterLeavingSoon else { return sortedStreams }
        return sortedStreams.filter { item in
            let onServicesOK = !filterOnMyServices || isOnMyServices(item)
            let leavingOK = !filterLeavingSoon || expiryInfo(for: item) != nil
            return onServicesOK && leavingOK
        }
    }

    private func expiryBadgeText(for item: UserStream) -> String? {
        expiryInfo(for: item).map { Self.badgeText(for: $0) }
    }

    /// Formats the matched row's leaving date + service into badge text.
    private static func badgeText(for info: ExpiryInfo) -> String {
        let dateText: String
        if let dateStr = info.leavingDate,
           let date = expiryDateParser.date(from: dateStr) {
            dateText = expiryDisplayFormatter.string(from: date)
        } else {
            dateText = "soon"
        }
        var text = "Leaving \(dateText)"
        if let service = info.serviceName, !service.isEmpty {
            text += " · \(service)"
        }
        return text
    }

    private static let expiryDateParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let expiryDisplayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "MMM d"
        return f
    }()

    private func departureReminderKey(for item: UserStream) -> String? {
        guard let id = TitleID.tmdbId(from: item.titleId) else { return nil }
        return String(id)
    }

    /// Bell action for a saved title matched as leaving — writes through the
    /// same release_reminders path with reminder_kind 'departure'.
    private func departureReminderAction(for item: UserStream) -> (() -> Void)? {
        guard expiryInfo(for: item) != nil,
              let key = departureReminderKey(for: item) else { return nil }
        let tmdbId = Int(key)
        let mediaType = (item.isTV ?? true) ? "tv" : "movie"
        return {
            Task {
                await reminders.toggleReminder(
                    titleId: key,
                    tmdbId: tmdbId,
                    source: "watchlist_leaving",
                    kind: .departure,
                    mediaType: mediaType
                )
            }
        }
    }

    /// Refreshes departure-reminder state for every saved title matched
    /// against the expiring cache.
    private func refreshDepartureReminders() async {
        for item in streams.userStreams {
            guard let key = departureReminderKey(for: item),
                  expiryInfo(for: item) != nil else { continue }
            await reminders.refreshReminded(titleId: key, kind: .departure)
        }
    }

    /// Fetch live_status for saved creator/streamer items so LIVE/OFFLINE pills
    /// render immediately without waiting for a Realtime event.
    private func hydrateLiveStatus() async {
        let creatorIds = streams.userStreams
            .filter { SourceKind.from(titleId: $0.titleId).isLivestream }
            .map { $0.titleId }
        guard !creatorIds.isEmpty else { return }
        if let statuses = try? await ContentSourcesService.shared.fetchLiveStatus(for: creatorIds) {
            var map: [String: LiveStatus] = [:]
            for s in statuses { map[s.titleId] = s }
            await MainActor.run { liveStatusMap = map }
        }
    }

    /// Gathers non-TMDB title_ids from user_streams, fetches their image_url
    /// from content_sources, and seeds sourceImageMap so every creator/podcast
    /// always shows a poster image.
    private func hydrateSourceImages() async {
        let creatorIds = streams.userStreams
            .filter { SourceKind.from(titleId: $0.titleId).isNonTMDB && ($0.posterUrl?.isEmpty ?? true) }
            .map { $0.titleId }
        guard !creatorIds.isEmpty else { return }
        if let map = try? await ContentSourcesService.shared.fetchSourceImages(for: creatorIds) {
            await MainActor.run { sourceImageMap.merge(map) { _, new in new } }
        }
    }

    /// Subscribe to live_status changes via Supabase Realtime so in-list
    /// LIVE pills update without a manual refresh.
    private func subscribeToLiveStatus() async {
        Task {
            let client = SupabaseManager.shared.client
            let channel = client.channel("live-status-watchlist")
            let changes = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "live_status"
            )
            await channel.subscribe()
            for await _ in changes {
                // hydrateLiveStatus is @MainActor and writes to @State liveStatusMap.
                await hydrateLiveStatus()
            }
        }
    }

    private func remove(_ item: UserStream) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task { await streams.removeFromMyStreams(titleId: item.titleId) }
    }

    private func posterShow(from item: UserStream) -> PosterShow {
        // Show the platform name when we have one; otherwise show the
        // generic media type so we don't leak "Streaming" as if it were a
        // platform. The detail sheet's Watchmode lookup will fill in the
        // real service moments later.
        let platformMeta: String = {
            if let resolved = Platform.from(providerName: item.platform),
               !resolved.name.isEmpty {
                return resolved.name
            }
            return "Watch list"
        }()
        return PosterShow(
            title: item.title ?? "Watch List Item",
            meta: platformMeta,
            posterColors: HomeFallback.posterColors,
            symbol: "play.tv.fill",
            posterUrl: item.posterUrl,
            tmdbId: TitleID.tmdbId(from: item.titleId),
            isTV: item.isTV ?? true
        )
    }
}

// MARK: - Row

private struct WatchListRow: View {
    let item: UserStream
    var isLive: Bool = false
    var isStreamer: Bool = false
    var streamTitle: String? = nil
    /// Resolved poster URL — uses content_sources.image_url as a fallback
    /// when user_streams.poster_url is nil, so every creator shows an image.
    var effectivePosterUrl: String? = nil
    /// Display-only: shows a small blue eye badge on the poster when the
    /// saved title is marked watched. Never mutates any watchlist state.
    var isWatched: Bool = false
    /// New-content badge text ("NEW EPISODE" or "NEW UPLOAD") from
    /// StreamsViewModel.newBadgeText, or nil when no badge should show.
    var badgeText: String? = nil
    /// Expiry badge text ("Leaving Mar 3 · Netflix") from the matched
    /// expiring-titles row, or nil when the title isn't leaving.
    var expiryText: String? = nil
    /// True when a departure reminder is set for this title.
    var isDepartureReminded: Bool = false
    /// Sets/unsets the departure reminder. nil when the title isn't leaving.
    var onToggleDepartureReminder: (() -> Void)? = nil

    private var posterKind: SourceKind { SourceKind.from(titleId: item.titleId) }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                // Full-bleed poster for all entities (TMDB and non-TMDB)
                // at the small watch-list row size. Non-TMDB creators now
                // fill the card the same way show/movie posters do — no more
                // circular inset crop. Brand-colour fallback when no image.
                Color.black
                    .overlay {
                        RemoteImage(
                            urlString: effectivePosterUrl ?? item.posterUrl,
                            contentMode: .fill,
                            fallbackColors: posterKind.isNonTMDB
                                ? [sourceKindColor(posterKind), sourceKindColor(posterKind).opacity(0.4)]
                                : HomeFallback.posterColors
                        )
                        .overlay {
                            if posterKind.isNonTMDB, ((effectivePosterUrl ?? item.posterUrl)?.isEmpty ?? true) {
                                Image(systemName: posterKind == .podcast ? "mic.fill" : "play.rectangle.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.30))
                            }
                        }
                        .allowsHitTesting(false)
                    }
            }
            .frame(width: 60, height: 90)
            .clipShape(.rect(cornerRadius: 8))
            .overlay(alignment: .topLeading) {
                if let badge = badgeText {
                    Text(badge)
                        .font(.system(size: 11, weight: .bold))
                        .textCase(.uppercase)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 6))
                        .padding(8)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isWatched {
                    Circle()
                        .fill(Color(hex: "1A6FE8"))
                        .frame(width: 20, height: 20)
                        .overlay {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .overlay {
                            Circle()
                                .stroke(Color.black.opacity(0.35), lineWidth: 1)
                        }
                        .padding(4)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    // Show LIVE/OFFLINE pill for streamer entities
                    if isStreamer {
                        if isLive {
                            LivePill()
                        } else {
                            OfflinePill()
                        }
                    }
                    // Only render the platform chip when we have a real,
                    // recognised streaming service. Generic placeholders like
                    // "Streaming" or "Stream" used to leak through here and
                    // confused users who saw the same neutral grey chip on
                    // every saved title.
                    if !isStreamer {
                        let resolved = Platform.from(providerName: item.platform)
                        if let resolved = resolved, !resolved.name.isEmpty {
                            Text(resolved.name.uppercased())
                                .scaledFont(size: 9, weight: .heavy)
                                .tracking(0.5)
                                .lineLimit(1)
                                .foregroundStyle(resolved.textColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(resolved.color)
                                )
                        } else if posterKind.isNonTMDB {
                            SourceTypeBadge(kind: posterKind)
                        }
                    }
                }
                if let expiry = expiryText {
                    Text(expiry)
                        .scaledFont(size: 10, weight: .heavy)
                        .tracking(0.3)
                        .lineLimit(1)
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.orange.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                        )
                }
                Text(item.title ?? "Untitled")
                    .scaledFont(size: 16, weight: .semibold)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                if let added = item.addedAt {
                    Text("Added \(WatchListRow.formatter.localizedString(for: added, relativeTo: Date()))")
                        .scaledFont(size: 11)
                        .foregroundStyle(Color.textTertiary)
                }
                if isLive, let liveTitle = streamTitle {
                    Text(liveTitle)
                        .scaledFont(size: 11)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let onToggleDepartureReminder {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onToggleDepartureReminder()
                } label: {
                    Image(systemName: isDepartureReminded ? "bell.fill" : "bell")
                        .scaledFont(size: 17, weight: .semibold)
                        .foregroundStyle(isDepartureReminded ? Color.orange : Color.white.opacity(0.55))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Image(systemName: "chevron.right")
                .scaledFont(size: 13, weight: .semibold)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    private func sourceKindColor(_ kind: SourceKind) -> Color {
        switch kind {
        case .youtube: return Color(red: 0xFF/255, green: 0x00/255, blue: 0x00/255)
        case .podcast: return Color(red: 0x7C/255, green: 0x3A/255, blue: 0xED/255)
        case .twitch: return Color(red: 0x91/255, green: 0x46/255, blue: 0xFF/255)
        case .kick: return Color(red: 0x53/255, green: 0xFC/255, blue: 0x18/255)
        case .tmdb: return Color.orange
        }
    }

    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()


}

// MARK: - Filter chip

/// Small capsule toggle used by the watch-list filter bar. New sheet surface
/// uses the literal depth tokens (#1B2739 fill, #2E3E58 raised) rather than
/// theme aliases.
private struct WatchListFilterChip: View {
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .scaledFont(size: 12, weight: .semibold)
                .foregroundStyle(isOn ? .white : Color.white.opacity(0.55))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(
                        Color(
                            red: isOn ? 0x2E / 255 : 0x1B / 255,
                            green: isOn ? 0x3E / 255 : 0x27 / 255,
                            blue: isOn ? 0x58 / 255 : 0x39 / 255
                        )
                    )
                )
                .overlay(
                    Capsule().stroke(
                        isOn ? Color.orange.opacity(0.85) : Color.white.opacity(0.10),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    Color.navy.sheet(isPresented: .constant(true)) {
        WatchListBottomSheet()
    }
}

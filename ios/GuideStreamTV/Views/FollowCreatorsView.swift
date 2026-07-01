//
//  FollowCreatorsView.swift
//  GuideStreamTV
//
//  Discovery surface for YouTube channels, podcasts, Twitch, and Kick.
//  Launched from the watch list entry card and from the Home search.
//

import SwiftUI

// MARK: - View

struct FollowCreatorsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var creators: [DiscoverableCreator] = []
    @State private var isLoading: Bool = true
    @State private var searchText: String = ""
    @State private var selectedFilter: CreatorFilter = .all
    @State private var followedIds: Set<String> = []
    @State private var streams = StreamsViewModel.shared
    @State private var creatorDetailTarget: CreatorDetailTarget?

    enum CreatorFilter: String, CaseIterable {
        case all, live, youtube, podcasts, streamers

        var label: String {
            switch self {
            case .all: return "All"
            case .live: return "Live"
            case .youtube: return "YouTube"
            case .podcasts: return "Podcasts"
            case .streamers: return "Streamers"
            }
        }

        var sourceType: String? {
            switch self {
            case .all, .live: return nil
            case .youtube: return "youtube"
            case .podcasts: return "podcast"
            case .streamers: return nil // twitch + kick handled in filter
            }
        }
    }

    /// Maps the selected filter to the live-search worker `type` param.
    /// Podcasts are not searchable via the live worker, so they fall back to local-only.
    private var liveSearchType: String {
        switch selectedFilter {
        case .all, .live: return "all"
        case .youtube: return "youtube"
        case .streamers: return "twitch"
        case .podcasts: return "all"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BrandBackground()

                VStack(spacing: 0) {
                    // Search field
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .scaledFont(size: 14, weight: .medium)
                            .foregroundStyle(Color.textTertiary)
                        TextField("Search creators & podcasts...", text: $searchText)
                            .scaledFont(size: 15)
                            .foregroundStyle(.white)
                            .tint(Color.orange)
                            .autocorrectionDisabled()
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Color.white.opacity(0.4))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Filter chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(CreatorFilter.allCases, id: \.rawValue) { filter in
                                Button {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        selectedFilter = filter
                                    }
                                } label: {
                                    Text(filter.label)
                                        .scaledFont(size: 12, weight: .semibold)
                                        .foregroundStyle(selectedFilter == filter ? .white : Color.textSecondary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule()
                                                .fill(selectedFilter == filter ? Color.orange : Color.white.opacity(0.08))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }

                    // Content
                    if isLoading {
                        Spacer()
                        ProgressView().tint(Color.orange)
                        Spacer()
                    } else if filteredCreators.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "person.2.slash")
                                .scaledFont(size: 36, weight: .regular)
                                .foregroundStyle(Color.textTertiary)
                            Text("No creators found")
                                .scaledFont(size: 16, weight: .semibold)
                                .foregroundStyle(Color.textSecondary)
                            Text("Try a different search or filter.")
                                .scaledFont(size: 13)
                                .foregroundStyle(Color.textTertiary)
                        }
                        Spacer()
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 2) {
                                ForEach(filteredCreators) { creator in
                                    CreatorRow(creator: creator, isFollowed: followedIds.contains(creator.titleId), onToggle: {
                                        toggleFollow(creator)
                                    }, onTap: {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        WatchIntentLogger.shared.log(
                                            eventType: .cardTapped,
                                            titleId: creator.titleId,
                                            platformId: creator.sourceType,
                                            metadata: ["section": "follow_creators", "kind": creator.sourceType]
                                        )
                                        creatorDetailTarget = CreatorDetailTarget(titleId: creator.titleId, initialEpisode: nil)
                                    })
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    Divider()
                                        .overlay(Color.white.opacity(0.06))
                                        .padding(.leading, 16)
                                }
                            }
                            .padding(.bottom, 40)
                        }
                    }
                }
            }
            .navigationTitle("Follow Creators")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .sheet(item: $creatorDetailTarget) { target in
            CreatorDetailView(
                titleId: target.titleId,
                initialEpisode: target.initialEpisode,
                onBack: { creatorDetailTarget = nil }
            )
        }
        .task { await loadCreators() }
        .onChange(of: searchText) { _, _ in
            Task { await loadCreators() }
        }
        .onChange(of: selectedFilter) { _, _ in
            Task { await loadCreators() }
        }
    }

    // MARK: - Filtered list

    private var filteredCreators: [DiscoverableCreator] {
        var result = creators
        // Apply text search locally (server already filters, but refine)
        if !searchText.isEmpty {
            let term = searchText.lowercased()
            result = result.filter { $0.displayName.lowercased().contains(term) }
        }
        // Apply client-side filter for streamers (twitch + kick)
        if selectedFilter == .streamers {
            result = result.filter { $0.kind.isLivestream }
        } else if selectedFilter == .live {
            result = result.filter { $0.isLive }
        } else if let st = selectedFilter.sourceType {
            result = result.filter { $0.sourceType == st }
        }
        // Live sort is handled server-side; preserve order
        return result
    }

    // MARK: - Data loading

    private func loadCreators() async {
        isLoading = true
        defer { isLoading = false }

        // Sync followed state
        followedIds = Set(streams.userStreams.filter {
            SourceKind.from(titleId: $0.titleId).isNonTMDB
        }.map { $0.titleId })

        do {
            let st = selectedFilter.sourceType
            if !searchText.isEmpty {
                let query = searchText
                // Local cached results + live worker results (YouTube/Twitch), merged & de-duped.
                async let localSources = ContentSourcesService.shared.searchSources(query: query, sourceType: st)
                async let remoteSources = ContentSourcesService.shared.searchCreatorsLive(query: query, type: liveSearchType)
                var byId: [String: ContentSource] = [:]
                for source in try await localSources { byId[source.titleId] = source }
                for source in await remoteSources where byId[source.titleId] == nil { byId[source.titleId] = source }
                let sources = Array(byId.values)
                let liveIds = sources.filter { SourceKind.from(titleId: $0.titleId).isLivestream }.map { $0.titleId }
                let liveMap = liveIds.isEmpty ? [:] : Dictionary(
                    uniqueKeysWithValues: (try? await ContentSourcesService.shared.fetchLiveStatus(for: liveIds))?.map { ($0.titleId, $0) } ?? []
                )
                creators = sources.map { source in
                    let status = liveMap[source.titleId]
                    return DiscoverableCreator(
                        titleId: source.titleId, sourceType: source.sourceType,
                        displayName: source.displayName, handle: source.handle,
                        imageUrl: source.imageUrl, category: source.category,
                        description: source.description,
                        isLive: status?.isLive ?? false, streamTitle: status?.streamTitle,
                        liveCategory: status?.category, viewerCount: status?.viewerCount,
                        startedAt: status?.startedAt
                    )
                }
                // Sort: live first
                creators.sort { a, b in
                    if a.isLive != b.isLive { return a.isLive }
                    return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
                }
            } else {
                creators = try await ContentSourcesService.shared.fetchDiscoverable(sourceType: st)
            }
        } catch {
            creators = []
        }
    }

    // MARK: - Follow toggle

    private func toggleFollow(_ creator: DiscoverableCreator) {
        let isFollowed = followedIds.contains(creator.titleId)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if isFollowed {
            followedIds.remove(creator.titleId)
            Task {
                await streams.removeFromMyStreams(titleId: creator.titleId)
                WatchIntentLogger.shared.log(
                    eventType: .streamRemoved,
                    titleId: creator.titleId,
                    platformId: creator.sourceType,
                    metadata: ["source": "follow_creators"]
                )
            }
        } else {
            followedIds.insert(creator.titleId)
            Task {
                await streams.addToMyStreams(
                    titleId: creator.titleId,
                    title: creator.displayName,
                    posterUrl: creator.imageUrl,
                    platform: creator.sourceType
                )
                WatchIntentLogger.shared.log(
                    eventType: .streamAdded,
                    titleId: creator.titleId,
                    platformId: creator.sourceType,
                    metadata: ["source": "follow_creators"]
                )
            }
        }
    }
}

// MARK: - Creator Row

private struct CreatorRow: View {
    let creator: DiscoverableCreator
    let isFollowed: Bool
    let onToggle: () -> Void
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(sourceColor.opacity(0.15))
                        .frame(width: 48, height: 48)
                    if let url = CreatorImageOverrides.resolve(titleId: creator.titleId, stored: creator.avatarUrl) {
                        RemoteImage(urlString: url, contentMode: .fill, fallbackColors: [sourceColor, sourceColor.opacity(0.5)])
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                            .allowsHitTesting(false)
                    } else {
                        Image(systemName: creator.kind == .podcast ? "mic.fill" : "play.rectangle.fill")
                            .scaledFont(size: 20, weight: .semibold)
                            .foregroundStyle(sourceColor)
                    }
                }

                // Info
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(creator.displayName)
                            .scaledFont(size: 15, weight: .semibold)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)

                        if creator.isLive {
                            LivePill()
                        }
                    }

                    HStack(spacing: 6) {
                        SourceTypeBadge(kind: creator.kind)
                        if let handle = creator.handle {
                            let cleanHandle = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
                            Text("@\(cleanHandle)")
                                .scaledFont(size: 12)
                                .foregroundStyle(Color.textTertiary)
                                .lineLimit(1)
                        }
                    }

                    if creator.isLive, let title = creator.streamTitle {
                        Text(title)
                            .scaledFont(size: 12)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                            .padding(.top, 2)
                    }

                    if creator.isLive, let category = creator.liveCategory {
                        HStack(spacing: 4) {
                            Image(systemName: "rectangle.3.group.fill")
                                .scaledFont(size: 9)
                            Text(category)
                                .scaledFont(size: 11)
                            if let viewers = creator.viewerCount {
                                Text("·")
                                Text(formatViewers(viewers))
                            }
                        }
                        .foregroundStyle(Color.textTertiary)
                        .padding(.top, 1)
                    }
                }

                Spacer(minLength: 8)

                // Follow button
                Button(action: onToggle) {
                    Text(isFollowed ? "Following" : "Follow")
                        .scaledFont(size: 12, weight: .bold)
                        .foregroundStyle(isFollowed ? Color.textSecondary : .white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(isFollowed ? Color.white.opacity(0.10) : Color.orange)
                        )
                        .overlay(
                            Capsule()
                                .stroke(isFollowed ? Color.white.opacity(0.20) : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sourceColor: Color {
        switch creator.kind {
        case .youtube: return Color(red: 0xFF/255, green: 0x00/255, blue: 0x00/255)
        case .podcast: return Color(red: 0x7C/255, green: 0x3A/255, blue: 0xED/255)
        case .twitch: return Color(red: 0x91/255, green: 0x46/255, blue: 0xFF/255)
        case .kick: return Color(red: 0x53/255, green: 0xFC/255, blue: 0x18/255)
        case .tmdb: return Color.orange
        }
    }

    private func formatViewers(_ count: Int) -> String {
        if count >= 1000 { return String(format: "%.1fK", Double(count) / 1000) }
        return "\(count)"
    }
}

// MARK: - Reusable badges

/// A small colored badge showing the source type (YouTube, Podcast, Twitch, Kick).
struct SourceTypeBadge: View {
    let kind: SourceKind

    var body: some View {
        Text(kind.displayLabel.uppercased())
            .scaledFont(size: 9, weight: .heavy)
            .tracking(0.5)
            .foregroundStyle(kind == .kick ? Color(white: 0.1) : .white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(badgeColor))
    }

    private var badgeColor: Color {
        switch kind {
        case .youtube: return Color(red: 0xFF/255, green: 0x00/255, blue: 0x00/255)
        case .podcast: return Color(red: 0x7C/255, green: 0x3A/255, blue: 0xED/255)
        case .twitch: return Color(red: 0x91/255, green: 0x46/255, blue: 0xFF/255)
        case .kick: return Color(red: 0x53/255, green: 0xFC/255, blue: 0x18/255)
        case .tmdb: return Color.orange
        }
    }
}

/// A pulsing red LIVE pill used on rows and cards.
struct LivePill: View {
    @State private var pulse: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color.red)
                .frame(width: 5, height: 5)
                .scaleEffect(pulse ? 1.3 : 0.8)
                .opacity(pulse ? 1.0 : 0.5)
            Text("LIVE")
                .scaledFont(size: 9, weight: .heavy)
                .tracking(0.5)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.red))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

/// Dimmed OFFLINE pill shown on streamer rows when the channel is not currently live.
struct OfflinePill: View {
    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color.white.opacity(0.35))
                .frame(width: 5, height: 5)
            Text("OFFLINE")
                .scaledFont(size: 9, weight: .heavy)
                .tracking(0.5)
        }
        .foregroundStyle(Color.white.opacity(0.5))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.white.opacity(0.10)))
    }
}

/// Compact corner LIVE badge for poster overlays.
struct LiveCornerBadge: View {
    @State private var pulse: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color.white)
                .frame(width: 4, height: 4)
                .scaleEffect(pulse ? 1.4 : 0.7)
            Text("LIVE")
                .scaledFont(size: 8, weight: .heavy)
                .tracking(0.5)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.red))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

#Preview {
    FollowCreatorsView()
        .preferredColorScheme(.dark)
}

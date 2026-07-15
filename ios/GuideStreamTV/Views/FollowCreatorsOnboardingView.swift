//
//  FollowCreatorsOnboardingView.swift
//  GuideStreamTV
//
//  Onboarding step — seed creators & podcasts. Placed after the TMDB
//  show-picker so the user can bulk-follow YouTube channels, Twitch/Kick
//  streamers, and podcasts before landing on the home feed.
//

import SwiftUI
import UIKit

/// Two-lane seed screen: Creators (YouTube / Twitch / Kick) and Podcasts
/// (audio + video). Selections are batched into `UserStreamInsert` values
/// and returned via `onContinue` so the coordinator can commit them through
/// the same upsert path used by the show-picker step.
struct FollowCreatorsOnboardingView: View {
    let onContinue: ([UserStreamInsert]) -> Void
    let onSkip: () -> Void

    // MARK: - Lanes

    private enum Lane: String, CaseIterable {
        case creators
        case podcasts

        var label: String {
            switch self {
            case .creators: return "Creators"
            case .podcasts: return "Podcasts"
            }
        }

        var title: String {
            switch self {
            case .creators: return "Now add your creators"
            case .podcasts: return "…and your podcasts"
            }
        }

        var subtitle: String {
            switch self {
            case .creators:
                return "Follow the channels you already watch — new uploads land on your home feed, right next to your shows."
            case .podcasts:
                return "Video or audio, we track new episodes the moment they drop."
            }
        }
    }

    // MARK: - Sub-filters

    private enum CreatorSubFilter: String, CaseIterable {
        case all, youtube, streamers

        var label: String {
            switch self {
            case .all: return "All"
            case .youtube: return "YouTube"
            case .streamers: return "Streamers"
            }
        }

        func matches(_ creator: DiscoverableCreator) -> Bool {
            switch self {
            case .all: return true
            case .youtube: return creator.kind == .youtube
            case .streamers: return creator.kind.isLivestream
            }
        }
    }

    private enum PodcastSubFilter: String, CaseIterable {
        case all, video, audio

        var label: String {
            switch self {
            case .all: return "All"
            case .video: return "Video"
            case .audio: return "Audio"
            }
        }

        func matches(_ creator: DiscoverableCreator) -> Bool {
            switch self {
            case .all: return true
            case .video: return creator.sourceType == "youtube"
            case .audio: return creator.sourceType == "podcast"
            }
        }
    }

    // MARK: - State

    @State private var lane: Lane = .creators
    @State private var creatorSubFilter: CreatorSubFilter = .all
    @State private var podcastSubFilter: PodcastSubFilter = .all
    @State private var creators: [DiscoverableCreator] = []
    @State private var podcasts: [DiscoverableCreator] = []
    @State private var loadingCreators = true
    @State private var loadingPodcasts = true
    @State private var selectedIds: Set<String> = []

    // MARK: - Computed

    private var totalSelected: Int { selectedIds.count }

    private var displayedCreators: [DiscoverableCreator] {
        switch creatorSubFilter {
        case .all: return creators
        case .youtube: return creators.filter { $0.kind == .youtube }
        case .streamers: return creators.filter { $0.kind.isLivestream }
        }
    }

    private var displayedPodcasts: [DiscoverableCreator] {
        switch podcastSubFilter {
        case .all: return podcasts
        case .video: return podcasts.filter { $0.sourceType == "youtube" }
        case .audio: return podcasts.filter { $0.sourceType == "podcast" }
        }
    }

    private var visibleCreatorSubFilters: [CreatorSubFilter] {
        CreatorSubFilter.allCases.filter { f in creators.contains(where: f.matches) }
    }

    private var visiblePodcastSubFilters: [PodcastSubFilter] {
        PodcastSubFilter.allCases.filter { f in podcasts.contains(where: f.matches) }
    }

    private var visibleLanes: [Lane] {
        Lane.allCases.filter { l in
            switch l {
            case .creators: return loadingCreators || !creators.isEmpty
            case .podcasts: return loadingPodcasts || !podcasts.isEmpty
            }
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            BrandBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    OnboardingHeader(progress: 1.0)

                    // Title section — changes with lane
                    VStack(alignment: .leading, spacing: 6) {
                        Text(lane.title)
                            .font(.custom("SF Pro Display", size: 24).weight(.bold))
                            .foregroundStyle(.white)
                        Text(lane.subtitle)
                            .font(.custom("SF Pro Text", size: 13))
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                    // Segmented control (only when both lanes have content)
                    if visibleLanes.count >= 2 {
                        segmentedControl
                            .padding(.horizontal, 20)
                            .padding(.bottom, 14)
                    }

                    // Sub-filter chips
                    subFilterChips
                        .padding(.bottom, 12)

                    // Grid
                    if isLoadingCurrentLane {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 12),
                                      GridItem(.flexible(), spacing: 12),
                                      GridItem(.flexible(), spacing: 12)],
                            spacing: 12
                        ) {
                            ForEach(0..<6, id: \.self) { _ in
                                skeletonGridCard
                            }
                        }
                        .padding(.horizontal, 16)
                    } else if currentList.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: lane == .creators ? "person.2.slash" : "waveform.slash")
                                .scaledFont(size: 36, weight: .regular)
                                .foregroundStyle(Color.textTertiary)
                            Text("Nothing here yet — check back soon.")
                                .scaledFont(size: 16, weight: .semibold)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .padding(.top, 40)
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 12),
                                      GridItem(.flexible(), spacing: 12),
                                      GridItem(.flexible(), spacing: 12)],
                            spacing: 12
                        ) {
                            ForEach(currentList) { item in
                                OnboardingCreatorCard(
                                    creator: item,
                                    isSelected: selectedIds.contains(item.titleId),
                                    onToggle: { toggleSelection(item) }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // Bottom spacer
                    Color.clear.frame(height: 120)
                }
            }

            // Sticky bottom bar
            bottomBar
        }
        .task {
            await loadCreators()
            await loadPodcasts()

            // Redirect to non-empty lane if current lane loaded empty
            if creators.isEmpty, !podcasts.isEmpty {
                lane = .podcasts
            } else if podcasts.isEmpty, !creators.isEmpty {
                lane = .creators
            }

            // Reset sub-filters that match nothing
            if creatorSubFilter != .all, !creators.contains(where: creatorSubFilter.matches) {
                creatorSubFilter = .all
            }
            if podcastSubFilter != .all, !podcasts.contains(where: podcastSubFilter.matches) {
                podcastSubFilter = .all
            }
        }
    }

    // MARK: - Segmented control

    private var segmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(visibleLanes, id: \.rawValue) { l in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        lane = l
                    }
                } label: {
                    Text(l.label)
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(lane == l ? .white : Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    lane == l
                                        ? AnyShapeStyle(LinearGradient(
                                            colors: [Color.orange, Color.orange.opacity(0.8)],
                                            startPoint: .top, endPoint: .bottom))
                                        : AnyShapeStyle(Color.clear)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
    }

    // MARK: - Sub-filter chips

    @ViewBuilder
    private var subFilterChips: some View {
        let showChips: Bool = {
            switch lane {
            case .creators: return visibleCreatorSubFilters.count >= 2
            case .podcasts: return visiblePodcastSubFilters.count >= 2
            }
        }()
        if showChips {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    switch lane {
                    case .creators:
                        ForEach(visibleCreatorSubFilters, id: \.rawValue) { filter in
                            chipButton(
                                label: filter.label,
                                isSelected: creatorSubFilter == filter,
                                action: {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        creatorSubFilter = filter
                                    }
                                }
                            )
                        }
                    case .podcasts:
                        ForEach(visiblePodcastSubFilters, id: \.rawValue) { filter in
                            chipButton(
                                label: filter.label,
                                isSelected: podcastSubFilter == filter,
                                action: {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        podcastSubFilter = filter
                                    }
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func chipButton(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .scaledFont(size: 12, weight: .semibold)
                .foregroundStyle(isSelected ? .white : Color.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.orange : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Text("\(totalSelected) selected")
                .font(.custom("SF Pro Text", size: 12))
                .foregroundStyle(Color.orange)

            Button {
                let gen = UIImpactFeedbackGenerator(style: .medium)
                gen.impactOccurred()
                onContinue(buildInserts())
            } label: {
                HStack(spacing: 8) {
                    Text("Add to My List")
                        .font(.custom("SF Pro Text", size: 16).weight(.bold))
                    Image(systemName: "arrow.right")
                        .scaledFont(size: 14, weight: .bold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    LinearGradient(
                        colors: [Color.orange, Color.orange.opacity(0.85)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .opacity(selectedIds.isEmpty ? 0.4 : 1.0)
                )
                .clipShape(Capsule())
                .shadow(color: Color.orange.opacity(selectedIds.isEmpty ? 0.0 : 0.45),
                        radius: 24, x: 0, y: 0)
            }
            .buttonStyle(.plain)


            Button(action: onSkip) {
                Text("Skip for now")
                    .font(.custom("SF Pro Text", size: 14).weight(.medium))
                    .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.navy.opacity(0), Color.navy],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 28)
                Color.navy
            }
        )
    }

    // MARK: - Helpers

    private var isLoadingCurrentLane: Bool {
        lane == .creators ? loadingCreators : loadingPodcasts
    }

    private var currentList: [DiscoverableCreator] {
        lane == .creators ? displayedCreators : displayedPodcasts
    }

    private func toggleSelection(_ creator: DiscoverableCreator) {
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
        if selectedIds.contains(creator.titleId) {
            selectedIds.remove(creator.titleId)
        } else {
            selectedIds.insert(creator.titleId)
        }
    }

    private func buildInserts() -> [UserStreamInsert] {
        let userId = AuthViewModel.shared.currentUserId
        let allItems = creators + podcasts
        return selectedIds.compactMap { titleId -> UserStreamInsert? in
            let item = allItems.first { $0.titleId == titleId }
            return UserStreamInsert(
                user_id: userId,
                title_id: titleId,
                title: item?.displayName,
                poster_url: item?.imageUrl,
                platform: item?.sourceType,
                // Creators/podcasts are not TMDB titles — no tv/movie type.
                is_tv: nil
            )
        }
    }

    // MARK: - Data loading

    private func loadCreators() async {
        loadingCreators = true
        defer { loadingCreators = false }
        do {
            creators = try await ContentSourcesService.shared.fetchDiscoverableCreators()
        } catch {
            creators = []
        }
    }

    private func loadPodcasts() async {
        loadingPodcasts = true
        defer { loadingPodcasts = false }
        do {
            podcasts = try await ContentSourcesService.shared.fetchDiscoverablePodcasts()
        } catch {
            podcasts = []
        }
    }

    // MARK: - Skeleton

    private var skeletonGridCard: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Onboarding Creator Card

/// Three-column avatar card with selection ring and checkmark.
/// Mirrors the show-seed grid treatment so this step feels consistent.
private struct OnboardingCreatorCard: View {
    let creator: DiscoverableCreator
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isSelected ? Color.orange : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
                    )
                    .shadow(color: isSelected ? Color.orange.opacity(0.35) : .clear, radius: isSelected ? 16 : 0)

                VStack(spacing: 8) {
                    // Avatar
                    ZStack {
                        Circle()
                            .fill(sourceColor.opacity(0.15))
                            .frame(width: 56, height: 56)
                        if let url = CreatorImageOverrides.resolve(titleId: creator.titleId, stored: creator.avatarUrl) {
                            RemoteImage(urlString: url, contentMode: .fill, fallbackColors: [sourceColor, sourceColor.opacity(0.5)])
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                                .allowsHitTesting(false)
                        } else {
                            Image(systemName: creator.kind == .podcast ? "mic.fill" : "play.rectangle.fill")
                                .scaledFont(size: 22, weight: .semibold)
                                .foregroundStyle(sourceColor)
                        }
                    }

                    // Name
                    Text(creator.displayName)
                        .scaledFont(size: 12, weight: .semibold)
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .padding(.horizontal, 6)
                }

                // Top-leading badges
                VStack(alignment: .leading, spacing: 3) {
                    SourceTypeBadge(kind: creator.kind)
                    if creator.kind == .youtube, creator.format == "podcast" {
                        PodcastBadge()
                    }
                    if creator.isLive {
                        LivePill()
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // Top-right selection check
                if isSelected {
                    VStack {
                        HStack {
                            Spacer()
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Image(systemName: "checkmark")
                                        .scaledFont(size: 12, weight: .bold)
                                        .foregroundStyle(.white)
                                )
                        }
                        Spacer()
                    }
                    .padding(8)
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
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
}

// MARK: - Podcast Badge

/// Purple PODCAST pill shown next to the YouTube badge for video podcasts.
private struct PodcastBadge: View {
    var body: some View {
        Text("PODCAST")
            .scaledFont(size: 9, weight: .heavy)
            .tracking(0.5)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color(red: 0x7C/255, green: 0x3A/255, blue: 0xED/255)))
    }
}

#Preview {
    FollowCreatorsOnboardingView(
        onContinue: { _ in },
        onSkip: {}
    )
    .preferredColorScheme(.dark)
}

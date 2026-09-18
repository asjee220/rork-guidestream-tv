//
//  WatchListSeedGrid.swift
//  GuideStreamTV
//
//  The empty watchlist's first-run surface. Replaces the onboarding
//  "Watching now" and "Follow creators" steps: a tappable grid of seeds for
//  whichever category tab is selected, saved one tap at a time straight into
//  `user_streams`. Never a gate — dismissible, and gone for good once the
//  user says so.
//

import SwiftUI
import UIKit
import UserNotifications

/// Which seed pool the grid draws from. Mirrors the watchlist's category tabs.
enum WatchListSeedCategory: String {
    case shows, movies, creators
}

/// Per-device flags for the seed surface. Both are conveniences, never
/// server state: a reinstall simply shows the grid again.
enum WatchListSeedPrefs {
    static let dismissedKey = "gs.watchlistSeedDismissed"
    static let pushAskedKey = "gs.pushAskedOnFirstSave"

    static var isDismissed: Bool {
        get { UserDefaults.standard.bool(forKey: dismissedKey) }
        set { UserDefaults.standard.set(newValue, forKey: dismissedKey) }
    }
}

struct WatchListSeedGrid: View {
    let category: WatchListSeedCategory
    /// Fired from the "Done" button once the nudge threshold is met.
    let onDone: () -> Void
    /// Fired from the ✕. The caller decides what replaces the grid.
    let onDismiss: () -> Void

    /// Saves before Home counts as personalized (Recommended for You, Top
    /// Picks genre, New Episodes all key off `user_streams`). Counted across
    /// every category, not per tab. Nothing on Home is gated on it — Today's
    /// Pick is a daily rotation that shows regardless — so the copy promises
    /// personalization, never an unlock.
    static let nudgeThreshold = 3
    static let columns = 3
    static let seedCount = 12

    @State private var streams = StreamsViewModel.shared
    @State private var seeds: [SeedItem] = []
    @State private var railIndex: Int = 0
    @State private var isLoading = true

    private var savedCount: Int { streams.userStreams.count }
    private var savedIds: Set<String> { Set(streams.userStreams.map(\.titleId)) }
    private var remaining: Int { max(Self.nudgeThreshold - savedCount, 0) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                nudge
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                rail
                    .padding(.top, 14)
                grid
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                if remaining == 0 {
                    doneButton
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                }
                Color.clear.frame(height: 110)
            }
        }
        .task(id: "\(category.rawValue)-\(railIndex)") {
            await load()
        }
        .onChange(of: category) { _, _ in railIndex = 0 }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Start your watchlist")
                    .scaledFont(size: 17, weight: .bold)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .scaledFont(size: 13)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                WatchListSeedPrefs.isDismissed = true
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .scaledFont(size: 12, weight: .bold)
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss suggestions")
        }
    }

    private var subtitle: LocalizedStringKey {
        switch category {
        case .shows: return "Save a few shows you'd actually watch. Everything else gets smarter from here."
        case .movies: return "Pick movies you've been meaning to see. We'll tell you when they land on a service you have."
        case .creators: return "Follow creators and podcasts so new drops show up next to your shows."
        }
    }

    // MARK: - Nudge

    private var nudge: some View {
        HStack(spacing: 10) {
            Group {
                if remaining == 0 {
                    Text("Your Home is personalized")
                } else if remaining == 1 {
                    Text("1 more to personalize your Home")
                } else {
                    Text("\(remaining) more to personalize your Home")
                }
            }
            .scaledFont(size: 12, weight: .semibold)
            .foregroundStyle(remaining == 0 ? Color.green : Color.textSecondary)
            .lineLimit(1)
            .fixedSize()

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(remaining == 0 ? Color.green : Color.orange)
                        .frame(width: geo.size.width * min(Double(savedCount) / Double(Self.nudgeThreshold), 1))
                        .animation(.easeOut(duration: 0.25), value: savedCount)
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Rail

    private var railLabels: [LocalizedStringKey] {
        switch category {
        case .shows: return ["Trending", "New this week", "Popular"]
        case .movies: return ["Trending", "In theaters", "Coming soon"]
        case .creators: return ["Top creators", "Podcasts", "Streamers"]
        }
    }

    private var rail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(railLabels.enumerated()), id: \.offset) { index, label in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        railIndex = index
                    } label: {
                        Text(label)
                            .scaledFont(size: 11, weight: .bold)
                            .foregroundStyle(railIndex == index ? .white : Color.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(railIndex == index ? Color.orange : Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Grid

    private var grid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: Self.columns),
            spacing: 10
        ) {
            if isLoading && seeds.isEmpty {
                ForEach(0..<Self.seedCount, id: \.self) { _ in
                    SeedSkeleton(round: category == .creators)
                }
            } else {
                ForEach(seeds) { seed in
                    SeedTile(
                        seed: seed,
                        isSaved: savedIds.contains(seed.titleId),
                        round: category == .creators,
                        onTap: { toggle(seed) }
                    )
                }
            }
        }
    }

    private var doneButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onDone()
        } label: {
            Text("Done — take me Home")
                .scaledFont(size: 15, weight: .bold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    LinearGradient(colors: [Color.orange, Color.orange.opacity(0.85)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        var items: [SeedItem] = []
        switch category {
        case .shows:
            let results: [TMDBResult]
            switch railIndex {
            case 1: results = (try? await TMDBService.shared.getOnTheAir()) ?? []
            case 2: results = (try? await TMDBService.shared.getPopularTV()) ?? []
            default: results = (try? await TMDBService.shared.getTrending(mediaType: "tv", timeWindow: "week")) ?? []
            }
            items = results.map { SeedItem(tmdb: $0, isTV: true) }
        case .movies:
            let results: [TMDBResult]
            switch railIndex {
            case 1: results = (try? await TMDBService.shared.getNowPlayingMovies()) ?? []
            case 2: results = (try? await TMDBService.shared.getUpcomingMovies()) ?? []
            default: results = (try? await TMDBService.shared.getTrending(mediaType: "movie", timeWindow: "week")) ?? []
            }
            items = results.map { SeedItem(tmdb: $0, isTV: false) }
        case .creators:
            let creators = (try? await ContentSourcesService.shared.fetchDiscoverableCreators()) ?? []
            let filtered: [DiscoverableCreator]
            switch railIndex {
            case 1: filtered = creators.filter { $0.kind == .podcast }
            case 2: filtered = creators.filter { $0.kind.isLivestream }
            default: filtered = creators
            }
            items = filtered.map { SeedItem(creator: $0) }
        }
        let trimmed = Array(items.filter { $0.posterUrl != nil }.prefix(Self.seedCount))
        await MainActor.run {
            seeds = trimmed
            isLoading = false
        }
    }

    private func toggle(_ seed: SeedItem) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let wasSaved = savedIds.contains(seed.titleId)
        Task {
            if wasSaved {
                await streams.removeFromMyStreams(titleId: seed.titleId)
                WatchIntentLogger.shared.log(
                    eventType: .streamRemoved,
                    titleId: seed.titleId,
                    platformId: seed.platform,
                    metadata: ["source": "watchlist_seed"]
                )
            } else {
                await streams.addToMyStreams(
                    titleId: seed.titleId,
                    title: seed.title,
                    posterUrl: seed.posterUrl,
                    platform: seed.platform,
                    isTV: seed.isTV
                )
                WatchIntentLogger.shared.log(
                    eventType: .streamAdded,
                    titleId: seed.titleId,
                    platformId: seed.platform,
                    metadata: ["source": "watchlist_seed", "category": category.rawValue]
                )
                maybeRequestPush()
            }
        }
    }

    /// The first save is the one moment a notification has an obvious
    /// payoff, so the system prompt fires here — once per install, and only
    /// while the status is still undetermined.
    private func maybeRequestPush() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: WatchListSeedPrefs.pushAskedKey) else { return }
        defaults.set(true, forKey: WatchListSeedPrefs.pushAskedKey)
        Task { @MainActor in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            AuthViewModel.shared.setNotificationPreferences(push: granted, sms: false)
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }
}

// MARK: - Model

private struct SeedItem: Identifiable, Hashable {
    let titleId: String
    let title: String
    let posterUrl: String?
    let platform: String?
    let isTV: Bool?

    var id: String { titleId }

    init(tmdb: TMDBResult, isTV: Bool) {
        titleId = String(tmdb.id)
        title = tmdb.displayName
        posterUrl = tmdb.posterUrl
        platform = nil
        self.isTV = isTV
    }

    init(creator: DiscoverableCreator) {
        titleId = creator.titleId
        title = creator.displayName
        posterUrl = CreatorImageOverrides.resolve(titleId: creator.titleId, stored: creator.imageUrl)
        platform = creator.sourceType
        isTV = nil
    }
}

// MARK: - Tile

private struct SeedTile: View {
    let seed: SeedItem
    let isSaved: Bool
    let round: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                artwork
                if round {
                    Text(seed.title)
                        .scaledFont(size: 11, weight: .semibold)
                        .foregroundStyle(isSaved ? Color.textPrimary : Color.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSaved ? "Remove \(seed.title)" : "Save \(seed.title)")
        .accessibilityAddTraits(isSaved ? [.isSelected, .isButton] : .isButton)
    }

    @ViewBuilder
    private var artwork: some View {
        if round {
            RemoteImage(urlString: seed.posterUrl, contentMode: .fill, fallbackColors: HomeFallback.posterColors)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(Circle())
                .overlay(Circle().stroke(isSaved ? Color.orange : Color.clear, lineWidth: 3))
                .overlay(alignment: .topTrailing) { bookmark.padding(2) }
        } else {
            RemoteImage(urlString: seed.posterUrl, contentMode: .fill, fallbackColors: HomeFallback.posterColors)
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, Color.black.opacity(0.75)],
                                   startPoint: .center, endPoint: .bottom)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .bottomLeading) {
                    Text(seed.title)
                        .scaledFont(size: 12, weight: .bold)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSaved ? Color.orange : Color.clear, lineWidth: 3)
                )
                .overlay(alignment: .topTrailing) { bookmark.padding(6) }
        }
    }

    private var bookmark: some View {
        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
            .scaledFont(size: 11, weight: .bold)
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(Circle().fill(isSaved ? Color.orange : Color.black.opacity(0.45)))
    }
}

private struct SeedSkeleton: View {
    let round: Bool
    @State private var opacity: Double = 0.08

    var body: some View {
        Group {
            if round {
                Circle().fill(Color.white.opacity(opacity)).aspectRatio(1, contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(opacity))
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                opacity = 0.18
            }
        }
    }
}

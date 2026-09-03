//
//  TVWatchListView.swift
//  GuideStreamTVTV
//
//  Focus grid of saved titles. Tapping any tile opens the same detail
//  sheet used on Home so the user can remove the title with one click.
//  Empty state nudges the user to head to Home and start saving.
//

import SwiftUI

/// The watch list's three categories, kept byte-compatible with the phone's
/// WatchListTab in Views/WatchListBottomSheet.swift — same cases, same order,
/// same filing rule — so a list looks the same on both. Duplicated rather
/// than shared, per the convention the rest of the tvOS target follows.
private enum TVWatchListTab: String, CaseIterable, Identifiable {
    case shows, movies, creators

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shows: return "Shows"
        case .movies: return "Movies"
        case .creators: return "Creators"
        }
    }

    var glyph: String {
        switch self {
        case .shows: return "tv"
        case .movies: return "film"
        case .creators: return "person.2.fill"
        }
    }

    /// Which tab a saved row belongs to. Every prefixed (non-TMDB) id is a
    /// creator; TMDB rows split on `is_tv`, falling back to the id's own
    /// prefix and only then to "show", so a saved movie is never quietly
    /// filed as a series. tvOS has no SourceKind, so the prefix set is
    /// spelled out — it must track SourceKind.from(titleId:).
    static func of(_ item: TVUserStream) -> TVWatchListTab {
        let id = item.titleId
        for prefix in ["yt:", "pod:", "tw:", "kick:"] where id.hasPrefix(prefix) {
            return .creators
        }
        let isTV = item.isTv ?? TitleID.isTV(from: id) ?? true
        return isTV ? .shows : .movies
    }
}

struct TVWatchListView: View {
    @State private var streams = TVStreamsViewModel.shared
    @State private var social = SocialViewModel.shared
    @State private var pendingDetail: TVTitleDetail?

    /// Which category is showing. Seeded once from the data so a viewer whose
    /// list is all movies does not land on an empty Shows tab; after that it
    /// follows their presses only.
    @State private var selectedTab: TVWatchListTab = .shows
    @State private var didSeedTab = false
    @FocusState private var focusedTab: TVWatchListTab?

    /// Six columns that share the row's width rather than each claiming a
    /// fixed 260pt. Fixed columns totalled 1740pt, more than the row has
    /// once the rail inset and padding are taken out, so the last one had
    /// nowhere to go.
    private let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(minimum: 200), spacing: 36),
        count: 6
    )

    var body: some View {
        ZStack {
            TVTheme.backgroundGradient

            if streams.userStreams.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 32) {
                        header
                            .padding(.leading, 80)
                            .padding(.trailing, 40)
                            .padding(.top, 24)

                        tabBar
                            .padding(.leading, 80)
                            .padding(.trailing, 40)

                        if visibleStreams.isEmpty {
                            emptyCategory
                        } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 48) {
                            ForEach(Array(visibleStreams.enumerated()), id: \.element.id) { index, row in
                                TVPosterCard(
                                    title: row.title ?? row.titleId,
                                    subtitle: row.platform,
                                    posterUrl: streams.displayPosterUrl(for: row),
                                    accent: TVTheme.orange,
                                    isSaved: true
                                ) {
                                    Task { await streams.markWatchlistSeen(titleId: row.titleId) }
                                    pendingDetail = TVTitleDetail(
                                        titleId: row.titleId,
                                        title: row.title ?? row.titleId,
                                        overview: nil,
                                        posterUrl: streams.displayPosterUrl(for: row),
                                        backdropUrl: streams.displayPosterUrl(for: row),
                                        tag: row.platform ?? "SAVED",
                                        accent: TVTheme.orange,
                                        year: nil,
                                        platform: row.platform,
                                        isTVHint: row.isTv
                                    )
                                }
                                .overlay(alignment: .topLeading) {
                                    if let badge = streams.newBadgeText(for: row) {
                                        Text(badge)
                                            .font(.system(size: 18, weight: .bold))
                                            .textCase(.uppercase)
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.black, in: RoundedRectangle(cornerRadius: 6))
                                            .padding(12)
                                    }
                                }
                                .overlay(alignment: .bottomTrailing) {
                                    if social.isWatched(row.titleId) {
                                        Circle()
                                            .fill(TVTheme.blue)
                                            .frame(width: 34, height: 34)
                                            .overlay {
                                                Image(systemName: "eye.fill")
                                                    .font(.system(size: 18, weight: .bold))
                                                    .foregroundStyle(.white)
                                            }
                                            .padding(10)
                                    }
                                }

                                // Sponsored chip beneath the first grid row
                                if index == 5, let chip = watchlistSponsoredChip {
                                    TVSponsoredChip(data: chip)
                                        .id("chip_\(chip.advertiser.key)_watchlist")
                                        .gridCellColumns(columns.count)
                                }
                            }
                        }
                        .padding(.leading, 80)
                        .padding(.trailing, 40)
                        .padding(.bottom, 60)
                        }
                    }
                }
            }
        }
        .task {
            await streams.fetchUserStreams()
            await streams.fetchLatestContentDates()
            await streams.fetchWatchlistSeen()
            await streams.backfillPosters()
            await social.loadAllWatched()
            await TVAffiliateService.shared.fetchIfNeeded()
            seedSelectedTabIfNeeded()
        }
        .onChange(of: streams.userStreams.count) { _, _ in
            seedSelectedTabIfNeeded()
        }
        .routesTitleDetail($pendingDetail)
    }

    /// The selected category's rows, in the list's usual order. The grid,
    /// the header count and the sponsored chip all read this, so nothing on
    /// screen can disagree with the tab that is lit.
    private var visibleStreams: [TVUserStream] {
        sortedStreams.filter { TVWatchListTab.of($0) == selectedTab }
    }

    /// Saved titles per tab, counted before the tab filter, so a chip can
    /// show what is waiting behind it.
    private var tabCounts: [TVWatchListTab: Int] {
        Dictionary(grouping: streams.userStreams, by: { TVWatchListTab.of($0) })
            .mapValues(\.count)
    }

    /// Moves to the first category that actually holds something, once, the
    /// first time saved titles arrive. Never overrides a tab the viewer has
    /// pressed, and never fires again once it has run.
    private func seedSelectedTabIfNeeded() {
        guard !didSeedTab, !streams.userStreams.isEmpty else { return }
        didSeedTab = true
        let counts = tabCounts
        guard (counts[selectedTab] ?? 0) == 0 else { return }
        if let first = TVWatchListTab.allCases.first(where: { (counts[$0] ?? 0) > 0 }) {
            selectedTab = first
        }
    }

    /// The category chips. Their own focus section, so a move down from here
    /// resolves into the grid rather than being decided by which poster
    /// happens to sit under the chip.
    private var tabBar: some View {
        HStack(spacing: 18) {
            ForEach(TVWatchListTab.allCases) { tab in
                tabChip(tab)
            }
        }
        .focusSection()
    }

    private func tabChip(_ tab: TVWatchListTab) -> some View {
        let isOn = selectedTab == tab
        let focused = focusedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 12) {
                Image(systemName: tab.glyph)
                    .font(.system(size: 22, weight: .semibold))
                Text(tab.title)
                    .font(.system(size: 24, weight: .semibold))
                Text("\(tabCounts[tab] ?? 0)")
                    .font(.system(size: 18, weight: .heavy))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(isOn ? 0.18 : 0.10), in: Capsule())
            }
            .foregroundStyle(isOn ? Color.black : TVTheme.textSecondary)
            .padding(.horizontal, 26)
            .padding(.vertical, 12)
            // Selection and focus stay separate cues, the way the season
            // pills on the title screen keep them apart: the filled capsule
            // says which category is showing, the plate says which chip the
            // remote is on.
            .background(isOn ? Color.white.opacity(0.92) : Color.white.opacity(0.10), in: Capsule())
            .overlay(Capsule().fill(Color.white.opacity(focused && !isOn ? 0.16 : 0)))
            .overlay(Capsule().stroke(Color.white.opacity(focused ? 0.9 : 0), lineWidth: 2))
            .scaleEffect(focused ? 1.06 : 1.0)
            .animation(.easeOut(duration: 0.15), value: focused)
        }
        // An empty style, not .plain: .plain still lays tvOS's white slab
        // over the chip even with the focus effect disabled.
        .buttonStyle(TVFlatButtonStyle())
        .focusEffectDisabled()
        .focused($focusedTab, equals: tab)
    }

    /// User streams sorted by recency (newest content first), then by
    /// date-added for titles without a `title_recency` row.
    private var sortedStreams: [TVUserStream] {
        let recencyMap = streams.latestContentAt
        return streams.userStreams.sorted { a, b in
            let aDate = recencyMap[a.titleId]
            let bDate = recencyMap[b.titleId]
            if let aD = aDate, let bD = bDate, aD != bD {
                return aD > bD
            }
            if aDate != nil && bDate == nil { return true }
            if aDate == nil && bDate != nil { return false }
            let aAdded = a.addedAt ?? Date.distantPast
            let bAdded = b.addedAt ?? Date.distantPast
            return aAdded > bAdded
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text("Watch List")
                .font(.system(size: 48, weight: .black))
                .foregroundStyle(.white)
            Text("\(visibleStreams.count)")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(TVTheme.orange, in: Capsule())
            Spacer()
            if streams.isLoading {
                ProgressView().tint(.white)
            }
        }
    }

    // MARK: - Sponsored chip

    /// Resolves a sponsored chip for the Watch List: walks the sorted
    /// streams, finds the first whose `platform` resolves to a gap-service
    /// advertiser with a non-nil `appStoreURL`. Maximum one chip on this
    /// screen.
    private var watchlistSponsoredChip: SponsoredChipData? {
        for row in visibleStreams {
            guard let platform = row.platform else { continue }
            guard let advertiser = TVAffiliateService.shared.advertiser(forProviderName: platform) else { continue }
            guard advertiser.appStoreURL != nil else { continue }
            guard TVAffiliateService.shared.isGapService(platform) else { continue }
            return SponsoredChipData(
                advertiser: advertiser,
                titleName: row.title ?? row.titleId,
                titleId: row.titleId,
                providerName: platform,
                surface: "watchlist"
            )
        }
        return nil
    }

    /// Shown when the list has titles but this category has none — distinct
    /// from the whole-list empty state below, which tells the viewer to go
    /// and save something.
    private var emptyCategory: some View {
        VStack(spacing: 16) {
            Image(systemName: selectedTab.glyph)
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(TVTheme.textSecondary)
            Text("No \(selectedTab.title.lowercased()) saved yet")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var emptyState: some View {
        VStack(spacing: 28) {
            Image(systemName: "popcorn.fill")
                .font(.system(size: 96, weight: .bold))
                .foregroundStyle(TVTheme.orange)
            Text("Your Watch List is empty")
                .font(.system(size: 38, weight: .black))
                .foregroundStyle(.white)
            Text("Open Home and click any title to add it. Saved shows appear here for everyone signed in to your account.")
                .font(.system(size: 22))
                .foregroundStyle(TVTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 700)
        }
        .padding(40)
    }
}


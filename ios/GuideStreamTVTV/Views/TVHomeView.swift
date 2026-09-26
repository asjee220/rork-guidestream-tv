//
//  TVHomeView.swift
//  GuideStreamTVTV
//
//  Living-room home: cinematic hero carousel on top, followed by rails
//  for Everyone's Watching, New Episodes (on the air), Coming to Streaming,
//  Popular on {service}, Creators/Podcasts for You, and Sports. Every
//  focusable card defers to its own action so navigation can flow back
//  through a single sheet pattern instead of nested stacks.
//

import SwiftUI
import UIKit

// MARK: - Rail item structs

nonisolated private struct EveryonesWatchingItem: Identifiable, Codable {
    let result: TVTMDBResult
    let rank: Int
    let providerName: String?
    var id: Int { result.id }
}

nonisolated private struct ComingToStreamingItem: Identifiable, Codable {
    let result: TVTMDBResult
    let badge: String
    let meta: String
    /// Sort key: dated items use the digital release date timestamp so
    /// earliest-first ordering is correct; heuristic items sort after all
    /// dated items via `.distantFuture`.
    let sortKey: Date
    var id: Int { result.id }
}

nonisolated private struct NowNextItem: Identifiable, Codable {
    let release: TVStreamingRelease
    let badge: String
    var id: Int { release.tmdbId }
}

/// One resolved row of the Continue Watching rail. `service` is nil when the
/// stored platform id does not map to a StreamingCatalog entry — the
/// source events store free text, so a miss is expected, not an error.
private struct ContinueWatchingItem: Identifiable {
    let row: TVContinueWatchingRow
    let posterUrl: String?
    let service: StreamingService?
    var id: Int { row.tmdbId }
    var titleId: String { "tmdb:\(row.isTV ? "tv" : "movie"):\(row.tmdbId)" }
    var accent: Color { service?.color ?? TVTheme.orange }
    /// "Resume on Netflix" when the service resolves, otherwise the plain
    /// media type — never a percentage, because launch intent does not
    /// tell us how far the title got.
    var subtitle: String {
        if let service { return "Resume on \(service.name)" }
        return row.isTV ? "Series" : "Movie"
    }
}

private struct NowAndNextRail: Identifiable {
    let service: StreamingService
    let items: [NowNextItem]
    var id: String { service.id }
}

/// A followed show's next scheduled episode (GUI-102).
nonisolated struct UpcomingEpisodeItem: Identifiable, Hashable, Codable {
    let tmdbId: Int
    let next: TVTMDBNextEpisode
    var id: Int { tmdbId }
}

/// Everything Home renders above and below the fold, as it was last built.
/// Painted on the next launch before any request; see TVHomeSnapshotStore.
/// Rule from the phone: any rail above the fold must be in here, or the
/// first paint reflows when the real data lands. Live sports, live creators
/// and creator uploads are deliberately left out — they are time-sensitive.
nonisolated private struct TVHomeSnapshot: Codable, Sendable {
    struct ContinueRow: Codable {
        let row: TVContinueWatchingRow
        let posterUrl: String?
        let serviceId: String?
    }
    struct NowNext: Codable {
        let serviceId: String
        let items: [NowNextItem]
    }
    var trending: [TVTMDBResult] = []
    var onAir: [TVTMDBResult] = []
    var ended: [TVTMDBResult] = []
    var topRated: [TVTMDBResult] = []
    var providerNames: [Int: String] = [:]
    var heroItems: [TVTMDBResult] = []
    var heroFeaturettes: [String: String] = [:]
    var continueWatching: [ContinueRow] = []
    var recommendedTitles: [TVRecommendedTitle] = []
    var todaysPick: TVStreamingRelease?
    var todaysPickBackdropUrl: String?
    var everyonesWatching: [EveryonesWatchingItem] = []
    var topPicksSource: [TVTMDBResult] = []
    var popularOnService: [String: [TVTMDBResult]] = [:]
    var nowAndNext: [NowNext] = []
    var comingToStreaming: [ComingToStreamingItem] = []
    var recommendedCreators: [TVRecommendedCreator] = []
    var followedNewEpisodes: [TVNewEpisodeRow] = []
    var newThisWeek: [TVStreamingRelease] = []
    var leavingSoon: [TVExpiringRow] = []
    var upcomingEpisodes: [UpcomingEpisodeItem] = []
    var aroundTheWorld: [TVTMDBResult] = []
    var aroundRegionCode: String?
    var aroundProviderName: String?
}

private struct TopPickItem: Identifiable {
    let result: TVTMDBResult
    let providerName: String
    let score: Double
    /// Trending position — breaks score ties deterministically.
    let rank: Int
    var matchPercent: Int {
        let clamped = min(max(score, 0.50), 0.99)
        return Int((clamped * 100).rounded())
    }
    var id: Int { result.id }
}

struct TVHomeView: View {
    /// Distance from the physical left edge of the display to this screen's
    /// leading edge — TVMainView's inset plus the title-safe margin tvOS
    /// applied above it. Measured by TVMainView, because a ScrollView's own
    /// content cannot see it.
    var leadingBleed: CGFloat = TVLayout.contentLeadingInset

    @State private var trending: [TVTMDBResult] = []
    @State private var newEpisodes: [TVTMDBResult] = []
    @State private var sports: [TVSportsGame] = []
    @State private var isLoading: Bool = true
    @State private var heroItems: [TVTMDBResult] = []
    /// What the hero actually shows: live games, live creators and the newest
    /// uploads ahead of `heroItems`, the same mix as the phone (GUI-102).
    @State private var heroEntries: [TVHeroEntry] = []
    @State private var heroGame: TVSportsGame?

    // GUI-102 — rails the phone had and the TV did not.
    @State private var endedShows: [TVTMDBResult] = []
    @State private var topRated: [TVTMDBResult] = []
    /// tmdb id -> top provider name, for the provider-gated rails.
    @State private var providerNames: [Int: String] = [:]
    @State private var followedNewEpisodes: [TVNewEpisodeRow] = []
    @State private var creatorUploads: [TVNewEpisodeRow] = []
    @State private var liveCreators: [TVLiveStatus] = []
    @State private var newThisWeek: [TVStreamingRelease] = []
    @State private var leavingSoon: [TVExpiringRow] = []
    @State private var upcomingEpisodes: [UpcomingEpisodeItem] = []
    @State private var aroundTheWorld: [TVTMDBResult] = []
    @State private var aroundCountry: CountryCatalogEntry?
    @State private var aroundProviderName: String?
    @State private var heroLoading: Bool = true
    /// canonicalTitleId -> hosted featurette URL for the hero pool.
    /// Empty until the single batched lookup resolves after the pool is
    /// final; a missing key renders that item as a still.
    @State private var heroFeaturettes: [String: String] = [:]

    @State private var pendingDetail: TVTitleDetail?
    /// 16:9 backdrop for Today's Pick, resolved from TMDB. `streaming_releases`
    /// carries poster art only, and a 2:3 poster filled into the wide banner
    /// crops the picture to a strip of its middle. Nil until it resolves (or
    /// if the title has no backdrop), in which case the poster is shown whole
    /// rather than cropped.
    @State private var todaysPickBackdropUrl: String? = nil
    @State private var todaysPickBackdropTmdbId: Int? = nil

    /// Drives the hero's Add to Watchlist button as the default focus for
    /// the Home scene, so the app opens with the hero fully visible.
    @FocusState private var heroCTAFocused: Bool
    /// One-shot guard so the hero CTA is claimed as focus exactly once,
    /// on the first load of this screen, and never steals focus afterwards.
    @State private var didClaimInitialFocus: Bool = false

    @State private var streams = TVStreamsViewModel.shared
    /// Observed so Continue Watching reloads when the Supabase session is
    /// restored — `loadAll()` fires from `.task` before auth settles, so a
    /// one-shot fetch there sees a signed-out client and returns nothing.
    @State private var auth = TVAuthViewModel.shared

    // New rails
    @State private var everyonesWatching: [EveryonesWatchingItem] = []
    /// "Recommended for You" — TMDB titles scored server-side by
    /// `recommend_titles` from this viewer's signals, filtered to the services
    /// they subscribe to. Second rail on tvOS by product decision: Continue
    /// Watching stays first because a half-finished show beats any suggestion.
    @State private var recommendedTitles: [TVRecommendedTitle] = []
    @State private var comingToStreaming: [ComingToStreamingItem] = []
    @State private var popularOnService: [String: [TVTMDBResult]] = [:]
    @State private var recommendedCreators: [TVRecommendedCreator] = []
    @State private var nowAndNextRails: [NowAndNextRail] = []

    /// Continue Watching — titles launched from any platform by this signed-in
    /// user. Empty for guests and whenever the view returns nothing.
    @State private var continueWatching: [ContinueWatchingItem] = []

    /// Focus scope for the Continue Watching cards, so entering the rail
    /// lands on the first card rather than wherever the focus engine picks.
    @Environment(\.showTitleDetail) private var showTitleDetail

    @Namespace private var continueWatchingScope
    @FocusState private var focusedContinueWatching: Int?

    /// Set the moment the hero CTA gives up focus, cleared by whichever card
    /// claims it next. prefersDefaultFocus only decides where a *reset* puts
    /// focus, not where a directional move lands, so a move down out of the
    /// hero was still resolved by the engine's own geometry and kept picking
    /// the rail's far end. This flag is what lets the rail tell a hand-off
    /// from the hero apart from a move up out of the rail below, where the
    /// card the viewer left is the right place to return to.
    @State private var heroHandingOffFocus = false

    /// Deterministic daily pick from streaming_releases, resolved once per
    /// load. Nil when the table is empty or unreachable.
    @State private var todaysPick: TVStreamingRelease?

    /// Payload driving the shared See-all grid full-screen cover.
    @State private var seeAllPayload: TVSeeAllGridPayload?

    /// Maps tvOS StreamingCatalog ids to TMDB Watch provider ids so
    /// `getPopularOnService` / `getPopularMoviesOnService` can query the
    /// correct provider.
    private let tmdbProviderIdMap: [String: Int] = [
        "netflix": 8,
        "prime": 9,
        "disney": 337,
        "max": 1899,
        "hulu": 15,
        "appletv": 350,
        "paramount": 2303,
        "peacock": 386,
        "starz": 43,
        "showtime": 37,
        "crunchyroll": 283,
        "youtube": 192,
    ]

    var body: some View {
        // Title-safe margins are symmetric, so the trailing gap is the
        // leading one minus the shell inset.
        let trailingBleed = max(0, leadingBleed - TVLayout.contentLeadingInset)
        // Positioned from the physical edge rather than accumulated from the
        // safe margin: TVRail's gutter sits inside contentLeading instead of
        // being added on top of it.
        let railLeading = max(0, TVLayout.contentLeading - TVLayout.railGutter)

        return ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 56) {
                // 1. Hero — true full bleed. It cancels every inset the rail
                // stack re-applies, so the art meets the top, leading and
                // trailing edges and the menu floats over it. The negative
                // bottom pull lets the first rail sit over the art at the
                // fold so the video / poster fades off into it.
                heroSection(metadataInset: TVLayout.contentLeading)
                    // The screen's height, not the container's.
                    // containerRelativeFrame resolved to two different values
                    // on two layout passes — measured on Living Room 7 as
                    // h=766 then h=886 against a 1080 screen. 766 is 1080
                    // minus the 120pt title-safe inset minus this 194 pull,
                    // so the first pass gets a safe-area-inset container and
                    // whatever paints in it leaves a band across the top.
                    // The screen is 1080 on every pass.
                    .frame(height: UIScreen.main.bounds.height)
                    .padding(.bottom, -194)
                    .padding(.leading, -railLeading)
                    .padding(.trailing, -trailingBleed)
                    // The hero is giving focus up. Where it goes is the
                    // focus engine's call; the rail below only needs to know
                    // that the move came from here.
                    .onChange(of: heroCTAFocused) { wasFocused, isFocused in
                        if wasFocused, !isFocused { heroHandingOffFocus = true }
                    }

                // Rows follow the phone's Home order (GUI-102); Continue
                // Watching stays directly under the hero.
                // 1a. Continue Watching — highest-intent rail on the screen, so
                // it sits directly under the hero. Hidden entirely when the
                // user is a guest or has no recent launches.
                if !continueWatching.isEmpty {
                    TVRail(
                        title: "Continue Watching",
                        accent: TVTheme.orange,
                        count: continueWatching.count,
                        seeAllKey: "continue_watching",
                        onSeeAll: {
                            seeAllPayload = TVSeeAllGridPayload(
                                title: "Continue Watching",
                                accent: TVTheme.orange,
                                items: continueWatchingGridItems
                            )
                        }
                    ) {
                        // The rail's cards are their own focus section, and a
                        // move into a section is resolved by the focus engine
                        // rather than by position — which was landing on the
                        // last card. Its own scope with the first card
                        // declared the default settles it.
                        HStack(spacing: 32) {
                            ForEach(Array(continueWatching.enumerated()),
                                    id: \.element.id) { index, item in
                                continueWatchingCard(for: item)
                                    .prefersDefaultFocus(index == 0, in: continueWatchingScope)
                                    .focused($focusedContinueWatching, equals: index)
                            }
                        }
                        .focusScope(continueWatchingScope)
                        .onChange(of: focusedContinueWatching) { _, index in
                            guard let index else { return }
                            TVNavLog.log("continue watching focus -> card \(index) of \(continueWatching.count)")
                            guard heroHandingOffFocus else { return }
                            heroHandingOffFocus = false
                            // Coming down off the hero always means the first
                            // card, however the engine resolved the move.
                            if index != 0 { focusedContinueWatching = 0 }
                        }
                    }
                }

                // 1b. Recommended for You — the second rail, under Continue
                // Watching. Hidden when empty: a viewer with no services or no
                // signals yet gets no rail at all, because an empty
                // personalised rail reads worse than none.
                if !recommendedTitles.isEmpty {
                    TVRail(
                        title: "Recommended for You",
                        accent: TVTheme.orange,
                        count: recommendedTitles.count
                    ) {
                        ForEach(recommendedTitles) { rec in
                            TVPosterCard(
                                title: rec.title,
                                subtitle: "\(rec.matchPercentage)% match",
                                posterUrl: rec.posterUrl,
                                accent: TVTheme.orange,
                                isSaved: streams.contains(titleId: String(rec.tmdbId))
                            ) {
                                pendingDetail = TVTitleDetail(
                                    titleId: String(rec.tmdbId),
                                    title: rec.title,
                                    overview: nil,
                                    posterUrl: rec.posterUrl,
                                    backdropUrl: rec.backdropUrl,
                                    tag: rec.isTV ? "SERIES" : "MOVIE",
                                    accent: TVTheme.orange,
                                    year: nil,
                                    platform: nil,
                                    isTVHint: rec.isTV
                                )
                            }
                        }
                    }
                }

                // 3. Today's Pick — one full-width card, deterministic per
                // local day.
                if let pick = todaysPick {
                    todaysPickSection(for: pick)
                }

                // New Episodes — episodes of shows this viewer follows, as on
                // the phone. Falls back to TMDB's on-the-air list only when
                // they follow nothing with a recent episode (GUI-102).
                if !followedNewEpisodes.isEmpty {
                    TVRail(title: "New Episodes", accent: TVTheme.blue, count: followedNewEpisodes.count) {
                        ForEach(followedNewEpisodes) { row in
                            if let tmdbId = row.tmdbId {
                                tmdbCard(
                                    tmdbId: tmdbId,
                                    isTV: true,
                                    title: row.showName,
                                    subtitle: episodeSubtitle(row),
                                    posterUrl: row.posterUrl,
                                    accent: TVTheme.blue
                                )
                            }
                        }
                    }
                } else if !newEpisodes.isEmpty {
                    TVRail(title: "New Episodes", accent: TVTheme.blue, count: newEpisodes.count) {
                        ForEach(newEpisodes) { item in
                            posterCard(for: item, accent: TVTheme.blue)
                        }
                    }
                }

                // Around the World — one country a day, relative to home.
                if let country = aroundCountry, !aroundTheWorld.isEmpty {
                    TVRail(
                        title: "Around the World · \(country.displayName)\(aroundProviderName.map { " on \($0)" } ?? "")",
                        accent: TVTheme.orange,
                        count: aroundTheWorld.count
                    ) {
                        ForEach(aroundTheWorld) { item in
                            tmdbCard(
                                tmdbId: item.id,
                                isTV: item.isTV,
                                title: item.displayName,
                                subtitle: item.year.map(String.init) ?? "Series",
                                posterUrl: item.posterUrl,
                                accent: TVTheme.orange
                            )
                        }
                    }
                }

                // 8. Coming to Streaming
                if !comingToStreaming.isEmpty {
                    TVRail(title: "Coming to Streaming", accent: TVTheme.orange, count: comingToStreaming.count) {
                        ForEach(comingToStreaming) { item in
                            comingToStreamingCard(for: item)
                        }
                    }
                }

                // New This Week — streaming_releases, newest first.
                if !newThisWeek.isEmpty {
                    TVRail(title: "New This Week", accent: TVTheme.orange, count: newThisWeek.count) {
                        ForEach(newThisWeek) { release in
                            tmdbCard(
                                tmdbId: release.tmdbId,
                                isTV: release.isTV,
                                title: release.title,
                                subtitle: release.sourceName ?? (release.isTV ? "Series" : "Movie"),
                                posterUrl: release.posterUrl,
                                accent: TVTheme.orange
                            )
                        }
                    }
                }

                // 4. Top Picks for You
                if !topPicks.isEmpty {
                    TVRail(
                        title: "Top Picks for You",
                        accent: TVTheme.orange,
                        count: topPicks.count,
                        seeAllKey: "top_picks",
                        onSeeAll: {
                            seeAllPayload = TVSeeAllGridPayload(
                                title: "Top Picks for You",
                                accent: TVTheme.orange,
                                items: topPicksGridItems
                            )
                        }
                    ) {
                        ForEach(topPicks) { item in
                            topPickCard(for: item)
                        }
                    }
                }

                // 9. Creators / Podcasts for You
                if !recommendedCreators.isEmpty {
                    TVRail(title: "Creators / Podcasts for You", accent: TVTheme.blue, count: recommendedCreators.count) {
                        ForEach(recommendedCreators) { creator in
                            creatorCard(for: creator)
                        }
                    }
                }

                // 2. Everyone's Watching
                if !everyonesWatching.isEmpty {
                    TVRail(
                        title: "Everyone's Watching",
                        accent: TVTheme.orange,
                        count: everyonesWatching.count,
                        seeAllKey: "everyones_watching",
                        onSeeAll: {
                            seeAllPayload = TVSeeAllGridPayload(
                                title: "Everyone's Watching",
                                accent: TVTheme.orange,
                                items: everyonesWatchingGridItems
                            )
                        }
                    ) {
                        ForEach(everyonesWatching) { item in
                            everyonesWatchingCard(for: item)
                        }
                    }
                }

                // Sponsored chip beneath Everyone's Watching — first
                // gap-service advertiser from the items' provider names.
                if let chip = everyonesWatchingSponsoredChip {
                    TVSponsoredChip(data: chip)
                        .id("chip_\(chip.advertiser.key)_home_everyones_watching")
                        .padding(.horizontal, 80)
                }

                // Leaving Soon — expiring_titles within 20 days.
                if !leavingSoon.isEmpty {
                    TVRail(title: "Leaving Soon", accent: TVTheme.orange, count: leavingSoon.count) {
                        ForEach(leavingSoon) { row in
                            tmdbCard(
                                tmdbId: row.tmdbId,
                                isTV: row.isTV,
                                title: row.title,
                                subtitle: leavingSubtitle(row),
                                posterUrl: row.posterUrl,
                                accent: TVTheme.orange
                            )
                        }
                    }
                }

                // 5. Popular on {service} — one rail per subscribed service
                ForEach(popularOnServiceOrder, id: \.id) { service in
                    if let items = popularOnService[service.id], !items.isEmpty {
                        TVRail(
                            title: "Popular on \(service.name)",
                            accent: service.color,
                            count: items.count,
                            seeAllKey: "popular_\(service.id)",
                            onSeeAll: {
                                seeAllPayload = TVSeeAllGridPayload(
                                    title: "Popular on \(service.name)",
                                    accent: service.color,
                                    items: popularGridItems(items)
                                )
                            }
                        ) {
                            ForEach(items) { item in
                                posterCard(for: item, accent: service.color)
                            }
                        }
                    }
                }

                // 6. Now & Next on {service} — one rail per subscribed service
                ForEach(nowAndNextRails) { rail in
                    TVRail(
                        title: "Now & Next on \(rail.service.name)",
                        accent: rail.service.color,
                        count: rail.items.count,
                        seeAllKey: "now_next_\(rail.service.id)",
                        onSeeAll: {
                            seeAllPayload = TVSeeAllGridPayload(
                                title: "Now & Next on \(rail.service.name)",
                                accent: rail.service.color,
                                items: nowNextGridItems(for: rail)
                            )
                        }
                    ) {
                        ForEach(rail.items) { item in
                            nowNextCard(for: item, accent: rail.service.color)
                        }
                    }
                }

                // Sponsored chip beneath the last Now & Next rail — first
                // gap-service advertiser with a non-nil appStoreURL from
                // the rail's items.
                if let chip = nowNextSponsoredChip {
                    TVSponsoredChip(data: chip)
                        .id("chip_\(chip.advertiser.key)_home_now_next")
                        .padding(.horizontal, 80)
                }

                // Top rated right now — only titles on a streaming service.
                if !topRatedOnService.isEmpty {
                    TVRail(title: "Top rated right now", accent: TVTheme.orange, count: topRatedOnService.count) {
                        ForEach(topRatedOnService) { item in
                            tmdbCard(
                                tmdbId: item.id,
                                isTV: item.isTV,
                                title: item.displayName,
                                subtitle: providerNames[item.id] ?? "",
                                posterUrl: item.posterUrl,
                                accent: TVTheme.orange
                            )
                        }
                    }
                }

                // New seasons — on-air shows already on this viewer's watchlist.
                if !newSeasonsYouFollow.isEmpty {
                    TVRail(title: "New seasons — shows you follow", accent: TVTheme.blue, count: newSeasonsYouFollow.count) {
                        ForEach(newSeasonsYouFollow) { item in
                            posterCard(for: item, accent: TVTheme.blue)
                        }
                    }
                }

                // Upcoming Episodes — next scheduled episode of followed shows.
                if !upcomingEpisodes.isEmpty {
                    TVRail(title: "Upcoming Episodes", accent: TVTheme.blue, count: upcomingEpisodes.count) {
                        ForEach(upcomingEpisodes) { item in
                            tmdbCard(
                                tmdbId: item.tmdbId,
                                isTV: true,
                                title: item.next.showName,
                                subtitle: upcomingSubtitle(item.next),
                                posterUrl: TVTMDBImage.url(item.next.posterPath, size: .poster500),
                                accent: TVTheme.blue
                            )
                        }
                    }
                }

                // Binge Worthy — ended series, on a streaming service.
                if !bingeWorthy.isEmpty {
                    TVRail(title: "Binge Worthy", accent: TVTheme.orange, count: bingeWorthy.count) {
                        ForEach(bingeWorthy) { item in
                            tmdbCard(
                                tmdbId: item.id,
                                isTV: true,
                                title: item.displayName,
                                subtitle: providerNames[item.id] ?? "Complete series",
                                posterUrl: item.posterUrl,
                                accent: TVTheme.orange
                            )
                        }
                    }
                }

                // 10. Live Sports
                if !sports.isEmpty {
                    TVRail(title: "Live Sports", accent: TVTheme.blue, count: sports.count) {
                        ForEach(sports) { game in
                            TVSportsTile(game: game) { /* read-only for v1 */ }
                        }
                    }
                }

                Color.clear.frame(height: 40)
                }
                .padding(.leading, railLeading)
                .padding(.trailing, trailingBleed)
            }
            // Pull the scroll view out to the physical edges; the rail stack
            // above puts both insets back, so only the hero escapes.
            // .ignoresSafeArea() alone does not do this — on this SDK it
            // expands a vertical ScrollView vertically only, which is why the
            // top went full bleed and the leading edge did not.
            .padding(.leading, -leadingBleed)
            .padding(.trailing, -trailingBleed)
            .ignoresSafeArea()
            .background(TVTheme.backgroundGradient.ignoresSafeArea())
            .defaultFocus($heroCTAFocused, true)
            .task { await loadAll() }
            // Keyed on the signed-in user: runs once on appear and again the
            // moment a restored session lands, which is the only way this
            // rail ever fills on a cold launch. Every other rail on this
            // screen is anonymous, so none of them need this.
            .task(id: auth.currentUser?.id) { await buildContinueWatching() }
            .onChange(of: heroEntries.isEmpty) { _, isEmpty in
                guard !isEmpty, !didClaimInitialFocus else { return }
                didClaimInitialFocus = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(120))
                    heroCTAFocused = true
                }
            }
            .routesTitleDetail($pendingDetail)
            .fullScreenCover(item: $seeAllPayload) { payload in
                TVSeeAllGridView(payload: payload, pendingDetail: $pendingDetail)
            }
            .fullScreenCover(item: $heroGame) { game in
                SportsWatchSheet(game: game)
            }
    }

    // MARK: - Hero

    /// `metadataInset` is where the hero's copy starts: it has to match the
    /// rail titles below, which the art itself no longer does now that it
    /// runs full bleed.
    @ViewBuilder
    private func heroSection(metadataInset: CGFloat) -> some View {
        if heroEntries.isEmpty {
            // Reserve the full-screen height so the rails below don't
            // jump when the data lands.
            Rectangle()
                .fill(TVTheme.surface)
                .overlay {
                    if heroLoading {
                        ProgressView()
                            .scaleEffect(2)
                            .tint(.white)
                    }
                }
        } else {
            TVHeroCarousel(
                items: heroEntries,
                ctaFocused: $heroCTAFocused,
                continueState: { item in
                    // Same identity the rail is built on — "tmdb:tv:1396".
                    guard let match = continueWatching.first(where: {
                        $0.titleId == item.canonicalTitleId
                    }) else { return nil }
                    return TVHeroContinueState(serviceName: match.service?.name)
                },
                onContinue: { item, serviceName in
                    guard let serviceName else {
                        // No service resolved for the row, so there is
                        // nothing to open. The title screen rather than a
                        // dead press.
                        showTitleDetail(heroDetail(for: item))
                        return
                    }
                    WatchIntentLogger.shared.log(
                        eventType: .deeplinkFired,
                        titleId: item.canonicalTitleId,
                        platformId: Platform.from(providerName: serviceName)?.catalogId ?? serviceName,
                        metadata: [
                            "source": "tv_hero_continue",
                            "tmdb_id": item.id,
                            "media_type": item.isTV ? "tv" : "movie"
                        ]
                    )
                    Task { @MainActor in
                        await openContinue(item: item, serviceName: serviceName)
                    }
                },
                onWatchNow: { entry in openHeroEntry(entry) },
                featurettes: heroFeaturettes,
                metadataInset: metadataInset
            )
        }
    }

    /// Opens the service the viewer last watched this title on, ON the title
    /// where Watchmode gives us a link for it.
    ///
    /// This was `TVOSDeepLinker.open(platform:title:)` with no URL, which
    /// could only ever reach the service's home screen — while the title
    /// screen two presses away opened the title itself, because TVTitleSheet
    /// resolved sources and this did not. Same resolver, same guard, same
    /// ordering now; `TVDeepLinkResolver` is the shared walk.
    ///
    /// Continue Watching carries no season/episode — it is built from launch
    /// events — so this is a title-level link by nature. For a series that
    /// means the show, not a specific episode, which is the honest
    /// destination for "resume where you were".
    private func openContinue(item: TVTMDBResult, serviceName: String) async {
        let resolved = await TVWatchmodeResolver.shared.resolve(
            tmdbId: item.id,
            isTV: item.isTV,
            season: nil,
            episode: nil,
            episodePlatformHint: serviceName
        )
        // The row the viewer was actually watching on, not whichever source
        // ranked first — resuming on a service they do not have is worse
        // than opening the app they do.
        let source = resolved?.usSources.first {
            TVDeepLinkResolver.isSameBrand($0.name, serviceName)
        } ?? resolved?.primarySource

        if let source, let deepLink = TVDeepLinkResolver.deepLink(for: source) {
            TVOSDeepLinker.open(
                platform: source.name,
                title: item.displayName,
                contentURL: TVDeepLinkResolver.webURL(for: source),
                tvosDeepLink: deepLink
            )
        } else {
            // Nothing usable came back. The service's own app is still the
            // right destination, and is exactly what this button did before.
            TVOSDeepLinker.open(platform: serviceName, title: item.displayName)
        }
    }

    /// The hero item as a title-screen payload.
    private func heroDetail(for item: TVTMDBResult) -> TVTitleDetail {
        TVTitleDetail(
            titleId: item.canonicalTitleId,
            title: item.displayName,
            overview: item.overview,
            posterUrl: item.posterUrl,
            backdropUrl: item.backdropUrl,
            tag: item.isTV ? "SERIES" : "MOVIE",
            accent: TVTheme.orange,
            year: item.year,
            platform: nil,
            isTVHint: item.isTV
        )
    }

    /// Hero CTA for anything that is not a resume.
    private func openHeroEntry(_ entry: TVHeroEntry) {
        switch entry {
        case .media(let item):
            showTitleDetail(heroDetail(for: item))
        case .game(let game):
            heroGame = game
        case .liveCreator(let titleId, let name, _, let imageUrl, _):
            pendingDetail = creatorDetail(titleId: titleId, name: name, imageUrl: imageUrl)
        case .upload(let row):
            pendingDetail = creatorDetail(titleId: row.titleId, name: row.showName, imageUrl: row.posterUrl)
        }
    }

    private func creatorDetail(titleId: String, name: String, imageUrl: String?) -> TVTitleDetail {
        TVTitleDetail(
            titleId: titleId,
            title: name,
            overview: nil,
            posterUrl: imageUrl,
            backdropUrl: nil,
            tag: (TVCreatorKind.from(titleId: titleId)?.displayLabel ?? "CREATOR").uppercased(),
            accent: TVTheme.blue,
            year: nil,
            platform: nil,
            isTVHint: nil
        )
    }

    /// Poster card for any TMDB title the parity rails show.
    private func tmdbCard(
        tmdbId: Int,
        isTV: Bool,
        title: String,
        subtitle: String,
        posterUrl: String?,
        accent: Color
    ) -> some View {
        let titleId = "tmdb:\(isTV ? "tv" : "movie"):\(tmdbId)"
        return TVPosterCard(
            title: title,
            subtitle: subtitle,
            posterUrl: posterUrl,
            accent: accent,
            isSaved: streams.contains(titleId: titleId) || streams.contains(titleId: String(tmdbId))
        ) {
            pendingDetail = TVTitleDetail(
                titleId: titleId,
                title: title,
                overview: nil,
                posterUrl: posterUrl,
                backdropUrl: nil,
                tag: isTV ? "SERIES" : "MOVIE",
                accent: accent,
                year: nil,
                platform: nil,
                isTVHint: isTV
            )
        }
    }


    // MARK: - GUI-102 parity rails

    private var topRatedOnService: [TVTMDBResult] {
        Array(topRated.filter { providerNames[$0.id] != nil }.prefix(20))
    }

    private var bingeWorthy: [TVTMDBResult] {
        Array(endedShows.filter { providerNames[$0.id] != nil }.prefix(20))
    }

    /// TMDB ids on this viewer's watchlist, whichever form they were saved in.
    private var savedTmdbIds: Set<Int> {
        Set(streams.userStreams.compactMap { TVTitleID.tmdbId(from: $0.titleId) })
    }

    private var newSeasonsYouFollow: [TVTMDBResult] {
        let saved = savedTmdbIds
        return Array(newEpisodes.filter { saved.contains($0.id) }.prefix(8))
    }

    private func episodeSubtitle(_ row: TVNewEpisodeRow) -> String {
        var parts: [String] = []
        if let s = row.seasonValue, let e = row.episodeValue { parts.append("S\(s) E\(e)") }
        if let platform = row.platform, !platform.isEmpty { parts.append(platform) }
        return parts.isEmpty ? "New episode" : parts.joined(separator: " · ")
    }

    private func leavingSubtitle(_ row: TVExpiringRow) -> String {
        let days = TVHomeRailsService.daysUntil(row.leavingDate) ?? 0
        let when = days <= 0 ? "Today" : days == 1 ? "1 day left" : "\(days) days left"
        return [when, row.serviceName].compactMap { $0 }.joined(separator: " · ")
    }

    private func upcomingSubtitle(_ next: TVTMDBNextEpisode) -> String {
        var parts: [String] = []
        if let s = next.seasonNumber, let e = next.episodeNumber { parts.append("S\(s) E\(e)") }
        if let date = next.airDate, !date.isEmpty { parts.append(date) }
        return parts.isEmpty ? "Coming up" : parts.joined(separator: " · ")
    }

    /// Everything the new rails read, fetched once per Home load.
    private func buildParityRails() async {
        let savedIds = streams.userStreams.map(\.titleId)
        async let episodesTask = TVHomeRailsService.fetchNewEpisodes(forTitleIds: savedIds)
        async let liveTask = TVHomeRailsService.fetchLive(titleIds: savedIds)
        async let leavingTask = TVHomeRailsService.fetchLeavingSoon()
        async let releasesTask = TVStreamingReleasesService.shared.fetchReleases()
        async let topRatedTask = TVTMDBService.shared.getTopRated()
        async let aroundTask: Void = buildAroundTheWorld()
        async let upcomingTask: Void = buildUpcomingEpisodes()

        let (episodes, live, leaving, releases, rated) = await (episodesTask, liveTask, leavingTask, releasesTask, topRatedTask)
        if let episodes {
            followedNewEpisodes = episodes.filter { $0.tmdbId != nil }
            // Newest upload per followed channel, as the phone's hero does.
            var seen = Set<String>()
            creatorUploads = episodes
                .filter { TVCreatorKind.from(titleId: $0.titleId) == .youtube }
                .filter { seen.insert($0.titleId).inserted }
        }
        liveCreators = live
        if let leaving { leavingSoon = leaving }
        if let releases { newThisWeek = Array(releases.prefix(20)) }
        topRated = rated
        await hydrateProviderNames(for: Array(rated.prefix(25)) + Array(endedShows.prefix(25)))
        _ = await (aroundTask, upcomingTask)
        composeHeroEntries()
    }

    /// Top provider name per title, for Top rated and Binge Worthy. Titles
    /// with no provider in this region are left out and so drop off the rail.
    private func hydrateProviderNames(for items: [TVTMDBResult]) async {
        var seen = Set<Int>()
        let todo = items.filter { providerNames[$0.id] == nil && seen.insert($0.id).inserted }
        guard !todo.isEmpty else { return }
        // Sliding window of 8 in flight. The hero, Everyone's Watching and
        // the parity rails all call this at once; unbounded, that was ~90
        // concurrent TMDB requests and the 429s came back as "no provider",
        // which emptied Everyone's Watching to four titles.
        let maxConcurrent = 8
        var cursor = 0
        let found = await withTaskGroup(of: (Int, String?).self) { group in
            func schedule(_ item: TVTMDBResult) {
                group.addTask {
                    let p = try? await TVTMDBService.shared.getTopWatchProvider(tmdbId: item.id, isTV: item.isTV)
                    return (item.id, p?.providerName)
                }
            }
            while cursor < todo.count && cursor < maxConcurrent { schedule(todo[cursor]); cursor += 1 }
            var out: [Int: String] = [:]
            while let (id, name) = await group.next() {
                if let name { out[id] = name }
                if cursor < todo.count { schedule(todo[cursor]); cursor += 1 }
            }
            return out
        }
        providerNames.merge(found) { _, new in new }
    }

    private func buildAroundTheWorld() async {
        let country = CountryCatalog.countryOfDay
        guard let provider = country.providers.first else { return }
        let results = await TVTMDBService.shared.discoverByProvider(
            providerId: provider.id,
            limit: 10,
            region: country.regionCode,
            originalLanguage: country.effectiveOriginalLanguage(for: provider),
            voteCountGte: country.voteFloor(for: provider),
            withoutKeywords: BrowseCatalog.adultKeywordIds
        )
        guard !results.isEmpty else { return }
        aroundCountry = country
        aroundProviderName = provider.name
        aroundTheWorld = results
    }

    /// Next episode for up to eight followed shows — the phone's cap.
    private func buildUpcomingEpisodes() async {
        let ids = Array(streams.userStreams.compactMap { TVTitleID.tmdbId(from: $0.titleId) }.prefix(8))
        guard !ids.isEmpty else { return }
        let found = await withTaskGroup(of: UpcomingEpisodeItem?.self) { group in
            for id in ids {
                group.addTask {
                    guard let next = await TVTMDBService.shared.getNextEpisode(tmdbId: id) else { return nil }
                    return UpcomingEpisodeItem(tmdbId: id, next: next)
                }
            }
            var out: [UpcomingEpisodeItem] = []
            for await item in group { if let item { out.append(item) } }
            return out
        }
        upcomingEpisodes = found.sorted { ($0.next.airDate ?? "9999") < ($1.next.airDate ?? "9999") }
    }

    /// The phone's hero mix: live games (4), live creators (2), newest
    /// uploads (4), then titles. Titles stay at the TV's own cap — each one
    /// can resolve a trailer, and that is the work that once exhausted the
    /// Apple TV's memory.
    private func composeHeroEntries() {
        var entries: [TVHeroEntry] = []
        for game in sports
            .filter({ $0.state == .live })
            .sorted(by: { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) })
            .prefix(4) {
            entries.append(.game(game))
        }
        let names = Dictionary(streams.userStreams.map { ($0.titleId, $0.title ?? "") }, uniquingKeysWith: { a, _ in a })
        let posters = Dictionary(streams.userStreams.map { ($0.titleId, $0.posterUrl) }, uniquingKeysWith: { a, _ in a })
        for live in liveCreators.prefix(2) {
            entries.append(.liveCreator(
                titleId: live.titleId,
                name: names[live.titleId].flatMap { $0.isEmpty ? nil : $0 } ?? "Live now",
                streamTitle: live.streamTitle,
                imageUrl: posters[live.titleId] ?? nil,
                viewers: live.viewerCount
            ))
        }
        for upload in creatorUploads.prefix(4) {
            entries.append(.upload(upload))
        }
        entries.append(contentsOf: heroItems.map { .media($0) })
        heroEntries = entries
    }

    // MARK: - Today's Pick

    /// Single full-width card beneath the hero rails. The day-of-year
    /// ordinal picks the row from the first 10 streaming_releases rows,
    /// advancing past candidates with no poster art.
    private func todaysPickSection(for pick: TVStreamingRelease) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                Capsule()
                    .fill(TVTheme.orange)
                    .frame(width: 6, height: 30)
                    .shadow(color: TVTheme.orange.opacity(0.65), radius: 10)
                Text("Today's Pick")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 80)

            GeometryReader { proxy in
                let size = Self.todaysPickSize(available: proxy.size.width)
                todaysPickCard(for: pick, width: size.width, height: size.height)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: Self.todaysPickHeight)
            .padding(.horizontal, 80)
            // A single card between two horizontal rails needs its own focus
            // section, or up/down can step straight past it.
            .focusSection()
        }
        .task(id: pick.tmdbId) { await resolveTodaysPickBackdrop(for: pick) }
    }

    /// The banner runs the full width of the row now, like every rail beside
    /// it, at a 2.4:1 billboard aspect.
    ///
    /// The history matters. It was once stretched to the full row at roughly
    /// 4:1, which sheared the top and bottom off a 16:9 backdrop and kept
    /// delivering the pick with its subject beheaded. The fix at the time was
    /// to lock it to 16:9 and cap it at 1200pt — which stopped the cropping but
    /// left the banner visibly narrower than the rails above and below it.
    ///
    /// 2.4:1 takes about a quarter off a 16:9 frame, an ordinary billboard crop
    /// rather than a beheading, and only the resolved TMDB backdrop is ever
    /// cropped at all: the poster fallback still renders whole on its blurred
    /// bed, which is the case the `.fit` rule was written for. Height is capped
    /// so Top Picks still peeks above the fold.
    private static let todaysPickAspect: CGFloat = 2.4
    private static let todaysPickMaxHeight: CGFloat = 700

    /// Fixed row height, so the GeometryReader's container does not depend on
    /// the width it is trying to measure.
    private static let todaysPickHeight: CGFloat = todaysPickMaxHeight

    private static func todaysPickSize(available: CGFloat) -> CGSize {
        let width = max(available, 1)
        return CGSize(width: width, height: min((width / todaysPickAspect).rounded(), todaysPickMaxHeight))
    }

    /// Resolves the pick's TMDB backdrop once per title. Failures are silent:
    /// the poster fallback renders whole, so there is nothing to report.
    private func resolveTodaysPickBackdrop(for pick: TVStreamingRelease) async {
        guard todaysPickBackdropTmdbId != pick.tmdbId else { return }
        todaysPickBackdropTmdbId = pick.tmdbId
        todaysPickBackdropUrl = nil
        let path = await TVTMDBService.shared.getBackdropPath(tmdbId: pick.tmdbId, isTV: pick.isTV)
        guard todaysPickBackdropTmdbId == pick.tmdbId else { return }
        todaysPickBackdropUrl = TVTMDBImage.url(path, size: .backdrop1280)
    }

    /// Full-width TVWideCard for the daily pick — shows the title, the
    /// source name, a Subscribed marker when the source is a subscribed
    /// service, and opens TVTitleSheet through the shared pendingDetail
    /// path.
    private func todaysPickCard(for pick: TVStreamingRelease, width: CGFloat, height: CGFloat) -> some View {
        let posterUrl = pick.posterUrl?.isEmpty == false
            ? pick.posterUrl
            : TVTMDBImage.url(pick.posterPath, size: .poster500)
        let titleId = "tmdb:\(pick.isTV ? "tv" : "movie"):\(pick.tmdbId)"
        let isSubscribed = pick.sourceName.map {
            AuthViewModel.shared.subscribesToService(named: $0)
        } ?? false
        // `.fill` only once the 16:9 TMDB backdrop has resolved — landscape
        // art survives a billboard crop. Until then the image is the 2:3
        // poster, and filling a portrait poster into a wide box is precisely
        // what cut faces in half, so that case stays `.fit` on its blurred bed.
        let hasBackdrop = !(todaysPickBackdropUrl ?? "").isEmpty
        return TVWideCard(
            title: pick.title,
            subtitle: pick.sourceName,
            backdropUrl: todaysPickBackdropUrl ?? posterUrl,
            accent: TVTheme.orange,
            isSaved: streams.contains(titleId: titleId),
            width: width,
            height: height,
            imageContentMode: hasBackdrop ? .fill : .fit,
            usesFlatFocus: true
        ) {
            pendingDetail = TVTitleDetail(
                titleId: titleId,
                title: pick.title,
                overview: nil,
                posterUrl: posterUrl,
                backdropUrl: nil,
                tag: pick.isTV ? "SERIES" : "MOVIE",
                accent: TVTheme.orange,
                year: nil,
                platform: nil,
                isTVHint: pick.isTV
            )
        }
        .overlay(alignment: .topLeading) {
            if isSubscribed {
                Text("SUBSCRIBED")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(TVTheme.orange, in: Capsule())
                    .padding(16)
            }
        }
    }

    // MARK: - Top Picks for You

    /// Ranked from the provider-resolved trending items: watched titles are
    /// excluded, each item scores 0.60 × (voteAverage/10) plus 0.20 when
    /// the resolved provider is a subscribed service. Sorted by score
    /// descending (trending rank breaks ties), capped at 20.
    private var topPicks: [TopPickItem] {
        let ranked = everyonesWatching.compactMap { item -> TopPickItem? in
            guard let providerName = item.providerName else { return nil }
            guard !SocialViewModel.shared.isWatched(item.result.canonicalTitleId) else { return nil }
            var score = 0.60 * ((item.result.voteAverage ?? 7.0) / 10.0)
            if AuthViewModel.shared.subscribesToService(named: providerName) {
                score += 0.20
            }
            return TopPickItem(
                result: item.result,
                providerName: providerName,
                score: score,
                rank: item.rank
            )
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.rank < rhs.rank
        }
        return Array(ranked.prefix(20))
    }

    private func topPickCard(for item: TopPickItem) -> some View {
        TVPosterCard(
            title: item.result.displayName,
            subtitle: "\(item.matchPercent)% Match",
            posterUrl: item.result.posterUrl,
            accent: TVTheme.orange,
            isSaved: streams.contains(titleId: item.result.canonicalTitleId)
        ) {
            pendingDetail = TVTitleDetail(
                titleId: item.result.canonicalTitleId,
                title: item.result.displayName,
                overview: item.result.overview,
                posterUrl: item.result.posterUrl,
                backdropUrl: item.result.backdropUrl,
                tag: item.result.isTV ? "SERIES" : "MOVIE",
                accent: TVTheme.orange,
                year: item.result.year,
                platform: nil,
                isTVHint: item.result.isTV
            )
        }
    }

    // MARK: - Continue Watching

    private func continueWatchingCard(for item: ContinueWatchingItem) -> some View {
        TVPosterCard(
            title: item.row.titleName,
            subtitle: item.subtitle,
            posterUrl: item.posterUrl,
            accent: item.accent,
            isSaved: streams.contains(titleId: item.titleId)
        ) {
            pendingDetail = TVTitleDetail(
                titleId: item.titleId,
                title: item.row.titleName,
                overview: nil,
                posterUrl: item.posterUrl,
                backdropUrl: nil,
                tag: item.row.isTV ? "SERIES" : "MOVIE",
                accent: item.accent,
                year: nil,
                platform: item.service?.name,
                isTVHint: item.row.isTV
            )
        }
    }

    private var continueWatchingGridItems: [TVSeeAllGridItem] {
        continueWatching.map { item in
            TVSeeAllGridItem(
                titleId: item.titleId,
                title: item.row.titleName,
                subtitle: item.subtitle,
                posterUrl: item.posterUrl,
                overview: nil,
                backdropUrl: nil,
                tag: item.row.isTV ? "SERIES" : "MOVIE",
                year: nil,
                isTVHint: item.row.isTV
            )
        }
    }

    /// Loads the Continue Watching rows and resolves a poster for each. The view
    /// returns no artwork — it is built from analytics rows — so each title
    /// needs one TMDB lookup, run concurrently and capped at the 20 rows the
    /// view already limits to. A row whose poster fails to resolve is kept
    /// and renders on TVPosterCard's placeholder rather than being dropped.
    private func buildContinueWatching() async {
        guard let rows = await TVContinueWatchingService.shared.fetch(), !rows.isEmpty else {
            continueWatching = []
            return
        }
        // Only the poster path is resolved off the main actor; the items
        // themselves are built below, so nothing non-Sendable crosses the
        // task-group boundary.
        let paths = await withTaskGroup(of: (Int, String?).self) { group in
            for (index, row) in rows.enumerated() {
                let tmdbId = row.tmdbId
                let isTV = row.isTV
                group.addTask {
                    let path: String? = isTV
                        ? await TVTMDBService.shared.getTVFreshness(tmdbId: tmdbId).posterPath
                        : await TVTMDBService.shared.getMoviePosterPath(tmdbId: tmdbId)
                    return (index, path)
                }
            }
            var out: [Int: String?] = [:]
            for await (index, path) in group { out[index] = path }
            return out
        }

        continueWatching = rows.enumerated().map { index, row in
            let service = row.platformId.flatMap { id in
                StreamingCatalog.all.first { $0.id == id.lowercased() }
            }
            return ContinueWatchingItem(
                row: row,
                posterUrl: TVTMDBImage.url(paths[index] ?? nil, size: .poster500),
                service: service
            )
        }
        // This rail is above the fold and arrives on its own task, so a
        // snapshot written by loadAll before it landed is refreshed here.
        persistHomeSnapshot()
    }

    // MARK: - Cards

    private func posterCard(for item: TVTMDBResult, accent: Color) -> some View {
        TVPosterCard(
            title: item.displayName,
            subtitle: item.isTV ? "Series" : "Movie",
            posterUrl: item.posterUrl,
            accent: accent,
            isSaved: streams.contains(titleId: item.canonicalTitleId)
        ) {
            pendingDetail = TVTitleDetail(
                titleId: item.canonicalTitleId,
                title: item.displayName,
                overview: item.overview,
                posterUrl: item.posterUrl,
                backdropUrl: item.backdropUrl,
                tag: item.isTV ? "SERIES" : "MOVIE",
                accent: accent,
                year: item.year,
                platform: nil,
                isTVHint: item.isTV
            )
        }
    }

    /// Everyone's Watching card — shows the provider name as subtitle and a
    /// "#rank" badge in the top-leading corner, mirroring the watched-badge
    /// overlay pattern from TVWatchListView.
    private func everyonesWatchingCard(for item: EveryonesWatchingItem) -> some View {
        TVPosterCard(
            title: item.result.displayName,
            subtitle: item.providerName,
            posterUrl: item.result.posterUrl,
            accent: TVTheme.orange,
            isSaved: streams.contains(titleId: item.result.canonicalTitleId)
        ) {
            pendingDetail = TVTitleDetail(
                titleId: item.result.canonicalTitleId,
                title: item.result.displayName,
                overview: item.result.overview,
                posterUrl: item.result.posterUrl,
                backdropUrl: item.result.backdropUrl,
                tag: item.result.isTV ? "SERIES" : "MOVIE",
                accent: TVTheme.orange,
                year: item.result.year,
                platform: nil,
                isTVHint: item.result.isTV
            )
        }
        .overlay(alignment: .topLeading) {
            Text("#\(item.rank)")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(TVTheme.orange, in: Capsule())
                .padding(12)
                .shadow(color: .black.opacity(0.6), radius: 8)
        }
    }

    /// Coming to Streaming card — shows the badge text as subtitle and opens
    /// the title sheet with `isTVHint: false` (these are movies).
    private func comingToStreamingCard(for item: ComingToStreamingItem) -> some View {
        TVPosterCard(
            title: item.result.displayName,
            subtitle: item.badge,
            posterUrl: item.result.posterUrl,
            accent: TVTheme.orange,
            isSaved: streams.contains(titleId: item.result.canonicalTitleId)
        ) {
            pendingDetail = TVTitleDetail(
                titleId: item.result.canonicalTitleId,
                title: item.result.displayName,
                overview: item.result.overview,
                posterUrl: item.result.posterUrl,
                backdropUrl: item.result.backdropUrl,
                tag: "MOVIE",
                accent: TVTheme.orange,
                year: item.result.year,
                platform: nil,
                isTVHint: false
            )
        }
    }

    /// Creator / Podcast card — uses the creator's image URL as the poster
    /// and the category (or match percentage) as the subtitle. Opens
    /// TVTitleSheet with the creator's title_id so `yt:` rows route to the
    /// YouTube app through the sheet's existing path.
    private func creatorCard(for creator: TVRecommendedCreator) -> some View {
        TVPosterCard(
            title: creator.displayName,
            subtitle: creator.category ?? "\(creator.matchPercentage)% match",
            posterUrl: creator.imageUrl,
            accent: TVTheme.blue,
            isSaved: streams.contains(titleId: creator.titleId)
        ) {
            pendingDetail = TVTitleDetail(
                titleId: creator.titleId,
                title: creator.displayName,
                overview: nil,
                posterUrl: creator.imageUrl,
                backdropUrl: nil,
                tag: creator.sourceType.uppercased(),
                accent: TVTheme.blue,
                year: nil,
                platform: nil,
                isTVHint: nil
            )
        }
    }

    // MARK: - Loading placeholders

    private func loadingRail(title: String, accent: Color) -> some View {
        TVRail(title: title, accent: accent, count: nil) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(TVTheme.surface)
                    .frame(width: 260, height: 380)
                    .overlay {
                        TVShimmer()
                            .clipShape(.rect(cornerRadius: 18))
                    }
            }
        }
    }

    /// Now & Next card — shows the NOW or NEXT badge as subtitle and opens
    /// the title sheet with the media-type hint from the streaming_releases
    /// / streaming_upcoming row.
    private func nowNextCard(for item: NowNextItem, accent: Color) -> some View {
        let release = item.release
        let posterUrl = release.posterUrl?.isEmpty == false
            ? release.posterUrl
            : TVTMDBImage.url(release.posterPath, size: .poster500)
        let titleId = "tmdb:\(release.isTV ? "tv" : "movie"):\(release.tmdbId)"
        return TVPosterCard(
            title: release.title,
            subtitle: item.badge,
            posterUrl: posterUrl,
            accent: accent,
            isSaved: streams.contains(titleId: titleId)
        ) {
            pendingDetail = TVTitleDetail(
                titleId: titleId,
                title: release.title,
                overview: nil,
                posterUrl: posterUrl,
                backdropUrl: nil,
                tag: release.isTV ? "SERIES" : "MOVIE",
                accent: accent,
                year: nil,
                platform: nil,
                isTVHint: release.isTV
            )
        }
    }

    // MARK: - Popular on service ordering

    /// Returns subscribed services in StreamingCatalog order, filtered to
    /// those with a TMDB provider id mapping. Used so the rails render in
    /// the same order the user selected their services.
    private var popularOnServiceOrder: [StreamingService] {
        let selected = AuthViewModel.shared.selectedServices
        return StreamingCatalog.ordered(from: selected).filter { tmdbProviderIdMap[$0.id] != nil }
    }

    // MARK: - See-all grid payloads

    /// Grid payloads are built from the arrays the rails already hold in
    /// state — opening a See-all grid never triggers a network call.
    private var everyonesWatchingGridItems: [TVSeeAllGridItem] {
        everyonesWatching.map { item in
            TVSeeAllGridItem(
                titleId: item.result.canonicalTitleId,
                title: item.result.displayName,
                subtitle: item.providerName,
                posterUrl: item.result.posterUrl,
                overview: item.result.overview,
                backdropUrl: item.result.backdropUrl,
                tag: item.result.isTV ? "SERIES" : "MOVIE",
                year: item.result.year,
                isTVHint: item.result.isTV
            )
        }
    }

    private var topPicksGridItems: [TVSeeAllGridItem] {
        topPicks.map { item in
            TVSeeAllGridItem(
                titleId: item.result.canonicalTitleId,
                title: item.result.displayName,
                subtitle: "\(item.matchPercent)% Match",
                posterUrl: item.result.posterUrl,
                overview: item.result.overview,
                backdropUrl: item.result.backdropUrl,
                tag: item.result.isTV ? "SERIES" : "MOVIE",
                year: item.result.year,
                isTVHint: item.result.isTV
            )
        }
    }

    private func popularGridItems(_ items: [TVTMDBResult]) -> [TVSeeAllGridItem] {
        items.map { item in
            TVSeeAllGridItem(
                titleId: item.canonicalTitleId,
                title: item.displayName,
                subtitle: item.isTV ? "Series" : "Movie",
                posterUrl: item.posterUrl,
                overview: item.overview,
                backdropUrl: item.backdropUrl,
                tag: item.isTV ? "SERIES" : "MOVIE",
                year: item.year,
                isTVHint: item.isTV
            )
        }
    }

    private func nowNextGridItems(for rail: NowAndNextRail) -> [TVSeeAllGridItem] {
        rail.items.map { item in
            let release = item.release
            let posterUrl = release.posterUrl?.isEmpty == false
                ? release.posterUrl
                : TVTMDBImage.url(release.posterPath, size: .poster500)
            return TVSeeAllGridItem(
                titleId: "tmdb:\(release.isTV ? "tv" : "movie"):\(release.tmdbId)",
                title: release.title,
                subtitle: item.badge,
                posterUrl: posterUrl,
                overview: nil,
                backdropUrl: nil,
                tag: release.isTV ? "SERIES" : "MOVIE",
                year: nil,
                isTVHint: release.isTV
            )
        }
    }

    // MARK: - Data loading

    private func loadAll() async {
        restoreHomeSnapshot()
        isLoading = true
        async let trendingTask = (try? TVTMDBService.shared.getTrending()) ?? []
        async let newEpisodesTask = (try? TVTMDBService.shared.getOnTheAir()) ?? []
        async let sportsTask = TVSportsService.shared.fetchAll()
        async let watchTask: Void = TVStreamsViewModel.shared.fetchUserStreams()
        async let watchedTask: Void = SocialViewModel.shared.loadAllWatched()
        async let endedTask = TVTMDBService.shared.getEndedSeries()

        let (t, ne, sp, _, _, ended) = await (trendingTask, newEpisodesTask, sportsTask, watchTask, watchedTask, endedTask)
        self.trending = t
        self.newEpisodes = ne
        self.endedShows = ended
        self.sports = sp
        self.isLoading = false

        // Only the hero pool gates the rails, as on the phone (930acc7): the
        // 18 hero candidates are resolved here, and Everyone's Watching and the
        // parity rails resolve the rest in their own builds, behind the hero.
        // Titles already known (snapshot, or an earlier pass) cost nothing.
        // This used to pre-resolve Everyone's 25 too — ~6 waves of 8 before
        // any rail could build on a cold launch.
        var heroSeen = Set<Int>()
        let heroPool = (t + ne + ended).filter { heroSeen.insert($0.id).inserted }
        await hydrateProviderNames(for: Array(heroPool.prefix(18)))

        // Build hero and new rails concurrently after base data lands.
        async let heroTask: Void = buildHeroItems()
        async let everyoneTask: Void = buildEveryonesWatching(from: t)
        async let comingTask: Void = buildComingToStreaming()
        async let popularTask: Void = buildPopularOnService()
        async let creatorsTask: Void = buildRecommendedCreators()
        async let recommendedTask: Void = buildRecommendedTitles()
        async let nowNextTask: Void = buildNowAndNext()
        async let todaysPickTask: Void = buildTodaysPick()
        async let affiliateTask: Void = TVAffiliateService.shared.fetchIfNeeded()
        async let parityTask: Void = buildParityRails()

        _ = await (heroTask, everyoneTask, comingTask, popularTask, creatorsTask, nowNextTask, todaysPickTask, affiliateTask, parityTask)
        _ = await recommendedTask
        persistHomeSnapshot()
    }

    // MARK: - Snapshot

    /// Paints the last load before the first request goes out. Only when this
    /// screen has nothing yet, so a pull of fresh data is never overwritten
    /// by a stale file.
    private func restoreHomeSnapshot() {
        guard trending.isEmpty, heroItems.isEmpty,
              let snap = TVHomeSnapshotStore.load(TVHomeSnapshot.self),
              !snap.trending.isEmpty else { return }
        trending = snap.trending
        newEpisodes = snap.onAir
        endedShows = snap.ended
        topRated = snap.topRated
        providerNames = snap.providerNames
        heroItems = snap.heroItems
        heroFeaturettes = snap.heroFeaturettes
        continueWatching = snap.continueWatching.map { c in
            ContinueWatchingItem(
                row: c.row,
                posterUrl: c.posterUrl,
                service: c.serviceId.flatMap { id in StreamingCatalog.all.first { $0.id == id } }
            )
        }
        recommendedTitles = snap.recommendedTitles
        todaysPick = snap.todaysPick
        todaysPickBackdropUrl = snap.todaysPickBackdropUrl
        everyonesWatching = snap.everyonesWatching
        popularOnService = snap.popularOnService
        nowAndNextRails = snap.nowAndNext.compactMap { rail in
            guard let service = StreamingCatalog.all.first(where: { $0.id == rail.serviceId }) else { return nil }
            return NowAndNextRail(service: service, items: rail.items)
        }
        comingToStreaming = snap.comingToStreaming
        recommendedCreators = snap.recommendedCreators
        followedNewEpisodes = snap.followedNewEpisodes
        newThisWeek = snap.newThisWeek
        leavingSoon = snap.leavingSoon
        upcomingEpisodes = snap.upcomingEpisodes
        aroundTheWorld = snap.aroundTheWorld
        aroundCountry = snap.aroundRegionCode.flatMap { CountryCatalog.entry(forRegionCode: $0) }
        aroundProviderName = snap.aroundProviderName
        composeHeroEntries()
        heroLoading = false
        isLoading = false
        #if DEBUG
        print("[home] painted from snapshot: \(heroItems.count) hero, \(everyonesWatching.count) everyone's, \(providerNames.count) providers")
        #endif
    }

    /// Writes what is on screen now. Called after a full load and after
    /// Continue Watching lands, which arrives on its own auth-keyed task.
    private func persistHomeSnapshot() {
        guard !trending.isEmpty, !heroItems.isEmpty else { return }
        var snap = TVHomeSnapshot()
        snap.trending = trending
        snap.onAir = newEpisodes
        snap.ended = endedShows
        snap.topRated = topRated
        snap.providerNames = providerNames
        snap.heroItems = heroItems
        snap.heroFeaturettes = heroFeaturettes
        snap.continueWatching = continueWatching.map {
            TVHomeSnapshot.ContinueRow(row: $0.row, posterUrl: $0.posterUrl, serviceId: $0.service?.id)
        }
        snap.recommendedTitles = recommendedTitles
        snap.todaysPick = todaysPick
        snap.todaysPickBackdropUrl = todaysPickBackdropUrl
        snap.everyonesWatching = everyonesWatching
        snap.popularOnService = popularOnService
        snap.nowAndNext = nowAndNextRails.map { TVHomeSnapshot.NowNext(serviceId: $0.service.id, items: $0.items) }
        snap.comingToStreaming = comingToStreaming
        snap.recommendedCreators = recommendedCreators
        snap.followedNewEpisodes = followedNewEpisodes
        snap.newThisWeek = newThisWeek
        snap.leavingSoon = leavingSoon
        snap.upcomingEpisodes = upcomingEpisodes
        snap.aroundTheWorld = aroundTheWorld
        snap.aroundRegionCode = aroundCountry?.regionCode
        snap.aroundProviderName = aroundProviderName
        TVHomeSnapshotStore.save(snap)
    }

    /// Loads the "Recommended for You" rail from the `recommend_titles` edge
    /// function.
    ///
    /// The server owns both the scoring and the freshness: it keys a cache on a
    /// fingerprint of this viewer's signals, so calling it on every Home load
    /// is one round trip and no TMDB calls when nothing has changed, and a
    /// rebuild the moment something has. Nothing here polls.
    private func buildRecommendedTitles() async {
        let services = Array(AuthViewModel.shared.selectedServices)
        guard !services.isEmpty else {
            recommendedTitles = []
            return
        }
        recommendedTitles = await TVRecommendedTitlesService.fetch(
            userId: AuthViewModel.shared.currentUser?.id.uuidString,
            deviceId: TVDeviceIdentity.shared.deviceId,
            subscribedServices: services
        )
    }

    // MARK: - Today's Pick resolution

    /// Fetches the same streaming_releases rows the Now & Next NOW badge
    /// reads and resolves the deterministic daily pick. A nil or empty
    /// fetch leaves the section omitted entirely.
    private func buildTodaysPick() async {
        guard let releases = await TVStreamingReleasesService.shared.fetchReleases() else { return }
        todaysPick = resolveTodaysPick(from: releases)
    }

    /// Day-of-year ordinal into the first 10 rows (in returned order),
    /// advancing to the next index modulo count while the candidate's
    /// posterUrl and posterPath are both empty.
    private func resolveTodaysPick(from releases: [TVStreamingRelease]) -> TVStreamingRelease? {
        let pool = Array(releases.prefix(10))
        guard !pool.isEmpty else { return nil }
        let count = pool.count
        let dayOrdinal = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        let startIndex = dayOrdinal % count
        var index = startIndex
        for _ in 0..<count {
            let candidate = pool[index]
            let hasArt = (candidate.posterUrl?.isEmpty == false)
                || (candidate.posterPath?.isEmpty == false)
            if hasArt { return candidate }
            index = (index + 1) % count
        }
        // Every candidate lacks art — fall back to the day's row.
        return pool[startIndex]
    }

    // MARK: - Sponsored chips

    /// Resolves a sponsored chip for the Now & Next rail: walks the items
    /// across all Now & Next rails, finds the first whose `sourceName`
    /// resolves to a gap-service advertiser with a non-nil `appStoreURL`,
    /// and returns a `SponsoredChipData` if one hasn't already been shown.
    /// Deduplicates against the Everyone's Watching chip so the same
    /// advertiser key never appears twice on one screen.
    private var nowNextSponsoredChip: SponsoredChipData? {
        for rail in nowAndNextRails {
            for item in rail.items {
                let providerName = item.release.sourceName
                guard let advertiser = TVAffiliateService.shared.advertiser(forProviderName: providerName) else { continue }
                guard advertiser.appStoreURL != nil else { continue }
                guard TVAffiliateService.shared.isGapService(providerName) else { continue }
                let titleId = "tmdb:\(item.release.isTV ? "tv" : "movie"):\(item.release.tmdbId)"
                let chip = SponsoredChipData(
                    advertiser: advertiser,
                    titleName: item.release.title,
                    titleId: titleId,
                    providerName: providerName,
                    surface: "home_now_next"
                )
                return chip
            }
        }
        return nil
    }

    /// Resolves a sponsored chip for the Everyone's Watching rail: walks
    /// the items, finds the first whose `providerName` resolves to a
    /// gap-service advertiser with a non-nil `appStoreURL`, and returns a
    /// `SponsoredChipData` if that advertiser key isn't already used by
    /// the Now & Next chip. Maximum two chips per screen.
    private var everyonesWatchingSponsoredChip: SponsoredChipData? {
        let nowNextKey = nowNextSponsoredChip?.advertiser.key
        for item in everyonesWatching {
            guard let providerName = item.providerName else { continue }
            guard let advertiser = TVAffiliateService.shared.advertiser(forProviderName: providerName) else { continue }
            guard advertiser.appStoreURL != nil else { continue }
            guard TVAffiliateService.shared.isGapService(providerName) else { continue }
            if let nowNextKey, advertiser.key == nowNextKey { continue }
            let chip = SponsoredChipData(
                advertiser: advertiser,
                titleName: item.result.displayName,
                titleId: item.result.canonicalTitleId,
                providerName: providerName,
                surface: "home_everyones_watching"
            )
            return chip
        }
        return nil
    }

    // MARK: - Hero assembly

    /// Builds a hero carousel pool from `trending` then `newEpisodes`, deduped by
    /// TMDB id (trending priority), capped at 18 candidates, and filtered to
    /// titles that have at least one real US streaming provider resolved via
    /// `getTopWatchProvider`. Theatrical-only titles are dropped. Falls back to
    /// the raw trending prefix when no candidates resolve so the hero never
    /// renders as a permanently empty grey slab.
    private func buildHeroItems() async {
        var seenIds = Set<Int>()
        var pool: [TVTMDBResult] = []
        for candidate in trending + newEpisodes + endedShows {
            if seenIds.insert(candidate.id).inserted {
                pool.append(candidate)
            }
        }
        let candidates = Array(pool.prefix(18))

        // Was one request at a time, up to 18 in a row, before the hero could
        // appear. Now one wave, and titles whose provider is already known
        // (snapshot, or another rail) cost nothing.
        await hydrateProviderNames(for: candidates)
        var survivors: [TVTMDBResult] = []
        for candidate in candidates where providerNames[candidate.id] != nil {
            if survivors.count >= 6 { break }
            survivors.append(candidate)
        }

        // Titles that resolve a provider in the user's own region lead, since
        // the hero's job is "you can watch this tonight". With the US fallback
        // gone a small market may resolve only two or three, so the rest of the
        // pool tops it up — a card without a badge beats a hero with one card.
        if survivors.count < 6 {
            let taken = Set(survivors.map(\.id))
            survivors.append(contentsOf: candidates.filter { !taken.contains($0.id) }.prefix(6 - survivors.count))
        }
        heroItems = survivors.isEmpty ? Array(trending.prefix(6)) : survivors
        composeHeroEntries()
        heroLoading = false

        // Video for the hero, in priority order. A hosted featurette is
        // authoritative when one exists; otherwise fall back to the YouTube
        // trailer already cached for that title, resolved to a direct stream
        // because tvOS has no web view to embed a player in. Items that
        // resolve to neither render as drifting stills.
        let featurettePool = heroItems.map { (tmdbId: $0.id, isTV: $0.isTV) }
        #if DEBUG
        print("[hero] pool=\(heroItems.count) titles: \(heroItems.map(\.displayName).joined(separator: ", "))")
        #endif
        // Hosted first, and on its own. These two used to run concurrently,
        // which meant every title paid for a YouTubeKit resolve even when a
        // hosted clip was going to win the merge anyway — roughly a second of
        // JavaScriptCore descrambling each, and the same work that once blew
        // the 2GB per-app limit on a real Apple TV and got the app killed.
        // Extraction now only sees the titles nothing else can serve, so
        // filling title_featurettes buys back its own cost.
        //
        // The trade is one Supabase round trip (~100ms, a single batched
        // query) no longer overlapping extraction. Worth it: that is the
        // floor, while extraction is seconds and the thing that fails.
        let hosted = await TVFeaturetteService.shared.fetchFeaturettes(for: featurettePool)
        let needsTrailer = heroItems
            .filter { hosted[$0.canonicalTitleId] == nil }
            .map { (tmdbId: $0.id, isTV: $0.isTV) }
        let trailers = needsTrailer.isEmpty
            ? [:]
            : await TVTrailerStreamService.shared.fetchTrailerStreams(for: needsTrailer)
        heroFeaturettes = trailers.merging(hosted) { _, hostedURL in hostedURL }
        #if DEBUG
        print("[hero] video resolved for \(heroFeaturettes.count)/\(heroItems.count) — "
              + "hosted=\(hosted.count) extracted=\(trailers.count) of \(needsTrailer.count) attempted")
        #endif
    }

    // MARK: - Everyone's Watching

    /// Builds the Everyone's Watching rail by resolving the top watch provider
    /// for the first ~25 trending items concurrently, keeping only items with
    /// a non-nil provider. Each item gets its one-based rank from its position
    /// in the full de-duplicated trending array, capped at 20.
    private func buildEveryonesWatching(from trendingItems: [TVTMDBResult]) async {
        let candidates = Array(trendingItems.prefix(25))
        // Shares the provider map with the hero and the parity rails, so a
        // title looked up once this launch is never looked up again.
        await hydrateProviderNames(for: candidates)
        var items: [EveryonesWatchingItem] = []
        for (index, result) in candidates.enumerated() {
            let providerName = providerNames[result.id]
            guard providerName != nil else { continue }
            let rank = index + 1
            if items.count >= 20 { break }
            items.append(EveryonesWatchingItem(result: result, rank: rank, providerName: providerName))
        }
        everyonesWatching = items
    }

    // MARK: - Coming to Streaming

    /// Builds the Coming to Streaming rail from now-playing movies. For each
    /// movie, fetches the US digital release date; when a future digital date
    /// exists, produces a dated item badged with the short date and the release
    /// note (or "Streaming soon"). When no future digital date exists but the
    /// movie's theatrical release is at least 30 days old, produces a heuristic
    /// item badged "Coming soon" with meta "In theaters now". Dated items sort
    /// earliest-first, ahead of heuristic ones, capped at 20.
    private func buildComingToStreaming() async {
        let movies = await TVTMDBService.shared.getNowPlayingMovies()
        let candidates = Array(movies.prefix(24))

        let results = await withTaskGroup(of: ComingToStreamingItem?.self) { group in
            for movie in candidates {
                group.addTask {
                    let digital = await TVTMDBService.shared.getUSDigitalReleaseDate(movieId: movie.id)
                    if let digital {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "MMM d"
                        let badge = formatter.string(from: digital.date)
                        let meta = digital.note ?? "Streaming soon"
                        return ComingToStreamingItem(
                            result: movie,
                            badge: badge,
                            meta: meta,
                            sortKey: digital.date
                        )
                    }
                    // Heuristic: theatrical release at least 30 days old.
                    let releaseDate = movie.releaseDate ?? movie.firstAirDate
                    if let dateStr = releaseDate, dateStr.count >= 10 {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        formatter.locale = Locale(identifier: "en_US_POSIX")
                        if let release = formatter.date(from: String(dateStr.prefix(10))) {
                            let daysOld = Date().timeIntervalSince(release) / 86400
                            if daysOld >= 30 {
                                return ComingToStreamingItem(
                                    result: movie,
                                    badge: "Coming soon",
                                    meta: "In theaters now",
                                    sortKey: .distantFuture
                                )
                            }
                        }
                    }
                    return nil
                }
            }
            var collected: [ComingToStreamingItem] = []
            for await item in group {
                if let item { collected.append(item) }
            }
            return collected
        }

        let sorted = results.sorted { $0.sortKey < $1.sortKey }
        comingToStreaming = Array(sorted.prefix(20))
    }

    // MARK: - Popular on service

    /// For each subscribed service with a TMDB provider id mapping, fetches
    /// popular TV and popular movies concurrently, interleaving show, movie,
    /// show, movie up to 12 items, and stores non-empty results under the
    /// service id.
    private func buildPopularOnService() async {
        let services = popularOnServiceOrder
        guard !services.isEmpty else { return }

        let results = await withTaskGroup(of: (String, [TVTMDBResult]).self) { group in
            for service in services {
                guard let providerId = tmdbProviderIdMap[service.id] else { continue }
                group.addTask {
                    async let shows = TVTMDBService.shared.getPopularOnService(tmdbProviderId: providerId)
                    async let movies = TVTMDBService.shared.getPopularMoviesOnService(tmdbProviderId: providerId)
                    let (s, m) = await (shows, movies)
                    // Interleave show, movie, show, movie up to 12.
                    var interleaved: [TVTMDBResult] = []
                    let maxCount = max(s.count, m.count)
                    for i in 0..<maxCount {
                        if interleaved.count >= 12 { break }
                        if i < s.count { interleaved.append(s[i]) }
                        if interleaved.count >= 12 { break }
                        if i < m.count { interleaved.append(m[i]) }
                    }
                    return (service.id, interleaved)
                }
            }
            var collected: [(String, [TVTMDBResult])] = []
            for await item in group { collected.append(item) }
            return collected
        }

        var map: [String: [TVTMDBResult]] = [:]
        for (serviceId, items) in results {
            if !items.isEmpty { map[serviceId] = items }
        }
        popularOnService = map
    }

    // MARK: - Now & Next on {service}

    /// Fetches streaming_releases (NOW) and streaming_upcoming (NEXT) from
    /// Supabase, filters by each subscribed service's TMDB provider id, and
    /// builds one rail per service that has at least one row. Reads services
    /// fresh on each load from AuthViewModel.shared.selectedServices.
    private func buildNowAndNext() async {
        let services = StreamingCatalog.ordered(from: AuthViewModel.shared.selectedServices)
            .filter { tmdbProviderIdMap[$0.id] != nil }
        guard !services.isEmpty else { return }

        async let releasesResult = TVStreamingReleasesService.shared.fetchReleases()
        async let upcomingResult = TVStreamingReleasesService.shared.fetchUpcoming()

        let releases = await releasesResult ?? []
        let upcoming = await upcomingResult ?? []

        var rails: [NowAndNextRail] = []
        for service in services {
            guard let providerId = tmdbProviderIdMap[service.id] else { continue }

            var items: [NowNextItem] = []

            // NOW: releases matching this service
            for release in releases where release.sourceId == providerId {
                items.append(NowNextItem(release: release, badge: "NOW"))
            }

            // NEXT: upcoming matching this service
            for release in upcoming where release.sourceId == providerId {
                items.append(NowNextItem(release: release, badge: "NEXT"))
            }

            if !items.isEmpty {
                rails.append(NowAndNextRail(service: service, items: items))
            }
        }

        nowAndNextRails = rails
    }

    // MARK: - Recommended creators

    /// Builds the Creators/Podcasts for You rail by collecting the user's
    /// followed non-TMDB title_ids and passing them to
    /// `TVContentSourcesService.fetchRecommendedCreators`.
    private func buildRecommendedCreators() async {
        let followedIds = streams.userStreams
            .map { $0.titleId }
            .filter { TVTitleID.tmdbId(from: $0) == nil }
        guard !followedIds.isEmpty else { return }
        let creators = await TVContentSourcesService.fetchRecommendedCreators(forFollowedIds: followedIds)
        recommendedCreators = creators
    }
}

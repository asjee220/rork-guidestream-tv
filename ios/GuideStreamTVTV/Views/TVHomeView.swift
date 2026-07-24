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

// MARK: - Rail item structs

private struct EveryonesWatchingItem: Identifiable {
    let result: TVTMDBResult
    let rank: Int
    let providerName: String?
    var id: Int { result.id }
}

private struct ComingToStreamingItem: Identifiable {
    let result: TVTMDBResult
    let badge: String
    let meta: String
    /// Sort key: dated items use the digital release date timestamp so
    /// earliest-first ordering is correct; heuristic items sort after all
    /// dated items via `.distantFuture`.
    let sortKey: Date
    var id: Int { result.id }
}

struct TVHomeView: View {
    @State private var trending: [TVTMDBResult] = []
    @State private var newEpisodes: [TVTMDBResult] = []
    @State private var sports: [TVSportsGame] = []
    @State private var isLoading: Bool = true
    @State private var heroItems: [TVTMDBResult] = []
    @State private var heroLoading: Bool = true

    @State private var pendingDetail: TVTitleDetail?

    @State private var streams = TVStreamsViewModel.shared

    // New rails
    @State private var everyonesWatching: [EveryonesWatchingItem] = []
    @State private var comingToStreaming: [ComingToStreamingItem] = []
    @State private var popularOnService: [String: [TVTMDBResult]] = [:]
    @State private var recommendedCreators: [TVRecommendedCreator] = []

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
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 56) {
                heroSection
                    .padding(.top, 8)

                // 1. Everyone's Watching
                if !everyonesWatching.isEmpty {
                    TVRail(title: "Everyone's Watching", accent: TVTheme.orange, count: everyonesWatching.count) {
                        ForEach(everyonesWatching) { item in
                            everyonesWatchingCard(for: item)
                        }
                    }
                }

                // 2. New Episodes (unchanged)
                if !newEpisodes.isEmpty {
                    TVRail(title: "New Episodes", accent: TVTheme.blue, count: newEpisodes.count) {
                        ForEach(newEpisodes) { item in
                            posterCard(for: item, accent: TVTheme.blue)
                        }
                    }
                }

                // 3. Coming to Streaming
                if !comingToStreaming.isEmpty {
                    TVRail(title: "Coming to Streaming", accent: TVTheme.orange, count: comingToStreaming.count) {
                        ForEach(comingToStreaming) { item in
                            comingToStreamingCard(for: item)
                        }
                    }
                }

                // 4. Popular on {service} — one rail per subscribed service
                ForEach(popularOnServiceOrder, id: \.id) { service in
                    if let items = popularOnService[service.id], !items.isEmpty {
                        TVRail(title: "Popular on \(service.name)", accent: service.color, count: items.count) {
                            ForEach(items) { item in
                                posterCard(for: item, accent: service.color)
                            }
                        }
                    }
                }

                // 5. Creators / Podcasts for You
                if !recommendedCreators.isEmpty {
                    TVRail(title: "Creators / Podcasts for You", accent: TVTheme.blue, count: recommendedCreators.count) {
                        ForEach(recommendedCreators) { creator in
                            creatorCard(for: creator)
                        }
                    }
                }

                // 6. Live Sports (unchanged)
                if !sports.isEmpty {
                    TVRail(title: "Live Sports", accent: TVTheme.blue, count: sports.count) {
                        ForEach(sports) { game in
                            TVSportsTile(game: game) { /* read-only for v1 */ }
                        }
                    }
                }

                Color.clear.frame(height: 40)
            }
        }
        .background(TVTheme.backgroundGradient)
        .task { await loadAll() }
        .sheet(item: $pendingDetail) { detail in
            TVTitleSheet(detail: detail) { isSaved in
                pendingDetail = nil
            }
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private var heroSection: some View {
        if heroItems.isEmpty {
            // Reserve the same height so the rails below don't jump
            // when the data lands.
            Rectangle()
                .fill(TVTheme.surface)
                .frame(height: 640)
                .overlay {
                    if heroLoading {
                        ProgressView()
                            .scaleEffect(2)
                            .tint(.white)
                    }
                }
        } else {
            TVHeroCarousel(
                items: heroItems,
                onToggleSave: { item in
                    Task {
                        await streams.toggle(
                            titleId: item.canonicalTitleId,
                            title: item.displayName,
                            posterUrl: item.posterUrl,
                            platform: nil
                        )
                    }
                },
                isSaved: { item in streams.contains(titleId: item.canonicalTitleId) }
            )
        }
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

    // MARK: - Popular on service ordering

    /// Returns subscribed services in StreamingCatalog order, filtered to
    /// those with a TMDB provider id mapping. Used so the rails render in
    /// the same order the user selected their services.
    private var popularOnServiceOrder: [StreamingService] {
        let selected = AuthViewModel.shared.selectedServices
        return StreamingCatalog.ordered(from: selected).filter { tmdbProviderIdMap[$0.id] != nil }
    }

    // MARK: - Data loading

    private func loadAll() async {
        isLoading = true
        async let trendingTask = (try? TVTMDBService.shared.getTrending()) ?? []
        async let newEpisodesTask = (try? TVTMDBService.shared.getOnTheAir()) ?? []
        async let sportsTask = TVSportsService.shared.fetchAll()
        async let watchTask: Void = TVStreamsViewModel.shared.fetchUserStreams()

        let (t, ne, sp, _) = await (trendingTask, newEpisodesTask, sportsTask, watchTask)
        self.trending = t
        self.newEpisodes = ne
        self.sports = sp
        self.isLoading = false

        // Build hero and new rails concurrently after base data lands.
        async let heroTask: Void = buildHeroItems()
        async let everyoneTask: Void = buildEveryonesWatching(from: t)
        async let comingTask: Void = buildComingToStreaming()
        async let popularTask: Void = buildPopularOnService()
        async let creatorsTask: Void = buildRecommendedCreators()

        await (heroTask, everyoneTask, comingTask, popularTask, creatorsTask)
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
        for candidate in trending + newEpisodes {
            if seenIds.insert(candidate.id).inserted {
                pool.append(candidate)
            }
        }
        let candidates = Array(pool.prefix(18))

        var survivors: [TVTMDBResult] = []
        for candidate in candidates {
            if survivors.count >= 6 { break }
            let provider = try? await TVTMDBService.shared.getTopWatchProvider(
                tmdbId: candidate.id,
                isTV: candidate.isTV
            )
            if provider != nil {
                survivors.append(candidate)
            }
        }

        if survivors.isEmpty {
            heroItems = trending.isEmpty ? [] : Array(trending.prefix(6))
        } else {
            heroItems = survivors
        }
        heroLoading = false
    }

    // MARK: - Everyone's Watching

    /// Builds the Everyone's Watching rail by resolving the top watch provider
    /// for the first ~25 trending items concurrently, keeping only items with
    /// a non-nil provider. Each item gets its one-based rank from its position
    /// in the full de-duplicated trending array, capped at 20.
    private func buildEveryonesWatching(from trendingItems: [TVTMDBResult]) async {
        let candidates = Array(trendingItems.prefix(25))
        let results = await withTaskGroup(of: (Int, TVTMDBResult, String?).self) { group in
            for (index, item) in candidates.enumerated() {
                group.addTask {
                    let provider = try? await TVTMDBService.shared.getTopWatchProvider(
                        tmdbId: item.id,
                        isTV: item.isTV
                    )
                    return (index, item, provider?.providerName)
                }
            }
            var collected: [(Int, TVTMDBResult, String?)] = []
            for await item in group { collected.append(item) }
            return collected
        }
        // Sort by original trending position so rank is stable.
        let sorted = results.sorted { $0.0 < $1.0 }
        var items: [EveryonesWatchingItem] = []
        for (index, result, providerName) in sorted {
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

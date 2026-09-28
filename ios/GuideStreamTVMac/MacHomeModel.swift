//
//  MacHomeModel.swift
//  GuideStreamTVMac
//
//  Home's data, in the phone's rail order. The loaders are the tvOS
//  TVHomeView loaders moved into a model, calling the same services, so
//  the three Apple apps build the same Home from the same sources.
//

import Foundation
import SwiftUI

nonisolated struct MacEveryonesItem: Identifiable, Sendable, Codable {
    let result: TVTMDBResult
    let rank: Int
    let providerName: String?
    var id: Int { result.id }
}

nonisolated struct MacComingItem: Identifiable, Sendable, Codable {
    let result: TVTMDBResult
    let badge: String
    let meta: String
    let sortKey: Date
    var id: Int { result.id }
}

struct MacTopPick: Identifiable {
    let result: TVTMDBResult
    let providerName: String
    let score: Double
    let rank: Int
    var matchPercent: Int { Int((min(max(score, 0.50), 0.99) * 100).rounded()) }
    var id: Int { result.id }
}

struct MacContinueItem: Identifiable {
    let row: TVContinueWatchingRow
    let posterUrl: String?
    let service: StreamingService?
    var id: Int { row.tmdbId }
    var titleId: String { "tmdb:\(row.isTV ? "tv" : "movie"):\(row.tmdbId)" }
    var subtitle: String {
        if let service { return "Resume on \(service.name)" }
        return row.isTV ? "Series" : "Movie"
    }
}

/// One card in the hero carousel — the phone's four kinds.
enum MacHeroEntry: Identifiable {
    case media(TVTMDBResult, provider: String?)
    case game(TVSportsGame)
    case liveCreator(titleId: String, name: String, streamTitle: String?, category: String?, imageUrl: String?, viewers: Int?)
    case upload(TVNewEpisodeRow)

    var id: String {
        switch self {
        case .media(let r, _): return "m-\(r.id)"
        case .game(let g): return "g-\(g.id)"
        case .liveCreator(let id, _, _, _, _, _): return "l-\(id)"
        case .upload(let u): return "u-\(u.id)"
        }
    }
}

@MainActor
@Observable
final class MacHomeModel {
    static let shared = MacHomeModel()

    var trending: [TVTMDBResult] = []
    var onAir: [TVTMDBResult] = []
    var ended: [TVTMDBResult] = []
    var sports: [TVSportsGame] = []
    var providerNames: [Int: String] = [:]
    var heroItems: [TVTMDBResult] = []
    var heroEntries: [MacHeroEntry] = []
    var recommendedTitles: [TVRecommendedTitle] = []
    var todaysPick: TVStreamingRelease?
    var todaysPickBackdropUrl: String?
    var followedNewEpisodes: [TVNewEpisodeRow] = []
    var creatorUploads: [TVNewEpisodeRow] = []
    var liveCreators: [TVLiveStatus] = []
    var aroundTheWorld: [TVTMDBResult] = []
    var aroundCountry: CountryCatalogEntry?
    var aroundProviderName: String?
    var comingToStreaming: [MacComingItem] = []
    var newThisWeek: [TVStreamingRelease] = []
    var everyonesWatching: [MacEveryonesItem] = []
    var recommendedCreators: [TVRecommendedCreator] = []
    var leavingSoon: [TVExpiringRow] = []
    var popularOnService: [String: [TVTMDBResult]] = [:]
    var continueWatching: [MacContinueItem] = []
    var isLoading = true
    private var lastLoad: Date?

    /// TMDB watch-provider ids for the Popular-on rails. Keyed by catalog id;
    /// Max appears as both "hbo" (the phone's id) and "max" (older rows).
    static let tmdbProviderIdMap: [String: Int] = [
        "netflix": 8, "prime": 9, "disney": 337, "hbo": 1899, "max": 1899,
        "hulu": 15, "appletv": 350, "paramount": 2303, "peacock": 386,
        "starz": 43, "showtime": 37, "crunchyroll": 283, "youtube": 192,
    ]

    private init() {}

    var popularOnServiceOrder: [StreamingService] {
        StreamingCatalog.ordered(from: AuthViewModel.shared.selectedServices)
            .filter { Self.tmdbProviderIdMap[$0.id] != nil }
    }

    var topPicks: [MacTopPick] {
        everyonesWatching.compactMap { item -> MacTopPick? in
            guard let provider = item.providerName else { return nil }
            guard !SocialViewModel.shared.isWatched(item.result.canonicalTitleId) else { return nil }
            var score = 0.60 * ((item.result.voteAverage ?? 7.0) / 10.0)
            if AuthViewModel.shared.subscribesToService(named: provider) { score += 0.20 }
            return MacTopPick(result: item.result, providerName: provider, score: score, rank: item.rank)
        }
        .sorted { $0.score != $1.score ? $0.score > $1.score : $0.rank < $1.rank }
        .prefix(20)
        .map { $0 }
    }

    /// Loads everything. Re-runs are skipped for 5 minutes unless forced.
    func loadAll(force: Bool = false) async {
        if !force, let lastLoad, Date().timeIntervalSince(lastLoad) < 300 { return }
        lastLoad = Date()
        restoreSnapshot()
        async let trendingTask = (try? TVTMDBService.shared.getTrending()) ?? []
        async let onAirTask = (try? TVTMDBService.shared.getOnTheAir()) ?? []
        async let sportsTask = TVSportsService.shared.fetchAll()
        async let watchTask: Void = TVStreamsViewModel.shared.fetchUserStreams()
        async let watchedTask: Void = SocialViewModel.shared.loadAllWatched()
        async let endedTask = TVTMDBService.shared.getEndedSeries()
        let (t, ne, sp, _, _, en) = await (trendingTask, onAirTask, sportsTask, watchTask, watchedTask, endedTask)
        trending = t
        onAir = ne
        ended = en
        sports = sp
        isLoading = false

        async let heroTask: Void = buildHeroItems()
        async let everyoneTask: Void = buildEveryonesWatching()
        async let comingTask: Void = buildComingToStreaming()
        async let popularTask: Void = buildPopularOnService()
        async let creatorsTask: Void = buildRecommendedCreators()
        async let recommendedTask: Void = buildRecommendedTitles()
        async let pickTask: Void = buildTodaysPick()
        async let parityTask: Void = buildParityRails()
        async let continueTask: Void = buildContinueWatching()
        _ = await (heroTask, everyoneTask, comingTask, popularTask, creatorsTask, recommendedTask, pickTask, parityTask, continueTask)
        persistSnapshot()
    }

    // MARK: - Snapshot (same pattern as iOS HomeSnapshotStore / tvOS TVHomeSnapshotStore)

    /// Paints the last full load before any request goes out, so a warm open
    /// shows Home instantly; the network load then replaces it in place.
    /// Live sports, live creators and creator uploads are left out — they are
    /// time-sensitive.
    private func restoreSnapshot() {
        guard trending.isEmpty, heroItems.isEmpty,
              let snap = TVHomeSnapshotStore.load(MacHomeSnapshot.self),
              !snap.trending.isEmpty else { return }
        trending = snap.trending
        onAir = snap.onAir
        ended = snap.ended
        providerNames = snap.providerNames
        heroItems = snap.heroItems
        recommendedTitles = snap.recommendedTitles
        todaysPick = snap.todaysPick
        todaysPickBackdropUrl = snap.todaysPickBackdropUrl
        everyonesWatching = snap.everyonesWatching
        comingToStreaming = snap.comingToStreaming
        popularOnService = snap.popularOnService
        recommendedCreators = snap.recommendedCreators
        followedNewEpisodes = snap.followedNewEpisodes
        newThisWeek = snap.newThisWeek
        leavingSoon = snap.leavingSoon
        continueWatching = snap.continueWatching.map { c in
            MacContinueItem(row: c.row, posterUrl: c.posterUrl,
                            service: c.serviceId.flatMap { id in StreamingCatalog.all.first { $0.id == id } })
        }
        if !snap.aroundTheWorld.isEmpty {
            aroundTheWorld = snap.aroundTheWorld
            aroundCountry = CountryCatalog.countryOfDay
            aroundProviderName = snap.aroundProviderName
        }
        composeHeroEntries()
        isLoading = false
    }

    private func persistSnapshot() {
        guard !trending.isEmpty, !heroItems.isEmpty else { return }
        var snap = MacHomeSnapshot()
        snap.trending = trending
        snap.onAir = onAir
        snap.ended = ended
        snap.providerNames = providerNames
        snap.heroItems = heroItems
        snap.recommendedTitles = recommendedTitles
        snap.todaysPick = todaysPick
        snap.todaysPickBackdropUrl = todaysPickBackdropUrl
        snap.everyonesWatching = everyonesWatching
        snap.comingToStreaming = comingToStreaming
        snap.popularOnService = popularOnService
        snap.recommendedCreators = recommendedCreators
        snap.followedNewEpisodes = followedNewEpisodes
        snap.newThisWeek = newThisWeek
        snap.leavingSoon = leavingSoon
        snap.continueWatching = continueWatching.map {
            MacHomeSnapshot.ContinueRow(row: $0.row, posterUrl: $0.posterUrl, serviceId: $0.service?.id)
        }
        snap.aroundTheWorld = aroundTheWorld
        snap.aroundProviderName = aroundProviderName
        TVHomeSnapshotStore.save(snap)
    }

    // MARK: - Builders (ported from TVHomeView)

    private func hydrateProviderNames(for items: [TVTMDBResult]) async {
        var seen = Set<Int>()
        let todo = items.filter { providerNames[$0.id] == nil && seen.insert($0.id).inserted }
        guard !todo.isEmpty else { return }
        let found = await withTaskGroup(of: (Int, String?).self) { group in
            var cursor = 0
            func schedule(_ item: TVTMDBResult) {
                group.addTask {
                    let p = try? await TVTMDBService.shared.getTopWatchProvider(tmdbId: item.id, isTV: item.isTV)
                    return (item.id, p?.providerName)
                }
            }
            while cursor < todo.count && cursor < 8 { schedule(todo[cursor]); cursor += 1 }
            var out: [Int: String] = [:]
            while let (id, name) = await group.next() {
                if let name { out[id] = name }
                if cursor < todo.count { schedule(todo[cursor]); cursor += 1 }
            }
            return out
        }
        providerNames.merge(found) { _, new in new }
    }

    private func buildHeroItems() async {
        var seen = Set<Int>()
        let pool = (trending + onAir + ended).filter { seen.insert($0.id).inserted }
        let candidates = Array(pool.prefix(18))
        await hydrateProviderNames(for: candidates)
        var survivors = candidates.filter { providerNames[$0.id] != nil }.prefix(6).map { $0 }
        if survivors.count < 6 {
            let taken = Set(survivors.map(\.id))
            survivors.append(contentsOf: candidates.filter { !taken.contains($0.id) }.prefix(6 - survivors.count))
        }
        heroItems = survivors.isEmpty ? Array(trending.prefix(6)) : survivors
        composeHeroEntries()
    }

    private func composeHeroEntries() {
        var entries: [MacHeroEntry] = []
        for game in sports.filter({ $0.state == .live })
            .sorted(by: { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) })
            .prefix(4) {
            entries.append(.game(game))
        }
        let streams = TVStreamsViewModel.shared.userStreams
        let names = Dictionary(streams.map { ($0.titleId, $0.title ?? "") }, uniquingKeysWith: { a, _ in a })
        let posters = Dictionary(streams.map { ($0.titleId, $0.posterUrl) }, uniquingKeysWith: { a, _ in a })
        for live in liveCreators.prefix(2) {
            let name = names[live.titleId].flatMap { $0.isEmpty ? nil : $0 } ?? "Live now"
            entries.append(.liveCreator(
                titleId: live.titleId, name: name, streamTitle: live.streamTitle,
                category: live.category, imageUrl: posters[live.titleId] ?? nil, viewers: live.viewerCount
            ))
        }
        for upload in creatorUploads.prefix(4) { entries.append(.upload(upload)) }
        entries.append(contentsOf: heroItems.map { .media($0, provider: providerNames[$0.id]) })
        heroEntries = entries
    }

    private func buildEveryonesWatching() async {
        let candidates = Array(trending.prefix(25))
        await hydrateProviderNames(for: candidates)
        var items: [MacEveryonesItem] = []
        for (index, result) in candidates.enumerated() {
            guard let provider = providerNames[result.id] else { continue }
            if items.count >= 20 { break }
            items.append(MacEveryonesItem(result: result, rank: index + 1, providerName: provider))
        }
        everyonesWatching = items
    }

    private func buildComingToStreaming() async {
        let movies = Array(await TVTMDBService.shared.getNowPlayingMovies().prefix(24))
        let results = await withTaskGroup(of: MacComingItem?.self) { group in
            for movie in movies {
                group.addTask {
                    if let digital = await TVTMDBService.shared.getUSDigitalReleaseDate(movieId: movie.id) {
                        let f = DateFormatter()
                        f.dateFormat = "MMM d"
                        return MacComingItem(result: movie, badge: f.string(from: digital.date),
                                             meta: digital.note ?? "Streaming soon", sortKey: digital.date)
                    }
                    if let raw = movie.releaseDate ?? movie.firstAirDate, raw.count >= 10 {
                        let f = DateFormatter()
                        f.dateFormat = "yyyy-MM-dd"
                        f.locale = Locale(identifier: "en_US_POSIX")
                        if let release = f.date(from: String(raw.prefix(10))),
                           Date().timeIntervalSince(release) / 86_400 >= 30 {
                            return MacComingItem(result: movie, badge: "Coming soon",
                                                 meta: "In theaters now", sortKey: .distantFuture)
                        }
                    }
                    return nil
                }
            }
            var out: [MacComingItem] = []
            for await item in group { if let item { out.append(item) } }
            return out
        }
        comingToStreaming = Array(results.sorted { $0.sortKey < $1.sortKey }.prefix(20))
    }

    private func buildPopularOnService() async {
        let services = popularOnServiceOrder
        guard !services.isEmpty else { popularOnService = [:]; return }
        let results = await withTaskGroup(of: (String, [TVTMDBResult]).self) { group in
            for service in services {
                guard let providerId = Self.tmdbProviderIdMap[service.id] else { continue }
                group.addTask {
                    async let shows = TVTMDBService.shared.getPopularOnService(tmdbProviderId: providerId)
                    async let movies = TVTMDBService.shared.getPopularMoviesOnService(tmdbProviderId: providerId)
                    let (s, m) = await (shows, movies)
                    var mixed: [TVTMDBResult] = []
                    for i in 0..<max(s.count, m.count) where mixed.count < 12 {
                        if i < s.count { mixed.append(s[i]) }
                        if i < m.count, mixed.count < 12 { mixed.append(m[i]) }
                    }
                    return (service.id, mixed)
                }
            }
            var out: [(String, [TVTMDBResult])] = []
            for await item in group { out.append(item) }
            return out
        }
        var map: [String: [TVTMDBResult]] = [:]
        for (id, items) in results where !items.isEmpty { map[id] = items }
        popularOnService = map
    }

    private func buildRecommendedCreators() async {
        let followed = TVStreamsViewModel.shared.userStreams.map(\.titleId)
            .filter { TVTitleID.tmdbId(from: $0) == nil }
        guard !followed.isEmpty else { return }
        recommendedCreators = await TVContentSourcesService.fetchRecommendedCreators(forFollowedIds: followed)
    }

    private func buildRecommendedTitles() async {
        let services = Array(AuthViewModel.shared.selectedServices)
        guard !services.isEmpty else { recommendedTitles = []; return }
        recommendedTitles = await TVRecommendedTitlesService.fetch(
            userId: AuthViewModel.shared.currentUser?.id.uuidString,
            deviceId: TVDeviceIdentity.shared.deviceId,
            subscribedServices: services
        )
    }

    private func buildTodaysPick() async {
        guard let releases = await TVStreamingReleasesService.shared.fetchReleases() else { return }
        let pool = Array(releases.prefix(10))
        guard !pool.isEmpty else { return }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        let start = day % pool.count
        var pick = pool[start]
        for offset in 0..<pool.count {
            let candidate = pool[(start + offset) % pool.count]
            if candidate.posterUrl?.isEmpty == false || candidate.posterPath?.isEmpty == false {
                pick = candidate
                break
            }
        }
        todaysPick = pick
        if let path = await TVTMDBService.shared.getBackdropPath(tmdbId: pick.tmdbId, isTV: pick.isTV) {
            todaysPickBackdropUrl = TVTMDBImage.url(path, size: .backdrop1280)
        }
    }

    private func buildParityRails() async {
        let savedIds = TVStreamsViewModel.shared.userStreams.map(\.titleId)
        async let episodesTask = TVHomeRailsService.fetchNewEpisodes(forTitleIds: savedIds)
        async let liveTask = TVHomeRailsService.fetchLive(titleIds: savedIds)
        async let leavingTask = TVHomeRailsService.fetchLeavingSoon()
        async let releasesTask = TVStreamingReleasesService.shared.fetchReleases()
        async let aroundTask: Void = buildAroundTheWorld()
        let (episodes, live, leaving, releases) = await (episodesTask, liveTask, leavingTask, releasesTask)
        if let episodes {
            followedNewEpisodes = episodes.filter { $0.tmdbId != nil }
            var seen = Set<String>()
            creatorUploads = episodes
                .filter { TVCreatorKind.from(titleId: $0.titleId) == .youtube }
                .filter { seen.insert($0.titleId).inserted }
        }
        liveCreators = live
        if let leaving { leavingSoon = leaving }
        if let releases { newThisWeek = Array(releases.prefix(20)) }
        _ = await aroundTask
        composeHeroEntries()
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

    private func buildContinueWatching() async {
        guard let rows = await TVContinueWatchingService.shared.fetch(), !rows.isEmpty else {
            continueWatching = []
            return
        }
        let paths = await withTaskGroup(of: (Int, String?).self) { group in
            for (index, row) in rows.enumerated() {
                let tmdbId = row.tmdbId, isTV = row.isTV
                group.addTask {
                    let path: String? = isTV
                        ? await TVTMDBService.shared.getTVFreshness(tmdbId: tmdbId).posterPath
                        : await TVTMDBService.shared.getMoviePosterPath(tmdbId: tmdbId)
                    return (index, path)
                }
            }
            var out: [Int: String?] = [:]
            for await (i, p) in group { out[i] = p }
            return out
        }
        continueWatching = rows.enumerated().map { index, row in
            MacContinueItem(
                row: row,
                posterUrl: TVTMDBImage.url(paths[index] ?? nil, size: .poster500),
                service: row.platformId.flatMap { id in StreamingCatalog.all.first { $0.id == id.lowercased() } }
            )
        }
    }
}

/// What Home last rendered, written to Caches via TVHomeSnapshotStore.
nonisolated private struct MacHomeSnapshot: Codable, Sendable {
    struct ContinueRow: Codable, Sendable {
        let row: TVContinueWatchingRow
        let posterUrl: String?
        let serviceId: String?
    }
    var trending: [TVTMDBResult] = []
    var onAir: [TVTMDBResult] = []
    var ended: [TVTMDBResult] = []
    var providerNames: [Int: String] = [:]
    var heroItems: [TVTMDBResult] = []
    var recommendedTitles: [TVRecommendedTitle] = []
    var todaysPick: TVStreamingRelease?
    var todaysPickBackdropUrl: String?
    var everyonesWatching: [MacEveryonesItem] = []
    var comingToStreaming: [MacComingItem] = []
    var popularOnService: [String: [TVTMDBResult]] = [:]
    var recommendedCreators: [TVRecommendedCreator] = []
    var followedNewEpisodes: [TVNewEpisodeRow] = []
    var newThisWeek: [TVStreamingRelease] = []
    var leavingSoon: [TVExpiringRow] = []
    var continueWatching: [ContinueRow] = []
    var aroundTheWorld: [TVTMDBResult] = []
    var aroundProviderName: String?
}

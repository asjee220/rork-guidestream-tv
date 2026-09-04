//
//  TVScheduleService.swift
//  GuideStreamTVTV
//
//  tvOS half of GUI-95. Mirrors `ScheduleService` on the phone: one week
//  engine, two surfaces (My Teams games, Watchlist episodes).
//
//  Kept as a parallel type rather than shared code because the tvOS target
//  carries its own model and service layer throughout (TVSportsGame,
//  TVUserStream, TVTMDBService). The week math, the UTC padding and the
//  local-day bucketing are the same decisions as the phone's — if one of them
//  changes, change both.
//

import Foundation

// MARK: - Week math

enum TVScheduleWeek {
    static let maxOffset: Int = 4

    static func start(of date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
    }

    static func end(of weekStart: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
    }

    static func days(from weekStart: Date, calendar: Calendar = .current) -> [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    static func rangeLabel(for weekStart: Date, calendar: Calendar = .current) -> String {
        let last = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let month = DateFormatter()
        month.locale = .current
        month.setLocalizedDateFormatFromTemplate("MMMd")
        let day = DateFormatter()
        day.locale = .current
        day.setLocalizedDateFormatFromTemplate("d")
        let sameMonth = calendar.isDate(weekStart, equalTo: last, toGranularity: .month)
        return "\(month.string(from: weekStart)) – \(sameMonth ? day.string(from: last) : month.string(from: last))"
    }
}

// MARK: - Scheduled episode

/// One dated episode of a saved show. TMDB gives a calendar date and no time,
/// so this carries a day and the grid shows the service rather than inventing
/// a drop time.
nonisolated struct TVScheduledEpisode: Identifiable, Hashable, Sendable {
    let titleId: String
    let showTitle: String
    let posterUrl: String?
    let platform: String?
    let season: Int?
    let number: Int?
    let name: String?
    let airDay: Date
    let isSeasonFinale: Bool

    var id: String { "\(titleId)-\(season ?? 0)-\(number ?? 0)" }

    var episodeLabel: String {
        if let season, let number { return "S\(season) E\(number)" }
        return name ?? "New episode"
    }
}

// MARK: - Service

@MainActor
@Observable
final class TVScheduleService {
    static let shared = TVScheduleService()
    private init() {}

    /// Ceiling on saved shows resolved against TMDB — two calls each.
    private static let maxShows = 30

    private(set) var games: [TVSportsGame] = []
    private(set) var episodes: [TVScheduledEpisode] = []
    private(set) var isLoadingGames = false
    private(set) var isLoadingEpisodes = false

    private var gameCache: [Date: [TVSportsGame]] = [:]
    private var episodeCache: [Int: [TVScheduledEpisode]] = [:]

    // MARK: - Sports

    func loadGames(weekStart: Date) async {
        if let cached = gameCache[weekStart] {
            games = cached
            return
        }
        // Key off `favoriteUids()`, not `rows`.
        //
        // The two are not interchangeable: `favoriteUids` is seeded from the
        // local cache at init and survives a signed-out or offline launch,
        // while `rows` is filled only by a successful `load()` from Supabase.
        // tvOS's My Teams rail already reads the uids and treats a row as
        // optional decoration, so the rail could be full of chips while this
        // screen — which used to require `rows` — reported "none of your teams
        // play", which is exactly what it did.
        let favorites = TVTeamFavoritesService.shared
        let uids = favorites.favoriteUids()
        guard !uids.isEmpty else {
            games = []
            return
        }

        isLoadingGames = true
        defer { isLoadingGames = false }

        // Rows, when present, only narrow the work: the abbreviation is a
        // fallback match for pre-uid rows and the sport trims the fan-out.
        // Absent rows mean every endpoint gets asked, which is correct rather
        // than empty.
        let stored = uids.compactMap { favorites.rows[$0] }
        let abbrs = Set(
            stored
                .compactMap { $0.team_abbr?.uppercased() }
                .filter { !$0.isEmpty }
        )
        let sports = stored.count == uids.count
            ? Set(stored.compactMap { $0.sport }.filter { !$0.isEmpty })
            : Set<String>()

        let end = TVScheduleWeek.end(of: weekStart)
        let all = await TVSportsService.shared.fetchRange(
            from: weekStart,
            to: end,
            sports: sports.isEmpty ? nil : sports
        )

        let mine = all
            .filter { game in
                guard let start = game.startDate else { return false }
                return start >= weekStart && start < end
            }
            .filter { Self.involvesFavorite($0, uids: uids, abbrs: abbrs) }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }

        gameCache[weekStart] = mine
        games = mine
    }

    private static func involvesFavorite(_ game: TVSportsGame, uids: Set<String>, abbrs: Set<String>) -> Bool {
        if let uid = game.home.uid, uids.contains(uid) { return true }
        if let uid = game.away.uid, uids.contains(uid) { return true }
        if abbrs.contains(game.home.abbreviation.uppercased()) { return true }
        if abbrs.contains(game.away.abbreviation.uppercased()) { return true }
        return false
    }

    // MARK: - Shows

    func loadEpisodes() async {
        let shows = TVStreamsViewModel.shared.userStreams.filter { stream in
            guard stream.isTv ?? true else { return false }
            return Int(stream.titleId.trimmingCharacters(in: .whitespaces)) != nil
        }
        guard !shows.isEmpty else {
            episodes = []
            return
        }

        isLoadingEpisodes = true
        defer { isLoadingEpisodes = false }

        var resolved: [TVScheduledEpisode] = []
        var pending: [(Int, TVUserStream)] = []
        for stream in shows.prefix(Self.maxShows) {
            guard let tmdbId = Int(stream.titleId.trimmingCharacters(in: .whitespaces)) else { continue }
            if let cached = episodeCache[tmdbId] {
                resolved.append(contentsOf: cached)
            } else {
                pending.append((tmdbId, stream))
            }
        }

        if !pending.isEmpty {
            let fetched = await withTaskGroup(of: (Int, [TVScheduledEpisode]).self) { group in
                for (tmdbId, stream) in pending {
                    group.addTask {
                        (tmdbId, await Self.fetchEpisodes(tmdbId: tmdbId, stream: stream))
                    }
                }
                var out: [(Int, [TVScheduledEpisode])] = []
                for await pair in group { out.append(pair) }
                return out
            }
            for (tmdbId, eps) in fetched {
                episodeCache[tmdbId] = eps
                resolved.append(contentsOf: eps)
            }
        }

        episodes = resolved.sorted { lhs, rhs in
            if lhs.airDay != rhs.airDay { return lhs.airDay < rhs.airDay }
            return lhs.showTitle.localizedCaseInsensitiveCompare(rhs.showTitle) == .orderedAscending
        }
    }

    /// The show's current season and the one after it. The next season is
    /// asked for because a week can straddle a season boundary — a finale and
    /// the following premiere land days apart. TMDB answers nil for a season
    /// that does not exist, which is the common case and costs one 404.
    private static func fetchEpisodes(tmdbId: Int, stream: TVUserStream) async -> [TVScheduledEpisode] {
        let freshness = await TVTMDBService.shared.getTVFreshness(tmdbId: tmdbId)
        guard let latest = freshness.latestSeason, latest > 0 else { return [] }

        var out: [TVScheduledEpisode] = []
        for seasonNumber in [latest, latest + 1] {
            // `getSeason` is both throwing and optional-returning, so `try?`
            // flattens to a single optional — one `guard let`, not two.
            guard let season = try? await TVTMDBService.shared.getSeason(tmdbId: tmdbId, seasonNumber: seasonNumber),
                  let episodes = season.episodes, !episodes.isEmpty else { continue }
            let finaleNumber = episodes.map(\.episodeNumber).max()
            for episode in episodes {
                guard let day = parseAirDay(episode.airDate) else { continue }
                out.append(
                    TVScheduledEpisode(
                        titleId: String(tmdbId),
                        showTitle: stream.title ?? stream.titleId,
                        posterUrl: stream.posterUrl,
                        platform: stream.platform,
                        season: episode.seasonNumber ?? seasonNumber,
                        number: episode.episodeNumber,
                        name: episode.name,
                        airDay: day,
                        isSeasonFinale: episode.episodeNumber == finaleNumber
                    )
                )
            }
        }
        return out
    }

    /// Parsed in the device's own zone — as UTC, every West Coast Sunday drop
    /// lands on Saturday.
    private static func parseAirDay(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: raw) else { return nil }
        return Calendar.current.startOfDay(for: date)
    }

    // MARK: - Per-day slicing

    func games(on day: Date, calendar: Calendar = .current) -> [TVSportsGame] {
        games.filter { game in
            guard let start = game.startDate else { return false }
            return calendar.isDate(start, inSameDayAs: day)
        }
    }

    func episodes(on day: Date, calendar: Calendar = .current) -> [TVScheduledEpisode] {
        episodes.filter { calendar.isDate($0.airDay, inSameDayAs: day) }
    }
}

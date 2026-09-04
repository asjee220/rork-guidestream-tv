//
//  ScheduleService.swift
//  GuideStreamTV
//
//  Backs the Schedule week view (GUI-95) on both of its surfaces:
//
//  * Sports → Schedule — the week's games for the teams in My Teams.
//  * Watchlist → Schedule — the week's episodes for saved shows.
//
//  They are two entry points over one week engine. The week math lives here
//  rather than in either view so the phone and the TV cannot disagree about
//  where a week starts or which local day something belongs to.
//

import Foundation

// MARK: - Week math

enum ScheduleWeek {
    /// How far the arrows travel in each direction. Bounds the ESPN and TMDB
    /// fan-out and keeps the cache small; four weeks either way covers a month
    /// of planning, which is more forward visibility than TMDB actually has.
    static let maxOffset: Int = 4

    /// Start of the week containing `date`, honouring the locale's first
    /// weekday rather than hard-coding Sunday.
    static func start(of date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
    }

    /// Exclusive upper bound of the week beginning at `weekStart`.
    static func end(of weekStart: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
    }

    static func days(from weekStart: Date, calendar: Calendar = .current) -> [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    /// "Aug 30 – Sep 5" / "Sep 27 – Oct 3". The month is repeated only when the
    /// week straddles two of them.
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

/// One dated episode of a saved show.
///
/// TMDB publishes `air_date` as a calendar date with no time of day, so this
/// carries a **day**, not an instant, and the UI shows the service instead of
/// inventing a drop time. Fabricating "3:00 AM" for Netflix would be a guess
/// wearing the clothes of a fact.
nonisolated struct ScheduledEpisode: Identifiable, Hashable, Sendable {
    let titleId: String
    let showTitle: String
    let posterUrl: String?
    let platform: String?
    let season: Int?
    let number: Int?
    let name: String?
    /// Start of the local day this episode airs.
    let airDay: Date
    let isSeasonFinale: Bool

    var id: String { "\(titleId)-\(season ?? 0)-\(number ?? 0)" }

    /// "S3 E5" when TMDB numbers the episode, otherwise its title.
    var episodeLabel: String {
        if let season, let number { return "S\(season) E\(number)" }
        return name ?? "New episode"
    }
}

// MARK: - Service

@MainActor
@Observable
final class ScheduleService {
    static let shared = ScheduleService()
    private init() {}

    /// Ceiling on how many saved shows are resolved against TMDB. Each one
    /// costs a detail call plus a season call, so an unbounded watch list
    /// would open the screen with a hundred requests in flight.
    private static let maxShows = 30

    private(set) var games: [SportsGame] = []
    private(set) var episodes: [ScheduledEpisode] = []
    private(set) var isLoadingGames = false
    private(set) var isLoadingEpisodes = false

    /// weekStart → that week's favourite-team games. Paging back to a week
    /// already fetched is instant and costs no requests.
    private var gameCache: [Date: [SportsGame]] = [:]
    /// tmdbId → every dated episode of the season(s) in play. A season spans
    /// many weeks, so this is fetched once per show per session and every week
    /// is then filtered out of it locally.
    private var episodeCache: [Int: [ScheduledEpisode]] = [:]

    // MARK: - Sports

    /// Loads the games for `weekStart` involving a favorited team.
    func loadGames(weekStart: Date) async {
        if let cached = gameCache[weekStart] {
            games = cached
            return
        }
        let favorites = TeamFavoritesService.shared.rows
        guard !favorites.isEmpty else {
            games = []
            return
        }

        isLoadingGames = true
        defer { isLoadingGames = false }

        let uids = Set(favorites.keys)
        let abbrs = Set(
            favorites.values
                .compactMap { $0.team_abbr?.uppercased() }
                .filter { !$0.isEmpty }
        )
        let sports = Set(
            favorites.values
                .compactMap { $0.sport }
                .filter { !$0.isEmpty }
        )

        let end = ScheduleWeek.end(of: weekStart)
        let all = await SportsService.shared.fetchRange(
            from: weekStart,
            to: end,
            sports: sports.isEmpty ? nil : sports
        )

        // The fetch window is padded a day either side for UTC, so the local
        // week bounds are re-applied here — this is the only place that
        // decides which week a game belongs to.
        let mine = all
            .filter { $0.startDate >= weekStart && $0.startDate < end }
            .filter { Self.involvesFavorite($0, uids: uids, abbrs: abbrs) }
            .sorted { $0.startDate < $1.startDate }

        gameCache[weekStart] = mine
        games = mine
    }

    /// Matches on ESPN's uid — the same join key `team_favorites` is built on —
    /// and falls back to the abbreviation for rows saved before uids were
    /// stored.
    private static func involvesFavorite(_ game: SportsGame, uids: Set<String>, abbrs: Set<String>) -> Bool {
        if let uid = game.home.uid, uids.contains(uid) { return true }
        if let uid = game.away.uid, uids.contains(uid) { return true }
        if abbrs.contains(game.home.abbreviation.uppercased()) { return true }
        if abbrs.contains(game.away.abbreviation.uppercased()) { return true }
        return false
    }

    // MARK: - Shows

    /// Resolves air dates for every saved TV title. Independent of the week —
    /// call it once and filter per week with `episodes(in:)`.
    func loadEpisodes() async {
        let shows = StreamsViewModel.shared.userStreams.filter { stream in
            guard stream.isTV ?? TitleID.isTV(from: stream.titleId) ?? false else { return false }
            return Int(stream.titleId.trimmingCharacters(in: .whitespaces)) != nil
        }
        guard !shows.isEmpty else {
            episodes = []
            return
        }

        isLoadingEpisodes = true
        defer { isLoadingEpisodes = false }

        var resolved: [ScheduledEpisode] = []
        var pending: [(Int, UserStream)] = []
        for stream in shows.prefix(Self.maxShows) {
            guard let tmdbId = Int(stream.titleId.trimmingCharacters(in: .whitespaces)) else { continue }
            if let cached = episodeCache[tmdbId] {
                resolved.append(contentsOf: cached)
            } else {
                pending.append((tmdbId, stream))
            }
        }

        if !pending.isEmpty {
            let fetched = await withTaskGroup(of: (Int, [ScheduledEpisode]).self) { group in
                for (tmdbId, stream) in pending {
                    group.addTask {
                        (tmdbId, await Self.fetchEpisodes(tmdbId: tmdbId, stream: stream))
                    }
                }
                var out: [(Int, [ScheduledEpisode])] = []
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

    /// The saved show's currently-airing season(s), dated.
    ///
    /// Both `next_episode_to_air` and `last_episode_to_air` are consulted
    /// because a week can straddle a season boundary — the finale of one and
    /// the premiere of the next land days apart, and taking only one of them
    /// silently drops half the week.
    private static func fetchEpisodes(tmdbId: Int, stream: UserStream) async -> [ScheduledEpisode] {
        guard let detail = try? await TMDBService.shared.getTVDetail(tmdbId: tmdbId) else { return [] }

        var seasons = Set<Int>()
        if let next = detail.nextEpisodeToAir?.seasonNumber { seasons.insert(next) }
        if let last = detail.lastEpisodeToAir?.seasonNumber { seasons.insert(last) }
        if seasons.isEmpty, let total = detail.numberOfSeasons, total > 0 { seasons.insert(total) }
        guard !seasons.isEmpty else { return [] }

        var out: [ScheduledEpisode] = []
        for seasonNumber in seasons.sorted() {
            guard let season = try? await TMDBService.shared.getSeason(tmdbId: tmdbId, seasonNumber: seasonNumber) else { continue }
            let finaleNumber = season.episodes.map(\.episodeNumber).max()
            for episode in season.episodes {
                guard let day = parseAirDay(episode.airDate) else { continue }
                out.append(
                    ScheduledEpisode(
                        titleId: String(tmdbId),
                        showTitle: stream.title ?? detail.name,
                        posterUrl: stream.posterUrl ?? detail.posterUrl,
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

    /// TMDB air dates are bare `yyyy-MM-dd` calendar dates. Parsing them in the
    /// device's own zone is what keeps an episode on the day the viewer would
    /// call it — parsing as UTC puts every West Coast Sunday drop on Saturday.
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

    func games(on day: Date, calendar: Calendar = .current) -> [SportsGame] {
        games.filter { calendar.isDate($0.startDate, inSameDayAs: day) }
    }

    func episodes(on day: Date, calendar: Calendar = .current) -> [ScheduledEpisode] {
        episodes.filter { calendar.isDate($0.airDay, inSameDayAs: day) }
    }

    /// Episodes falling inside the week beginning at `weekStart`.
    func episodes(in weekStart: Date) -> [ScheduledEpisode] {
        let end = ScheduleWeek.end(of: weekStart)
        return episodes.filter { $0.airDay >= weekStart && $0.airDay < end }
    }
}

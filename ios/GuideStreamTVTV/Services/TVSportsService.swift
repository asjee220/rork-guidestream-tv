//
//  TVSportsService.swift
//  GuideStreamTVTV
//
//  ESPN scoreboard fetcher — surfaces live + upcoming games across the
//  major leagues so the Home sports rail mirrors the phone app.
//

import Foundation

// MARK: - Streaming Simulcast Companions

/// Deterministic linear-network → streaming-companion lookup for the sports
/// Where to Watch chips. ESPN's public scoreboard only reports the linear
/// carrier (e.g. "NBC") and never the streaming simulcast (e.g. Peacock).
/// Applied ONLY where the chips are built — the game's `broadcasts` array is
/// never mutated, so the Home tile and every list keep the linear network
/// alone. Named with the TV prefix because TVModels/TVCompatStubs already
/// alias the phone types and a bare `SportsSimulcast` would be ambiguous.
nonisolated enum TVSportsSimulcast {

    /// Normalized names that are already streaming destinations — these never
    /// get a companion appended.
    private static let streamingDestinations: Set<String> = [
        "peacock", "peacockpremium", "paramount", "paramountplus", "primevideo",
        "amazonprime", "netflix", "appletv", "appletvplus", "hbomax", "max",
        "hulu", "fubo", "fubotv", "slingtv", "youtube", "youtubetv", "tubi",
        "disneyplus", "espn", "espnplus", "nflplus", "nbaleaguepass", "mlbtv",
        "foxone"
    ]

    /// Exact normalized key → streaming companion. Matched exactly, never by
    /// substring, so unexpected network names (MSG, FDSSO, …) yield nothing.
    private static let companions: [String: String] = [
        "nbc": "Peacock", "nbcsn": "Peacock", "cnbc": "Peacock",
        "usa": "Peacock", "usanetwork": "Peacock", "usanet": "Peacock",
        "telemundo": "Peacock",
        "universo": "Peacock", "golf": "Peacock", "golfchannel": "Peacock",
        "cbs": "Paramount+", "cbssn": "Paramount+", "cbssportsnetwork": "Paramount+",
        "abc": "ESPN", "espn2": "ESPN", "espnu": "ESPN", "espnews": "ESPN",
        "espndeportes": "ESPN", "secn": "ESPN", "secnetwork": "ESPN",
        "secnplus": "ESPN",
        "accn": "ESPN", "accnetwork": "ESPN",
        "fox": "Fox One", "foxsports": "Fox One", "fs1": "Fox One",
        "fs2": "Fox One", "btn": "Fox One", "bigtennetwork": "Fox One",
        "foxdeportes": "Fox One",
        "tnt": "HBO Max", "tbs": "HBO Max", "trutv": "HBO Max",
        "nfln": "NFL+", "nflnetwork": "NFL+",
        "nbatv": "NBA League Pass",
        "mlbn": "MLB.TV", "mlbnetwork": "MLB.TV"
    ]

    /// Lowercased with every non-alphanumeric character removed.
    private static func normalize(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Returns the broadcasts with each linear network's streaming companion
    /// inserted immediately after it, deduplicated case-insensitively. Index
    /// zero is always the original first broadcast. These mappings encode US
    /// streaming rights only, so non-US regions get the input back unchanged.
    static func enrich(_ broadcasts: [String]) -> [String] {
        guard Locale.current.region?.identifier.uppercased() == "US" else { return broadcasts }
        var result: [String] = []
        var seen = Set<String>()
        for name in broadcasts {
            let key = normalize(name)
            if seen.insert(key).inserted {
                result.append(name)
            }
            guard !streamingDestinations.contains(key),
                  let companion = companions[key],
                  seen.insert(normalize(companion)).inserted else { continue }
            result.append(companion)
        }
        return result
    }
}

@MainActor
final class TVSportsService {
    static let shared = TVSportsService()
    private init() {}

    private struct Endpoint {
        let sport: String
        let path: String
    }

    // Kept deliberately identical to the iOS and Android endpoint lists — tvOS
    // had drifted behind (no NBA Summer, no World Cup), so a game visible on
    // the phone was missing on the TV.
    private let endpoints: [Endpoint] = [
        Endpoint(sport: "NBA",    path: "basketball/nba/scoreboard"),
        Endpoint(sport: "NBA Summer", path: "basketball/nba-summer-las-vegas/scoreboard"),
        Endpoint(sport: "NBA Summer", path: "basketball/nba-summer-utah/scoreboard"),
        Endpoint(sport: "NBA Summer", path: "basketball/nba-summer-sacramento/scoreboard"),
        Endpoint(sport: "NFL",    path: "football/nfl/scoreboard"),
        Endpoint(sport: "Soccer", path: "soccer/eng.1/scoreboard"),
        Endpoint(sport: "Soccer", path: "soccer/fifa.world/scoreboard"),
        Endpoint(sport: "MLB",    path: "baseball/mlb/scoreboard"),
        Endpoint(sport: "UFC",    path: "mma/ufc/scoreboard"),
        Endpoint(sport: "WNBA",   path: "basketball/wnba/scoreboard"),
        // groups=80 is ESPN's FBS group. Without it college-football returns
        // every division down to D3 (760 teams, 158 games on a Saturday), most
        // of which carry no national broadcast to deep-link into.
        Endpoint(sport: "CFB",    path: "football/college-football/scoreboard?groups=80"),
        Endpoint(sport: "NCAA Men",  path: "basketball/mens-college-basketball/scoreboard"),
        Endpoint(sport: "NCAA Women",  path: "basketball/womens-college-basketball/scoreboard")
    ]

    func fetchAll() async -> [TVSportsGame] {
        await withTaskGroup(of: [TVSportsGame].self) { group in
            for ep in endpoints {
                group.addTask { [weak self] in
                    guard let self else { return [] }
                    return await self.fetch(endpoint: ep)
                }
            }
            var all: [TVSportsGame] = []
            for await games in group { all.append(contentsOf: games) }
            return all.sorted { a, b in
                if a.state.isLive != b.state.isLive { return a.state.isLive }
                return (a.startDate ?? .distantFuture) < (b.startDate ?? .distantFuture)
            }
        }
    }

    /// Every game on the scoreboards between `from` and `to` for the given
    /// sports. Backs the Schedule week grid (GUI-95). Mirrors the phone's
    /// `SportsService.fetchRange` exactly — see that comment for why the
    /// window is padded (ESPN reads `dates=` in UTC) and why `sports` narrows
    /// the fan-out.
    func fetchRange(from: Date, to: Date, sports: Set<String>? = nil) async -> [TVSportsGame] {
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.timeZone = TimeZone(identifier: "UTC")
        stamp.dateFormat = "yyyyMMdd"
        let range = "\(stamp.string(from: from.addingTimeInterval(-86_400)))-\(stamp.string(from: to.addingTimeInterval(86_400)))"

        let targets: [Endpoint] = {
            guard let sports, !sports.isEmpty else { return endpoints }
            return endpoints.filter { sports.contains($0.sport) }
        }()
        guard !targets.isEmpty else { return [] }

        return await withTaskGroup(of: [TVSportsGame].self) { group in
            for ep in targets {
                group.addTask { [weak self] in
                    guard let self else { return [] }
                    return await self.fetch(endpoint: ep, dates: range)
                }
            }
            var all: [TVSportsGame] = []
            for await games in group { all.append(contentsOf: games) }
            return all.sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
        }
    }

    private func fetch(endpoint ep: Endpoint, dates: String? = nil) async -> [TVSportsGame] {
        var urlString = "https://site.api.espn.com/apis/site/v2/sports/\(ep.path)"
        if let dates {
            urlString += (ep.path.contains("?") ? "&" : "?") + "dates=\(dates)&limit=400"
        }
        guard let url = URL(string: urlString) else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(TVESPNScoreboard.self, from: data)
            return decoded.events?.compactMap { ev in
                Self.mapEvent(ev, sport: ep.sport)
            } ?? []
        } catch {
            return []
        }
    }

    private static func mapEvent(_ ev: TVESPNEvent, sport: String) -> TVSportsGame? {
        guard let comp = ev.competitions?.first,
              let competitors = comp.competitors, competitors.count >= 2 else { return nil }

        let homeRaw = competitors.first(where: { $0.homeAway == "home" }) ?? competitors[0]
        let awayRaw = competitors.first(where: { $0.homeAway == "away" }) ?? competitors[1]

        let state: TVGameState = {
            switch ev.status?.type?.state {
            case "in": return .live
            case "post": return .post
            default: return .pre
            }
        }()

        let detail: String = {
            if state == .live, let s = ev.status?.type?.shortDetail { return s }
            if state == .post { return ev.status?.type?.shortDetail ?? "Final" }
            if let date = parseDate(ev.date) {
                let f = DateFormatter()
                f.dateFormat = "h:mm a"
                f.timeZone = TimeZone(identifier: "America/New_York")
                return "\(f.string(from: date)) ET"
            }
            return ev.status?.type?.shortDetail ?? ""
        }()

        let broadcasts: [String] = {
            let names = comp.broadcasts?.flatMap { $0.names ?? [] } ?? []
            return Array(Set(names)).sorted()
        }()

        return TVSportsGame(
            id: ev.id ?? UUID().uuidString,
            sport: sport,
            // GUI-81: NOT ev.season?.slug — that is the season type
            // ("regular-season", "final", …), never a league. Kept identical
            // to the phone and Android services.
            leagueShort: sport,
            state: state,
            statusDetail: detail,
            startDate: parseDate(ev.date),
            home: makeTeam(from: homeRaw),
            away: makeTeam(from: awayRaw),
            broadcasts: broadcasts
        )
    }

    private static func makeTeam(from c: TVESPNCompetitor) -> TVGameTeam {
        let fallbackAbbrev: String = {
            if let s = c.team?.shortDisplayName { return String(s.prefix(3)).uppercased() }
            return "—"
        }()
        return TVGameTeam(
            id: c.team?.id,
            uid: c.team?.uid,
            abbreviation: c.team?.abbreviation ?? fallbackAbbrev,
            displayName: c.team?.displayName ?? "—",
            shortName: c.team?.shortDisplayName ?? c.team?.name ?? "—",
            score: c.score ?? "0",
            primaryHex: c.team?.color,
            isWinner: c.winner ?? false,
            logoURL: c.team?.logo
        )
    }

    /// ESPN scoreboard dates come in several variants:
    ///
    ///     2026-06-27T00:00:00.000Z  (fractional seconds)
    ///     2026-06-27T00:00:00Z      (with seconds)
    ///     2026-06-27T00:00Z         (no seconds — MOST COMMON)
    ///
    /// This used to be `ISO8601DateFormatter` with `.withInternetDateTime`
    /// alone, which requires seconds and therefore returned nil for nearly
    /// every game ESPN serves. Nothing on tvOS noticed, because
    /// `TVSportsGame.startDate` is optional and the Home rail only sorts by it
    /// (`?? .distantFuture`) — a nil sorts last instead of failing loudly. The
    /// Schedule week view (GUI-95) filters by it, so every game fell outside
    /// every week and the grid was always empty while the phone's was full.
    ///
    /// Kept identical to `SportsService.parseDate` on the phone.
    private static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }

        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFractional.date(from: s) { return d }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }

        let withSeconds: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
            return f
        }()
        if let d = withSeconds.date(from: s) { return d }

        let withoutSeconds: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd'T'HH:mmXXXXX"
            return f
        }()
        if let d = withoutSeconds.date(from: s) { return d }

        return nil
    }
}

// MARK: - ESPN response models

nonisolated struct TVESPNScoreboard: Decodable {
    let events: [TVESPNEvent]?
}

nonisolated struct TVESPNEvent: Decodable {
    let id: String?
    let date: String?
    let status: TVESPNStatus?
    let competitions: [TVESPNCompetition]?
    let season: TVESPNSeason?
}

nonisolated struct TVESPNSeason: Decodable {
    let slug: String?
}

nonisolated struct TVESPNStatus: Decodable {
    let type: TVESPNStatusType?
}

nonisolated struct TVESPNStatusType: Decodable {
    let state: String?
    let shortDetail: String?
}

nonisolated struct TVESPNCompetition: Decodable {
    let competitors: [TVESPNCompetitor]?
    let broadcasts: [TVESPNBroadcast]?
}

nonisolated struct TVESPNBroadcast: Decodable {
    let names: [String]?
}

nonisolated struct TVESPNCompetitor: Decodable {
    let homeAway: String?
    let score: String?
    let winner: Bool?
    let team: TVESPNTeam?
}

nonisolated struct TVESPNTeam: Decodable {
    let id: String?
    let uid: String?
    let abbreviation: String?
    let displayName: String?
    let shortDisplayName: String?
    let name: String?
    let color: String?
    let logo: String?
}

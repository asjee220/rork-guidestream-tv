//
//  SportsService.swift
//  GuideStreamTV
//
//  Fetches live + upcoming games from ESPN's public scoreboard endpoints.
//

import Foundation
import SwiftUI
import Supabase

// MARK: - Public Models

struct SportsGame: Identifiable, Hashable {
    let id: String
    let sport: String              // "NBA" / "NFL" / "Soccer" / "MLB" / "UFC"
    let leagueShort: String        // "NBA", "Premier League", etc
    let state: GameState
    let statusDetail: String       // "3rd Qtr · 8:42" or "8:30 PM ET" or "Final"
    let startDate: Date
    let home: GameTeam
    let away: GameTeam
    let broadcasts: [String]       // ["ESPN+", "TNT"]
}

enum GameState: String {
    case pre, live, post

    var isLive: Bool { self == .live }
}

struct GameTeam: Hashable {
    let id: String?
    let uid: String?
    let abbreviation: String
    let displayName: String
    let shortName: String
    let score: String
    let primaryHex: String?
    let isWinner: Bool
    var logoURL: String? = nil
}

// MARK: - Streaming Simulcast Companions

/// Deterministic linear-network → streaming-companion lookup for the sports
/// Where to Watch chips. ESPN's public scoreboard only reports the linear
/// carrier (e.g. "NBC") and never the streaming simulcast (e.g. Peacock), so
/// the chip row would otherwise never tell a cord-cutter where the game
/// actually streams. Applied ONLY at the point where the chips are built —
/// `SportsGame.broadcasts` itself is never mutated, so every other surface
/// (sports cards, detail screen, hero carousel, tvOS tiles) keeps showing
/// the linear network alone.
nonisolated enum SportsSimulcast {

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
    /// streaming rights only, so non-US regions get the input back unchanged
    /// rather than being pointed at a service that doesn't carry the game.
    static func enrich(_ broadcasts: [String]) -> [String] {
        guard DeviceLocale.current().region == "US" else { return broadcasts }
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

// MARK: - Service

@MainActor
final class SportsService {
    static let shared = SportsService()
    private init() {}

    private struct Endpoint {
        let sport: String
        let path: String
    }

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

    func fetchAll() async -> [SportsGame] {
        await withTaskGroup(of: [SportsGame].self) { group in
            for ep in endpoints {
                group.addTask { [weak self] in
                    guard let self else { return [] }
                    return await self.fetch(endpoint: ep)
                }
            }
            var all: [SportsGame] = []
            for await games in group { all.append(contentsOf: games) }
            return all.sorted { a, b in
                if a.state.isLive != b.state.isLive { return a.state.isLive }
                return a.startDate < b.startDate
            }
        }
    }

    /// Single-game refresh used by the game detail screen. Re-fetches only the
    /// endpoints whose sport matches `game.sport` (1 call for MLB/NBA/NFL/
    /// Soccer/UFC, 3 for "NBA Summer") and returns the game with the same id,
    /// or nil when it is no longer on the scoreboard / every call failed.
    /// Reuses `fetch(endpoint:)` and its mapping — no second ESPN parser.
    func refresh(game: SportsGame) async -> SportsGame? {
        let matching = endpoints.filter { $0.sport == game.sport }
        guard !matching.isEmpty else { return nil }
        return await withTaskGroup(of: [SportsGame].self) { group -> SportsGame? in
            for ep in matching {
                group.addTask { [weak self] in
                    guard let self else { return [] }
                    return await self.fetch(endpoint: ep)
                }
            }
            var match: SportsGame?
            for await games in group where match == nil {
                match = games.first { $0.id == game.id }
            }
            return match
        }
    }

    /// Resolves a single game by its ESPN id from Supabase's `sports_games`
    /// table, which `sports_poll_and_notify` keeps current.
    ///
    /// `fetchAll()` reads ESPN's live scoreboards directly, so it only ever
    /// contains games on today's slate — a "Final" push tapped later, or any
    /// tap made while ESPN is refusing the app's requests, finds nothing there
    /// and the sports push silently opens no detail. `sports_games` always
    /// holds the row the push was generated from, so this is the authoritative
    /// lookup for a notification tap. Returns nil when the id is unknown.
    func fetchGame(id gameId: String) async -> SportsGame? {
        let trimmed = gameId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let rows: [SportsGameRow] = try await SupabaseManager.shared.client
                .from("sports_games")
                .select()
                .eq("game_id", value: trimmed)
                .limit(1)
                .execute()
                .value
            return rows.first.map(Self.mapRow)
        } catch {
            print("[SportsService] fetchGame(\(trimmed)) failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Builds a `SportsGame` from a `sports_games` row. Scores are stored as
    /// integers there and as display strings on the model, so nil becomes "".
    private static func mapRow(_ r: SportsGameRow) -> SportsGame {
        let state: GameState = {
            switch r.state {
            case "live": return .live
            case "final": return .post
            default: return .pre
            }
        }()
        let homeScore = r.home_score.map(String.init) ?? ""
        let awayScore = r.away_score.map(String.init) ?? ""
        let homeWins = (r.home_score ?? 0) > (r.away_score ?? 0)
        return SportsGame(
            id: r.game_id,
            sport: r.sport ?? "",
            leagueShort: r.sport ?? "",
            state: state,
            statusDetail: r.status_detail ?? "",
            startDate: r.start_at.flatMap(parseDate) ?? Date(),
            home: GameTeam(
                id: r.home_id,
                uid: r.home_uid,
                abbreviation: r.home_abbr ?? "",
                displayName: r.home_name ?? "",
                shortName: r.home_name ?? "",
                score: homeScore,
                primaryHex: nil,
                isWinner: state == .post && homeWins
            ),
            away: GameTeam(
                id: r.away_id,
                uid: r.away_uid,
                abbreviation: r.away_abbr ?? "",
                displayName: r.away_name ?? "",
                shortName: r.away_name ?? "",
                score: awayScore,
                primaryHex: nil,
                isWinner: state == .post && !homeWins
            ),
            broadcasts: [r.broadcast].compactMap { $0 }.filter { !$0.isEmpty }
        )
    }

    private func fetch(endpoint ep: Endpoint) async -> [SportsGame] {
        let urlString = "https://site.api.espn.com/apis/site/v2/sports/\(ep.path)"
        guard let url = URL(string: urlString) else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(ESPNScoreboard.self, from: data)
            return decoded.events?.compactMap { ev in
                Self.mapEvent(ev, sport: ep.sport)
            } ?? []
        } catch {
            print("[SportsService] \(ep.sport) fetch failed: \(error)")
            return []
        }
    }

    private static func mapEvent(_ ev: ESPNEvent, sport: String) -> SportsGame? {
        guard let comp = ev.competitions?.first,
              let competitors = comp.competitors, competitors.count >= 2 else { return nil }

        let homeRaw = competitors.first(where: { $0.homeAway == "home" }) ?? competitors[0]
        let awayRaw = competitors.first(where: { $0.homeAway == "away" }) ?? competitors[1]

        let state: GameState = {
            switch ev.status?.type?.state {
            case "in": return .live
            case "post": return .post
            default: return .pre
            }
        }()

        let detail: String = {
            if state == .live, let s = ev.status?.type?.shortDetail { return s }
            if state == .post { return ev.status?.type?.shortDetail ?? "Final" }
            // pre — format like "8:30 PM ET"
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

        let leagueShort = ev.season?.slug ?? sport

        return SportsGame(
            id: ev.id ?? UUID().uuidString,
            sport: sport,
            leagueShort: leagueShort,
            state: state,
            statusDetail: detail,
            startDate: parseDate(ev.date) ?? .distantPast,
            home: makeTeam(from: homeRaw),
            away: makeTeam(from: awayRaw),
            broadcasts: broadcasts
        )
    }

    private static func makeTeam(from c: ESPNCompetitor) -> GameTeam {
        let fallbackAbbrev: String = {
            if let s = c.team?.shortDisplayName { return String(s.prefix(3)).uppercased() }
            return "—"
        }()
        return GameTeam(
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

    private static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }

        // ESPN scoreboard dates come in several variants:
        //   2026-06-27T00:00:00.000Z  (fractional seconds)
        //   2026-06-27T00:00:00Z     (with seconds)
        //   2026-06-27T00:00Z        (no seconds — most common)
        // Try strict ISO8601 first, then fall back to custom formats.

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

// MARK: - ESPN response models (nonisolated, decoded on background)

nonisolated struct ESPNScoreboard: Decodable {
    let events: [ESPNEvent]?
}

nonisolated struct ESPNEvent: Decodable {
    let id: String?
    let date: String?
    let status: ESPNStatus?
    let competitions: [ESPNCompetition]?
    let season: ESPNSeason?
}

nonisolated struct ESPNSeason: Decodable {
    let slug: String?
}

nonisolated struct ESPNStatus: Decodable {
    let type: ESPNStatusType?
}

nonisolated struct ESPNStatusType: Decodable {
    let state: String?
    let shortDetail: String?
    let completed: Bool?
}

nonisolated struct ESPNCompetition: Decodable {
    let competitors: [ESPNCompetitor]?
    let broadcasts: [ESPNBroadcast]?
}

nonisolated struct ESPNBroadcast: Decodable {
    let names: [String]?
}

nonisolated struct ESPNCompetitor: Decodable {
    let homeAway: String?
    let score: String?
    let winner: Bool?
    let team: ESPNTeam?
}

nonisolated struct ESPNTeam: Decodable {
    let id: String?
    let uid: String?
    let abbreviation: String?
    let displayName: String?
    let shortDisplayName: String?
    let name: String?
    let color: String?
    let logo: String?
}


/// Row decoder for `public.sports_games`, written by the
/// `sports_poll_and_notify` edge function. Every column but `game_id` is
/// optional so a partially-populated row still decodes.
nonisolated struct SportsGameRow: Decodable, Sendable {
    let game_id: String
    let league: String?
    let sport: String?
    let home_uid: String?
    let home_id: String?
    let home_abbr: String?
    let home_name: String?
    let away_uid: String?
    let away_id: String?
    let away_abbr: String?
    let away_name: String?
    let state: String?
    let status_detail: String?
    let home_score: Int?
    let away_score: Int?
    let start_at: String?
    let broadcast: String?
}

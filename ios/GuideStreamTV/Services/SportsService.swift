//
//  SportsService.swift
//  GuideStreamTV
//
//  Fetches live + upcoming games from ESPN's public scoreboard endpoints.
//

import Foundation
import SwiftUI

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
        Endpoint(sport: "NFL",    path: "football/nfl/scoreboard"),
        Endpoint(sport: "Soccer", path: "soccer/eng.1/scoreboard"),
        Endpoint(sport: "Soccer", path: "soccer/fifa.world/scoreboard"),
        Endpoint(sport: "MLB",    path: "baseball/mlb/scoreboard"),
        Endpoint(sport: "UFC",    path: "mma/ufc/scoreboard")
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
            isWinner: c.winner ?? false
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
}

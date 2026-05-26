//
//  TVSportsService.swift
//  GuideStreamTVTV
//
//  ESPN scoreboard fetcher — surfaces live + upcoming games across the
//  major leagues so the Home sports rail mirrors the phone app.
//

import Foundation

@MainActor
final class TVSportsService {
    static let shared = TVSportsService()
    private init() {}

    private struct Endpoint {
        let sport: String
        let path: String
    }

    private let endpoints: [Endpoint] = [
        Endpoint(sport: "NBA",    path: "basketball/nba/scoreboard"),
        Endpoint(sport: "NFL",    path: "football/nfl/scoreboard"),
        Endpoint(sport: "Soccer", path: "soccer/eng.1/scoreboard"),
        Endpoint(sport: "MLB",    path: "baseball/mlb/scoreboard"),
        Endpoint(sport: "UFC",    path: "mma/ufc/scoreboard")
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
                return a.startDate < b.startDate
            }
        }
    }

    private func fetch(endpoint ep: Endpoint) async -> [TVSportsGame] {
        let urlString = "https://site.api.espn.com/apis/site/v2/sports/\(ep.path)"
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
            leagueShort: ev.season?.slug ?? sport,
            state: state,
            statusDetail: detail,
            startDate: parseDate(ev.date) ?? Date(),
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
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
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
    let abbreviation: String?
    let displayName: String?
    let shortDisplayName: String?
    let name: String?
    let color: String?
}

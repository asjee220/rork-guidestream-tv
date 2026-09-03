//
//  TVTeamFavoritesService.swift
//  GuideStreamTVTV
//
//  Favourited teams, persisted to the same `team_favorites` rows the phone
//  writes — so a team followed on the Apple TV shows up in My Teams on the
//  phone, and the backend's starting-soon / going-live / final-score pushes
//  cover it too.
//
//  Mirrors ios/GuideStreamTV/Services/TeamFavoritesService.swift, including
//  its guest scoping (device_id with user_id IS NULL) and its optimistic
//  local update: a failed write is logged and never rolls the UI back, the
//  same contract StreamsViewModel keeps.
//
//  One deliberate difference: the phone calls PushTokenManager after a
//  favourite lands, to make sure the device is registered for the pushes
//  that favourite unlocks. tvOS has no push registration — the rows are
//  still written, and the alerts arrive on the viewer's phone.
//

import Foundation
import Supabase

@MainActor
@Observable
final class TVTeamFavoritesService {
    static let shared = TVTeamFavoritesService()

    /// Favourited team uids — ESPN's globally unique id, which is the join
    /// key `team_favorites` is built on.
    private(set) var favoritedUids: Set<String> = []

    /// The loaded rows, keyed by uid, so a chip can render a team's name and
    /// abbreviation without a game in hand.
    private(set) var rows: [String: TVTeamFavoriteRow] = [:]

    /// Survives a signed-out launch and a cold start with no network.
    private let localCacheKey = "gs.teamFavorites.localCache.v1"

    private var currentUserId: UUID? { AuthViewModel.shared.currentUser?.id }
    private var deviceId: String { TVDeviceIdentity.shared.deviceId }

    private init() {
        favoritedUids = loadLocalCache()
    }

    // MARK: - Load

    func load() async {
        do {
            var query = TVSupabaseManager.shared.client
                .from("team_favorites")
                .select()
            if let uid = currentUserId?.uuidString {
                query = query.eq("user_id", value: uid)
            } else {
                query = query.eq("device_id", value: deviceId)
                    .filter("user_id", operator: "is", value: "null")
            }
            let loaded: [TVTeamFavoriteRow] = try await query.execute().value
            var uids = Set<String>()
            var map: [String: TVTeamFavoriteRow] = [:]
            for row in loaded {
                guard let teamUid = row.team_uid else { continue }
                uids.insert(teamUid)
                map[teamUid] = row
            }
            favoritedUids = uids
            rows = map
            saveLocalCache(uids)
        } catch {
            print("[TVTeamFavorites] load failed: \(error.localizedDescription)")
            favoritedUids = loadLocalCache()
        }
    }

    // MARK: - Query

    func isFavorite(_ uid: String?) -> Bool {
        guard let uid else { return false }
        return favoritedUids.contains(uid)
    }

    func favoriteUids() -> Set<String> { favoritedUids }

    // MARK: - Toggle

    func toggle(team: TVGameTeam, league: String?, sport: String?) async {
        guard let uid = team.uid else { return }
        let wasFavorited = favoritedUids.contains(uid)

        if wasFavorited {
            favoritedUids.remove(uid)
            rows.removeValue(forKey: uid)
        } else {
            favoritedUids.insert(uid)
        }
        saveLocalCache(favoritedUids)

        do {
            if wasFavorited {
                // Scoped to this user, or for a guest to this device with a
                // null user_id, so two accounts on one Apple TV never delete
                // each other's teams.
                var query = TVSupabaseManager.shared.client
                    .from("team_favorites")
                    .delete()
                    .eq("team_uid", value: uid)
                if let userId = currentUserId?.uuidString {
                    query = query.eq("user_id", value: userId)
                } else {
                    query = query.eq("device_id", value: deviceId)
                        .filter("user_id", operator: "is", value: "null")
                }
                try await query.execute()
            } else {
                try await TVSupabaseManager.shared.client
                    .from("team_favorites")
                    .insert(payload(for: team, league: league, sport: sport, uid: uid))
                    .execute()
                await load()
            }
        } catch {
            let message = error.localizedDescription.lowercased()
            // A duplicate is the row already being there, which is the state
            // the viewer asked for.
            if !(message.contains("duplicate") || message.contains("23505")) {
                print("[TVTeamFavorites] toggle failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Batch add

    /// One insert for a whole picker session. Teams already followed are
    /// skipped, so passing the full selection is safe.
    func addMany(_ entries: [(team: TVGameTeam, league: String?, sport: String?)]) async {
        var payloads: [[String: AnyJSON]] = []
        var added: [String] = []

        for entry in entries {
            guard let uid = entry.team.uid, !favoritedUids.contains(uid) else { continue }
            payloads.append(payload(for: entry.team, league: entry.league, sport: entry.sport, uid: uid))
            added.append(uid)
        }
        guard !payloads.isEmpty else { return }

        for uid in added { favoritedUids.insert(uid) }
        saveLocalCache(favoritedUids)

        do {
            try await TVSupabaseManager.shared.client
                .from("team_favorites")
                .insert(payloads)
                .execute()
            await load()
        } catch {
            let message = error.localizedDescription.lowercased()
            if message.contains("duplicate") || message.contains("23505") {
                await load()
            } else {
                print("[TVTeamFavorites] addMany failed: \(error.localizedDescription)")
            }
        }
    }

    private func payload(for team: TVGameTeam, league: String?, sport: String?, uid: String) -> [String: AnyJSON] {
        var payload: [String: AnyJSON] = [
            "device_id": .string(deviceId),
            "team_uid": .string(uid)
        ]
        if let userId = currentUserId?.uuidString { payload["user_id"] = .string(userId) }
        if let teamId = team.id { payload["team_id"] = .string(teamId) }
        if !team.abbreviation.isEmpty, team.abbreviation != "\u{2014}" {
            payload["team_abbr"] = .string(team.abbreviation)
        }
        payload["team_name"] = .string(team.shortName)
        if let league { payload["league"] = .string(league) }
        if let sport { payload["sport"] = .string(sport) }
        return payload
    }

    // MARK: - Local cache

    private func loadLocalCache() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: localCacheKey),
              let decoded = try? JSONDecoder().decode(Set<String>.self, from: data)
        else { return [] }
        return decoded
    }

    private func saveLocalCache(_ uids: Set<String>) {
        guard let data = try? JSONEncoder().encode(uids) else { return }
        UserDefaults.standard.set(data, forKey: localCacheKey)
    }
}

/// Row from `public.team_favorites`. Field names are the column names, as on
/// the phone, so the two decoders stay comparable at a glance.
nonisolated struct TVTeamFavoriteRow: Decodable, Sendable {
    let team_uid: String?
    let team_id: String?
    let team_abbr: String?
    let team_name: String?
    let league: String?
    let sport: String?
    let user_id: String?
    let device_id: String?
}

// MARK: - Team catalogue

/// The pickable roster, from `public.sports_teams`. Mirrors
/// ios/GuideStreamTV/Services/SportsTeamCatalogService.swift.
@MainActor
@Observable
final class TVSportsTeamCatalogService {
    static let shared = TVSportsTeamCatalogService()

    private(set) var teams: [TVSportsTeamRow] = []
    private(set) var isLoading = false

    private let localCacheKey = "gs.sportsTeamCatalog.v1"

    private init() {
        teams = loadLocalCache()
    }

    /// Sports in catalogue order, de-duplicated. The order the table returns
    /// is the order the picker's pills appear in.
    var sports: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for team in teams where seen.insert(team.sport).inserted {
            ordered.append(team.sport)
        }
        return ordered
    }

    func teams(forSport sport: String) -> [TVSportsTeamRow] {
        teams.filter { $0.sport == sport }
    }

    /// Skips the network when a non-empty copy is already in memory, so
    /// opening the picker twice in one session costs one round trip.
    func load(force: Bool = false) async {
        if !force, !teams.isEmpty { return }
        isLoading = true
        defer { isLoading = false }
        do {
            // Paged: the roster runs well past a default limit, and taking
            // one page would silently drop whichever leagues sort last.
            let pageSize = 500
            var all: [TVSportsTeamRow] = []
            var from = 0
            while true {
                let page: [TVSportsTeamRow] = try await TVSupabaseManager.shared.client
                    .from("sports_teams")
                    .select()
                    .eq("is_active", value: true)
                    .order("league", ascending: true)
                    .order("sort_order", ascending: true)
                    .range(from: from, to: from + pageSize - 1)
                    .execute()
                    .value
                all.append(contentsOf: page)
                if page.count < pageSize { break }
                from += pageSize
            }
            if !all.isEmpty {
                teams = all
                saveLocalCache(all)
            }
        } catch {
            print("[TVTeamCatalog] load failed: \(error.localizedDescription)")
        }
    }

    private func loadLocalCache() -> [TVSportsTeamRow] {
        guard let data = UserDefaults.standard.data(forKey: localCacheKey),
              let decoded = try? JSONDecoder().decode([TVSportsTeamRow].self, from: data)
        else { return [] }
        return decoded
    }

    private func saveLocalCache(_ rows: [TVSportsTeamRow]) {
        guard let data = try? JSONEncoder().encode(rows) else { return }
        UserDefaults.standard.set(data, forKey: localCacheKey)
    }
}

nonisolated struct TVSportsTeamRow: Codable, Sendable, Hashable, Identifiable {
    let team_uid: String
    let team_id: String?
    let team_abbr: String?
    let team_name: String
    let short_name: String?
    let league: String
    let sport: String
    let color: String?
    let logo_url: String?
    let sort_order: Int

    var id: String { team_uid }

    /// Tile label — the short name where ESPN has one ("Knicks"), otherwise
    /// the full display name.
    var displayLabel: String {
        let short = short_name?.trimmingCharacters(in: .whitespaces) ?? ""
        return short.isEmpty ? team_name : short
    }

    /// Bridges a catalogue row into the shape TVTeamFavoritesService takes,
    /// so following from the picker and starring a team on a game card go
    /// through exactly the same persistence path.
    var asGameTeam: TVGameTeam {
        TVGameTeam(
            id: team_id,
            uid: team_uid,
            abbreviation: team_abbr ?? String(team_name.prefix(3)).uppercased(),
            displayName: team_name,
            shortName: displayLabel,
            score: "",
            primaryHex: color,
            isWinner: false,
            logoURL: logo_url
        )
    }
}

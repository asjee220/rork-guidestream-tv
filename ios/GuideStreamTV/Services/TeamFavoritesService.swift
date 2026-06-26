//
//  TeamFavoritesService.swift
//  GuideStreamTV
//
//  Persists favorited sports team uids to Supabase so the backend can
//  deliver starting-soon, going-live, and final-score push notifications
//  for games involving those teams. Scoped to the signed-in user or guest
//  device, mirroring the StreamsViewModel persistence pattern.
//

import Foundation
import Supabase

@MainActor
@Observable
final class TeamFavoritesService {
    static let shared = TeamFavoritesService()

    /// In-memory set of favorited team uids (ESPN's globally-unique uid).
    private(set) var favoritedUids: Set<String> = []

    /// Loaded rows from the team_favorites table, keyed by team_uid.
    /// Public so SportsView can read team_abbr/team_name/league/sport for chip rendering.
    private(set) var rows: [String: TeamFavoriteRow] = [:]

    /// Cached UserDefaults key for offline/guest survival.
    private let localCacheKey = "gs.teamFavorites.localCache.v1"

    private var currentUserId: UUID? {
        AuthViewModel.shared.currentUser?.id
    }

    private var deviceId: String {
        DeviceIdentity.shared.deviceId
    }

    private init() {
        favoritedUids = loadLocalCache()
    }

    // MARK: - Load

    /// Fetches the current user's or device's favorites from the server.
    func load() async {
        do {
            var query = SupabaseManager.shared.client
                .from("team_favorites")
                .select()
            if let uid = currentUserId?.uuidString {
                query = query.or("user_id.eq.\(uid),device_id.eq.\(deviceId)")
            } else {
                query = query.eq("device_id", value: deviceId)
            }
            let loaded: [TeamFavoriteRow] = try await query.execute().value
            var uids = Set<String>()
            var rowMap: [String: TeamFavoriteRow] = [:]
            for row in loaded {
                guard let teamUid = row.team_uid else { continue }
                uids.insert(teamUid)
                rowMap[teamUid] = row
            }
            self.favoritedUids = uids
            self.rows = rowMap
            saveLocalCache(uids)
        } catch {
            print("[TeamFavorites] load failed: \(error.localizedDescription)")
            // Keep showing local cache on failure.
            favoritedUids = loadLocalCache()
        }
    }

    // MARK: - Query

    /// Returns `true` when the given team uid is currently favorited.
    func isFavorite(_ uid: String?) -> Bool {
        guard let uid else { return false }
        return favoritedUids.contains(uid)
    }

    /// Returns the current set of favorited team uids.
    func favoriteUids() -> Set<String> {
        favoritedUids
    }

    // MARK: - Toggle

    /// Optimistically adds or removes a team favorite, then persists to Supabase.
    /// No-ops when `team.uid` is nil.
    func toggle(team: GameTeam, league: String?, sport: String?) async {
        guard let uid = team.uid else { return }

        let wasFavorited = favoritedUids.contains(uid)

        // Optimistic local update
        if wasFavorited {
            favoritedUids.remove(uid)
            rows.removeValue(forKey: uid)
        } else {
            favoritedUids.insert(uid)
        }
        saveLocalCache(favoritedUids)

        do {
            if wasFavorited {
                // Delete matching row(s) for this team_uid scoped to current user/device.
                var query = SupabaseManager.shared.client
                    .from("team_favorites")
                    .delete()
                    .eq("team_uid", value: uid)
                if let userId = currentUserId?.uuidString {
                    query = query.or("user_id.eq.\(userId),device_id.eq.\(deviceId)")
                } else {
                    query = query.eq("device_id", value: deviceId)
                }
                try await query.execute()
            } else {
                // Insert a row with the team details.
                var payload: [String: AnyJSON] = [
                    "device_id": .string(deviceId),
                    "team_uid": .string(uid)
                ]
                if let userId = currentUserId?.uuidString {
                    payload["user_id"] = .string(userId)
                }
                if let teamId = team.id { payload["team_id"] = .string(teamId) }
                if !team.abbreviation.isEmpty, team.abbreviation != "—" {
                    payload["team_abbr"] = .string(team.abbreviation)
                }
                payload["team_name"] = .string(team.shortName)
                if let league { payload["league"] = .string(league) }
                if let sport { payload["sport"] = .string(sport) }

                try await SupabaseManager.shared.client
                    .from("team_favorites")
                    .insert(payload)
                    .execute()
            }
            // When favoriting a team, ensure the user is set up for push notifications
            // via the existing PushTokenManager path so the backend can deliver
            // starting-soon, going-live, and final-score alerts.
            if !wasFavorited {
                await PushTokenManager.shared.resaveCachedToken()
            }
        } catch {
            let message = error.localizedDescription.lowercased()
            // Duplicate row → not really an error.
            if message.contains("duplicate") || message.contains("23505") {
                // Already saved — no-op.
            } else {
                print("[TeamFavorites] toggle persist failed: \(error.localizedDescription)")
                // Keep the optimistic local state — failures are logged but never
                // undo what the user sees, matching the StreamsViewModel pattern.
            }
        }
    }

    // MARK: - Local cache

    private func loadLocalCache() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: localCacheKey) else { return [] }
        do {
            return try JSONDecoder().decode(Set<String>.self, from: data)
        } catch {
            return []
        }
    }

    private func saveLocalCache(_ uids: Set<String>) {
        do {
            let data = try JSONEncoder().encode(uids)
            UserDefaults.standard.set(data, forKey: localCacheKey)
        } catch {
            print("[TeamFavorites] local cache encode failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Decodable row for server reads

nonisolated struct TeamFavoriteRow: Decodable, Sendable {
    let team_uid: String?
    let team_id: String?
    let team_abbr: String?
    let team_name: String?
    let league: String?
    let sport: String?
    let user_id: String?
    let device_id: String?
}

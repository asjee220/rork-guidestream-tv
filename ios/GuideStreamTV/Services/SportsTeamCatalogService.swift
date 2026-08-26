//
//  SportsTeamCatalogService.swift
//  GuideStreamTV
//
//  Read-only accessor for public.sports_teams — the full roster for every
//  supported league, refreshed weekly server-side by the sports_teams_sync
//  edge function.
//
//  Why this exists: favorites could previously only be created by starring a
//  team that happened to appear on today's ESPN scoreboard, so out of season
//  most teams were unfavoritable. sports_games is not a substitute — it is a
//  record of games played, not a roster.
//
//  Mirrors the ProviderBrandMapService pattern: singleton, in-memory cache,
//  never throws, callers degrade gracefully when the fetch fails.
//

import Foundation
import Supabase

@MainActor
@Observable
final class SportsTeamCatalogService {
    static let shared = SportsTeamCatalogService()

    /// All catalogue rows, already ordered by (league, sort_order) server-side.
    private(set) var teams: [SportsTeamRow] = []
    private(set) var isLoading: Bool = false
    private(set) var lastLoadFailed: Bool = false

    /// UserDefaults cache so the picker can render instantly on a warm launch
    /// and still works offline. Keyed with a version suffix so the shape can
    /// change without stale decodes.
    private let localCacheKey = "gs.sportsTeamCatalog.v1"

    private init() {
        teams = loadLocalCache()
    }

    /// Distinct sports in catalogue order, e.g. ["NFL", "NBA", "MLB", "Soccer"].
    var sports: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for team in teams where seen.insert(team.sport).inserted {
            ordered.append(team.sport)
        }
        return ordered
    }

    func teams(forSport sport: String) -> [SportsTeamRow] {
        teams.filter { $0.sport == sport }
    }

    /// Fetches the catalogue. Skips the network entirely when a non-empty
    /// in-memory copy already exists unless `force` is set, so opening the
    /// picker twice in one session costs one round trip.
    func load(force: Bool = false) async {
        if !force && !teams.isEmpty { return }
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let rows: [SportsTeamRow] = try await SupabaseManager.shared.client
                .from("sports_teams")
                .select()
                .eq("is_active", value: true)
                .order("league", ascending: true)
                .order("sort_order", ascending: true)
                .execute()
                .value
            if !rows.isEmpty {
                teams = rows
                saveLocalCache(rows)
            }
            lastLoadFailed = rows.isEmpty && teams.isEmpty
        } catch {
            print("[SportsTeamCatalog] load failed: \(error.localizedDescription)")
            // Keep whatever is already cached; only report failure when there
            // is genuinely nothing to show.
            lastLoadFailed = teams.isEmpty
        }
    }

    // MARK: - Local cache

    private func loadLocalCache() -> [SportsTeamRow] {
        guard let data = UserDefaults.standard.data(forKey: localCacheKey) else { return [] }
        return (try? JSONDecoder().decode([SportsTeamRow].self, from: data)) ?? []
    }

    private func saveLocalCache(_ rows: [SportsTeamRow]) {
        guard let data = try? JSONEncoder().encode(rows) else { return }
        UserDefaults.standard.set(data, forKey: localCacheKey)
    }
}

// MARK: - Row

nonisolated struct SportsTeamRow: Codable, Sendable, Hashable, Identifiable {
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

    /// Label used on picker tiles — the short name where ESPN provides one
    /// ("Knicks"), otherwise the full display name.
    var displayLabel: String {
        let short = short_name?.trimmingCharacters(in: .whitespaces) ?? ""
        return short.isEmpty ? team_name : short
    }

    /// Lowercased haystack for the picker's search field.
    var searchHaystack: String {
        [team_name, short_name ?? "", team_abbr ?? ""]
            .joined(separator: " ")
            .lowercased()
    }

    /// Bridges a catalogue row into the `GameTeam` shape TeamFavoritesService
    /// already accepts, so favoriting from the picker goes through exactly the
    /// same persistence path as starring a team on a live game card.
    var asGameTeam: GameTeam {
        GameTeam(
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

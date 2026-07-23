//
//  ProviderBrandMapService.swift
//  GuideStreamTV
//
//  Read-only accessor for the public.provider_brand_map table (331 rows,
//  refreshed weekly by a server-side cron). Maps TMDB watch-provider ids
//  to the app's streaming-service catalogue ids so Platform resolution can
//  key off the stable TMDB id rather than a display name. The app never
//  writes to this table.
//

import Foundation
import Supabase

@MainActor
@Observable
final class ProviderBrandMapService {
    static let shared = ProviderBrandMapService()

    /// Cached brand-map rows — loaded synchronously from UserDefaults in
    /// init so the very first render already has a map, then refreshed
    /// from the network once per launch via `refresh()`.
    private(set) var rows: [ProviderBrandRow] = []

    private let cacheKey = "gs_provider_brand_map_v2"

    private init() {
        loadCachedRows()
    }

    /// Loads cached rows from UserDefaults so Platform.from() can resolve
    /// brands before the network fetch completes.
    private func loadCachedRows() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return }
        if let decoded = try? JSONDecoder().decode([ProviderBrandRow].self, from: data) {
            rows = decoded
        }
    }

    /// Fetches all rows from provider_brand_map and updates the in-memory
    /// cache plus the UserDefaults cache. Returns silently on failure so
    /// callers can continue with the existing (possibly stale) cache.
    func refresh() async {
        do {
            let fetched: [ProviderBrandRow] = try await SupabaseManager.shared.client
                .from("provider_brand_map")
                .select()
                .execute()
                .value
            rows = fetched
            if let data = try? JSONEncoder().encode(fetched) {
                UserDefaults.standard.set(data, forKey: cacheKey)
            }
        } catch {
            print("[ProviderBrandMap] refresh failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Decodable row for server reads

nonisolated struct ProviderBrandRow: Codable, Sendable {
    let tmdbProviderId: Int
    let displayName: String
    let logoPath: String?
    let catalogId: String?
    let aliases: [String]
    let linkSource: String
    let badgeLabel: String?
    let badgeHex: String?

    enum CodingKeys: String, CodingKey {
        case tmdbProviderId = "tmdb_provider_id"
        case displayName = "display_name"
        case logoPath = "logo_path"
        case catalogId = "catalog_id"
        case aliases
        case linkSource = "link_source"
        case badgeLabel = "badge_label"
        case badgeHex = "badge_hex"
    }
}

//
//  TVProviderBrandMapService.swift
//  GuideStreamTVTV
//
//  Read-only accessor for the public.provider_brand_map table. Caches
//  decoded rows in UserDefaults so the first render already has a map,
//  then refreshes once per launch from the server. Never throws —
//  callers fall back to the twelve-entry local catalogue on failure.
//

import Foundation
import Supabase

nonisolated struct TVProviderBrandRow: Codable, Sendable, Hashable {
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
        case displayName    = "display_name"
        case logoPath       = "logo_path"
        case catalogId      = "catalog_id"
        case aliases
        case linkSource     = "link_source"
        case badgeLabel     = "badge_label"
        case badgeHex       = "badge_hex"
    }
}

/// Thread-safe singleton mirroring the `@unchecked Sendable` pattern used by
/// `TVSupabaseManager`. A lock guards the `_rows` array so reads from any
/// actor context (including `Platform.from` called inside a `TaskGroup`)
/// never race with the single `refresh()` write per launch.
final class TVProviderBrandMapService: @unchecked Sendable {
    static let shared = TVProviderBrandMapService()

    private let lock = NSLock()
    private var _rows: [TVProviderBrandRow] = []

    /// All decoded brand-map rows. Thread-safe read — returns a copy of the
    /// array under the lock. Populated synchronously from UserDefaults at
    /// init, then refreshed from the server once per launch via `refresh()`.
    var rows: [TVProviderBrandRow] {
        lock.lock()
        defer { lock.unlock() }
        return _rows
    }

    private let cacheKey = "tv.providerBrandMap.cache.v2"

    private init() {
        loadCacheSync()
    }

    private func loadCacheSync() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return }
        do {
            _rows = try JSONDecoder().decode([TVProviderBrandRow].self, from: data)
        } catch {
            _rows = []
        }
    }

    /// Fetches all rows from `provider_brand_map` (331 rows, well under the
    /// PostgREST thousand-row cap — plain select, no pagination). Overwrites
    /// the in-memory cache and persists to UserDefaults on success. On
    /// failure, silently keeps the existing cache so callers degrade to
    /// local fallback rather than crash.
    func refresh() async {
        do {
            let fetched: [TVProviderBrandRow] = try await TVSupabaseManager.shared.client
                .from("provider_brand_map")
                .select("tmdb_provider_id,display_name,logo_path,catalog_id,aliases,link_source,badge_label,badge_hex")
                .execute()
                .value
            lock.lock()
            _rows = fetched
            lock.unlock()
            if let data = try? JSONEncoder().encode(fetched) {
                UserDefaults.standard.set(data, forKey: cacheKey)
            }
        } catch {
            // Keep cached state — never blank badges or rails.
        }
    }
}

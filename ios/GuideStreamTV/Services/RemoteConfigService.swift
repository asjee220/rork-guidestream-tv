//
//  RemoteConfigService.swift
//  GuideStreamTV
//
//  Lightweight remote-configuration layer that lets AdMob ad unit IDs,
//  the Rakuten publisher id, and the full Rakuten advertiser catalog be
//  updated from Supabase without shipping a new build.
//
//  Strategy:
//  1. On init, synchronously hydrate from UserDefaults caches so values
//     are available immediately at cold launch, before the network returns.
//  2. `load()` reads every row from `app_config` (ad unit ids + publisher
//     id) and every row from `affiliate_advertisers` (the full advertiser
//     catalog), decodes them into typed structs, stores them in memory, and
//     persists the raw JSON back to UserDefaults so the next cold launch
//     has a last-known-good copy.
//  3. `load()` never throws to the caller and silently no-ops on any
//     network or decode failure, leaving cached or hardcoded values intact.
//
//  No secrets, tokens, or API keys are stored in or read from `app_config`
//  or `affiliate_advertisers`.
//

import Foundation
import Supabase

/// Typed shape of an `ads_ios` / `ads_android` row value.
nonisolated struct RemoteAdConfig: Codable, Sendable {
    let banner: String?
    let interstitial: String?
    let native: String?
}

/// Typed shape of the `affiliate_rakuten` row value. Only `publisher_id` is
/// read now that merchant IDs come from `affiliate_advertisers`. The
/// `merchants` field is kept optional so old cached JSON that still contains
/// a merchants object decodes without crashing.
nonisolated struct RemoteRakutenConfig: Codable, Sendable {
    let publisherId: String?
    let merchants: RemoteRakutenMerchants?

    enum CodingKeys: String, CodingKey {
        case publisherId = "publisher_id"
        case merchants
    }
}

/// Retained solely so old cached JSON with a merchants object decodes
/// without crashing. No longer used for merchant-id resolution.
nonisolated struct RemoteRakutenMerchants: Codable, Sendable {
    let netflix: String?
    let hulu: String?
    let disney: String?
    let hbo: String?
    let apple: String?
    let peacock: String?
    let paramount: String?
    let prime: String?
}

/// A single row from `affiliate_advertisers` — the remotely-configurable
/// Rakuten advertiser catalog. Merchant IDs, signup URLs, fallback URLs,
/// display names and brand aliases all come from rows of this shape.
nonisolated struct RemoteAdvertiser: Codable, Sendable {
    let key: String
    let displayName: String
    let aliases: [String]
    let merchantId: String?
    let signupUrl: String
    let fallbackUrl: String?
    let commissionType: String
    let enabled: Bool
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case key
        case displayName = "display_name"
        case aliases
        case merchantId = "merchant_id"
        case signupUrl = "signup_url"
        case fallbackUrl = "fallback_url"
        case commissionType = "commission_type"
        case enabled
        case sortOrder = "sort_order"
    }
}

/// Raw row shape returned by `select()` on `app_config`.
nonisolated struct AppConfigRow: Codable, Sendable {
    let key: String
    let value: AnyJSON
}

@MainActor
final class RemoteConfigService {
    static let shared = RemoteConfigService()

    /// UserDefaults key for the last-known-good `app_config` payload.
    private let cacheKey = "gs_remote_config_cache"
    /// UserDefaults key for the last-known-good `affiliate_advertisers` payload.
    private let catalogCacheKey = "gs_affiliate_catalog_cache"

    /// In-memory decoded values. Populated from cache on init, refreshed by
    /// `load()`. All accessors read these optionals directly.
    private var adsConfig: RemoteAdConfig?
    private var rakutenConfig: RemoteRakutenConfig?
    private var advertisers: [RemoteAdvertiser] = []

    private init() {
        hydrateFromCache()
    }

    // MARK: - Load

    /// Reads all rows from `app_config` and `affiliate_advertisers`, decodes
    /// them into typed structs, stores them in memory, and persists the raw
    /// JSON to UserDefaults so the next cold launch can hydrate from cache.
    /// Never throws — any failure leaves cached or hardcoded values intact.
    func load() async {
        do {
            let rows: [AppConfigRow] = try await SupabaseManager.shared.client
                .from("app_config")
                .select()
                .execute()
                .value
            ingest(rows)
        } catch {
            // Silent no-op: cached or hardcoded values stay in place.
        }

        do {
            let catalog: [RemoteAdvertiser] = try await SupabaseManager.shared.client
                .from("affiliate_advertisers")
                .select()
                .execute()
                .value
            ingestCatalog(catalog)
        } catch {
            // Silent no-op: cached or hardcoded catalog stays in place.
        }
    }

    /// Decodes the supplied app_config rows into the typed structs, then
    /// persists the raw JSON to UserDefaults.
    private func ingest(_ rows: [AppConfigRow]) {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var newAds: RemoteAdConfig?
        var newRakuten: RemoteRakutenConfig?

        for row in rows {
            guard let data = try? encoder.encode(row.value) else { continue }
            switch row.key {
            case "ads_ios":
                newAds = try? decoder.decode(RemoteAdConfig.self, from: data)
            case "ads_android":
                if newAds == nil {
                    newAds = try? decoder.decode(RemoteAdConfig.self, from: data)
                }
            case "affiliate_rakuten":
                newRakuten = try? decoder.decode(RemoteRakutenConfig.self, from: data)
            default:
                break
            }
        }

        if newAds != nil { adsConfig = newAds }
        if newRakuten != nil { rakutenConfig = newRakuten }

        if let cacheData = try? encoder.encode(rows) {
            UserDefaults.standard.set(cacheData, forKey: cacheKey)
        }
    }

    /// Stores the supplied advertiser rows in memory and persists the raw
    /// JSON to UserDefaults under the catalog cache key.
    private func ingestCatalog(_ rows: [RemoteAdvertiser]) {
        advertisers = rows
        let encoder = JSONEncoder()
        if let cacheData = try? encoder.encode(rows) {
            UserDefaults.standard.set(cacheData, forKey: catalogCacheKey)
        }
    }

    // MARK: - Accessors

    /// Returns the ad unit id for the given slot ("banner", "interstitial",
    /// "native"), or nil when the key is missing, null, or an empty string.
    func adUnit(_ slot: String) -> String? {
        guard let ads = adsConfig else { return nil }
        let raw: String?
        switch slot {
        case "banner": raw = ads.banner
        case "interstitial": raw = ads.interstitial
        case "native": raw = ads.native
        default: raw = nil
        }
        guard let value = raw, !value.isEmpty else { return nil }
        return value
    }

    /// Returns the Rakuten publisher id, or nil when missing/empty.
    var rakutenPublisherId: String? {
        guard let id = rakutenConfig?.publisherId, !id.isEmpty else { return nil }
        return id
    }

    /// Returns the enabled advertiser rows sorted ascending by sort_order.
    /// Returns an empty array when no remote rows have been loaded, so the
    /// caller can fall back to the hardcoded catalog.
    func affiliateCatalog() -> [RemoteAdvertiser] {
        advertisers
            .filter { $0.enabled }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - Cache

    /// Synchronously hydrates the typed structs from the UserDefaults raw
    /// JSON caches so values are available before the network returns.
    private func hydrateFromCache() {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        // app_config cache
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let rows = try? decoder.decode([AppConfigRow].self, from: data) {
            for row in rows {
                guard let rowData = try? encoder.encode(row.value) else { continue }
                switch row.key {
                case "ads_ios":
                    adsConfig = try? decoder.decode(RemoteAdConfig.self, from: rowData)
                case "ads_android":
                    if adsConfig == nil {
                        adsConfig = try? decoder.decode(RemoteAdConfig.self, from: rowData)
                    }
                case "affiliate_rakuten":
                    rakutenConfig = try? decoder.decode(RemoteRakutenConfig.self, from: rowData)
                default:
                    break
                }
            }
        }

        // affiliate_advertisers cache
        if let catalogData = UserDefaults.standard.data(forKey: catalogCacheKey),
           let catalogRows = try? decoder.decode([RemoteAdvertiser].self, from: catalogData) {
            advertisers = catalogRows
        }
    }
}

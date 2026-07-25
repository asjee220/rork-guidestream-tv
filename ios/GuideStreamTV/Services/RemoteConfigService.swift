//
//  RemoteConfigService.swift
//  GuideStreamTV
//
//  Lightweight remote-configuration layer that lets AdMob ad unit IDs and
//  Rakuten merchant IDs be updated from Supabase (`public.app_config`)
//  without shipping a new build.
//
//  Strategy:
//  1. On init, synchronously hydrate from a UserDefaults cache so values
//     are available immediately at cold launch, before the network returns.
//  2. `load()` reads every row from `app_config`, decodes the three known
//     keys into typed structs, stores them in memory, and persists the raw
//     JSON back to UserDefaults so the next cold launch has a last-known-
//     good copy.
//  3. `load()` never throws to the caller and silently no-ops on any
//     network or decode failure, leaving cached or hardcoded values intact.
//
//  No secrets, tokens, or API keys are stored in or read from `app_config`.
//

import Foundation
import Supabase

/// Typed shape of an `ads_ios` / `ads_android` row value.
nonisolated struct RemoteAdConfig: Codable, Sendable {
    let banner: String?
    let interstitial: String?
    let native: String?
}

/// Typed shape of the `affiliate_rakuten` row value.
nonisolated struct RemoteRakutenConfig: Codable, Sendable {
    let publisherId: String?
    let merchants: RemoteRakutenMerchants?

    enum CodingKeys: String, CodingKey {
        case publisherId = "publisher_id"
        case merchants
    }
}

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

/// Raw row shape returned by `select()` on `app_config`.
nonisolated struct AppConfigRow: Codable, Sendable {
    let key: String
    let value: AnyJSON
}

@MainActor
final class RemoteConfigService {
    static let shared = RemoteConfigService()

    /// UserDefaults key for the last-known-good raw JSON payload.
    private let cacheKey = "gs_remote_config_cache"

    /// In-memory decoded values. Populated from cache on init, refreshed by
    /// `load()`. All accessors read these optionals directly.
    private var adsConfig: RemoteAdConfig?
    private var rakutenConfig: RemoteRakutenConfig?

    private init() {
        hydrateFromCache()
    }

    // MARK: - Load

    /// Reads all rows from `app_config`, decodes the three known keys, stores
    /// them in memory, and persists the raw JSON to UserDefaults. Never
    /// throws — any failure leaves cached or hardcoded values intact.
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
    }

    /// Decodes the supplied rows into the typed structs, then persists the
    /// raw JSON to UserDefaults so the next cold launch can hydrate from it.
    private func ingest(_ rows: [AppConfigRow]) {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var newAds: RemoteAdConfig?
        var newRakuten: RemoteRakutenConfig?

        for row in rows {
            // Convert the AnyJSON value to Data via JSONEncoder (AnyJSON is
            // Encodable) so we can decode it into a typed struct.
            guard let data = try? encoder.encode(row.value) else { continue }
            switch row.key {
            case "ads_ios":
                newAds = try? decoder.decode(RemoteAdConfig.self, from: data)
            case "ads_android":
                // Only used as a fallback when ads_ios is missing.
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

        // Persist the raw rows so the next cold launch can hydrate from cache.
        if let cacheData = try? encoder.encode(rows) {
            UserDefaults.standard.set(cacheData, forKey: cacheKey)
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

    /// Returns the Rakuten merchant id for the given service key (e.g.
    /// "netflix", "hulu"), or nil when missing/empty.
    func rakutenMerchantId(for key: String) -> String? {
        guard let merchants = rakutenConfig?.merchants else { return nil }
        let raw: String?
        switch key {
        case "netflix": raw = merchants.netflix
        case "hulu": raw = merchants.hulu
        case "disney": raw = merchants.disney
        case "hbo": raw = merchants.hbo
        case "apple": raw = merchants.apple
        case "peacock": raw = merchants.peacock
        case "paramount": raw = merchants.paramount
        case "prime": raw = merchants.prime
        default: raw = nil
        }
        guard let value = raw, !value.isEmpty else { return nil }
        return value
    }

    // MARK: - Cache

    /// Synchronously hydrates the typed structs from the UserDefaults raw
    /// JSON cache so values are available before the network returns.
    private func hydrateFromCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return }
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        guard let rows = try? decoder.decode([AppConfigRow].self, from: data) else {
            return
        }
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
}

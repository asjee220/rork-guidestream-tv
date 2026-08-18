//
//  TVAffiliateService.swift
//  GuideStreamTVTV
//
//  Fetches the affiliate_advertisers table once per launch and resolves
//  on-screen provider names to advertisers the viewer is missing (gap
//  services). The app is read-only on this table — it never writes.
//  On fetch failure the cache stays empty and every lookup returns nil;
//  the UI renders nothing, never crashes, and never retries in a loop.
//

import Foundation
import Supabase

@MainActor
@Observable
final class TVAffiliateService {
    static let shared = TVAffiliateService()

    private init() {}

    private var advertisers: [Advertiser] = []
    private var hasFetched: Bool = false

    // MARK: - Advertiser row

    /// Decoded row from `public.affiliate_advertisers`. Only the columns
    /// needed for resolution and App Store linking are selected.
    nonisolated struct Advertiser: Decodable, Sendable, Hashable {
        let key: String
        let displayName: String
        let aliases: [String]
        let fallbackUrl: String?
        let enabled: Bool?
        let sortOrder: Int?

        enum CodingKeys: String, CodingKey {
            case key
            case displayName = "display_name"
            case aliases
            case fallbackUrl = "fallback_url"
            case enabled
            case sortOrder = "sort_order"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            key = try c.decode(String.self, forKey: .key)
            displayName = try c.decode(String.self, forKey: .displayName)
            aliases = (try? c.decode([String].self, forKey: .aliases)) ?? []
            fallbackUrl = try? c.decode(String.self, forKey: .fallbackUrl)
            enabled = try? c.decode(Bool.self, forKey: .enabled)
            sortOrder = (try? c.decode(Int.self, forKey: .sortOrder)) ?? 0
        }

        /// Rebuilds `fallback_url` with the `itms-apps` scheme on the same
        /// host and path. Returns `nil` unless the stored value is an
        /// `https` URL whose host is `apps.apple.com`.
        var appStoreURL: URL? {
            guard let fallbackUrl, let url = URL(string: fallbackUrl) else { return nil }
            guard url.scheme?.lowercased() == "https" else { return nil }
            guard let host = url.host?.lowercased(), host == "apps.apple.com" else { return nil }
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            comps?.scheme = "itms-apps"
            return comps?.url
        }
    }

    // MARK: - Fetch

    /// Fetches `affiliate_advertisers` once per launch, filters to
    /// enabled rows ordered by `sort_order`, and caches them in memory.
    /// Subsequent calls are no-ops. On failure the cache is left empty.
    func fetchIfNeeded() async {
        guard !hasFetched else { return }
        hasFetched = true
        do {
            let rows: [Advertiser] = try await SupabaseManager.shared.client
                .from("affiliate_advertisers")
                .select("key,display_name,aliases,fallback_url,enabled,sort_order")
                .order("sort_order", ascending: true)
                .execute()
                .value
            advertisers = rows.filter { $0.enabled == true }
        } catch {
            advertisers = []
        }
    }

    // MARK: - Lookup

    /// Lowercases and trims the provider name, maps it through
    /// `Platform.from(providerName:)` to a catalogue id, then matches that
    /// id against each cached advertiser's aliases. Returns `nil` when the
    /// name is unrecognised, the cache is empty, or no alias matches.
    func advertiser(forProviderName name: String?) -> Advertiser? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        guard let catalogId = Platform.from(providerName: name)?.catalogId else { return nil }
        for advertiser in advertisers {
            if advertiser.aliases.contains(where: { $0.lowercased() == catalogId }) {
                return advertiser
            }
        }
        return nil
    }

    /// Returns `true` only when the catalogue id resolved from the provider
    /// name is absent from the viewer's `selectedServices`. Reads
    /// `AuthViewModel.shared.selectedServices` fresh on every call so a
    /// service toggle that happens mid-session is respected immediately.
    func isGapService(_ name: String?) -> Bool {
        guard let catalogId = Platform.from(providerName: name)?.catalogId else { return false }
        return !AuthViewModel.shared.selectedServices.contains(catalogId)
    }
}

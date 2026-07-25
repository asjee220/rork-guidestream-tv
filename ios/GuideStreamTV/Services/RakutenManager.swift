//
//  RakutenManager.swift
//  GuideStreamTV
//
//  Rakuten Advertising affiliate link manager. Opens trackable deep links
//  that earn commission when users subscribe to streaming services, with
//  an App Store fallback if the tracking URL fails to open.
//
//  The advertiser catalog is now remotely configurable via
//  `public.affiliate_advertisers` in Supabase. When remote rows are loaded,
//  they drive matching, signup URLs, fallback URLs, and merchant IDs. The
//  hardcoded eight-entry catalog below is kept purely as an offline
//  fallback so a first launch with no network behaves identically to today.
//

import Foundation
import UIKit

struct RakutenAffiliate {
    let service: String
    let merchantId: String
    let trackingUrl: String
    let fallbackUrl: String   // direct App Store URL if tracking fails
    let commissionType: String // "cpa" = per signup, "cps" = per sale
}

/// Replace with your Rakuten Publisher ID from rakutenadvertising.com/affiliates.
private let publisherId = "lVjcZs0f2q0"

@MainActor
final class RakutenManager {
    static let shared = RakutenManager()
    private init() {}

    /// Streaming service affiliate entries. Register for each program at
    /// rakutenadvertising.com/publishers/programs and swap in real merchant IDs.
    /// Kept as the offline fallback catalog — when `affiliate_advertisers` is
    /// reachable, remote rows take precedence.
    let affiliates: [String: RakutenAffiliate] = [
        "netflix": RakutenAffiliate(
            service: "Netflix",
            merchantId: "[NETFLIX_MERCHANT_ID]",
            trackingUrl: "https://click.linksynergy.com/deeplink?id=\(publisherId)&mid=[NETFLIX_MERCHANT_ID]&murl=https%3A%2F%2Fwww.netflix.com%2Fsignup",
            fallbackUrl: "https://apps.apple.com/app/netflix/id363590051",
            commissionType: "cpa"
        ),
        "hulu": RakutenAffiliate(
            service: "Hulu",
            merchantId: "[HULU_MERCHANT_ID]",
            trackingUrl: "https://click.linksynergy.com/deeplink?id=\(publisherId)&mid=[HULU_MERCHANT_ID]&murl=https%3A%2F%2Fwww.hulu.com%2Fstart",
            fallbackUrl: "https://apps.apple.com/app/hulu/id376510438",
            commissionType: "cpa"
        ),
        "disney": RakutenAffiliate(
            service: "Disney+",
            merchantId: "[DISNEY_MERCHANT_ID]",
            trackingUrl: "https://click.linksynergy.com/deeplink?id=\(publisherId)&mid=[DISNEY_MERCHANT_ID]&murl=https%3A%2F%2Fwww.disneyplus.com%2Fsign-up",
            fallbackUrl: "https://apps.apple.com/app/disney/id1446075923",
            commissionType: "cpa"
        ),
        "hbo": RakutenAffiliate(
            service: "Max",
            merchantId: "[HBO_MERCHANT_ID]",
            trackingUrl: "https://click.linksynergy.com/deeplink?id=\(publisherId)&mid=[HBO_MERCHANT_ID]&murl=https%3A%2F%2Fwww.max.com%2Fplans-and-pricing",
            fallbackUrl: "https://apps.apple.com/app/max/id1666192693",
            commissionType: "cpa"
        ),
        "apple": RakutenAffiliate(
            service: "Apple TV+",
            merchantId: "[APPLE_MERCHANT_ID]",
            trackingUrl: "https://click.linksynergy.com/deeplink?id=\(publisherId)&mid=[APPLE_MERCHANT_ID]&murl=https%3A%2F%2Ftv.apple.com",
            fallbackUrl: "https://apps.apple.com/app/apple-tv/id1174078549",
            commissionType: "cpa"
        ),
        "peacock": RakutenAffiliate(
            service: "Peacock",
            merchantId: "[PEACOCK_MERCHANT_ID]",
            trackingUrl: "https://click.linksynergy.com/deeplink?id=\(publisherId)&mid=[PEACOCK_MERCHANT_ID]&murl=https%3A%2F%2Fwww.peacocktv.com%2Fplan",
            fallbackUrl: "https://apps.apple.com/app/peacock/id1508186374",
            commissionType: "cpa"
        ),
        "paramount": RakutenAffiliate(
            service: "Paramount+",
            merchantId: "[PARAMOUNT_MERCHANT_ID]",
            trackingUrl: "https://click.linksynergy.com/deeplink?id=\(publisherId)&mid=[PARAMOUNT_MERCHANT_ID]&murl=https%3A%2F%2Fwww.paramountplus.com%2Fsignup",
            fallbackUrl: "https://apps.apple.com/app/paramount/id1340650234",
            commissionType: "cpa"
        ),
        "prime": RakutenAffiliate(
            service: "Prime Video",
            merchantId: "[PRIME_MERCHANT_ID]",
            trackingUrl: "https://click.linksynergy.com/deeplink?id=\(publisherId)&mid=[PRIME_MERCHANT_ID]&murl=https%3A%2F%2Fwww.amazon.com%2Famazonprimevideo",
            fallbackUrl: "https://apps.apple.com/app/amazon-prime-video/id545519333",
            commissionType: "cpa"
        )
    ]

    // MARK: - Effective catalog

    /// Returns the effective advertiser catalog: remote rows from
    /// `affiliate_advertisers` when non-empty, otherwise the hardcoded
    /// affiliates mapped into `RemoteAdvertiser` shape.
    private func effectiveCatalog() -> [RemoteAdvertiser] {
        let remote = RemoteConfigService.shared.affiliateCatalog()
        if !remote.isEmpty { return remote }
        return hardcodedCatalog()
    }

    /// Maps the hardcoded `affiliates` dictionary into `RemoteAdvertiser`
    /// shape so the fallback path uses the same resolution code as the
    /// remote path. Aliases are derived from the existing contains-logic.
    private func hardcodedCatalog() -> [RemoteAdvertiser] {
        let aliasMap: [String: [String]] = [
            "netflix": ["netflix"],
            "hbo": ["max", "hbo"],
            "hulu": ["hulu"],
            "disney": ["disney"],
            "apple": ["apple"],
            "prime": ["prime", "amazon"],
            "paramount": ["paramount"],
            "peacock": ["peacock"],
        ]
        let order = ["netflix", "hbo", "hulu", "disney", "apple", "prime", "paramount", "peacock"]
        return order.enumerated().compactMap { index, key in
            guard let aff = affiliates[key] else { return nil }
            let signup = Self.directSignupURL(for: key)?.absoluteString ?? ""
            return RemoteAdvertiser(
                key: key,
                displayName: aff.service,
                aliases: aliasMap[key] ?? [key],
                merchantId: nil,
                signupUrl: signup,
                fallbackUrl: aff.fallbackUrl,
                commissionType: aff.commissionType,
                enabled: true,
                sortOrder: index
            )
        }
    }

    // MARK: - Matching

    /// Resolves a streaming service display name or catalog id to the
    /// affiliate key using the effective catalog's alias contains-matching.
    func affiliateKey(forServiceNamed name: String) -> String? {
        let lowered = name.lowercased()
        for entry in effectiveCatalog() {
            if entry.aliases.contains(where: { lowered.contains($0) }) {
                return entry.key
            }
        }
        return nil
    }

    /// Returns true when an affiliate entry exists for the given service.
    func hasAffiliate(forServiceNamed name: String) -> Bool {
        affiliateKey(forServiceNamed: name) != nil
    }

    /// Convenience wrapper that resolves the service name to an affiliate
    /// key and delegates to `openAffiliateLink(serviceId:metadata:)`.
    func openAffiliateLink(forServiceNamed name: String, metadata: [String: Any] = [:]) {
        guard let key = affiliateKey(forServiceNamed: name) else { return }
        openAffiliateLink(serviceId: key, metadata: metadata)
    }

    // MARK: - Resolution

    func affiliate(for serviceId: String) -> RakutenAffiliate? {
        let normalized = serviceId.lowercased()
        guard let entry = effectiveCatalog().first(where: { $0.key == normalized }) else { return nil }
        return RakutenAffiliate(
            service: entry.displayName,
            merchantId: entry.merchantId ?? "",
            trackingUrl: affiliateURL(for: normalized)?.absoluteString ?? "",
            fallbackUrl: entry.fallbackUrl ?? "",
            commissionType: entry.commissionType
        )
    }

    func affiliateURL(for serviceId: String) -> URL? {
        let normalized = serviceId.lowercased()
        guard let entry = effectiveCatalog().first(where: { $0.key == normalized }) else { return nil }
        // Resolve the publisher id from remote config, falling back to the
        // hardcoded constant so a missing row never breaks tracking.
        let resolvedPublisher = RemoteConfigService.shared.rakutenPublisherId ?? publisherId
        // Read the merchant id from the effective-catalog entry.
        guard let merchantId = entry.merchantId, !merchantId.isEmpty else {
            // No real merchant id available — return nil so the caller falls
            // through to the direct-signup branch.
            return nil
        }
        // Build the tracking URL at call time using the entry's signupUrl.
        guard let encoded = entry.signupUrl.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics
        ) else { return nil }
        let urlString = "https://click.linksynergy.com/deeplink?id=\(resolvedPublisher)&mid=\(merchantId)&murl=\(encoded)"
        return URL(string: urlString)
    }

    func fallbackURL(for serviceId: String) -> URL? {
        let normalized = serviceId.lowercased()
        if let entry = effectiveCatalog().first(where: { $0.key == normalized }),
           let fb = entry.fallbackUrl, !fb.isEmpty {
            return URL(string: fb)
        }
        return nil
    }

    // MARK: - Open

    /// Opens the Rakuten tracking URL for the given service id, falling back
    /// to the direct signup URL if the tracking URL fails or no merchant id
    /// is available. Always logs an `affiliate_link_tapped` event.
    func openAffiliateLink(serviceId: String, metadata: [String: Any] = [:]) {
        let normalized = serviceId.lowercased()
        let trackingURL = affiliateURL(for: normalized)

        if let url = trackingURL {
            UIApplication.shared.open(url, options: [:]) { [weak self] success in
                guard !success, let fallback = self?.fallbackURL(for: normalized) else { return }
                UIApplication.shared.open(fallback)
            }
        } else {
            // Direct-signup branch: open the entry's signupUrl. Fall back to
            // directSignupURL when the entry has no signupUrl or the key is
            // unknown (espn/disney_bundle/default cases).
            let entry = effectiveCatalog().first(where: { $0.key == normalized })
            if let signup = entry?.signupUrl, !signup.isEmpty, let url = URL(string: signup) {
                UIApplication.shared.open(url)
            } else if let directURL = Self.directSignupURL(for: normalized) {
                UIApplication.shared.open(directURL)
            }
        }

        let metaType = trackingURL == nil ? "direct_fallback" : "subscribe_cta"
        var meta: [String: Any] = ["type": metaType]
        for (k, v) in metadata { meta[k] = v }

        WatchIntentLogger.shared.log(
            eventType: .affiliateLinkTapped,
            platformId: normalized,
            metadata: meta
        )
    }

    private static func directSignupURL(for serviceId: String) -> URL? {
        switch serviceId {
        case "netflix":
            return URL(string: "https://www.netflix.com/signup")
        case "hbo":
            return URL(string: "https://www.max.com/plans-and-pricing")
        case "hulu":
            return URL(string: "https://www.hulu.com/start")
        case "disney":
            return URL(string: "https://www.disneyplus.com/sign-up")
        case "appletv", "apple":
            return URL(string: "https://tv.apple.com")
        case "prime":
            return URL(string:
                "https://www.amazon.com/amazonprimevideo")
        case "paramount":
            return URL(string:
                "https://www.paramountplus.com/signup")
        case "peacock":
            return URL(string: "https://www.peacocktv.com/plan")
        case "espn", "disney_bundle":
            return URL(string:
                "https://www.espn.com/espnplus/signup")
        default:
            return URL(string:
                "https://www.google.com/search?q=\(serviceId)+streaming+free+trial")
        }
    }
}

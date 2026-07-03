//
//  RakutenManager.swift
//  GuideStreamTV
//
//  Rakuten Advertising affiliate link manager. Opens trackable deep links
//  that earn commission when users subscribe to streaming services, with
//  an App Store fallback if the tracking URL fails to open.
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

    /// Resolves a streaming service display name or catalog id to the
    /// affiliate dictionary key using brand-key contains matching.
    func affiliateKey(forServiceNamed name: String) -> String? {
        let key = name.lowercased()
        if key.contains("netflix") { return "netflix" }
        if key.contains("max") || key.contains("hbo") { return "hbo" }
        if key.contains("hulu") { return "hulu" }
        if key.contains("disney") { return "disney" }
        if key.contains("apple") { return "apple" }
        if key.contains("prime") || key.contains("amazon") { return "prime" }
        if key.contains("paramount") { return "paramount" }
        if key.contains("peacock") { return "peacock" }
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

    func affiliate(for serviceId: String) -> RakutenAffiliate? {
        affiliates[serviceId.lowercased()]
    }

    func affiliateURL(for serviceId: String) -> URL? {
        guard let affiliate = affiliate(for: serviceId) else { return nil }
        return URL(string: affiliate.trackingUrl)
    }

    func fallbackURL(for serviceId: String) -> URL? {
        guard let affiliate = affiliate(for: serviceId) else { return nil }
        return URL(string: affiliate.fallbackUrl)
    }

    /// Opens the Rakuten tracking URL for the given service id, falling back
    /// to the App Store listing if the tracking URL fails. Always logs an
    /// `affiliate_link_tapped` event for attribution analytics.
    func openAffiliateLink(serviceId: String, metadata: [String: Any] = [:]) {
        let normalized = serviceId.lowercased()

        // Check if the merchant ID is still a placeholder.
        // If so, skip Rakuten entirely and open the direct signup
        // URL so the link always works even before real IDs are set.
        if let affiliate = affiliate(for: normalized),
           affiliate.merchantId.hasPrefix("[") {
            let directURL = Self.directSignupURL(for: normalized)
            if let url = directURL {
                UIApplication.shared.open(url)
            }
            WatchIntentLogger.shared.log(
                eventType: .affiliateLinkTapped,
                platformId: normalized,
                metadata: ["type": "direct_fallback", "source":
                    (metadata["source"] as? String) ?? "unknown"]
            )
            return
        }

        if let url = affiliateURL(for: normalized) {
            UIApplication.shared.open(url, options: [:]) { [weak self] success in
                guard !success, let fallback = self?.fallbackURL(for: normalized) else { return }
                UIApplication.shared.open(fallback)
            }
        } else if let fallback = fallbackURL(for: normalized) {
            UIApplication.shared.open(fallback)
        }

        var meta: [String: Any] = ["type": "subscribe_cta"]
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

//
//  InlineAdSlotView.swift
//  GuideStreamTV
//
//  Shared inline ad slot view used by HomeView, HomeDestinations drill-down
//  grids/lists, and SearchView. Holds the eight-entry affiliate offer pool,
//  selects an offer by slot index from the services the user hasn't
//  selected, and renders a SponsoredSlotView with the appropriate adSource,
//  sectionKey, and preferredSource. When every pool service is owned the
//  Rakuten card is suppressed and the slot renders native-AdMob-only. The
//  caller owns dismissal state.
//

import SwiftUI

/// Splits an array into chunks of the given size. Used by drill-down grids
/// and lists to insert an inline ad after every six cells.
extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

/// The eight affiliate offers shared across every inline ad surface.
/// Strings match the pool previously embedded in HomeView so historical
/// Watch Graph attribution stays comparable.
internal let inlineAdOfferPool: [(serviceId: String, headline: String, subtitle: String)] = [
    ("netflix", "Stream more on Netflix", "Unlimited shows & movies · Try free"),
    ("hbo", "Watch more on Max", "HBO, Max Originals & more · Try free"),
    ("hulu", "Live TV + streaming on Hulu", "Starting at $7.99/mo · Try free"),
    ("disney", "Disney+, Hulu & ESPN+ bundle", "Disney Bundle · Try free"),
    ("appletv", "Award-winning originals", "Apple TV+ · First month free"),
    ("prime", "Included with Prime", "Prime Video · Try free"),
    ("paramount", "NFL on CBS & live sports", "Paramount+ · Try free"),
    ("peacock", "Stream free on Peacock", "NBC shows & live sports · Free tier")
]

/// Renders a single inline ad slot. The caller controls visibility (e.g.
/// via a dismissed set) — this view itself does not conditionally hide.
struct InlineAdSlotView: View {
    let slotIndex: Int
    let adSource: String
    let sectionKey: String
    let onDismiss: () -> Void

    var body: some View {
        let offer = InlineAdSlotView.selectOffer(for: slotIndex)
        if let offer {
            let service = StreamingCatalog.service(for: offer.serviceId)
            SponsoredSlotView(
                service: service,
                fallbackName: service?.name ?? offer.headline,
                fallbackColor: service?.glow ?? .white,
                headline: offer.headline,
                subtitle: offer.subtitle,
                onTap: {
                    RakutenManager.shared.openAffiliateLink(
                        serviceId: offer.serviceId,
                        metadata: ["section": "\(sectionKey)_\(slotIndex)"]
                    )
                    WatchIntentLogger.shared.log(
                        eventType: .cardTapped,
                        metadata: ["section": "\(sectionKey)_\(slotIndex)"]
                    )
                },
                onDismiss: onDismiss,
                adSource: adSource,
                compact: true,
                preferredSource: slotIndex % 2 == 0 ? .adMobFirst : .rakutenFirst
            )
        } else {
            // Every affiliate service is owned — never render a Rakuten card
            // for something the user already has. Keep the slot mounted with
            // allowRakutenFallback false so AdMob can still fill it natively,
            // and collapse to nothing when it can't.
            SponsoredSlotView(
                service: nil,
                fallbackName: "",
                fallbackColor: .white,
                headline: "",
                subtitle: "",
                onTap: {},
                onDismiss: onDismiss,
                adSource: adSource,
                compact: true,
                preferredSource: slotIndex % 2 == 0 ? .adMobFirst : .rakutenFirst,
                allowRakutenFallback: false
            )
        }
    }

    /// Picks the affiliate offer for a slot from the pool entries the user
    /// doesn't already subscribe to, rotating by slot index. Returns nil
    /// when every pool service is owned — the caller then suppresses the
    /// Rakuten card instead of advertising an owned service.
    private static func selectOffer(for slotIndex: Int) -> (serviceId: String, headline: String, subtitle: String)? {
        let owned = AuthViewModel.shared.selectedServices
        let unowned = inlineAdOfferPool.filter { !owned.contains($0.serviceId) }
        guard !unowned.isEmpty else { return nil }
        return unowned[slotIndex % unowned.count]
    }
}

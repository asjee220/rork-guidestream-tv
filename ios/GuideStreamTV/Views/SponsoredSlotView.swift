//
//  SponsoredSlotView.swift
//  GuideStreamTV
//
//  Smart ad slot that prefers a real Google native ad (via AdManager's pool)
//  and falls back to the existing Rakuten SponsoredAffiliateCard when no
//  native ad is available. Used by the three detail-sheet affiliate banners
//  (CreatorDetailView, EpisodeDetailSheet, SportsWatchSheet) so they all
//  share a single, consistent fallback strategy.
//
//  On the cloud simulator AdManager.nextNativeAd() always returns nil, so
//  every banner renders the Rakuten card — identical to before this change.
//

import SwiftUI
#if canImport(GoogleMobileAds) && !targetEnvironment(simulator)
import GoogleMobileAds
#endif

struct SponsoredSlotView: View {
    let service: StreamingService?
    let fallbackName: String
    let fallbackColor: Color
    let headline: String
    let subtitle: String
    let onTap: () -> Void
    let onDismiss: () -> Void

    /// Logging source label passed through to WatchIntentLogger so each
    /// surface can distinguish its own native impressions.
    var adSource: String = "sponsored_slot"
    var compact: Bool = false

    /// Fixed height for the native card. Sized to fully show the icon tile,
    /// two-line headline, body, advertiser, CTA, Ad badge, AdChoices, and
    /// dismiss control without clipping, while staying close to the full
    /// SponsoredAffiliateCard height so the fallback→native upgrade is seamless.
    private static let nativeCardHeight: CGFloat = 96

    /// Native ad pulled from the pool on appear. nil → Rakuten fallback.
    @State private var currentNativeAd: AnyObject? = nil

    /// Observe the shared AdManager so the view re-evaluates when its native
    /// pool fills (via nativePoolTick), letting a late-arriving ad upgrade the
    /// Rakuten fallback to a native card.
    @ObservedObject private var adManager = AdManager.shared

    var body: some View {
        Group {
            if let nativeAd = currentNativeAd {
                nativeCard(nativeAd)
            } else {
                SponsoredAffiliateCard(
                    service: service,
                    fallbackName: fallbackName,
                    fallbackColor: fallbackColor,
                    headline: headline,
                    subtitle: subtitle,
                    onTap: onTap,
                    onDismiss: onDismiss,
                    compact: compact
                )
            }
        }
        .onAppear { fetchNativeAd() }
        .onChange(of: adManager.nativePoolTick) { _, _ in
            fetchNativeAd()
        }
    }

    // MARK: - Native card

    @ViewBuilder
    private func nativeCard(_ nativeAd: AnyObject) -> some View {
        #if canImport(GoogleMobileAds) && !targetEnvironment(simulator)
        if let ad = nativeAd as? NativeAd {
            NativeAdCardView(nativeAd: ad) {
                onDismiss()
            }
            // A UIViewRepresentable reports no intrinsic height, so SwiftUI
            // would collapse the card after its first layout pass. Pin a
            // definite height that fully shows the icon, headline, body,
            // advertiser, CTA, Ad badge, AdChoices, and dismiss control, and
            // closely matches the full SponsoredAffiliateCard so upgrading
            // from the Rakuten fallback causes no visible layout jump.
            .frame(maxWidth: .infinity)
            .frame(height: Self.nativeCardHeight)
            .onAppear {
                WatchIntentLogger.shared.log(
                    eventType: .adImpression,
                    metadata: ["ad_type": "native", "source": adSource]
                )
            }
        } else {
            // Fallback if cast fails (shouldn't happen, but never blank).
            SponsoredAffiliateCard(
                service: service,
                fallbackName: fallbackName,
                fallbackColor: fallbackColor,
                headline: headline,
                subtitle: subtitle,
                onTap: onTap,
                onDismiss: onDismiss,
                compact: compact
            )
        }
        #else
        // Simulator: never reached because nextNativeAd() returns nil.
        EmptyView()
        #endif
    }

    // MARK: - Native ad fetch

    /// Boots the ad system (idempotent via start()'s didStart guard) so a
    /// detail banner that is the first surface the user opens still initializes
    /// the SDK, requests ATT, and loads the pool. Then ensures a native load is
    /// in flight and attempts to claim one ad from the pool. Once an ad is
    /// claimed it is never replaced, so we bail early if we already have one. On
    /// simulator or no-fill this stays nil and the Rakuten fallback renders.
    private func fetchNativeAd() {
        guard currentNativeAd == nil else { return }
        AdManager.shared.start()
        AdManager.shared.loadNativePool()
        if let ad = AdManager.shared.nextNativeAd() {
            currentNativeAd = ad
        }
    }
}

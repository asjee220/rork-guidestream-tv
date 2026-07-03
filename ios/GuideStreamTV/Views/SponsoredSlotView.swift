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

    /// Native ad pulled from the pool on appear. nil → Rakuten fallback.
    @State private var currentNativeAd: AnyObject? = nil

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
    }

    // MARK: - Native card

    @ViewBuilder
    private func nativeCard(_ nativeAd: AnyObject) -> some View {
        #if canImport(GoogleMobileAds) && !targetEnvironment(simulator)
        if let ad = nativeAd as? NativeAd {
            NativeAdCardView(nativeAd: ad) {
                onDismiss()
            }
            .frame(maxWidth: .infinity)
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

    /// Pulls one native ad from the pool on appear. On simulator or no-fill
    /// this stays nil and the Rakuten fallback renders.
    private func fetchNativeAd() {
        let ad = AdManager.shared.nextNativeAd()
        if ad != nil {
            currentNativeAd = ad
        }
    }
}

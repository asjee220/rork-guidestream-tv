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

/// Preferred ad source for a pooled inline slot. `adMobFirst` shows a native
/// AdMob unit when it fills and backfills with the Rakuten affiliate card;
/// `rakutenFirst` skips the native claim so the Rakuten card renders directly.
enum PooledAdSource {
    case adMobFirst
    case rakutenFirst
}

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

    /// Whether this slot prefers a native AdMob unit or the Rakuten card.
    /// Defaults to `.adMobFirst` so the three existing detail-sheet callers
    /// are unchanged.
    var preferredSource: PooledAdSource = .adMobFirst

    /// When false the Rakuten affiliate card is never rendered — the slot
    /// attempts the AdMob native path regardless of `preferredSource` and
    /// collapses to a zero-height `Color.clear` when no native ad is
    /// available, so an unfillable slot occupies no space. Used when every
    /// affiliate offer would advertise a service the user already
    /// subscribes to.
    var allowRakutenFallback: Bool = true

    /// Fixed height for the native card. Sized to fully contain the 120pt
    /// media square plus padding, the two-line headline, body, advertiser,
    /// CTA, Ad attribution badge, AdChoices, and dismiss control without
    /// clipping, while staying close to the full SponsoredAffiliateCard height
    /// so the fallback→native upgrade is seamless. Inline feed slots
    /// (compactNative + feedStyle) pin 96 instead — see
    /// `effectiveNativeCardHeight`.
    var nativeCardHeight: CGFloat = 136

    /// When true the native card uses the compact icon-based layout.
    /// Forwarded into NativeAdCardView; defaults to true because every
    /// current caller (inline feed slots + the three detail sheets) wants
    /// the icon layout. The Reels carousel calls NativeAdCardView directly
    /// and is unaffected by this default.
    var compactNative: Bool = true

    /// When true (with `compactNative`) both the native card and the Rakuten
    /// fallback render the 96pt inline-feed chip row: elevated surface, 72pt
    /// creative square, "advertiser · Ad" attribution line, no CTA pill, and a
    /// trailing close control wired to `onDismiss`.
    /// Defaults to true so the three detail-sheet callers pick up the chip
    /// with no edits; pass false to keep the taller cards.
    var feedStyle: Bool = true

    /// Native ad pulled from the pool on appear. nil → Rakuten fallback.
    @State private var currentNativeAd: AnyObject? = nil

    /// Observe the shared AdManager so the view re-evaluates when its native
    /// pool fills (via nativePoolTick), letting a late-arriving ad upgrade the
    /// Rakuten fallback to a native card.
    @ObservedObject private var adManager = AdManager.shared

    /// Inline feed slots (compactNative + feedStyle) pin the 96pt chip row;
    /// every other combination keeps the full-height card.
    private var effectiveNativeCardHeight: CGFloat {
        compactNative && feedStyle ? 96 : nativeCardHeight
    }

    var body: some View {
        Group {
            if let nativeAd = currentNativeAd {
                nativeCard(nativeAd)
            } else if allowRakutenFallback {
                SponsoredAffiliateCard(
                    service: service,
                    fallbackName: fallbackName,
                    fallbackColor: fallbackColor,
                    headline: headline,
                    subtitle: subtitle,
                    onTap: onTap,
                    onDismiss: onDismiss,
                    compact: compact,
                    feedStyle: feedStyle
                )
            } else {
                // No eligible Rakuten offer and no native fill — occupy zero
                // height rather than advertise an owned service. Color.clear
                // (not EmptyView) keeps the slot a live view node so
                // onAppear and onChange(nativePoolTick) keep firing and a
                // late pool fill can still upgrade this slot to a native ad.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 0)
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
            NativeAdCardView(nativeAd: ad, compact: compactNative, feedStyle: feedStyle) {
                onDismiss()
            }
            // A UIViewRepresentable reports no intrinsic height, so SwiftUI
            // would collapse the card after its first layout pass. Pin a
            // definite height that fully shows the icon, headline, body,
            // advertiser, CTA, Ad badge, AdChoices, and dismiss control, and
            // closely matches the full SponsoredAffiliateCard so upgrading
            // from the Rakuten fallback causes no visible layout jump.
            .frame(maxWidth: .infinity)
            .frame(height: effectiveNativeCardHeight)
            .onAppear {
                WatchIntentLogger.shared.log(
                    eventType: .adImpression,
                    metadata: ["ad_type": "native", "source": adSource]
                )
            }
        } else if allowRakutenFallback {
            // Fallback if cast fails (shouldn't happen, but never blank).
            SponsoredAffiliateCard(
                service: service,
                fallbackName: fallbackName,
                fallbackColor: fallbackColor,
                headline: headline,
                subtitle: subtitle,
                onTap: onTap,
                onDismiss: onDismiss,
                compact: compact,
                feedStyle: feedStyle
            )
        } else {
            // Zero-height live node — see the matching branch in `body`.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 0)
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
    /// Rakuten-first slots never claim a native ad, so the Rakuten
    /// affiliate card always renders as the guaranteed backfill. Slots
    /// with `allowRakutenFallback == false` always attempt the native
    /// path regardless of `preferredSource`, because the Rakuten card is
    /// not an option for them.
    private func fetchNativeAd() {
        guard currentNativeAd == nil else { return }
        // Skip the native claim ONLY when the Rakuten card is both preferred
        // AND actually allowed. When `allowRakutenFallback` is false there is
        // no other content for this slot, so the native path must always be
        // attempted regardless of `preferredSource` — otherwise the slot can
        // never render anything at all.
        guard !(allowRakutenFallback && preferredSource == .rakutenFirst) else { return }
        AdManager.shared.start()
        AdManager.shared.loadNativePool()
        if let ad = AdManager.shared.nextNativeAd() {
            currentNativeAd = ad
        }
    }
}

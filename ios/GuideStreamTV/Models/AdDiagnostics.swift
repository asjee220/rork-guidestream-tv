//
//  AdDiagnostics.swift
//  GuideStreamTV
//
//  Plain snapshot of the ad stack's live state. Produced by AdManager on both
//  the real-SDK and simulator-stub branches so the Ad Diagnostics sheet in
//  Help & Feedback compiles and renders identically everywhere.
//

import Foundation

/// Immutable snapshot of everything the Ad Diagnostics sheet displays.
///
/// Exists so a TestFlight build can explain why ads are (or are not) showing
/// without needing a cable and Console.app: it captures whether the SDK is
/// linked and initialized, where the consent/ATT chain stopped, which ad unit
/// IDs are actually in use, and the most recent load errors.
nonisolated struct AdDiagnostics: Equatable {
    /// False on the simulator / when the GoogleMobileAds SDK isn't linked.
    let sdkLinked: Bool
    /// True once `MobileAds.start` has completed.
    let didInitializeSDK: Bool
    /// True while the consent → ATT → init chain is still running.
    let startInFlight: Bool
    /// UMP consent status, human readable.
    let consentStatus: String
    /// UMP's verdict on whether ad requests are permitted at all.
    let canRequestAds: Bool
    /// Whether UMP requires a privacy options entry point (EEA/UK).
    let privacyOptionsRequired: Bool
    /// App Tracking Transparency authorization status, human readable.
    let trackingAuthorization: String
    /// The native ad unit actually being requested.
    let nativeAdUnitID: String
    /// The interstitial ad unit actually being requested.
    let interstitialAdUnitID: String
    /// True when remote config supplied the native unit; false means the
    /// hardcoded fallback is in use.
    let remoteConfigHasNativeUnit: Bool
    /// Native ads currently buffered and ready to claim.
    let nativePoolCount: Int
    /// Native load requests issued this session.
    let nativeLoadAttempts: Int
    /// Native ads successfully received this session.
    let nativeAdsReceived: Int
    /// Whether an interstitial is loaded and ready.
    let hasInterstitial: Bool
    /// Last native load failure, or nil.
    let lastNativeError: String?
    /// Last interstitial load failure, or nil.
    let lastInterstitialError: String?

    /// One-line plain-English verdict describing the current blocker, shown at
    /// the top of the sheet so the cause is obvious without reading the rows.
    var summary: String {
        if !sdkLinked {
            return "Ad SDK is not linked in this build (simulator). Ads never render here — test on a device."
        }
        if !canRequestAds {
            return "Consent does not permit ad requests yet, so the SDK has not started. Check network, then tap Retry."
        }
        if !didInitializeSDK {
            return startInFlight
                ? "Ad SDK is still starting up. Give it a moment, then refresh."
                : "Ad SDK has not started. Tap Retry to run the consent and startup chain again."
        }
        if let lastNativeError {
            return "SDK is running but the last native ad request failed: \(lastNativeError)"
        }
        if nativeAdsReceived == 0 && nativeLoadAttempts > 0 {
            return "SDK is running and requests are going out, but AdMob has returned no ads yet — this is normal for a brand-new ad unit."
        }
        if nativeLoadAttempts == 0 {
            return "SDK is running but no native ad request has been made yet."
        }
        return "Ad stack is healthy — \(nativeAdsReceived) native ad(s) received this session."
    }

    /// Multi-line plain-text rendering used by the Copy button so the user can
    /// paste the whole snapshot into a support email.
    var plainText: String {
        """
        Ad Diagnostics
        --------------
        Summary: \(summary)

        SDK linked: \(sdkLinked)
        SDK initialized: \(didInitializeSDK)
        Start in flight: \(startInFlight)
        Consent status: \(consentStatus)
        Can request ads: \(canRequestAds)
        Privacy options required: \(privacyOptionsRequired)
        Tracking authorization: \(trackingAuthorization)

        Native unit: \(nativeAdUnitID)
        Native unit from remote config: \(remoteConfigHasNativeUnit)
        Interstitial unit: \(interstitialAdUnitID)

        Native pool count: \(nativePoolCount)
        Native load attempts: \(nativeLoadAttempts)
        Native ads received: \(nativeAdsReceived)
        Interstitial ready: \(hasInterstitial)

        Last native error: \(lastNativeError ?? "none")
        Last interstitial error: \(lastInterstitialError ?? "none")
        """
    }
}

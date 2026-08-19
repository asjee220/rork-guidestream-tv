//
//  AdManager.swift
//  GuideStreamTV
//
//  Singleton wrapping the Google Mobile Ads SDK. Real ad serving is
//  compiled in only when the SDK is linked (`canImport(GoogleMobileAds)`)
//  AND the build is not targeting the simulator — the cloud iOS simulator
//  has no AdMob support, so we keep the no-op path there to avoid a launch
//  crash. On a real device with the SPM package linked, `start()` initialises
//  the SDK, preloads an interstitial, and primes a small native-ad pool.
//

import Foundation
import Combine
import UIKit

#if canImport(GoogleMobileAds) && !targetEnvironment(simulator)
import GoogleMobileAds
import UserMessagingPlatform
import AppTrackingTransparency

@MainActor
final class AdManager: NSObject, ObservableObject, FullScreenContentDelegate, NativeAdLoaderDelegate, NativeAdDelegate {

    static let shared = AdManager()

    private override init() {
        super.init()
    }

    // MARK: - Startup

    private var didStart = false

    /// Initialises the SDK once and preloads the interstitial + native pool.
    /// Runs the UMP consent flow first — consent info update, then the consent
    /// form when the GDPR message requires one — followed by the ATT
    /// authorization request, and only initialises the ad SDK when consent
    /// allows ad requests (`canRequestAds`). Ads serve regardless of the
    /// user's ATT choice — we gate on the request *completing*, never on it
    /// being granted. A UMP error never blocks the chain: the ATT prompt
    /// still fires and the SDK still starts whenever consent permits. Safe to
    /// call multiple times; an already-satisfied form is never re-presented.
    /// No-op on simulator (the build excludes this entire class body via the
    /// compile-time guard above).
    func start() {
        guard !didStart else { return }
        didStart = true

        let parameters = RequestParameters()
        parameters.tagForUnderAgeOfConsent = false
        ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { [weak self] consentError in
            if let consentError {
                print("[AdManager] Consent info update failed: \(consentError.localizedDescription)")
            }
            Task { @MainActor in
                self?.presentConsentFormIfRequired()
            }
        }
    }

    /// Loads and presents the UMP consent form if the GDPR message requires
    /// one, then moves on to the ATT prompt. A missing root view controller
    /// or a form error skips the form and falls straight through — the ATT
    /// request and the `canRequestAds` check always run.
    private func presentConsentFormIfRequired() {
        guard let rootViewController = Self.rootViewController() else {
            proceedToATT()
            return
        }
        ConsentForm.loadAndPresentIfRequired(from: rootViewController) { [weak self] formError in
            if let formError {
                print("[AdManager] Consent form failed: \(formError.localizedDescription)")
            }
            Task { @MainActor in
                guard let self else { return }
                self.refreshPrivacyOptionsRequirement()
                self.proceedToATT()
            }
        }
    }

    /// Requests App Tracking Transparency authorization, then starts the ad
    /// SDK once the request completes (gated on completion, never on grant).
    private func proceedToATT() {
        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization { _ in
                Task { @MainActor in
                    self.startSDKIfConsented()
                }
            }
        } else {
            startSDKIfConsented()
        }
    }

    /// Starts the Google Mobile Ads SDK and preloads the interstitial + native
    /// pool, but only when UMP consent allows ad requests.
    private func startSDKIfConsented() {
        guard ConsentInformation.shared.canRequestAds else { return }
        startSDKAndPreload()
    }

    /// Starts the Google Mobile Ads SDK and preloads the interstitial + native
    /// pool. Runs exactly once, after ATT authorization has been resolved.
    private func startSDKAndPreload() {
        MobileAds.shared.start { [weak self] _ in
            self?.loadInterstitial()
            self?.loadNativePool()
        }
    }

    // MARK: - UMP privacy options

    /// True when UMP requires a privacy options entry point (EEA/UK). Drives
    /// the "Ad Privacy Options" row in Help & Feedback.
    @Published private(set) var privacyOptionsRequired: Bool = false

    /// Presents the UMP privacy options form from the key window's root view
    /// controller and refreshes `privacyOptionsRequired` once dismissed.
    func presentPrivacyOptions() {
        guard let rootViewController = Self.rootViewController() else { return }
        ConsentForm.presentPrivacyOptionsForm(from: rootViewController) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPrivacyOptionsRequirement()
            }
        }
    }

    private func refreshPrivacyOptionsRequirement() {
        privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    /// Resolves the key window's root view controller across all connected
    /// scenes. Returns nil when no key window exists yet — callers treat that
    /// as "skip the form".
    private static func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first(where: \.isKeyWindow)?.rootViewController }
            .first
    }

    // MARK: - Ad unit IDs

    var bannerAdUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/2934735716"
        #else
        return RemoteConfigService.shared.adUnit("banner") ?? "ca-app-pub-6595855555549220/0000000000"
        #endif
    }

    var interstitialAdUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/4411468910"
        #else
        return RemoteConfigService.shared.adUnit("interstitial") ?? "ca-app-pub-6595855555549220/5285695856"
        #endif
    }

    var nativeAdUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/3986624511"
        #else
        return RemoteConfigService.shared.adUnit("native") ?? "ca-app-pub-6595855555549220/8047590567"
        #endif
    }

    // MARK: - Interstitial

    private var interstitial: InterstitialAd?
    private var interstitialLoadInProgress: Bool = false

    /// True when an interstitial is loaded and ready to present.
    var hasInterstitial: Bool { interstitial != nil }

    /// Preloads an interstitial ad. Called on `start()` and again after each
    /// presentation so the next ad is always warming up.
    func loadInterstitial() {
        guard !interstitialLoadInProgress else { return }
        interstitialLoadInProgress = true
        InterstitialAd.load(
            with: interstitialAdUnitID,
            request: Request()
        ) { [weak self] ad, error in
            Task { @MainActor in
                guard let self else { return }
                self.interstitialLoadInProgress = false
                if let error {
                    print("[AdManager] Interstitial load failed: \(error.localizedDescription)")
                    return
                }
                self.interstitial = ad
                self.interstitial?.fullScreenContentDelegate = self
            }
        }
    }

    /// Presents the preloaded interstitial if one is ready. Calls `completion`
    /// on dismiss (or immediately if no ad is ready).
    func showInterstitial(from viewController: UIViewController, completion: @escaping () -> Void) {
        guard let ad = interstitial else {
            completion()
            return
        }
        // Capture completion so the dismiss delegate can fire it exactly once.
        interstitialDismissCompletion = completion
        interstitial = nil
        ad.present(from: viewController)
    }

    private var interstitialDismissCompletion: (() -> Void)?

    // MARK: - FullScreenContentDelegate (interstitial lifecycle)

    nonisolated func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        Task { @MainActor in
            print("[AdManager] Interstitial present failed: \(error.localizedDescription)")
            self.interstitialDismissCompletion?()
            self.interstitialDismissCompletion = nil
            self.loadInterstitial()
        }
    }

    nonisolated func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        Task { @MainActor in
            self.interstitialDismissCompletion?()
            self.interstitialDismissCompletion = nil
            self.loadInterstitial()
        }
    }

    // MARK: - Native ad pool

    private let nativePoolTarget: Int = 5
    private var nativePool: [NativeAd] = []
    private var nativeAdLoader: AdLoader?

    /// Observable signal that changes whenever a native ad becomes available.
    /// Views (e.g. SponsoredSlotView) observe this to re-attempt claiming an
    /// ad from the pool once the async load completes.
    @Published private(set) var nativePoolTick: Int = 0

    /// Returns a native ad from the pool (or nil if empty), and kicks off a
    /// background refill so the pool stays topped up.
    func nextNativeAd() -> NativeAd? {
        guard !nativePool.isEmpty else { return nil }
        let ad = nativePool.removeFirst()
        if nativePool.count < nativePoolTarget {
            loadNativePool()
        }
        return ad
    }

    /// Loads one or more native ads into the pool via GADAdLoader.
    func loadNativePool() {
        guard nativeAdLoader == nil else { return }
        let multiAdOptions = MultipleAdsAdLoaderOptions()
        multiAdOptions.numberOfAds = 5
        let loader = AdLoader(
            adUnitID: nativeAdUnitID,
            rootViewController: nil,
            adTypes: [.native],
            options: [multiAdOptions]
        )
        loader.delegate = self
        nativeAdLoader = loader
        loader.load(Request())
    }

    // MARK: - NativeAdLoaderDelegate

    nonisolated func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        Task { @MainActor in
            nativeAd.delegate = self
            nativePool.append(nativeAd)
            nativePoolTick += 1
        }
    }

    nonisolated func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        Task { @MainActor in
            print("[AdManager] Native load failed: \(error.localizedDescription)")
            self.nativeAdLoader = nil
        }
    }

    nonisolated func adLoaderDidFinishLoading(_ adLoader: AdLoader) {
        Task { @MainActor in
            self.nativeAdLoader = nil
        }
    }
}

#else
// MARK: - Simulator / no-SDK stub (cloud simulator safe)

@MainActor
final class AdManager: NSObject, ObservableObject {

    static let shared = AdManager()

    private override init() {
        super.init()
    }

    // MARK: - Startup

    private var didStart = false

    /// No-op stub. Safe to call multiple times.
    func start() {
        guard !didStart else { return }
        didStart = true
        // AdMob SDK intentionally not initialized — no SDK on simulator.
    }

    // MARK: - UMP privacy options (stubbed — no UMP SDK on simulator)

    /// Mirrors the real class so Help & Feedback compiles on simulator builds.
    @Published private(set) var privacyOptionsRequired: Bool = false

    /// No-op stub.
    func presentPrivacyOptions() {}

    // MARK: - Ad unit IDs (kept for future wiring)

    var bannerAdUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/2934735716"
        #else
        return RemoteConfigService.shared.adUnit("banner") ?? "ca-app-pub-6595855555549220/0000000000"
        #endif
    }

    var interstitialAdUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/4411468910"
        #else
        return RemoteConfigService.shared.adUnit("interstitial") ?? "ca-app-pub-6595855555549220/5285695856"
        #endif
    }

    var nativeAdUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/3986624511"
        #else
        return RemoteConfigService.shared.adUnit("native") ?? "ca-app-pub-6595855555549220/8047590567"
        #endif
    }

    // MARK: - Interstitial (stubbed)

    var hasInterstitial: Bool { false }

    func loadInterstitial() {}

    func showInterstitial(from viewController: UIViewController, completion: @escaping () -> Void) {
        completion()
    }

    // MARK: - Native ad pool (stubbed — always nil on simulator)

    /// Observable signal mirrored from the real class so SponsoredSlotView
    /// compiles against both branches. Never changes on the simulator/stub.
    @Published private(set) var nativePoolTick: Int = 0

    func nextNativeAd() -> AnyObject? { nil }
    func loadNativePool() {}
}

#endif

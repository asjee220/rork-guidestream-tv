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

@MainActor
final class AdManager: NSObject, ObservableObject, FullScreenContentDelegate, NativeAdLoaderDelegate, NativeAdDelegate {

    static let shared = AdManager()

    private override init() {
        super.init()
    }

    // MARK: - Startup

    private var didStart = false

    /// Initialises the SDK once and preloads the interstitial + native pool.
    /// Safe to call multiple times. No-op on simulator (the build excludes
    /// this entire class body via the compile-time guard above).
    func start() {
        guard !didStart else { return }
        didStart = true
        MobileAds.shared.start { [weak self] _ in
            self?.loadInterstitial()
            self?.loadNativePool()
        }
    }

    // MARK: - Ad unit IDs

    var bannerAdUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/2934735716"
        #else
        return "ca-app-pub-6595855555549220/0000000000"
        #endif
    }

    var interstitialAdUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/4411468910"
        #else
        return "ca-app-pub-6595855555549220/5285695856"
        #endif
    }

    var nativeAdUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/3986624511"
        #else
        return "ca-app-pub-6595855555549220/8047590567"
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

    private let nativePoolTarget: Int = 3
    private var nativePool: [NativeAd] = []
    private var nativeAdLoader: AdLoader?

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
        let loader = AdLoader(
            adUnitID: nativeAdUnitID,
            rootViewController: nil,
            adTypes: [.native],
            options: nil
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

    // MARK: - Ad unit IDs (kept for future wiring)

    var bannerAdUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/2934735716"
        #else
        return "ca-app-pub-6595855555549220/0000000000"
        #endif
    }

    var interstitialAdUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/4411468910"
        #else
        return "ca-app-pub-6595855555549220/5285695856"
        #endif
    }

    var nativeAdUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/3986624511"
        #else
        return "ca-app-pub-6595855555549220/8047590567"
        #endif
    }

    // MARK: - Interstitial (stubbed)

    var hasInterstitial: Bool { false }

    func loadInterstitial() {}

    func showInterstitial(from viewController: UIViewController, completion: @escaping () -> Void) {
        completion()
    }

    // MARK: - Native ad pool (stubbed — always nil on simulator)

    func nextNativeAd() -> AnyObject? { nil }
    func loadNativePool() {}
}

#endif

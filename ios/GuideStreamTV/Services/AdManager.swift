//
//  AdManager.swift
//  GuideStreamTV
//
//  NOTE: The Google Mobile Ads SDK is temporarily removed because its
//  initialization was preventing the app from launching on the cloud
//  simulator. The public surface below is preserved as a no-op stub so the
//  rest of the codebase (Reels interstitials, etc.) keeps compiling. When
//  building for a real device, re-add the `swift-package-manager-google-mobile-ads`
//  Swift package and restore the real implementation.
//

import Foundation
import Combine
import UIKit

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
        // AdMob SDK intentionally not initialized in this build.
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
        return "ca-app-pub-6595855555549220/0000000000"
        #endif
    }

    var nativeAdUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/3986624511"
        #else
        return "ca-app-pub-6595855555549220/0000000000"
        #endif
    }

    // MARK: - Interstitial (stubbed)

    /// No-op. Real implementation will preload an `InterstitialAd` here.
    func loadInterstitial() {}

    /// Calls `completion` immediately. Real implementation will present the
    /// preloaded interstitial first.
    func showInterstitial(from viewController: UIViewController, completion: @escaping () -> Void) {
        completion()
    }
}

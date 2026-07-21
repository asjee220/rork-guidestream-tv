//
//  DeviceIdentity.swift
//  GuideStreamTV
//

import Foundation
import UIKit

/// Stable per-device identifier used to track analytics events for **every**
/// user — signed-in or guest. Persisted across launches in UserDefaults so the
/// id survives auth state changes, and falls back to `identifierForVendor` on
/// first launch when nothing is cached yet. Always a valid UUID string so it
/// can safely live in a `uuid` Postgres column.
@MainActor
final class DeviceIdentity {
    static let shared = DeviceIdentity()

    private let storageKey = "gs.deviceId"

    /// Stable UUID string for this device install. Generated on first access
    /// and persisted forever (until the user uninstalls the app or clears
    /// "gs.deviceId" from defaults).
    let deviceId: String

    /// Indicates whether this is the very first launch on this install (no
    /// cached device id existed before this run). Useful for first-open
    /// analytics.
    let isFirstLaunch: Bool

    /// Runtime environment stamp written to `watch_intent_events.environment`
    /// so preview/simulator/debug/TestFlight traffic can be separated from
    /// real production traffic in Supabase. Resolved once at init in this
    /// exact precedence: simulator (compile-time) → debug (DEBUG flag) →
    /// testflight (sandboxReceipt) → production. Always exactly one of the
    /// four lowercase strings, never null or empty.
    let environment: String

    private init() {
        let defaults = UserDefaults.standard
        if let cached = defaults.string(forKey: storageKey), !cached.isEmpty {
            self.deviceId = cached
            self.isFirstLaunch = false
        } else {
            // Prefer identifierForVendor so the same id is reused if the user
            // reinstalls while other apps from the same vendor are present.
            // Fall back to a fresh UUID otherwise.
            let fresh = UIDevice.current.identifierForVendor?.uuidString
                ?? UUID().uuidString
            defaults.set(fresh, forKey: storageKey)
            self.deviceId = fresh
            self.isFirstLaunch = true
        }

        // Resolve the environment stamp once. Order matters: the simulator
        // check is compile-time and takes precedence over DEBUG, which takes
        // precedence over the TestFlight sandbox-receipt check.
        #if targetEnvironment(simulator)
        self.environment = "simulator"
        #elseif DEBUG
        self.environment = "debug"
        #else
        if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
            self.environment = "testflight"
        } else {
            self.environment = "production"
        }
        #endif
    }
}

//
//  DeviceIdentity.swift
//  GuideStreamTV
//

import Foundation
import Security
import UIKit

/// Stable per-device identifier used to track analytics events for **every**
/// user — signed-in or guest. Persisted in the Keychain (accessible after
/// first unlock, never synchronized to iCloud) so the id survives not just
/// auth state changes but an uninstall/reinstall of the app on the same
/// device. UserDefaults keeps a mirrored copy so existing readers (and
/// upgrades from older builds) keep working unchanged. Always a valid UUID
/// string so it can safely live in a `uuid` Postgres column.
@MainActor
final class DeviceIdentity {
    static let shared = DeviceIdentity()

    private let storageKey = "gs.deviceId"
    private let keychainService = "com.guidestream.tv.device"
    private let keychainAccount = "gs.deviceId"

    /// Stable UUID string for this device. Resolved once at init in this
    /// exact precedence: existing Keychain value → legacy UserDefaults
    /// "gs.deviceId" value (migrated into the Keychain) →
    /// `identifierForVendor` → fresh UUID.
    let deviceId: String

    /// Indicates whether this is the very first launch on this install (no id
    /// existed in the Keychain or UserDefaults before this run). Useful for
    /// first-open analytics.
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

        // Resolution order: Keychain → legacy UserDefaults → identifierForVendor → fresh UUID.
        let keychainId = Self.readKeychainId(service: keychainService, account: keychainAccount)
        let defaultsId = defaults.string(forKey: storageKey)

        let resolved: String
        var firstLaunch = false
        if let stored = keychainId, !stored.isEmpty {
            resolved = stored
        } else if let cached = defaultsId, !cached.isEmpty {
            // Existing install upgrading from the UserDefaults-only era —
            // keep its id and copy it into the Keychain so it survives the
            // next uninstall/reinstall.
            resolved = cached
            Self.writeKeychainId(cached, service: keychainService, account: keychainAccount)
        } else {
            // Prefer identifierForVendor so the same id is reused if the user
            // reinstalls while other apps from the same vendor are present.
            // Fall back to a fresh UUID otherwise.
            firstLaunch = true
            resolved = UIDevice.current.identifierForVendor?.uuidString
                ?? UUID().uuidString
            Self.writeKeychainId(resolved, service: keychainService, account: keychainAccount)
        }

        // Keep UserDefaults in sync so every existing reader keeps working.
        defaults.set(resolved, forKey: storageKey)

        self.deviceId = resolved
        self.isFirstLaunch = firstLaunch

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

    // MARK: - Keychain helpers

    /// Reads the stored device id from the Keychain. Returns `nil` on any
    /// failure (missing item, locked keychain, unexpected data) — never throws
    /// and never crashes.
    private static func readKeychainId(service: String, account: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        // Only require after-first-unlock accessibility so the read never
        // blocks; a locked-device read simply returns nil and the caller
        // falls back to the UserDefaults copy.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Writes the device id to the Keychain, replacing any existing value.
    /// Any failure is silently ignored so the UserDefaults copy remains the
    /// source of truth for this run — a Keychain write failure must never
    /// take the app down with it.
    private static func writeKeychainId(_ value: String, service: String, account: String) {
        let data = Data(value.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]

        // Update the existing item when present, otherwise add a new one.
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            ] as CFDictionary
        )
        guard updateStatus == errSecItemNotFound else { return }
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
}

//
//  TVDeviceIdentity.swift
//  GuideStreamTVTV
//
//  Stable per-device identifier for the Apple TV install. Persisted in
//  UserDefaults so guest watch list rows keep working across launches.
//  `identifierForVendor` is used as the seed on first launch — that lets
//  the tvOS install pair with the same vendor namespace as the phone
//  app when they are signed into the same Apple TV account.
//

import Foundation
import UIKit

@MainActor
final class TVDeviceIdentity {
    static let shared = TVDeviceIdentity()

    private let storageKey = "gs.tv.deviceId"

    let deviceId: String

    private init() {
        let defaults = UserDefaults.standard
        if let cached = defaults.string(forKey: storageKey), !cached.isEmpty {
            self.deviceId = cached
        } else {
            let fresh = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            defaults.set(fresh, forKey: storageKey)
            self.deviceId = fresh
        }
    }
}

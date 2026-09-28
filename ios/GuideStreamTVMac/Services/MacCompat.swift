//
//  MacCompat.swift
//  GuideStreamTVMac
//
//  The Mac target compiles the same service layer as tvOS plus ios/Shared.
//  Those files were written against UIKit, which does not exist on macOS.
//  This file supplies the few UIKit names they reach for, backed by AppKit,
//  so the shared sources stay untouched.
//

import AppKit
import SwiftUI

/// OS version string for analytics rows (device_sessions.os_version).
enum MacSystem {
    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}

/// Stand-in for the UIApplication calls made from ios/Shared
/// (PushTokenManager). The Mac build ships without push in its first
/// release, so remote-notification registration is a no-op here.
@MainActor
final class UIApplication {
    static let shared = UIApplication()
    private init() {}

    func registerForRemoteNotifications() {}

    func open(_ url: URL, options: [String: Any] = [:], completionHandler: ((Bool) -> Void)? = nil) {
        let ok = NSWorkspace.shared.open(url)
        completionHandler?(ok)
    }
}

/// Opens a URL in the default browser (or the app registered for it).
enum MacLinkOpener {
    @MainActor
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

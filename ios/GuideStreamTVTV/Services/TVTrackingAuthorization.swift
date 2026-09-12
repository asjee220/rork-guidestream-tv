//
//  TVTrackingAuthorization.swift
//  GuideStreamTVTV
//
//  App Tracking Transparency on Apple TV.
//
//  The tvOS app does not track. It links no ad SDK — only Supabase and
//  YouTubeKit — never reads the IDFA, and its own PrivacyInfo.xcprivacy
//  declares `NSPrivacyTracking = false` with an empty tracking-domain list.
//  The prompt is here because App Privacy in App Store Connect is ONE
//  record shared by every platform of the app, and the phone app — which
//  does serve AdMob ads — declares Device ID collected for tracking. App
//  Review read that shared label against the tvOS binary, found no ATT
//  request, and rejected tvOS 1.0.11 (19) under Guideline 5.1.2(i) on
//  12 Sep 2026.
//
//  Nothing downstream reads the result: no tvOS code path behaves
//  differently on `authorized` versus `denied`, because nothing on this
//  platform tracks either way. If the shared privacy label is ever split
//  per platform, or the phone app stops tracking, this whole file should
//  go — an alert that gates nothing is not worth a launch beat.
//
//  Available from tvOS 14; this target's deployment floor is 18.0, so no
//  availability guard is needed.
//

import AppTrackingTransparency
import Foundation
import UIKit

@MainActor
enum TVTrackingAuthorization {

    /// Set once the alert has been asked for in this process, so the
    /// launch `.task` and the `scenePhase` transition cannot both present
    /// it. The system itself only shows the alert while the status is
    /// `notDetermined`, so later launches are a no-op regardless.
    private static var didRequest = false

    /// Presents the tracking-authorization alert on first use.
    ///
    /// Must be called while the app is active — a request made before the
    /// scene is foregrounded is dropped by the system and the status stays
    /// `notDetermined` with no alert ever shown.
    static func requestIfNeeded() {
        guard !didRequest else { return }
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
            didRequest = true
            return
        }
        // A request made before the scene is foregrounded is dropped with no
        // alert, so leave `didRequest` clear and let the next call in — the
        // launch `.task` can land ahead of `.active`.
        guard UIApplication.shared.applicationState == .active else { return }
        didRequest = true
        ATTrackingManager.requestTrackingAuthorization { status in
            print("[ATT tvOS] authorization status: \(describe(status))")
        }
    }

    private static func describe(_ status: ATTrackingManager.AuthorizationStatus) -> String {
        switch status {
        case .authorized: return "Authorized"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not determined"
        @unknown default: return "Unrecognized"
        }
    }
}

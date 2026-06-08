//
//  TVAppDelegate.swift
//  GuideStreamTVTV
//
//  Handles tvOS remote-notification registration and presentation.
//  The shared PushTokenManager (in ios/Shared/) persists the APNs token
//  to Supabase so the Cloudflare Worker can deliver push notifications.
//

import UIKit
import UserNotifications
import Supabase

final class TVAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // MARK: - APNs registration

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        Task { @MainActor in
            await PushTokenManager.shared.saveToken(token)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[Push tvOS] APNs registration failed: \(error.localizedDescription)")
    }

    // MARK: - Notification handling

    /// Show banners when a push arrives while the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .badge, .sound, .list]
    }

    /// Handle taps on a notification — open deep link.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        if let deepLink = userInfo["deep_link"] as? String,
           let url = URL(string: deepLink) {
            await MainActor.run {
                UIApplication.shared.open(url)
            }
        }
    }
}

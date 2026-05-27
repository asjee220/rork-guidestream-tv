//
//  AppDelegate.swift
//  GuideStreamTV
//

import UIKit
import UserNotifications
import Supabase

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

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
        print("[Push] APNs registration failed: \(error.localizedDescription)")
    }

    // MARK: - URL handling (OAuth callbacks)

    /// Catch OAuth redirects from Google Sign-In, Apple, and password recovery.
    /// Supabase's `signInWithOAuth` uses `ASWebAuthenticationSession` internally,
    /// but this handler serves as a safety net for edge cases where the session
    /// doesn't intercept the callback (e.g. app-switching during authentication).
    func application(
        _ application: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        guard url.scheme == "guidestream" else { return false }
        Task {
            do {
                try await SupabaseManager.shared.client.auth.session(from: url)
                print("[Auth] OAuth callback handled via URL: \(url)")
            } catch {
                print("[Auth] URL session exchange failed: \(error.localizedDescription)")
            }
        }
        return true
    }

    // MARK: - Notification handling

    /// Show banners + sound + badge when a push arrives while the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .badge, .sound, .list]
    }

    /// Handle taps on a notification — open deep link + log the event.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo

        let titleId = userInfo["title_id"] as? String
        let platformId = userInfo["platform_id"] as? String
        let notifType = userInfo["notification_type"] as? String

        WatchIntentLogger.shared.log(
            eventType: .notificationOpened,
            titleId: titleId,
            platformId: platformId,
            metadata: [
                "notification_type": notifType ?? "",
                "source": "push_notification"
            ]
        )

        if let deepLink = userInfo["deep_link"] as? String,
           let url = URL(string: deepLink) {
            await MainActor.run {
                UIApplication.shared.open(url)
            }
        }
    }
}

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
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .authorized {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
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

        if let titleId, !titleId.isEmpty {
            // Route in-app: post the same notification GuideStreamTVApp's
            // onOpenURL handler posts, but enriched with the payload's
            // display metadata so the detail sheet renders correctly.
            let titleName = userInfo["title_name"] as? String
            let posterUrl = userInfo["poster_url"] as? String
            let isTV = Self.parseIsTV(from: userInfo)
            await MainActor.run {
                // Cold-launch-safe buffer: if the delegate fires before
                // ContentView's .onReceive subscriber is committed, the
                // NotificationCenter post is discarded. Writing the route
                // here lets ContentView drain it on first appearance. The
                // warm path still works via the post below; take-once
                // semantics on the inbox prevent double presentation.
                PendingRouteInbox.shared.setTitle(PendingTitleRoute(
                    titleId: titleId,
                    titleName: titleName,
                    posterUrl: posterUrl,
                    isTV: isTV
                ))
                var info: [String: Any] = ["titleId": titleId, "isTV": isTV]
                if let titleName, !titleName.isEmpty { info["titleName"] = titleName }
                if let posterUrl, !posterUrl.isEmpty { info["posterUrl"] = posterUrl }
                NotificationCenter.default.post(
                    name: .guideStreamOpenTitle,
                    object: nil,
                    userInfo: info
                )
            }
        } else if let gameId = userInfo["game_id"] as? String, !gameId.isEmpty {
            // Sports notification: route in-app to the game detail screen
            // instead of falling through to the legacy deep_link URL open.
            await MainActor.run {
                // Mirror the title branch: buffer for cold-launch safety
                // before posting for the warm path.
                PendingRouteInbox.shared.setGameId(gameId)
                NotificationCenter.default.post(
                    name: .guideStreamOpenSports,
                    object: nil,
                    userInfo: ["gameId": gameId]
                )
            }
        } else if let deepLink = userInfo["deep_link"] as? String,
                  let url = URL(string: deepLink) {
            // Legacy fallback (no title_id): guidestream://show payloads
            // continue on their existing unchanged path.
            await MainActor.run {
                UIApplication.shared.open(url)
            }
        }
    }

    /// Tolerantly parse `is_tv` from an APNs payload. JSON bridging can deliver
    /// Bool, NSNumber, Int, or the strings "true"/"false". Falls back to true
    /// when absent; `media_type == "movie"` always means not-TV.
    nonisolated private static func parseIsTV(from userInfo: [AnyHashable: Any]) -> Bool {
        if let mediaType = userInfo["media_type"] as? String,
           mediaType.lowercased() == "movie" {
            return false
        }
        guard let raw = userInfo["is_tv"] else { return true }
        if let b = raw as? Bool { return b }
        if let n = raw as? NSNumber { return n.boolValue }
        if let i = raw as? Int { return i != 0 }
        if let s = raw as? String {
            switch s.lowercased() {
            case "true", "1": return true
            case "false", "0": return false
            default: return true
            }
        }
        return true
    }
}

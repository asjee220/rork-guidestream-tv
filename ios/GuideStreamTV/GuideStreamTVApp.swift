//
//  GuideStreamTVApp.swift
//  GuideStreamTV
//

import SwiftUI
import Supabase
import WidgetKit

@main
struct GuideStreamTVApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        // Every time the user brings the app to the foreground,
                        // kick the widget timelines so the widget picks up any
                        // data that may have been written while the app was
                        // backgrounded (or if the widget missed a previous reload).
                        WidgetCenter.shared.reloadTimelines(ofKind: "GuideStreamWidget")
                        // Re-register for remote notifications on every
                        // activation (cold launch + each return to foreground)
                        // so iOS-rotated APNs tokens get refreshed in
                        // `push_tokens`. Idempotent — only fires when the user
                        // already granted permission; never shows the dialog.
                        Task { await PushTokenManager.shared.refreshRegistrationIfAuthorized() }
                    }
                }
                .onOpenURL { url in
                    guard url.scheme == "guidestream" else { return }

                    // Show deep links carry title + platform info so we can
                    // open the correct streaming app directly from a push tap.
                    if let host = url.host, host == "show" {
                        handleShowDeepLink(url)
                        return
                    }

                    // Title deep links (e.g. guidestream://title/tw:caedrel)
                    // route into the in-app detail views — CreatorDetailView for
                    // non-TMDB prefixed ids, ShowDetailScreen for bare TMDB ids.
                    if let host = url.host, host == "title" {
                        handleTitleDeepLink(url)
                        return
                    }

                    // OAuth callback (existing flow)
                    Task {
                        do {
                            try await SupabaseManager.shared.client.auth.session(from: url)
                            print("[Auth] SwiftUI onOpenURL handled: \(url)")
                        } catch {
                            print("[Auth] SwiftUI onOpenURL failed: \(error.localizedDescription)")
                        }
                    }
                }
        }
    }

    /// Parses a `guidestream://title/{title_id}` URL and routes to the appropriate
    /// in-app detail view. Prefixed ids (yt:, pod:, tw:, kick:) open CreatorDetailView;
    /// bare numeric TMDB ids open the existing show-detail path.
    private func handleTitleDeepLink(_ url: URL) {
        let rawTitleId = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !rawTitleId.isEmpty else {
            print("[DeepLink] title URL missing title_id: \(url)")
            return
        }
        print("[DeepLink] title deep link: title_id=\(rawTitleId)")
        // Post a notification so HomeView can route the user to the correct screen.
        NotificationCenter.default.post(
            name: .guideStreamOpenTitle,
            object: nil,
            userInfo: ["titleId": rawTitleId]
        )
    }

    /// Parses a `guidestream://show/{title_id}?platform=...&title=...` URL and
    /// opens the corresponding streaming app via `StreamingDeepLinker`. Falls
    /// back to a platform-name search when no Watchmode resolution is available.
    private func handleShowDeepLink(_ url: URL) {
        // Path is "/{title_id}" — drop the leading slash.
        let rawTitleId = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !rawTitleId.isEmpty else {
            print("[DeepLink] show URL missing title_id: \(url)")
            return
        }

        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let params = (comps?.queryItems ?? []).reduce(into: [String: String]()) { dict, item in
            dict[item.name] = item.value?.removingPercentEncoding ?? ""
        }

        let platform = params["platform"] ?? ""
        let platformId = params["platform_id"] ?? platform.lowercased()
        let title = params["title"] ?? ""

        print("[DeepLink] show deep link: title_id=\(rawTitleId) platform=\(platform) title=\(title)")

        // Log the watch intent so WatchGraph captures that the user acted on
        // a notification and intended to watch on this service.
        WatchIntentLogger.shared.log(
            eventType: .deeplinkFired,
            titleId: rawTitleId,
            platformId: platformId.isEmpty ? nil : platformId,
            metadata: [
                "url": url.absoluteString,
                "platform_name": platform,
                "title": title,
                "source": "push_notification"
            ]
        )

        // Open the streaming app. When we have a recognisable platform, use
        // the title for a search-based fallback; otherwise there's nowhere to go.
        guard !platform.isEmpty else {
            print("[DeepLink] no platform in show URL — cannot open streaming app")
            return
        }

        StreamingDeepLinker.open(
            platform: platform,
            title: title.isEmpty ? rawTitleId : title,
            tmdbId: nil,
            titleSlug: rawTitleId
        )
    }
}

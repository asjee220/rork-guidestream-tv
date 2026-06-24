//
//  GuideStreamTVApp.swift
//  GuideStreamTV
//

import SwiftUI
import Supabase

@main
struct GuideStreamTVApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    guard url.scheme == "guidestream" else { return }

                    // Show deep links carry title + platform info so we can
                    // open the correct streaming app directly from a push tap.
                    if let host = url.host, host == "show" {
                        handleShowDeepLink(url)
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

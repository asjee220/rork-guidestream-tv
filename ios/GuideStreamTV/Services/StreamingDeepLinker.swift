//
//  StreamingDeepLinker.swift
//  GuideStreamTV
//
//  Opens the appropriate streaming app on the device for a given platform and title.
//  Tries the native app URL scheme first; falls back to the platform's web URL
//  (which iOS will route into the installed app via universal links when possible).
//

import Foundation
import UIKit

enum StreamingDeepLinker {

    /// Resolves a (appURL, webURL) pair for a given platform + title.
    struct Target {
        let appURL: URL?
        let webURL: URL
    }

    /// Opens the streaming app for the given platform/title. Logs the intent.
    @MainActor
    static func open(
        platform: String,
        title: String,
        tmdbId: Int? = nil,
        isTV: Bool = false,
        titleSlug: String? = nil
    ) {
        let target = resolve(platform: platform, title: title, tmdbId: tmdbId, isTV: isTV)

        WatchIntentLogger.shared.log(
            eventType: .deeplinkFired,
            titleId: titleSlug ?? WatchIntentLogger.titleSlug(title),
            platformId: platform.lowercased(),
            metadata: [
                "url": (target.appURL ?? target.webURL).absoluteString,
                "platform_name": platform
            ]
        )

        if let appURL = target.appURL {
            UIApplication.shared.open(appURL, options: [:]) { success in
                if !success {
                    UIApplication.shared.open(target.webURL)
                }
            }
        } else {
            UIApplication.shared.open(target.webURL)
        }
    }

    /// Builds the best-effort deep link for a platform name. We don't always have
    /// a per-service title ID, so we try a title-search URL as the universal-link
    /// fallback — iOS will route it into the installed app when possible.
    static func resolve(platform: String, title: String, tmdbId: Int? = nil, isTV: Bool = false) -> Target {
        let key = platform.lowercased()
        let q = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        if key.contains("netflix") {
            return Target(
                appURL: URL(string: "nflx://www.netflix.com/search?q=\(q)"),
                webURL: URL(string: "https://www.netflix.com/search?q=\(q)")!
            )
        }
        if key.contains("hbo") || key.contains("max") {
            return Target(
                appURL: URL(string: "hbomax://"),
                webURL: URL(string: "https://play.max.com/search?q=\(q)")!
            )
        }
        if key.contains("hulu") {
            return Target(
                appURL: URL(string: "hulu://"),
                webURL: URL(string: "https://www.hulu.com/search?q=\(q)")!
            )
        }
        if key.contains("disney") {
            return Target(
                appURL: URL(string: "disneyplus://"),
                webURL: URL(string: "https://www.disneyplus.com/search?q=\(q)")!
            )
        }
        if key.contains("apple") {
            // Apple TV deep link form
            return Target(
                appURL: URL(string: "videos://tv.apple.com/search?term=\(q)"),
                webURL: URL(string: "https://tv.apple.com/search?term=\(q)")!
            )
        }
        if key.contains("prime") || key.contains("amazon") {
            return Target(
                appURL: URL(string: "aiv://"),
                webURL: URL(string: "https://www.primevideo.com/search/ref=atv_nb_sr?phrase=\(q)")!
            )
        }
        if key.contains("paramount") {
            return Target(
                appURL: URL(string: "paramountplus://"),
                webURL: URL(string: "https://www.paramountplus.com/search/?query=\(q)")!
            )
        }
        if key.contains("peacock") {
            return Target(
                appURL: URL(string: "peacock://"),
                webURL: URL(string: "https://www.peacocktv.com/search?q=\(q)")!
            )
        }
        if key.contains("youtube") {
            return Target(
                appURL: URL(string: "youtube://www.youtube.com/results?search_query=\(q)"),
                webURL: URL(string: "https://www.youtube.com/results?search_query=\(q)")!
            )
        }
        if key.contains("showtime") {
            return Target(
                appURL: URL(string: "showtimeanytime://"),
                webURL: URL(string: "https://www.showtime.com/")!
            )
        }
        if key.contains("starz") {
            return Target(
                appURL: URL(string: "starz://"),
                webURL: URL(string: "https://www.starz.com/")!
            )
        }
        if key.contains("crunchyroll") {
            return Target(
                appURL: URL(string: "crunchyroll://"),
                webURL: URL(string: "https://www.crunchyroll.com/search?q=\(q)")!
            )
        }

        // Generic fallback — Google search for "watch <title>"
        let fallback = "https://www.google.com/search?q=watch+\(q)+on+\(platform.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        return Target(appURL: nil, webURL: URL(string: fallback)!)
    }
}

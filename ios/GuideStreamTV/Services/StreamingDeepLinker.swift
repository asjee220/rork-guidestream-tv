//
//  StreamingDeepLinker.swift
//  GuideStreamTV
//
//  Opens the appropriate streaming app on the device for a given platform and title.
//  When a TMDB id is provided we look up the title's per-source iOS deep link via
//  Watchmode (which returns the universal-link URL that opens the streaming app
//  directly on the title page). If that lookup fails we fall back to a search URL.
//

import Foundation
import UIKit

enum StreamingDeepLinker {

    struct Target {
        let appURL: URL?
        let webURL: URL
    }

    /// Opens the streaming app for the given platform/title.
    /// If `tmdbId` is supplied, we first try to resolve a *title-specific* iOS deep
    /// link from Watchmode (so tapping "Watch on HBO Max" lands you on the show's
    /// page, not the app's home screen). Falls back to a search URL otherwise.
    @MainActor
    static func open(
        platform: String,
        title: String,
        tmdbId: Int? = nil,
        isTV: Bool = false,
        titleSlug: String? = nil
    ) {
        let fallback = resolve(platform: platform, title: title)

        // Log the intent immediately so analytics fires even if resolution races.
        WatchIntentLogger.shared.log(
            eventType: .deeplinkFired,
            titleId: titleSlug ?? WatchIntentLogger.titleSlug(title),
            platformId: platform.lowercased(),
            metadata: [
                "url": (fallback.appURL ?? fallback.webURL).absoluteString,
                "platform_name": platform,
                "tmdb_id": tmdbId.map(String.init) ?? ""
            ]
        )

        guard let tmdbId else {
            openTarget(fallback)
            return
        }

        // Try to resolve a per-title deep link, then open whichever URL we got.
        Task { @MainActor in
            if let direct = await resolveDirectURL(tmdbId: tmdbId, isTV: isTV, platform: platform) {
                UIApplication.shared.open(direct, options: [:]) { success in
                    if !success { openTarget(fallback) }
                }
            } else {
                openTarget(fallback)
            }
        }
    }

    @MainActor
    private static func openTarget(_ target: Target) {
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

    // MARK: - Watchmode resolution

    /// Looks up the title on Watchmode by TMDB id, finds the source matching the
    /// requested platform, and returns its iOS deep-link URL (universal link that
    /// opens the streaming app directly to the title page).
    private static func resolveDirectURL(tmdbId: Int, isTV: Bool, platform: String) async -> URL? {
        do {
            guard let watchmodeId = try await WatchmodeService.shared.watchmodeId(forTMDBId: tmdbId, isTV: isTV) else {
                return nil
            }
            let detail = try await WatchmodeService.shared.titleDetail(titleId: watchmodeId)
            guard let sources = detail.sources, !sources.isEmpty else { return nil }
            let candidates = sources.filter { matches(sourceName: $0.name, platform: platform) }
            // Prefer subscription/free over rent/purchase, and US region.
            let ranked = candidates.sorted { a, b in
                let ra = sourceRank(a), rb = sourceRank(b)
                if ra != rb { return ra < rb }
                let usA = (a.region ?? "").uppercased() == "US"
                let usB = (b.region ?? "").uppercased() == "US"
                if usA != usB { return usA }
                return false
            }
            for src in ranked {
                if let s = src.iosUrl, let url = URL(string: s) { return url }
                if let s = src.webUrl, let url = URL(string: s) { return url }
            }
            return nil
        } catch {
            return nil
        }
    }

    private static func sourceRank(_ s: WatchmodeSource) -> Int {
        switch (s.type.lowercased()) {
        case "sub": return 0
        case "free": return 1
        case "tve": return 2          // requires cable login
        case "rent": return 3
        case "purchase", "buy": return 4
        default: return 5
        }
    }

    /// Maps platform display names (HBO Max, Disney+, etc.) to Watchmode's
    /// source name strings.
    private static func matches(sourceName: String, platform: String) -> Bool {
        let s = sourceName.lowercased()
        let p = platform.lowercased()
        if p.contains("netflix") { return s.contains("netflix") }
        if p.contains("hbo") || p.contains("max") { return s.contains("max") || s.contains("hbo") }
        if p.contains("hulu") { return s.contains("hulu") }
        if p.contains("disney") { return s.contains("disney") }
        if p.contains("apple") { return s.contains("apple tv") }
        if p.contains("prime") || p.contains("amazon") { return s.contains("amazon") || s.contains("prime") }
        if p.contains("paramount") { return s.contains("paramount") }
        if p.contains("peacock") { return s.contains("peacock") }
        if p.contains("youtube") { return s.contains("youtube") }
        if p.contains("showtime") { return s.contains("showtime") }
        if p.contains("starz") { return s.contains("starz") }
        if p.contains("crunchyroll") { return s.contains("crunchyroll") }
        // Last resort: substring match either direction
        return s.contains(p) || p.contains(s)
    }

    // MARK: - Search-URL fallback

    static func resolve(platform: String, title: String) -> Target {
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

        let google = "https://www.google.com/search?q=watch+\(q)+on+\(platform.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        return Target(appURL: nil, webURL: URL(string: google)!)
    }
}

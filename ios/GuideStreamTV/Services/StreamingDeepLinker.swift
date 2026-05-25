//
//  StreamingDeepLinker.swift
//  GuideStreamTV
//
//  Opens the appropriate streaming app on the device for a given title.
//
//  Strategy (per-tap):
//    1. Look up the title's per-source iOS URL via Watchmode (using tmdb id).
//    2. From the matching source's `web_url` (which IS the universal link for
//       each streaming service), build the most reliable open URL for iOS —
//       preferring known-good native schemes (`nflx://title`, `videos://show`,
//       `youtube://watch`, `primevideo://detail`) over universal links.
//    3. For platforms where the native scheme doesn't accept title paths
//       (Disney+, Hulu, Max, Paramount+, Peacock, Crunchyroll), open the
//       universal HTTPS link — iOS routes it into the installed app via the
//       app's `apple-app-site-association` file.
//    4. If everything fails, fall back to the platform's search URL so the
//       user can still find their show inside the app.
//

import Foundation
import UIKit

enum StreamingDeepLinker {

    struct Target {
        let appURL: URL?
        let webURL: URL
    }

    /// Opens the streaming app for the given platform/title.
    ///
    /// When `tmdbId` is supplied we resolve a title-specific link from
    /// Watchmode (so "Watch on Netflix" lands on the show's page, not the
    /// app's home screen). If the lookup fails we open a search URL.
    @MainActor
    static func open(
        platform: String,
        title: String,
        tmdbId: Int? = nil,
        isTV: Bool = false,
        titleSlug: String? = nil
    ) {
        let fallback = resolve(platform: platform, title: title)

        // Fire analytics immediately so we always log the intent, even if
        // the network lookup races against the open.
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

        Task { @MainActor in
            if let direct = await resolveDirectURL(tmdbId: tmdbId, isTV: isTV, platform: platform) {
                #if DEBUG
                print("[Deeplink] Opening direct title URL: \(direct.absoluteString)")
                #endif
                UIApplication.shared.open(direct, options: [:]) { success in
                    if !success {
                        #if DEBUG
                        print("[Deeplink] Direct URL failed, falling back to: \(fallback.appURL?.absoluteString ?? fallback.webURL.absoluteString)")
                        #endif
                        openTarget(fallback)
                    }
                }
            } else {
                #if DEBUG
                print("[Deeplink] No direct URL resolved, using fallback for platform=\(platform)")
                #endif
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

    /// Picks the best deep-link URL for the requested platform by querying
    /// Watchmode for the title's per-source data. Returns the most reliable
    /// URL we can construct — preferring native schemes when known-good,
    /// otherwise the universal HTTPS link.
    private static func resolveDirectURL(tmdbId: Int, isTV: Bool, platform: String) async -> URL? {
        do {
            guard let watchmodeId = try await WatchmodeService.shared.watchmodeId(forTMDBId: tmdbId, isTV: isTV) else {
                return nil
            }
            let detail = try await WatchmodeService.shared.titleDetail(titleId: watchmodeId)
            guard let sources = detail.sources, !sources.isEmpty else { return nil }

            // Rank candidates: matching platform first, then by source type
            // (subscription > free > tve > rent > buy), then prefer US.
            let candidates = sources.filter { matches(sourceName: $0.name, platform: platform) }
            let pool: [WatchmodeSource] = candidates.isEmpty ? sources : candidates
            let ranked = pool.sorted { a, b in
                let ra = sourceRank(a), rb = sourceRank(b)
                if ra != rb { return ra < rb }
                let usA = (a.region ?? "").uppercased() == "US"
                let usB = (b.region ?? "").uppercased() == "US"
                if usA != usB { return usA }
                return false
            }

            for src in ranked {
                // Watchmode free tier returns "Deeplinks available for paid plans only."
                // in ios_url, so guard against placeholders.
                if let s = src.iosUrl, isRealURL(s), let url = URL(string: s) {
                    #if DEBUG
                    print("[Deeplink] Watchmode ios_url for \(src.name): \(s)")
                    #endif
                    return url
                }
                if let s = src.webUrl, isRealURL(s) {
                    // Prefer a known-good native scheme; otherwise the
                    // universal HTTPS link is what the streaming app's
                    // associated-domains entitlement will catch.
                    if let native = nativeDeepLink(fromWebURL: s, sourceName: src.name) {
                        #if DEBUG
                        print("[Deeplink] Native scheme for \(src.name): \(native.absoluteString)")
                        #endif
                        return native
                    }
                    if let url = URL(string: s) {
                        #if DEBUG
                        print("[Deeplink] Universal link for \(src.name): \(s)")
                        #endif
                        return url
                    }
                }
            }
            return nil
        } catch {
            #if DEBUG
            print("[Deeplink] Watchmode lookup failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    /// Filters out Watchmode placeholders ("Deeplinks available for paid plans only.").
    private static func isRealURL(_ s: String) -> Bool {
        let lower = s.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.contains("://") else { return false }
        return URL(string: s) != nil
    }

    // MARK: - Native scheme conversion

    /// Converts a Watchmode `web_url` to a native iOS scheme when the platform
    /// has a known-working scheme that accepts title paths.
    ///
    /// For platforms where the native scheme only opens the home screen
    /// (Disney+, Hulu, Max, etc.), we return `nil` — the caller then opens
    /// the universal HTTPS URL, which iOS routes into the app via universal
    /// links. That's actually the more reliable path for those platforms.
    private static func nativeDeepLink(fromWebURL web: String, sourceName: String) -> URL? {
        guard let comps = URLComponents(string: web) else { return nil }
        let host = (comps.host ?? "").lowercased()
        let path = comps.path
        let name = sourceName.lowercased()

        // Netflix — `nflx://www.netflix.com/title/{id}` opens directly to the title.
        if host.contains("netflix.com") || name.contains("netflix") {
            if path.contains("/title/") {
                return URL(string: "nflx://www.netflix.com\(path)")
            }
            return URL(string: "nflx://www.netflix.com\(path.isEmpty ? "/" : path)")
        }

        // YouTube — convert /watch?v= to youtube:// scheme.
        if host.contains("youtube.com") || host.contains("youtu.be") || name.contains("youtube") {
            if let v = comps.queryItems?.first(where: { $0.name == "v" })?.value {
                return URL(string: "youtube://www.youtube.com/watch?v=\(v)")
            }
            // youtu.be/{id} shortlink
            if host.contains("youtu.be") {
                let id = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !id.isEmpty { return URL(string: "youtube://www.youtube.com/watch?v=\(id)") }
            }
            // Universal link is fine for other YouTube paths (channels, playlists).
            return nil
        }

        // Apple TV — `videos://tv.apple.com/...` works for both shows and movies.
        if host.contains("tv.apple.com") || name.contains("apple tv") {
            return URL(string: "videos://tv.apple.com\(path)")
        }

        // Prime Video — modern scheme is `primevideo://detail?gti={asin}`,
        // and the universal link via primevideo.com routes into the app.
        // We extract the ASIN from `gti=` when present.
        if host.contains("primevideo.com") || host.contains("amazon.com") || name.contains("prime video") || name.contains("amazon prime") {
            if let gti = comps.queryItems?.first(where: { $0.name == "gti" })?.value, !gti.isEmpty {
                return URL(string: "primevideo://detail?gti=\(gti)")
            }
            // /detail/{ASIN}/... path style
            if path.contains("/detail/") {
                let parts = path.split(separator: "/").map(String.init)
                if let idx = parts.firstIndex(of: "detail"), idx + 1 < parts.count {
                    let asin = parts[idx + 1]
                    return URL(string: "primevideo://detail?gti=\(asin)")
                }
            }
            // No ASIN extractable — return nil so caller uses the universal link.
            return nil
        }

        // For the platforms below, the universal HTTPS link is more reliable
        // than the custom scheme (which usually only opens the app's home).
        // Returning nil signals "use the web URL directly via UIApplication.open".
        if host.contains("disneyplus.com") || name.contains("disney+") || name.contains("disney plus") { return nil }
        if host.contains("hulu.com") || name.contains("hulu") { return nil }
        if host.contains("max.com") || host.contains("hbomax.com") || name.contains("max") || name.contains("hbo") { return nil }
        if host.contains("paramountplus.com") || host.contains("paramount.com") || name.contains("paramount") { return nil }
        if host.contains("peacocktv.com") || host.contains("peacock.com") || name.contains("peacock") { return nil }
        if host.contains("crunchyroll.com") || name.contains("crunchyroll") { return nil }
        if host.contains("showtime.com") || host.contains("sho.com") || name.contains("showtime") { return nil }
        if host.contains("starz.com") || name.contains("starz") { return nil }

        return nil
    }

    private static func sourceRank(_ s: WatchmodeSource) -> Int {
        switch s.type.lowercased() {
        case "sub": return 0
        case "free": return 1
        case "tve": return 2          // requires cable login
        case "rent": return 3
        case "purchase", "buy": return 4
        default: return 5
        }
    }

    /// Maps a platform display name (e.g. "HBO Max", "DISNEY+") to a
    /// Watchmode source name with fuzzy matching.
    private static func matches(sourceName: String, platform: String) -> Bool {
        let s = sourceName.lowercased()
        let p = platform.lowercased()
        if p.isEmpty { return true }     // no filter when caller doesn't know
        if p.contains("netflix") { return s.contains("netflix") }
        if p.contains("hbo") || p.contains("max") { return s.contains("max") || s.contains("hbo") }
        if p.contains("hulu") { return s.contains("hulu") }
        if p.contains("disney") { return s.contains("disney") }
        if p.contains("apple") { return s.contains("apple tv") }
        if p.contains("prime") || p.contains("amazon") { return s.contains("amazon") || s.contains("prime") }
        if p.contains("paramount") { return s.contains("paramount") }
        if p.contains("peacock") { return s.contains("peacock") }
        if p.contains("youtube") { return s.contains("youtube") }
        if p.contains("showtime") { return s.contains("showtime") || s.contains("sho ") }
        if p.contains("starz") { return s.contains("starz") }
        if p.contains("crunchyroll") { return s.contains("crunchyroll") }
        // Last-resort substring either direction.
        return s.contains(p) || p.contains(s)
    }

    // MARK: - Search-URL fallback

    /// Builds a (native scheme, web URL) pair for a search-based open when
    /// we don't have a title-specific deep link. The native scheme is tried
    /// first; if iOS rejects it (app not installed), we fall through to the
    /// HTTPS URL.
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
                appURL: URL(string: "primevideo://"),
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

//
//  StreamingDeepLinker.swift
//  GuideStreamTV
//
//  Opens the appropriate streaming app on the device for a given title.
//
//  Why deep links to a specific show/movie used to open the app home
//  instead of the title page:
//
//  * Old approach: convert Watchmode's `web_url` (e.g. `https://www.netflix.com/title/80057281`)
//    into a custom URL scheme like `nflx://www.netflix.com/title/80057281`. iOS launches the
//    app via the scheme, but the streaming apps frequently strip / ignore the path,
//    so Netflix / Apple TV / Prime end up on the home screen.
//
//  * New approach: open the HTTPS `web_url` with `UIApplication.shared.open` and
//    the `universalLinksOnly: true` option. That forces iOS to route the URL into the
//    installed streaming app via its `applinks:` entitlement, preserving the path
//    (`/title/...`, `/series/...`, `/movie/...`) so the app lands directly on the
//    title page. If the app isn't installed or doesn't claim the URL, the open
//    request returns success=false and we fall back to the native scheme (so we
//    at least open the app's home), and finally to Safari.
//
//  Sheets that already have a resolved `WatchmodeSource` should call
//  `openResolvedURL` instead of `open(...)` — that path skips the second Watchmode
//  round-trip and removes the previous race where the sheet's dismiss animation
//  ran ahead of the URL open, causing iOS to silently drop the foreground request.
//

import Foundation
import UIKit

enum StreamingDeepLinker {

    struct Target {
        let appURL: URL?
        let webURL: URL
    }

    // MARK: - Public API

    /// Opens a pre-resolved title URL (typically Watchmode's `web_url`) without
    /// re-querying Watchmode. Preferred entry point from sheets that already
    /// resolved a `WatchmodeSource` — avoids ~500–1500ms of latency and the
    /// dismiss-during-open race that previously dropped the launch.
    @MainActor
    static func openResolvedURL(
        _ url: URL,
        platform: String,
        title: String,
        tmdbId: Int? = nil,
        titleSlug: String? = nil
    ) {
        let urlString = url.absoluteString
        print("[Deeplink] openResolvedURL platform=\(platform) url=\(urlString)")

        WatchIntentLogger.shared.log(
            eventType: .deeplinkFired,
            titleId: titleSlug ?? WatchIntentLogger.titleSlug(title),
            platformId: platform.lowercased(),
            metadata: [
                "url": urlString,
                "platform_name": platform,
                "tmdb_id": tmdbId.map(String.init) ?? "",
                "source": "pre_resolved"
            ]
        )

        openWithFallback(url, platform: platform, title: title)
    }

    /// Opens the streaming app for the given platform/title. When `tmdbId` is
    /// provided, queries Watchmode for the title-specific URL; otherwise opens
    /// a search-based fallback.
    @MainActor
    static func open(
        platform: String,
        title: String,
        tmdbId: Int? = nil,
        isTV: Bool = false,
        titleSlug: String? = nil
    ) {
        let fallback = resolve(platform: platform, title: title)

        WatchIntentLogger.shared.log(
            eventType: .deeplinkFired,
            titleId: titleSlug ?? WatchIntentLogger.titleSlug(title),
            platformId: platform.lowercased(),
            metadata: [
                "url": (fallback.appURL ?? fallback.webURL).absoluteString,
                "platform_name": platform,
                "tmdb_id": tmdbId.map(String.init) ?? "",
                "source": tmdbId == nil ? "search_fallback" : "watchmode_lookup"
            ]
        )

        guard let tmdbId else {
            print("[Deeplink] No tmdbId; opening search fallback for \(platform)")
            openTarget(fallback)
            return
        }

        Task { @MainActor in
            if let direct = await resolveDirectURL(tmdbId: tmdbId, isTV: isTV, platform: platform) {
                print("[Deeplink] Watchmode resolved \(platform): \(direct.absoluteString)")
                openWithFallback(direct, platform: platform, title: title)
            } else {
                print("[Deeplink] No Watchmode URL for \(platform); falling back to search")
                openTarget(fallback)
            }
        }
    }

    // MARK: - Open chain

    /// Three-step open chain:
    ///   1. **HTTPS + `universalLinksOnly: true`** — forces iOS to route the URL
    ///      into the installed streaming app via its `applinks:` entitlement.
    ///      This is what makes the app land on the actual title, not just home.
    ///      Returns false if no installed app claims the URL.
    ///   2. **Native scheme home** (e.g. `nflx://`, `disneyplus://`) — at least
    ///      opens the app so the user can search manually.
    ///   3. **Open in Safari** — last resort if the app isn't installed at all.
    @MainActor
    private static func openWithFallback(_ url: URL, platform: String, title: String) {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "https" || scheme == "http" {
            UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { universalOk in
                if universalOk {
                    print("[Deeplink] ✓ universal link opened in app: \(url.absoluteString)")
                } else {
                    print("[Deeplink] universal link not claimed by any app; trying native scheme home")
                    openHomeOrSafariFallback(platform: platform, title: title, originalURL: url)
                }
            }
        } else {
            // Already a native scheme — open directly. iOS handles the
            // app-not-installed case via the completion handler.
            UIApplication.shared.open(url, options: [:]) { ok in
                if ok {
                    print("[Deeplink] ✓ native scheme opened: \(url.absoluteString)")
                } else {
                    print("[Deeplink] native scheme failed; trying platform fallback")
                    openHomeOrSafariFallback(platform: platform, title: title, originalURL: url)
                }
            }
        }
    }

    /// Tries the platform's native-scheme app home; if that also fails (app
    /// not installed), opens the URL in Safari as the last-resort path.
    @MainActor
    private static func openHomeOrSafariFallback(platform: String, title: String, originalURL: URL) {
        let target = resolve(platform: platform, title: title)

        if let appURL = target.appURL {
            UIApplication.shared.open(appURL, options: [:]) { ok in
                if ok {
                    print("[Deeplink] ✓ opened app home via native scheme: \(appURL.absoluteString)")
                } else {
                    print("[Deeplink] native scheme home failed too; opening in Safari")
                    UIApplication.shared.open(originalURL, options: [:])
                }
            }
        } else {
            UIApplication.shared.open(originalURL, options: [:])
        }
    }

    /// Opens the search-based `Target` we use when no Watchmode resolution is
    /// available (sports, missing tmdbId, etc.). Native scheme is tried first;
    /// if iOS rejects it (app not installed), we fall through to the HTTPS URL.
    @MainActor
    private static func openTarget(_ target: Target) {
        if let appURL = target.appURL {
            UIApplication.shared.open(appURL, options: [:]) { ok in
                if !ok {
                    UIApplication.shared.open(target.webURL)
                }
            }
        } else {
            UIApplication.shared.open(target.webURL)
        }
    }

    // MARK: - Watchmode resolution

    /// Picks the best deep-link URL for the requested platform by querying
    /// Watchmode for the title's per-source data. Always returns the
    /// universal HTTPS link (`web_url`) — we deliberately do NOT convert
    /// to a custom scheme here because the streaming apps' AASA files
    /// honour the HTTPS path and route to the title, whereas the custom
    /// schemes typically only open the app home.
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
                // in ios_url, so isRealURL filters those out. When a paid Watchmode
                // tier returns a real iOS deep link, prefer that.
                if let s = src.iosUrl, isRealURL(s), let url = URL(string: s) {
                    print("[Deeplink] watchmode ios_url for \(src.name): \(s)")
                    return url
                }
                // Universal HTTPS link — the path is what makes the app land
                // on the title page via universal-link routing.
                if let s = src.webUrl, isRealURL(s), let url = URL(string: s) {
                    print("[Deeplink] watchmode web_url for \(src.name): \(s)")
                    return url
                }
            }
            return nil
        } catch {
            print("[Deeplink] Watchmode lookup failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Filters out Watchmode placeholders ("Deeplinks available for paid plans only.").
    private static func isRealURL(_ s: String) -> Bool {
        let lower = s.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.contains("://") else { return false }
        if lower.contains("deeplinks available") || lower.contains("paid plan") { return false }
        return URL(string: s) != nil
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

        // MARK: Sports broadcasters
        // Note: live sports broadcasters don't expose game-specific deep
        // links publicly, so these always open the app to its home screen
        // (or the watch landing page). That's the best we can do.

        // ESPN / ESPN+ / ESPN2 / ESPNU
        if key.contains("espn") {
            return Target(
                appURL: URL(string: "sportscenter://"),
                webURL: URL(string: "https://www.espn.com/watch/")!
            )
        }
        // TNT / TBS / truTV — Bleacher Report Live carries the streams
        if key.contains("tnt") || key.contains("tbs") || key.contains("trutv") {
            return Target(
                appURL: URL(string: "bleacherreport://"),
                webURL: URL(string: "https://bleacherreport.com/live")!
            )
        }
        // FOX Sports / FS1 / FS2
        if key.contains("fox") {
            return Target(
                appURL: URL(string: "foxsports://"),
                webURL: URL(string: "https://www.foxsports.com/live")!
            )
        }
        // NBC Sports — most live coverage now lives in the Peacock app.
        if key.contains("nbc") {
            return Target(
                appURL: URL(string: "nbcsports://"),
                webURL: URL(string: "https://www.nbcsports.com/live")!
            )
        }
        // CBS Sports
        if key.contains("cbs") {
            return Target(
                appURL: URL(string: "cbssportsapp://"),
                webURL: URL(string: "https://www.cbssports.com/live/")!
            )
        }
        // ABC — owned by Disney, watch via the ESPN app for sports.
        if key.contains("abc") {
            return Target(
                appURL: URL(string: "sportscenter://"),
                webURL: URL(string: "https://www.espn.com/watch/")!
            )
        }
        // NFL Network / NFL+
        if key.contains("nfl") {
            return Target(
                appURL: URL(string: "nflmobile://"),
                webURL: URL(string: "https://www.nfl.com/plus/")!
            )
        }
        // NBA TV / NBA League Pass
        if key.contains("nba") {
            return Target(
                appURL: URL(string: "nbaapp://"),
                webURL: URL(string: "https://www.nba.com/watch")!
            )
        }
        // MLB Network / MLB.tv
        if key.contains("mlb") {
            return Target(
                appURL: URL(string: "mlbatbat://"),
                webURL: URL(string: "https://www.mlb.com/tv")!
            )
        }
        // NHL Network / NHL.tv
        if key.contains("nhl") {
            return Target(
                appURL: URL(string: "nhl://"),
                webURL: URL(string: "https://www.nhl.com/tv")!
            )
        }
        // UFC Fight Pass
        if key.contains("ufc") {
            return Target(
                appURL: URL(string: "ufc://"),
                webURL: URL(string: "https://www.ufc.com/fight-pass")!
            )
        }
        // FuboTV — common cord-cutter aggregator for live sports.
        if key.contains("fubo") {
            return Target(
                appURL: URL(string: "fubotv://"),
                webURL: URL(string: "https://www.fubo.tv/welcome")!
            )
        }
        // Sling TV
        if key.contains("sling") {
            return Target(
                appURL: URL(string: "sling://"),
                webURL: URL(string: "https://www.sling.com/")!
            )
        }
        // DAZN — boxing / international sports
        if key.contains("dazn") {
            return Target(
                appURL: URL(string: "dazn://"),
                webURL: URL(string: "https://www.dazn.com/")!
            )
        }

        let google = "https://www.google.com/search?q=watch+\(q)+on+\(platform.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        return Target(appURL: nil, webURL: URL(string: google)!)
    }
}

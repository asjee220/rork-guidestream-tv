//
// TVOSDeepLinker.swift
// GuideStreamTV (tvOS target)
//
// The tvOS counterpart to StreamingDeepLinker. Runs INSIDE the GuideStream
// tvOS app and opens the streaming app locally on the Apple TV when a
// "Play on TV" command arrives over Supabase realtime.
//
// Why a separate file from StreamingDeepLinker:
// tvOS streaming apps do NOT share the iPhone's URL schemes. Some schemes
// are different, many are undocumented, and a few apps support no inter-app
// deep linking on tvOS at all. The iOS table cannot be reused as-is.
//
// Strategy (three tiers, tried in order):
// 1. PLAY — open directly to the title's playback page (best UX).
// 2. HOME — open the app to its landing screen (always works if installed).
// 3. SEARCH— open an in-app/web search for the title so the user finishes
// in one click.
//
// Each platform carries a `confidence` flag describing how well tvOS deep
// linking is known to work, so the hardware test matrix is explicit. Verify
// every PLAY link on a real Apple TV 4K before trusting it in a demo — these
// schemes break with app updates (Netflix changed theirs in Sept 2025).
//
// How to discover/verify a working PLAY link for a new app (pyatv method):
// • Open the title in the iOS or macOS app, use Share → Copy Link.
// • Or inspect the app's associated-domains / apple-app-site-association.
// • Test the resulting URL with UIApplication.shared.open on the device.
//

import Foundation
import UIKit

enum TVOSDeepLinker {

    struct TVTarget {
        let playURL: URL?        // tier 1: direct to the title
        let appHomeURL: URL?     // tier 2: app landing screen
        let searchURL: URL?      // tier 3: search inside the app / on the web
        let confidence: PlaybackConfidence
    }

    /// Opens the best available destination for the title on this Apple TV.
    /// Walks tvosDeepLink (tier 0) → PLAY → HOME → SEARCH, falling through
    /// whenever `open` reports the previous URL couldn't be handled (app not
    /// installed, scheme rejected).
    @MainActor
    static func open(
        platform: String,
        title: String,
        contentURL: URL? = nil,
        tvosDeepLink: URL? = nil,
        completion: ((Bool) -> Void)? = nil
    ) {
        let target = resolve(platform: platform, title: title, contentURL: contentURL)
        var chain: [URL] = []
        // Split the incoming tvosDeepLink by scheme: native custom schemes
        // (nflx://, aiv://, vuduapp://, etc.) go before playURL; https
        // universal links (play.hbomax.com, tv.apple.com) go after playURL
        // but before app home. tvOS has no browser, so an https URL placed
        // first silently consumes the launch and the user lands nowhere.
        if let tvosDeepLink, !Self.isWebScheme(tvosDeepLink) {
            chain.append(tvosDeepLink)
        }
        if let playURL = target.playURL { chain.append(playURL) }
        if let tvosDeepLink, Self.isWebScheme(tvosDeepLink) {
            chain.append(tvosDeepLink)
        }
        chain.append(contentsOf: [target.appHomeURL, target.searchURL].compactMap { $0 })

        #if DEBUG
        print("[tvOS Deeplink] \(platform) confidence=\(target.confidence) chain=\(chain.map(\.absoluteString))")
        #endif

        openChain(chain, completion: completion)
    }

    /// Tries each URL in order; the first one iOS/tvOS can open wins.
    @MainActor
    private static func openChain(_ urls: [URL], completion: ((Bool) -> Void)?) {
        guard let first = urls.first else { completion?(false); return }
        let rest = Array(urls.dropFirst())
        UIApplication.shared.open(first, options: [:]) { success in
            if success {
                completion?(true)
            } else {
                openChain(rest, completion: completion)
            }
        }
    }

    /// Opens a YouTube creator channel on the tvOS YouTube app. Walks the
    /// channel URL, then a search by name, then the YouTube app home, so a
    /// creator lands on their channel where the tvOS app supports it and
    /// inside the YouTube app in every other case.
    @MainActor
    static func openYouTubeChannel(channelId: String, name: String, completion: ((Bool) -> Void)? = nil) {
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let chain: [URL] = [
            URL(string: "youtube://www.youtube.com/channel/\(channelId)"),
            URL(string: "youtube://www.youtube.com/results?search_query=\(encodedName)"),
            URL(string: "youtube://")
        ].compactMap { $0 }
        openChain(chain, completion: completion)
    }

    /// Returns true when the URL's scheme is http or https (a universal
    /// link that tvOS cannot open in a browser), false for native custom
    /// schemes (nflx://, aiv://, youtube://, etc.).
    private static func isWebScheme(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        return scheme == "http" || scheme == "https"
    }

    // MARK: - Per-platform resolution

    /// Builds the tiered target for a platform. `contentURL` is the resolved
    /// web/universal URL the iPhone already produced via Watchmode (e.g.
    /// https://www.netflix.com/watch/81587873); we convert it to the tvOS
    /// PLAY scheme where one is known.
    static func resolve(platform: String, title: String, contentURL: URL?) -> TVTarget {
        // When the iPhone already supplied a native tvOS deep-link scheme
        // (e.g. hulu://, paramountplus://, nflx://, peacock://), use it
        // directly as the playURL. The existing per-platform branches are
        // consulted without contentURL so the home/search fallback tiers
        // are still available if the scheme isn't handled by the OS.
        if let contentURL,
           let scheme = contentURL.scheme?.lowercased(),
           scheme != "http", scheme != "https" {
            let fallback = resolve(platform: platform, title: title, contentURL: nil)
            return TVTarget(
                playURL: contentURL,
                appHomeURL: fallback.appHomeURL,
                searchURL: fallback.searchURL,
                confidence: fallback.confidence
            )
        }

        let key = platform.lowercased()
        let q = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let contentId = extractContentId(from: contentURL)

        // NETFLIX — best-supported on tvOS. `nflx://.../watch/{id}` plays directly.
        if key.contains("netflix") {
            let play = contentId.map { URL(string: "nflx://www.netflix.com/watch/\($0)") } ?? nil
            return TVTarget(
                playURL: play ?? nil,
                appHomeURL: URL(string: "nflx://"),
                searchURL: URL(string: "nflx://www.netflix.com/search?q=\(q)"),
                confidence: PlaybackSupport.confidence(for: platform)
            )
        }

        // HULU — `hulu://w/{id}` opens the title; playback is inconsistent by version.
        if key.contains("hulu") {
            let play = contentId.map { URL(string: "hulu://w/\($0)") } ?? nil
            return TVTarget(
                playURL: play ?? nil,
                appHomeURL: URL(string: "hulu://"),
                searchURL: URL(string: "hulu://search?q=\(q)"),
                confidence: PlaybackSupport.confidence(for: platform)
            )
        }

        // DISNEY+ — tvOS deep-link scheme not publicly documented for titles.
        if key.contains("disney") {
            return TVTarget(
                playURL: nil,
                appHomeURL: URL(string: "disneyplus://"),
                searchURL: nil,
                confidence: PlaybackSupport.confidence(for: platform)
            )
        }

        // MAX / HBO MAX — opens to home reliably; title deep links unverified on tvOS.
        if key.contains("hbo") || key.contains("max") {
            return TVTarget(
                playURL: nil,
                appHomeURL: URL(string: "hbomax://"),
                searchURL: nil,
                confidence: PlaybackSupport.confidence(for: platform)
            )
        }

        // PRIME VIDEO
        if key.contains("prime") || key.contains("amazon") {
            return TVTarget(
                playURL: nil,
                appHomeURL: URL(string: "aiv://aiv/resume"),
                searchURL: nil,
                confidence: PlaybackSupport.confidence(for: platform)
            )
        }

        // APPLE TV — Apple's own app; `videos://` opens it, but you usually
        // route Apple Originals through the system rather than a scheme.
        if key.contains("apple") {
            return TVTarget(
                playURL: nil,
                appHomeURL: URL(string: "videos://"),
                searchURL: nil,
                confidence: PlaybackSupport.confidence(for: platform)
            )
        }

        // PARAMOUNT+
        if key.contains("paramount") {
            return TVTarget(
                playURL: nil,
                appHomeURL: URL(string: "paramountplus://"),
                searchURL: nil,
                confidence: PlaybackSupport.confidence(for: platform)
            )
        }

        // PEACOCK
        if key.contains("peacock") {
            return TVTarget(
                playURL: nil,
                appHomeURL: URL(string: "peacock://"),
                searchURL: nil,
                confidence: PlaybackSupport.confidence(for: platform)
            )
        }

        // YOUTUBE — `youtube://` opens; video id plays where present.
        if key.contains("youtube") {
            let play = contentId.map { URL(string: "youtube://www.youtube.com/watch?v=\($0)") } ?? nil
            return TVTarget(
                playURL: play ?? nil,
                appHomeURL: URL(string: "youtube://"),
                searchURL: URL(string: "youtube://results?search_query=\(q)"),
                confidence: PlaybackSupport.confidence(for: platform)
            )
        }

        // CRUNCHYROLL
        if key.contains("crunchyroll") {
            return TVTarget(
                playURL: nil,
                appHomeURL: URL(string: "crunchyroll://"),
                searchURL: nil,
                confidence: PlaybackSupport.confidence(for: platform)
            )
        }

        // BROADCASTERS — best-effort app schemes for sports/game rows that
        // have no TMDB id and no YouTube channel. These schemes are
        // best-effort and MUST be verified on a real Apple TV before
        // trusting them in a demo; tvOS app schemes change without notice.
        // Broadcasters with no known public tvOS scheme (CHSN, CNBC, TNT,
        // TBS, ABC, CBS, local network affiliates) fall through to the
        // all-nil target so the launch fails cleanly rather than
        // mis-opening another app.
        if key.contains("espn") {
            return TVTarget(playURL: nil, appHomeURL: URL(string: "espn://"), searchURL: nil, confidence: PlaybackSupport.confidence(for: platform))
        }
        if key.contains("fox sports") || key.contains("foxsports") {
            return TVTarget(playURL: nil, appHomeURL: URL(string: "foxsports://"), searchURL: nil, confidence: PlaybackSupport.confidence(for: platform))
        }
        if key.contains("nbc sports") || key.contains("nbcsports") {
            return TVTarget(playURL: nil, appHomeURL: URL(string: "nbcsports://"), searchURL: nil, confidence: PlaybackSupport.confidence(for: platform))
        }

        // Unknown platform — nothing safe to open on tvOS.
        return TVTarget(playURL: nil, appHomeURL: nil, searchURL: nil, confidence: PlaybackSupport.confidence(for: platform))
    }

    // MARK: - Helpers

    /// Pulls the numeric/string content id from a resolved web URL. Handles
    /// the common `/watch/{id}`, `/title/{id}`, `?v={id}` shapes. Returns nil
    /// when the URL is search-only or unrecognized.
    private static func extractContentId(from url: URL?) -> String? {
        guard let url else { return nil }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)

        // youtube ?v=
        if let v = comps?.queryItems?.first(where: { $0.name == "v" })?.value {
            return v
        }

        // /watch/{id} or /title/{id}
        let parts = url.pathComponents.filter { $0 != "/" }
        if let idx = parts.firstIndex(where: { $0 == "watch" || $0 == "title" }),
           idx + 1 < parts.count {
            // Strip any trailing query already removed by pathComponents.
            return parts[idx + 1]
        }

        // Trailing numeric segment (some apps use /{id} directly).
        if let last = parts.last, last.allSatisfy(\.isNumber), !last.isEmpty {
            return last
        }

        return nil
    }
}

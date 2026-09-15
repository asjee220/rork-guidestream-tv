//
//  TVDeepLinkResolver.swift
//  GuideStreamTVTV
//
//  Picks the URL that actually opens a title on this Apple TV, out of the
//  sources `watchmode_resolve` returned.
//
//  This logic was private to TVTitleSheet, and that is exactly why the Home
//  hero's Continue button did not have it: that button called
//  `TVOSDeepLinker.open(platform:title:)` with a service name and no URL at
//  all, so the furthest it could ever get was the service's home screen —
//  while the title screen two presses away opened the exact episode. One
//  copy now, used by both.
//
//  The ordering is the whole point:
//
//  1. Episode-level before title-level. A title row's id names ONE episode
//     (a Prime `gti`, a Hulu show guid), so opening a series off the title
//     row lands on whatever episode that row happens to carry — Reacher
//     opened S3E2 from the phone on 15 Sep 2026 for precisely this reason.
//  2. Native schemes (nflx://, aiv://, hulu:///, pplus://, vuduapp://)
//     before https universal links. tvOS has no browser, so an https URL
//     tried first can consume the launch and land the viewer nowhere.
//  3. The brand guard at every step, so a Prime link served against an
//     Apple TV+ row can never open Prime.
//

import Foundation

enum TVDeepLinkResolver {

    typealias Source = TVWatchmodeResolver.TVResolvedSource

    /// The best app-opening URL for `source`, or nil when nothing usable and
    /// on-brand was supplied. Pass `episode` whenever an episode-level source
    /// for the SAME service is known — the caller owns that match, because
    /// only it knows which episode was asked for.
    static func deepLink(for source: Source, episode: Source? = nil) -> URL? {
        let appUrls = [episode?.tvosUrl, source.tvosUrl, episode?.iosUrl, source.iosUrl]

        for candidate in appUrls {
            if let url = usable(candidate, forService: source.name), !isWebScheme(url) { return url }
        }
        for candidate in appUrls {
            if let url = usable(candidate, forService: source.name), isWebScheme(url) { return url }
        }
        return webURL(for: source, episode: episode)
    }

    /// The service's web URL for this title. On tvOS this is not something to
    /// open — there is no browser — but `TVOSDeepLinker` reads a content id
    /// out of it when it has to rebuild a scheme itself.
    static func webURL(for source: Source, episode: Source? = nil) -> URL? {
        for candidate in [episode?.webUrl, source.webUrl] {
            if let url = usable(candidate, forService: source.name) { return url }
        }
        return nil
    }

    // MARK: - Candidate filtering

    /// A candidate is usable when it is a real URL (not Watchmode's free-tier
    /// placeholder sentence, "Deeplinks available for paid plans only.") and
    /// its brand is either unknown or the service's own.
    private static func usable(_ raw: String?, forService name: String) -> URL? {
        guard let raw, raw.contains("://") else { return nil }
        let lower = raw.lowercased()
        guard !lower.contains("deeplinks available"), !lower.contains("paid plan") else { return nil }
        guard let url = URL(string: raw), allowed(url, forService: name) else { return nil }
        return url
    }

    private static func isWebScheme(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        return scheme == "http" || scheme == "https"
    }

    // MARK: - Brand guard

    /// A URL is allowed for a service when the URL's detected brand is nil or
    /// equal to the service's. A different non-nil brand is rejected, which is
    /// what stops a wrong-app deep link (a Prime link served for an Apple TV+
    /// title) from opening the wrong app.
    private static func allowed(_ url: URL, forService name: String) -> Bool {
        guard let detected = brandToken(forURL: url) else { return true }
        return detected == brandToken(forServiceName: name)
    }

    private static func brandToken(forURL url: URL) -> String? {
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host?.lowercased() ?? ""
        if scheme == "aiv" || host.contains("amazon") || host.contains("primevideo") { return "amazon" }
        if scheme == "nflx" || host.contains("netflix") { return "netflix" }
        if scheme == "videos" || host.contains("apple") { return "apple" }
        if host.contains("hulu") { return "hulu" }
        if scheme == "disneyplus" || host.contains("disney") { return "disney" }
        if scheme == "hbomax" || host.contains("max") || host.contains("hbo") { return "max" }
        if scheme == "paramountplus" || host.contains("paramount") { return "paramount" }
        if scheme == "peacock" || host.contains("peacock") { return "peacock" }
        if scheme == "youtube" || host.contains("youtube") { return "youtube" }
        if host.contains("crunchyroll") { return "crunchyroll" }
        return nil
    }

    private static func brandToken(forServiceName name: String) -> String? {
        guard let catalogId = Platform.from(providerName: name)?.catalogId else { return nil }
        // Map catalog ids into the URL-brand-token space above.
        switch catalogId {
        case "prime":   return "amazon"
        case "appletv": return "apple"
        default:        return catalogId
        }
    }

    /// True when two service names are the same brand. Used by callers that
    /// have a service NAME (a Continue Watching row, a badge) and need to find
    /// its row among the resolved sources.
    static func isSameBrand(_ a: String, _ b: String) -> Bool {
        guard let left = Platform.from(providerName: a)?.catalogId,
              let right = Platform.from(providerName: b)?.catalogId else { return false }
        return left == right
    }
}

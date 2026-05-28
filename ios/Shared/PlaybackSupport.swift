//
// PlaybackSupport.swift
// GuideStreamTV (SHARED target — must compile into BOTH iOS and tvOS)
//
// Single source of truth for how reliably each streaming app deep-links on
// tvOS, plus the honest UI verb that follows from it.
//
// Two readers:
// • The iPhone "Play on TV" sheet (PlayOnBottomSheet) — for button/row copy
//   and the post-tap confirmation toast.
// • TVOSDeepLinker (tvOS) — should source its `confidence` from here so the
//   label the phone shows and the behavior the TV performs can't diverge.
//
// RORK MAX NOTE: add this file to the SHARED group, not the iOS-only or
// tvOS-only target. It has no UIKit/SwiftUI imports specifically so it can be
// compiled by every Apple platform target in the universal app.
//

import Foundation

enum PlaybackConfidence {
    case verified   // direct-to-title playback confirmed on tvOS (e.g. Netflix)
    case partial    // app opens; title/playback inconsistent across versions
    case unverified // opens to home only; no known tvOS title scheme yet
}

enum PlaybackSupport {

    /// Source-of-truth confidence per platform. Mirrors the schemes baked into
    /// TVOSDeepLinker — keep the two aligned (or have TVOSDeepLinker call this).
    static func confidence(for platform: String) -> PlaybackConfidence {
        let key = platform.lowercased()
        if key.contains("netflix") { return .verified }
        if key.contains("hulu") || key.contains("youtube") { return .partial }
        // Disney+, Max, Prime, Apple TV, Paramount+, Peacock, Crunchyroll, etc.
        // open to home until verified on real Apple TV 4K hardware.
        return .unverified
    }

    /// True only when playback is expected to actually start: a high-confidence
    /// platform AND a resolved title id in the link. Drives "Playing" vs
    /// "Opening" so the UI never over-promises and a dead deep link never
    /// makes the copy a lie mid-demo.
    static func willPlayDirectly(platform: String, contentURL: URL?) -> Bool {
        guard confidence(for: platform) == .verified else { return false }
        return hasPlayableId(contentURL)
    }

    /// Honest action verb for a button or row hint.
    static func verb(platform: String, contentURL: URL?) -> String {
        willPlayDirectly(platform: platform, contentURL: contentURL) ? "Playing" : "Opening"
    }

    /// Full status string for the post-tap confirmation, e.g.
    /// "Playing Criminal Minds on Mark's Room"
    /// "Opening Hulu on Living Room"
    static func statusLabel(platform: String, title: String, room: String, contentURL: URL?) -> String {
        if willPlayDirectly(platform: platform, contentURL: contentURL) {
            return "Playing \(title) on \(room)"
        } else {
            return "Opening \(platform) on \(room)"
        }
    }

    // MARK: - Helper

    /// Lightweight check for a title id in the resolved web/universal URL
    /// (`/watch/{id}`, `/title/{id}`, or `?v={id}`). Mirrors the extractor in
    /// TVOSDeepLinker without depending on the tvOS target.
    private static func hasPlayableId(_ url: URL?) -> Bool {
        guard let url else { return false }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if comps?.queryItems?.contains(where: { $0.name == "v" && !($0.value ?? "").isEmpty }) == true {
            return true
        }
        let parts = url.pathComponents.filter { $0 != "/" }
        if let idx = parts.firstIndex(where: { $0 == "watch" || $0 == "title" }), idx + 1 < parts.count {
            return true
        }
        return false
    }
}

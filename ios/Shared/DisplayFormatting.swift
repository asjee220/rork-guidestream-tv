//
// DisplayFormatting.swift
// GuideStreamTV (SHARED target — must compile into BOTH iOS and tvOS)
//
// Single source of truth for count pluralization ("1 episode" / "5 episodes")
// and season/episode code formatting ("S:1 EP:2", "S1 E2", "S1 · E2").
//
// Readers across both targets: availability sections, detail screens, sheets,
// onboarding, and the watching-now grid — anywhere a count or episode code is
// rendered as text.
//
// RORK MAX NOTE: add this file to the SHARED group, not the iOS-only or
// tvOS-only target. It has no UIKit/SwiftUI imports specifically so it can be
// compiled by every Apple platform target in the universal app.
//

import Foundation

enum DisplayFormatting {

    /// "1 episode" / "5 episodes"
    static func episodes(_ n: Int) -> String {
        "\(n) episode\(n == 1 ? "" : "s")"
    }

    /// "1 ep" / "5 eps"
    static func episodesShort(_ n: Int) -> String {
        "\(n) ep\(n == 1 ? "" : "s")"
    }

    /// "1 service" / "5 services"
    static func services(_ n: Int) -> String {
        "\(n) service\(n == 1 ? "" : "s")"
    }

    /// "1 show" / "5 shows"
    static func shows(_ n: Int) -> String {
        "\(n) show\(n == 1 ? "" : "s")"
    }

    /// "S:1 EP:2"
    static func seasonEpisodeColon(season: Int, episode: Int) -> String {
        "S:\(season) EP:\(episode)"
    }

    /// "S1 EP2"
    static func seasonEpisodeCompact(season: Int, episode: Int) -> String {
        "S\(season) EP\(episode)"
    }

    /// "S1 E2"
    static func seasonEpisodeShort(season: Int, episode: Int) -> String {
        "S\(season) E\(episode)"
    }

    /// "S1 · E2"
    static func seasonEpisodeDot(season: Int, episode: Int) -> String {
        "S\(season) · E\(episode)"
    }

    /// "Season 1"
    static func seasonLabel(_ n: Int) -> String {
        "Season \(n)"
    }

    /// "1 creator" / "5 creators"
    static func creators(_ n: Int) -> String {
        "\(n) creator\(n == 1 ? "" : "s")"
    }

    /// "1 device" / "5 devices"
    static func devices(_ n: Int) -> String {
        "\(n) device\(n == 1 ? "" : "s")"
    }

    /// "1 Season" / "5 Seasons" (capital S, matches existing Reels output)
    static func seasons(_ n: Int) -> String {
        "\(n) Season\(n == 1 ? "" : "s")"
    }
}

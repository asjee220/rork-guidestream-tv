//
//  SportsActivityAttributes.swift
//  GuideStreamTV
//
//  Static payload for the live-sports-scores Live Activity. This file is a
//  member of BOTH the GuideStreamTV app target (which requests the activity)
//  and the GuideStreamWidget extension target (which renders it), so it must
//  not depend on any app-only type.
//

import ActivityKit
import Foundation

nonisolated struct SportsActivityAttributes: ActivityAttributes {
    let gameId: String
    let sport: String
    let leagueShort: String
    let homeAbbr: String
    let awayAbbr: String
    let homeShortName: String
    let awayShortName: String
    let homeHex: String
    let awayHex: String
    let broadcast: String

    /// Live score payload. Stored property names match the server push
    /// payload literally — do not rename, reorder, or add CodingKeys.
    struct ContentState: Codable, Hashable {
        let homeScore: Int
        let awayScore: Int
        let statusDetail: String
        let state: String
    }
}

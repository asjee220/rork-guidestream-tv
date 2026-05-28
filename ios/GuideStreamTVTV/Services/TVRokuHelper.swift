//
//  TVRokuHelper.swift
//  GuideStreamTVTV
//
//  No-op stubs for Roku ECP — on Apple TV there is no need to remote-launch
//  a Roku channel, so these return sensible defaults without network calls.
//

import Foundation

enum RokuChannel {
    /// Maps a streaming platform label to the Roku channel ID.
    static func id(for platform: String) -> String? {
        let key = platform.lowercased()
        if key.contains("netflix")             { return "12" }
        if key.contains("hbo") || key.contains("max") { return "61322" }
        if key.contains("hulu")                { return "2285" }
        if key.contains("disney")              { return "291097" }
        if key.contains("prime") || key.contains("amazon") { return "13" }
        if key.contains("apple")               { return "551012" }
        if key.contains("paramount")           { return "31440" }
        if key.contains("peacock")             { return "593099" }
        if key.contains("youtube tv")          { return "195316" }
        if key.contains("youtube")             { return "837" }
        if key.contains("showtime")            { return "60308" }
        if key.contains("starz")               { return "151908" }
        if key.contains("crunchyroll")         { return "55307" }
        return nil
    }
}

enum RokuECPClient {
    /// No-op launch — on tvOS there's no other device to launch a channel on.
    static func launch(
        host: String,
        port: UInt16,
        channelId: String,
        contentId: String? = nil,
        mediaType: String = "series"
    ) async -> Bool {
        return false
    }
}

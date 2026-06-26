//
//  CreatorChannel.swift
//  GuideStreamTV
//
//  Model for the youtube_show_creators edge function response. The function
//  returns YouTube creator channels that publish analysis, breakdown, and
//  theory content about a given show or movie.
//

import Foundation

// MARK: - Public model

nonisolated struct CreatorChannel: Codable, Identifiable, Hashable, Sendable {
    let titleId: String
    let channelId: String
    let name: String
    let avatarUrl: String?
    let subscriberCount: Int
    let subscribersHidden: Bool
    let relevantVideos: Int
    let namedShow: Bool
    let channelUrl: String

    var id: String { titleId }

    /// Compact subscriber count label (e.g. 817000 → "817K", 1660000 → "1.7M").
    /// Returns `nil` when the count is below 1000 or the channel hides its
    /// subscriber count, so the UI can suppress the label entirely.
    var subscriberLabel: String? {
        guard !subscribersHidden, subscriberCount >= 1000 else { return nil }
        let n = subscriberCount
        if n >= 1_000_000_000 { return String(format: "%.1fB", Double(n) / 1_000_000_000) }
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case titleId = "title_id"
        case channelId = "channel_id"
        case name
        case avatarUrl = "avatar_url"
        case subscriberCount = "subscriber_count"
        case subscribersHidden = "subscribers_hidden"
        case relevantVideos = "relevant_videos"
        case namedShow = "named_show"
        case channelUrl = "channel_url"
    }
}

// MARK: - Response envelope (private)

nonisolated fileprivate struct CreatorChannelResponse: Codable, Sendable {
    let ok: Bool
    let cached: Bool?
    let creators: [CreatorChannel]?
}

//
//  ContentSource.swift
//  GuideStreamTV
//
//  Models for the public.content_sources and public.live_status tables.
//  Both tables already exist in Supabase and are public-readable.
//

import Foundation

/// Row from public.content_sources — a YouTube channel, podcast feed,
/// Twitch channel, or Kick channel that users can follow.
nonisolated struct ContentSource: Codable, Identifiable, Hashable, Sendable {
    let titleId: String
    let sourceType: String
    let displayName: String
    let handle: String?
    let imageUrl: String?
    let externalId: String?
    let feedUrl: String?
    let channelUrl: String?
    let websubTopic: String?
    let category: String?
    let description: String?
    let createdAt: Date?
    let updatedAt: Date?

    var id: String { titleId }

    enum CodingKeys: String, CodingKey {
        case titleId = "title_id"
        case sourceType = "source_type"
        case displayName = "display_name"
        case handle
        case imageUrl = "image_url"
        case externalId = "external_id"
        case feedUrl = "feed_url"
        case channelUrl = "channel_url"
        case websubTopic = "websub_topic"
        case category
        case description
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Row from public.live_status — live/offline state of a Twitch or Kick channel.
nonisolated struct LiveStatus: Codable, Identifiable, Hashable, Sendable {
    let titleId: String
    let isLive: Bool
    let streamTitle: String?
    let category: String?
    let viewerCount: Int?
    let sessionId: String?
    let startedAt: Date?
    let updatedAt: Date?

    var id: String { titleId }

    enum CodingKeys: String, CodingKey {
        case titleId = "title_id"
        case isLive = "is_live"
        case streamTitle = "stream_title"
        case category
        case viewerCount = "viewer_count"
        case sessionId = "session_id"
        case startedAt = "started_at"
        case updatedAt = "updated_at"
    }
}

/// Combined view of a content source with its live status, used by discovery and search.
nonisolated struct DiscoverableCreator: Identifiable, Hashable, Sendable {
    let titleId: String
    let sourceType: String
    let displayName: String
    let handle: String?
    let imageUrl: String?
    let category: String?
    let description: String?
    let isLive: Bool
    let streamTitle: String?
    let liveCategory: String?
    let viewerCount: Int?

    var id: String { titleId }

    /// The SourceKind for this creator's titleId, derived from the prefix.
    var kind: SourceKind { SourceKind.from(titleId: titleId) }

    /// True when the source is a livestream platform (twitch or kick).
    var isStreamer: Bool { kind.isLivestream }

    /// URL string for the creator's avatar image.
    var avatarUrl: String? { imageUrl }
}

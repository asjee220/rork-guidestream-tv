//
//  ChannelMetaResponse.swift
//  GuideStreamTV
//
//  Decodable response for the `youtube_channel_meta` Supabase edge function,
//  which proxies the YouTube Data API channels.list / playlistItems.list calls
//  server-side so YOUTUBE_API_KEY never ships in the client.
//
//  Shape (verified live):
//  {
//    "ok": true,
//    "pending": false,
//    "channel": { "name", "description", "avatar", "channel_url" },
//    "stats":   { "subscribers", "videos", "views" } | null,
//    "uploads": [ { "video_id", "title", "published_at", "thumbnail",
//                   "views", "duration_seconds", "deep_link" } ]
//  }
//
//  When `pending` is true the channel id hasn't been resolved server-side yet:
//  `stats` is null and `uploads` is empty, but `channel` still carries
//  name/description/avatar/channel_url.
//

import Foundation

nonisolated struct ChannelMetaResponse: Decodable, Sendable {
    let ok: Bool
    let pending: Bool
    let channel: Channel?
    let stats: Stats?
    let uploads: [Upload]

    enum CodingKeys: String, CodingKey {
        case ok, pending, channel, stats, uploads
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? c.decode(Bool.self, forKey: .ok)) ?? false
        pending = (try? c.decode(Bool.self, forKey: .pending)) ?? false
        channel = try? c.decode(Channel.self, forKey: .channel)
        stats = try? c.decode(Stats.self, forKey: .stats)
        uploads = (try? c.decode([Upload].self, forKey: .uploads)) ?? []
    }

    nonisolated struct Channel: Decodable, Sendable {
        let name: String?
        let description: String?
        let avatar: String?
        let channelUrl: String?

        enum CodingKeys: String, CodingKey {
            case name, description, avatar
            case channelUrl = "channel_url"
        }
    }

    /// Channel-level statistics. Numbers can be very large (hundreds of
    /// millions / billions of views), so they decode as `Int64`.
    nonisolated struct Stats: Decodable, Sendable {
        let subscribers: Int64
        let videos: Int64
        let views: Int64
    }

    /// A single recent upload from the channel's uploads playlist.
    nonisolated struct Upload: Decodable, Sendable, Identifiable, Hashable {
        let videoId: String
        let title: String
        /// ISO-8601 string (kept as text so a format mismatch can't fail the
        /// whole response decode); parsed for display in the view.
        let publishedAt: String?
        let thumbnail: String?
        let views: Int64
        let durationSeconds: Int
        let deepLink: String

        var id: String { videoId }

        enum CodingKeys: String, CodingKey {
            case videoId = "video_id"
            case title
            case publishedAt = "published_at"
            case thumbnail
            case views
            case durationSeconds = "duration_seconds"
            case deepLink = "deep_link"
        }

        nonisolated init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            videoId = (try? c.decode(String.self, forKey: .videoId)) ?? ""
            title = (try? c.decode(String.self, forKey: .title)) ?? ""
            publishedAt = try? c.decode(String.self, forKey: .publishedAt)
            thumbnail = try? c.decode(String.self, forKey: .thumbnail)
            views = (try? c.decode(Int64.self, forKey: .views)) ?? 0
            durationSeconds = (try? c.decode(Int.self, forKey: .durationSeconds)) ?? 0
            deepLink = (try? c.decode(String.self, forKey: .deepLink)) ?? ""
        }
    }
}

/// Minimal row decoder for the `creator_notification_preferences` table.
/// Mirrors the dual-ownership pattern (`user_id` / `device_id` + `title_id`)
/// used by `title_likes`.
nonisolated struct CreatorNotifPrefRow: Decodable, Sendable {
    let notify_uploads: Bool?
}

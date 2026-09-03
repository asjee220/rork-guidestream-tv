//
//  TVCreatorService.swift
//  GuideStreamTVTV
//
//  Everything the creator screen reads. Mirrors the slices of the phone's
//  ContentSourcesService (ios/GuideStreamTV/Services/ContentSourcesService.swift)
//  that CreatorDetailView depends on — the source row, live status, recent
//  episodes — plus the two channel-meta edge functions the phone calls
//  directly from the view.
//
//  Duplicated rather than shared, the same convention the rest of the tvOS
//  target follows: the two copies have to be changed together.
//

import Foundation
import Supabase

// MARK: - Rows

/// Row from `public.content_sources`. The tvOS copy used to carry five
/// columns because recommendations were all it fed; the creator screen needs
/// the handle, the bio and the channel/feed URLs as well.
nonisolated struct TVCreatorSource: Decodable, Identifiable, Sendable {
    let titleId: String
    let sourceType: String
    let displayName: String
    let handle: String?
    let imageUrl: String?
    let externalId: String?
    let feedUrl: String?
    let channelUrl: String?
    let category: String?
    let description: String?
    let format: String?

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
        case category
        case description
        case format
    }
}

/// Row from `public.live_status` — the live/offline state of a Twitch or
/// Kick channel.
nonisolated struct TVLiveStatus: Decodable, Sendable {
    let titleId: String
    let isLive: Bool
    let streamTitle: String?
    let category: String?
    let viewerCount: Int?

    enum CodingKeys: String, CodingKey {
        case titleId = "title_id"
        case isLive = "is_live"
        case streamTitle = "stream_title"
        case category
        case viewerCount = "viewer_count"
    }
}

/// Row from `public.new_episodes`, for a single creator. The target's
/// existing `NewEpisodeRow` is a non-decodable stub kept for shared view
/// signatures, so this is its own type rather than an extension of that one.
nonisolated struct TVCreatorEpisode: Decodable, Identifiable, Sendable {
    let id: String
    let titleId: String
    let title: String?
    let posterUrl: String?
    let thumbnailUrl: String?
    let deepLinkUrl: String?
    let releasedAt: Date?
    let durationMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case titleId = "title_id"
        case title
        case posterUrl = "poster_url"
        case thumbnailUrl = "thumbnail_url"
        case deepLinkUrl = "deep_link_url"
        case releasedAt = "released_at"
        case durationMinutes = "duration_minutes"
    }
}

/// Response from the `youtube_channel_meta` / `twitch_channel_meta` edge
/// functions. Byte-compatible with the phone's ChannelMetaResponse, including
/// its lenient decoding: every field falls back rather than failing the whole
/// response, because `stats` is null and `uploads` empty while the channel id
/// is still being resolved server-side.
nonisolated struct TVChannelMetaResponse: Decodable, Sendable {
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

    /// View counts run to billions, so these are Int64 like the phone's.
    nonisolated struct Stats: Decodable, Sendable {
        let subscribers: Int64
        let videos: Int64
        let views: Int64
    }

    nonisolated struct Upload: Decodable, Sendable, Identifiable, Hashable {
        let videoId: String
        let title: String
        /// Kept as text so a format mismatch cannot fail the whole response;
        /// parsed for display in the view.
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

// MARK: - Kind

/// Which platform a saved id belongs to. tvOS has no SourceKind; this is the
/// same prefix table, and has to track ios/GuideStreamTV/Models/SourceKind.swift.
enum TVCreatorKind: String, Sendable {
    case youtube, podcast, twitch, kick

    static func from(titleId: String) -> TVCreatorKind? {
        if titleId.hasPrefix("yt:") { return .youtube }
        if titleId.hasPrefix("pod:") { return .podcast }
        if titleId.hasPrefix("tw:") { return .twitch }
        if titleId.hasPrefix("kick:") { return .kick }
        return nil
    }

    var displayLabel: String {
        switch self {
        case .youtube: return "YouTube"
        case .podcast: return "Podcast"
        case .twitch: return "Twitch"
        case .kick: return "Kick"
        }
    }

    var isLivestream: Bool { self == .twitch || self == .kick }

    /// The id with its prefix stripped — the channel id, feed id or slug the
    /// deep links are built from.
    func externalId(from titleId: String) -> String {
        guard titleId.hasPrefix(prefix) else { return titleId }
        return String(titleId.dropFirst(prefix.count))
    }

    var prefix: String {
        switch self {
        case .youtube: return "yt:"
        case .podcast: return "pod:"
        case .twitch: return "tw:"
        case .kick: return "kick:"
        }
    }
}

// MARK: - Service

enum TVCreatorService {
    static let shared = TVCreatorService.self

    private static var client: SupabaseClient { TVSupabaseManager.shared.client }

    /// The creator's own `content_sources` row.
    static func fetchSource(titleId: String) async -> TVCreatorSource? {
        do {
            let rows: [TVCreatorSource] = try await client
                .from("content_sources")
                .select()
                .eq("title_id", value: titleId)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch {
            print("[TVCreator] fetchSource failed for \(titleId): \(error)")
            return nil
        }
    }

    /// Live state, for Twitch and Kick only. Returns nil for everything else
    /// rather than querying a table that will never have the row.
    static func fetchLiveStatus(titleId: String) async -> TVLiveStatus? {
        guard TVCreatorKind.from(titleId: titleId)?.isLivestream == true else { return nil }
        do {
            let rows: [TVLiveStatus] = try await client
                .from("live_status")
                .select()
                .eq("title_id", value: titleId)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch {
            print("[TVCreator] fetchLiveStatus failed for \(titleId): \(error)")
            return nil
        }
    }

    /// Recent episodes for a podcast, newest first. Same query and limit the
    /// phone uses.
    static func fetchEpisodes(titleId: String) async -> [TVCreatorEpisode] {
        do {
            let rows: [TVCreatorEpisode] = try await client
                .from("new_episodes")
                .select()
                .eq("title_id", value: titleId)
                .order("released_at", ascending: false)
                .limit(30)
                .execute()
                .value
            return rows
        } catch {
            print("[TVCreator] fetchEpisodes failed for \(titleId): \(error)")
            return []
        }
    }

    /// Channel name, bio, stats and recent uploads, for YouTube and Twitch.
    /// The API keys live server-side, so this is an edge-function call and
    /// not a direct API request — the same one the phone makes.
    static func fetchChannelMeta(titleId: String) async -> TVChannelMetaResponse? {
        guard let kind = TVCreatorKind.from(titleId: titleId),
              kind == .youtube || kind == .twitch else { return nil }
        let function = kind == .twitch ? "twitch_channel_meta" : "youtube_channel_meta"
        do {
            let response: TVChannelMetaResponse = try await client.functions.invoke(
                function,
                options: FunctionInvokeOptions(body: ["title_id": titleId])
            )
            return response.ok ? response : nil
        } catch {
            print("[TVCreator] \(function) failed for \(titleId): \(error)")
            return nil
        }
    }
}

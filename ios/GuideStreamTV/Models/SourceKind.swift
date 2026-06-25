//
//  SourceKind.swift
//  GuideStreamTV
//
//  Single-source classifier for title_id prefixes.
//  Every routing and rendering decision keys off this helper.
//

import Foundation

/// Notification posted when the app receives a `guidestream://title/{id}` deep link.
/// The `userInfo` dictionary contains a `"titleId"` key with the raw title_id string.
/// HomeView observes this to route to CreatorDetailView (non-TMDB) or show detail (TMDB).
extension Notification.Name {
    static let guideStreamOpenTitle = Notification.Name("GuideStreamOpenTitle")
}

/// Curated avatar overrides for seed creators whose stored `image_url` /
/// `poster_url` points at a placeholder default YouTube letter-avatar (because
/// the seed data referenced the wrong channel) rather than the real channel
/// photo. Keyed by the prefixed title_id. When an override exists it takes
/// precedence over any stored URL so cards always show a real image.
enum CreatorImageOverrides {
    static let map: [String: String] = [
        // "Mat Armstrong" (Automotive / BMX) — real channel photo.
        "yt:UCmat": "https://yt3.googleusercontent.com/ytc/AIdro_llPlK76qJ3vTfaeS0kmTk8L_1a-Ux7kWoMopedNGwzEK4=s800-c-k-c0x00ffffff-no-rj",
        // "Gil's Arena" (NBA debate show) — real channel photo.
        "yt:UCgil": "https://yt3.googleusercontent.com/OFBs63C5LsEv-FScjEAFg432Wisv6xRneRq2dV7LJ-gOhv0TnA1WRn_OHOCw-kZnrkEt0XGu=s800-c-k-c0x00ffffff-no-rj"
    ]

    /// Returns the best image URL for a title_id: the curated override when one
    /// exists, otherwise the supplied stored value.
    static func resolve(titleId: String, stored: String?) -> String? {
        if let override = map[titleId] { return override }
        return stored
    }
}

/// The kind of source a title_id represents, derived from its prefix.
enum SourceKind: String, CaseIterable, Sendable {
    case tmdb
    case youtube
    case podcast
    case twitch
    case kick

    /// Map a raw title_id string to its SourceKind by inspecting the prefix.
    /// A bare id (no colon prefix) is always `.tmdb`.
    static func from(titleId: String) -> SourceKind {
        if titleId.hasPrefix("yt:") { return .youtube }
        if titleId.hasPrefix("pod:") { return .podcast }
        if titleId.hasPrefix("tw:") { return .twitch }
        if titleId.hasPrefix("kick:") { return .kick }
        return .tmdb
    }

    /// True when this kind represents a livestream platform (Twitch or Kick).
    var isLivestream: Bool {
        self == .twitch || self == .kick
    }

    /// True when this kind is not TMDB (any prefixed id).
    var isNonTMDB: Bool {
        self != .tmdb
    }

    /// The prefix string stored in title_id (e.g. "yt:", "pod:").
    var prefix: String {
        switch self {
        case .tmdb: return ""
        case .youtube: return "yt:"
        case .podcast: return "pod:"
        case .twitch: return "tw:"
        case .kick: return "kick:"
        }
    }

    /// The source_type value used in content_sources and user_streams.platform.
    var sourceType: String {
        switch self {
        case .tmdb: return "tmdb"
        case .youtube: return "youtube"
        case .podcast: return "podcast"
        case .twitch: return "twitch"
        case .kick: return "kick"
        }
    }

    /// Human-readable display label used in filter chips and badges.
    var displayLabel: String {
        switch self {
        case .tmdb: return "Show"
        case .youtube: return "YouTube"
        case .podcast: return "Podcast"
        case .twitch: return "Twitch"
        case .kick: return "Kick"
        }
    }

    /// Brand color for badges and chips.
    var brandColor: String {
        switch self {
        case .youtube: return "#FF0000"
        case .podcast: return "#7C3AED"
        case .twitch: return "#9146FF"
        case .kick: return "#53FC18"
        case .tmdb: return "#6A3FE0"
        }
    }
}

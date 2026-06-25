//
//  SourceKind.swift
//  GuideStreamTV
//
//  Single-source classifier for title_id prefixes.
//  Every routing and rendering decision keys off this helper.
//

import Foundation

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

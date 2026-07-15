//
//  UserStream.swift
//  GuideStreamTV
//

import Foundation

nonisolated struct UserStream: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let userId: String
    let titleId: String
    let title: String?
    let posterUrl: String?
    let platform: String?
    let addedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case titleId = "title_id"
        case title
        case posterUrl = "poster_url"
        case platform
        case addedAt = "added_at"
    }
}

nonisolated struct NewEpisodeRow: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let titleId: String
    let title: String?
    let season: Int?
    let episode: Int?
    let durationMinutes: Int?
    let platform: String?
    let posterUrl: String?
    let isNew: Bool?
    let releasedAt: Date?
    /// YouTube video id or podcast episode GUID/permalink.
    let episodeId: String?
    /// YouTube watch URL or podcast direct audio .mp3 URL.
    let deepLinkUrl: String?
    /// Alternative thumbnail image URL — used as a fallback when poster_url is null.
    let thumbnailUrl: String?
    /// YouTube video title or podcast episode name — distinct from the channel-level title.
    let episodeTitle: String?

    enum CodingKeys: String, CodingKey {
        case id
        case titleId = "title_id"
        case title
        case season
        case episode
        case durationMinutes = "duration_minutes"
        case platform
        case posterUrl = "poster_url"
        case isNew = "is_new"
        case releasedAt = "released_at"
        case episodeId = "episode_id"
        case deepLinkUrl = "deep_link_url"
        case thumbnailUrl = "thumbnail_url"
        case episodeTitle = "episode_title"
    }
}

nonisolated struct UserStreamInsert: Encodable, Sendable {
    let user_id: String
    let title_id: String
    let title: String?
    let poster_url: String?
    let platform: String?
}

nonisolated struct UserProfileUpsert: Encodable, Sendable {
    let id: String
    let display_name: String?
    let first_name: String?
    let last_name: String?
    let avatar_url: String?
    let email: String?
}

nonisolated struct OnboardingPrefsUpsert: Encodable, Sendable {
    let id: String
    let services: [String]
    let notify_push: Bool
    let notify_sms: Bool
    let onboarding_complete: Bool
}

/// Minimal decoder for re-hydrating onboarding state from the `users` row
/// after sign-in. Fields are optional so older projects missing the
/// `onboarding_complete` column still decode cleanly.
nonisolated struct OnboardingStateRow: Decodable, Sendable {
    let onboarding_complete: Bool?
    let services: [String]?
}

/// Lightweight decode helper for fetching display_name + first_name + last_name
/// from the `users` table. Older installs may only have `display_name`; the
/// extra fields are optional so decoding still succeeds.
nonisolated struct UserProfileNameRow: Decodable, Sendable {
    let display_name: String?
    let first_name: String?
    let last_name: String?
    let phone: String?
}

/// Small payload for upserting phone and SMS consent into the `users` table.
nonisolated struct PhoneUpsert: Encodable, Sendable {
    let id: String
    let phone: String
    let sms_consent_at: String
    let notify_sms: Bool
}

/// Minimal row decoder for the `users.notify_movie_releases` column.
nonisolated struct UserMovieReleaseRow: Decodable, Sendable {
    let notify_movie_releases: Bool?
}

/// Minimal decoder for the `title_recency` table — reads the most-recent
/// content timestamp per title (last aired episode, release date, latest upload).
nonisolated struct TitleRecencyRow: Decodable, Sendable {
    let titleId: String
    let lastContentAt: Date?

    enum CodingKeys: String, CodingKey {
        case titleId = "title_id"
        case lastContentAt = "last_content_at"
    }
}

/// Row shape used by the Devices screen when listing a user's installs.
/// Mirrors the `device_sessions` schema documented in `DeviceSessionService`.
nonisolated struct DeviceSessionRow: Decodable, Sendable, Identifiable, Hashable {
    let device_id: String
    let device_model: String?
    let os_version: String?
    let app_version: String?
    let build_number: String?
    let last_seen_at: String?
    let first_seen_at: String?
    let is_authenticated: Bool?
    let is_guest: Bool?
    let session_count: Int?

    var id: String { device_id }
}

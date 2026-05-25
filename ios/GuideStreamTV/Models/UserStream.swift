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
    let avatar_url: String?
    let email: String?
}

nonisolated struct OnboardingPrefsUpsert: Encodable, Sendable {
    let id: String
    let services: [String]
    let notify_push: Bool
    let notify_sms: Bool
}

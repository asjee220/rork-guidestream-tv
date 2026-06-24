//
//  WidgetData.swift
//  GuideStreamWidget
//
//  Shared data model decoded from the App Group UserDefaults blob
//  that the main app writes whenever Leaving Soon / watchlist data changes.
//

import Foundation

/// One title that is about to leave a streaming service, ready for widget display.
nonisolated struct LeavingSoonItem: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let platform: String
    let platformColorHex: String
    let posterUrl: String?
    let daysRemaining: Int
    let expireDate: String
}

/// The full widget payload written by the main app.
nonisolated struct WidgetPayload: Codable, Sendable {
    let leavingSoon: [LeavingSoonItem]
    let watchlistCount: Int
    let newEpisodeCount: Int
    let lastUpdated: Date
}

// MARK: - App Group helpers

enum WidgetDataStore {
    static let appGroupId = "group.app.rork.guidestream-tv"
    static let payloadKey = "gs.widgetPayload.v1"

    static func load() -> WidgetPayload? {
        guard let shared = UserDefaults(suiteName: appGroupId),
              let data = shared.data(forKey: payloadKey) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetPayload.self, from: data)
    }
}

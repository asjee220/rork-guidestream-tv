//
//  WidgetData.swift
//  GuideStreamWidget
//
//  Shared data model decoded from the JSON file that the main app writes
//  into the App Group shared container whenever Leaving Soon / watchlist
//  data changes.
//
//  Uses FileManager.containerURL (not UserDefaults) for more reliable
//  cross-process data sharing between the main app and widget extension.
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
    static let payloadFileName = "widget_payload_v1.json"

    /// Loads the payload from the JSON file in the shared App Group container.
    /// Falls back to UserDefaults if the file doesn't exist yet (during the
    /// transition period), then returns nil if neither source has data.
    static func load() -> WidgetPayload? {
        // Primary: file-based approach via containerURL
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) {
            let fileURL = containerURL.appendingPathComponent(payloadFileName)
            if let data = try? Data(contentsOf: fileURL) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let payload = try? decoder.decode(WidgetPayload.self, from: data) {
                    return payload
                }
            }
        }

        // Fallback: try the old UserDefaults key (for devices that still
        // have data from the previous version of the service).
        if let shared = UserDefaults(suiteName: appGroupId),
           let data = shared.data(forKey: "gs.widgetPayload.v1") {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(WidgetPayload.self, from: data)
        }

        return nil
    }
}

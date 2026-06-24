//
//  WidgetData.swift
//  GuideStreamWidget
//
//  Shared data model decoded from the JSON that the main app writes into
//  the App Group shared container. The main app writes to BOTH a flat file
//  AND UserDefaults(suiteName:) on every change — this loader tries both
//  transports so the widget never misses data due to a single-path failure.
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
    static let userDefaultsKey = "gs.widgetPayload.v1"

    /// Loads the payload from the App Group shared container.
    ///
    /// The main app writes to BOTH a JSON file AND UserDefaults(suiteName:)
    /// on every data change. This loader tries both paths — whichever has
    /// data and decodes successfully wins. Returns nil only if neither
    /// transport has valid data yet (first launch before any data is pushed).
    static func load() -> WidgetPayload? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // --- Transport 1: JSON file via containerURL ---
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) {
            let fileURL = containerURL.appendingPathComponent(payloadFileName)
            if let data = try? Data(contentsOf: fileURL),
               let payload = try? decoder.decode(WidgetPayload.self, from: data) {
                return payload
            }
        }

        // --- Transport 2: UserDefaults(suiteName:) ---
        if let shared = UserDefaults(suiteName: appGroupId),
           let data = shared.data(forKey: userDefaultsKey),
           let payload = try? decoder.decode(WidgetPayload.self, from: data) {
            return payload
        }

        return nil
    }
}

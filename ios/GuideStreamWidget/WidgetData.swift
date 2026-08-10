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

/// One item in the unified "Next Up" widget feed. The `kind` field is one
/// of exactly four lowercase string values — `live`, `new`, `soon`, `out` —
/// and drives badge colour only.
nonisolated struct WidgetFeedItem: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let kind: String
    let title: String
    let subtitle: String
    let badge: String
    let platform: String
    let platformColorHex: String
    let posterUrl: String?
    let deepLink: String?
}

/// The full widget payload written by the main app.
///
/// Custom decoding ensures that a stale v1 payload (which lacks the `items`
/// key) causes `load()` to return nil rather than crash, while a v2 payload
/// whose `items` array partially fails to decode defaults to an empty array.
nonisolated struct WidgetPayload: Codable, Sendable {
    let items: [WidgetFeedItem]
    let watchlistCount: Int
    let newEpisodeCount: Int
    let liveCount: Int
    let lastUpdated: Date

    enum CodingKeys: String, CodingKey {
        case items, watchlistCount, newEpisodeCount, liveCount, lastUpdated
    }

    init(
        items: [WidgetFeedItem],
        watchlistCount: Int,
        newEpisodeCount: Int,
        liveCount: Int,
        lastUpdated: Date
    ) {
        self.items = items
        self.watchlistCount = watchlistCount
        self.newEpisodeCount = newEpisodeCount
        self.liveCount = liveCount
        self.lastUpdated = lastUpdated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // If the items key is missing entirely this is a v1 payload — throw
        // so load() returns nil via try? and the widget shows its empty state
        // once, then fills on the next app foreground.
        guard container.contains(.items) else {
            throw DecodingError.keyNotFound(
                CodingKeys.items,
                .init(codingPath: decoder.codingPath, debugDescription: "v1 payload — no items key")
            )
        }
        items = (try? container.decodeIfPresent([WidgetFeedItem].self, forKey: .items)) ?? []
        watchlistCount = try container.decodeIfPresent(Int.self, forKey: .watchlistCount) ?? 0
        newEpisodeCount = try container.decodeIfPresent(Int.self, forKey: .newEpisodeCount) ?? 0
        liveCount = try container.decodeIfPresent(Int.self, forKey: .liveCount) ?? 0
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
    }
}

// MARK: - App Group helpers

enum WidgetDataStore {
    static let appGroupId = "group.app.rork.guidestream-tv"
    static let payloadFileName = "widget_payload_v2.json"
    static let userDefaultsKey = "gs.widgetPayload.v2"

    /// Loads the payload from the App Group shared container.
    ///
    /// The main app writes to BOTH a JSON file AND UserDefaults(suiteName:)
    /// on every data change. This loader tries both paths — whichever has
    /// data and decodes successfully wins. Returns nil only if neither
    /// transport has valid v2 data yet (first launch, or only a stale v1
    /// payload exists).
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

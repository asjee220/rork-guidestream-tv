//
//  WidgetDataService.swift
//  GuideStreamTV
//
//  Writes a WidgetPayload JSON into BOTH a file AND UserDefaults in the
//  App Group shared container. Belt-and-suspenders: if one transport fails
//  (entitlement sandbox, provisioning profile, iOS version quirk) the other
//  still delivers the payload to the widget.
//
//  IMPORTANT — Data preservation:
//  `pushCounts()` (called early at launch before the home screen loads) first
//  reads any existing payload already in the shared container. If the
//  previous session wrote real feed data, we preserve it — we only update
//  the counts. This prevents the widget from flashing empty on every
//  fresh app launch.
//
//  The `push()` method also preserves previously written items when the
//  incoming array is empty and the stored payload is less than 48 hours old,
//  so a transient network failure never wipes the widget.
//

import Foundation
import WidgetKit

// MARK: - Codable payload types (must match the widget target's decoding keys)

nonisolated struct WidgetFeedItem: Codable, Sendable {
    let id: String
    let kind: String
    let title: String
    let subtitle: String
    let badge: String
    let platform: String
    let platformColorHex: String
    let posterUrl: String?
    let deepLink: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, title, subtitle, badge, platform, platformColorHex, posterUrl, deepLink
    }
}

nonisolated struct WidgetPayload: Codable, Sendable {
    let items: [WidgetFeedItem]
    let watchlistCount: Int
    let newEpisodeCount: Int
    let liveCount: Int
    let lastUpdated: Date

    enum CodingKeys: String, CodingKey {
        case items, watchlistCount, newEpisodeCount, liveCount, lastUpdated
    }
}

// MARK: - Service

@MainActor
final class WidgetDataService {
    static let shared = WidgetDataService()
    private init() {}

    private let appGroupId = "group.app.rork.guidestream-tv"
    private let payloadFileName = "widget_payload_v2.json"
    private let userDefaultsKey = "gs.widgetPayload.v2"

    /// Cached feed items from the last full push so `pushCounts()`
    /// (called from ContentView / StreamsViewModel on every change) can
    /// preserve them without needing a fresh feed build.
    private var cachedItems: [WidgetFeedItem] = []

    // MARK: - Full push (called from HomeView after the feed is assembled)

    func push(
        items: [WidgetFeedItem],
        watchlistCount: Int,
        newEpisodeCount: Int,
        liveCount: Int
    ) {
        // --- Wipe-bug fix: preserve good data on transient empty results ---
        // If the freshly built feed is empty (e.g. all four tiers failed),
        // keep the previously written items as long as they are less than
        // 48h old — mirroring the preservation logic in `pushCounts()`.
        var effectiveItems = items
        if effectiveItems.isEmpty {
            if let existing = loadExistingPayload(),
               !existing.items.isEmpty,
               Date().timeIntervalSince(existing.lastUpdated) < 48 * 60 * 60 {
                effectiveItems = existing.items
                cachedItems = existing.items
            }
        } else {
            cachedItems = items
        }

        writePayload(
            items: effectiveItems,
            watchlistCount: watchlistCount,
            newEpisodeCount: newEpisodeCount,
            liveCount: liveCount
        )
    }

    // MARK: - Counts-only push (called early from ContentView / StreamsViewModel)

    /// Updates watchlist and new-episode counts without overwriting any
    /// feed items that were written by a previous session. If the
    /// in-memory cache is empty (first launch), we try to recover the
    /// items already stored in the shared container so the widget doesn't
    /// blink back to empty.
    func pushCounts(
        watchlistCount: Int,
        newEpisodeCount: Int
    ) {
        var items = cachedItems

        // If cache is cold, try to recover from the shared container so
        // the widget doesn't lose its feed data on a fresh launch.
        if items.isEmpty {
            if let existing = loadExistingPayload(),
               !existing.items.isEmpty {
                items = existing.items
                cachedItems = existing.items
            }
        }

        writePayload(
            items: items,
            watchlistCount: watchlistCount,
            newEpisodeCount: newEpisodeCount,
            liveCount: loadExistingPayload()?.liveCount ?? 0
        )
    }

    // MARK: - Diagnostics

    /// Snapshot of the shared-container health, used by the in-app Widget
    /// setup screen to show ground truth instead of guessing.
    struct Diagnostics {
        let fileContainerReachable: Bool
        let userDefaultsReachable: Bool
        let hasPayload: Bool
        let feedItemCount: Int
        let watchlistCount: Int
        let newEpisodeCount: Int
        let liveCount: Int
        let lastUpdated: Date?
    }

    func diagnostics() -> Diagnostics {
        let fileReachable = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) != nil
        let defaultsReachable = UserDefaults(suiteName: appGroupId) != nil
        let payload = loadExistingPayload()
        return Diagnostics(
            fileContainerReachable: fileReachable,
            userDefaultsReachable: defaultsReachable,
            hasPayload: payload != nil,
            feedItemCount: payload?.items.count ?? 0,
            watchlistCount: payload?.watchlistCount ?? 0,
            newEpisodeCount: payload?.newEpisodeCount ?? 0,
            liveCount: payload?.liveCount ?? 0,
            lastUpdated: payload?.lastUpdated
        )
    }

    /// Writes a known sample payload so the user can confirm the transport
    /// end-to-end without depending on live data. If the widget shows this
    /// sample, the App Group container works and the real issue is upstream.
    func pushTestData() {
        let sample: [WidgetFeedItem] = [
            WidgetFeedItem(
                id: "sample-live", kind: "live",
                title: "Live Channel Demo",
                subtitle: "Just Chatting",
                badge: "Live now",
                platform: "TWITCH", platformColorHex: "#FF3B30",
                posterUrl: nil, deepLink: nil
            ),
            WidgetFeedItem(
                id: "sample-new", kind: "new",
                title: "New Show Example",
                subtitle: "Season 3 just dropped",
                badge: "S3 E1",
                platform: "NETFLIX", platformColorHex: "#009E8A",
                posterUrl: nil, deepLink: nil
            ),
            WidgetFeedItem(
                id: "sample-soon", kind: "soon",
                title: "Coming Soon Demo",
                subtitle: "Arrives this week",
                badge: "in 3d",
                platform: "PRIME", platformColorHex: "#1A6FE8",
                posterUrl: nil, deepLink: nil
            ),
        ]
        cachedItems = sample
        writePayload(items: sample, watchlistCount: 12, newEpisodeCount: 3, liveCount: 1)
    }

    // MARK: - Widget reload trigger

    /// Call this when the app enters the foreground so the widget can
    /// pick up any data written by a previous session.
    func refreshWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: "GuideStreamWidget")
    }

    // MARK: - Dual-transport read

    private func loadExistingPayload() -> WidgetPayload? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Try file first
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) {
            let fileURL = containerURL.appendingPathComponent(payloadFileName)
            if let data = try? Data(contentsOf: fileURL),
               let payload = try? decoder.decode(WidgetPayload.self, from: data) {
                return payload
            }
        }

        // Then UserDefaults
        if let shared = UserDefaults(suiteName: appGroupId),
           let data = shared.data(forKey: userDefaultsKey),
           let payload = try? decoder.decode(WidgetPayload.self, from: data) {
            return payload
        }

        return nil
    }

    // MARK: - Dual-transport write (file + UserDefaults)

    private func writePayload(
        items: [WidgetFeedItem],
        watchlistCount: Int,
        newEpisodeCount: Int,
        liveCount: Int
    ) {
        let payload = WidgetPayload(
            items: items,
            watchlistCount: watchlistCount,
            newEpisodeCount: newEpisodeCount,
            liveCount: liveCount,
            lastUpdated: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(payload) else {
            print("[WidgetData] Failed to encode payload")
            return
        }

        var anySucceeded = false

        // --- Transport 1: JSON file in App Group shared container ---
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) {
            let fileURL = containerURL.appendingPathComponent(payloadFileName)
            do {
                try data.write(to: fileURL, options: .atomic)
                anySucceeded = true
            } catch {
                print("[WidgetData] File write failed: \(error.localizedDescription)")
            }
        }

        // --- Transport 2: UserDefaults in the same App Group ---
        if let shared = UserDefaults(suiteName: appGroupId) {
            shared.set(data, forKey: userDefaultsKey)
            shared.synchronize()
            anySucceeded = true
        }

        if anySucceeded {
            WidgetCenter.shared.reloadTimelines(ofKind: "GuideStreamWidget")
        }
    }
}

// MARK: - Platform color mapping

extension Platform {
    var colorHex: String {
        switch name {
        case "NETFLIX":  return "#E50914"
        case "HBO":      return "#5A1FCB"
        case "Apple TV+": return "#101010"
        case "HULU":     return "#1CE783"
        case "PRIME":    return "#00A8E1"
        case "DISNEY+":  return "#113CCF"
        case "PARAMOUNT+": return "#0064FF"
        case "PEACOCK":  return "#000000"
        case "STARZ":    return "#000000"
        case "SHOWTIME": return "#D80000"
        case "CRUNCHYROLL": return "#F47B20"
        case "YOUTUBE":  return "#FF0000"
        default:         return "#F5821F"
        }
    }
}

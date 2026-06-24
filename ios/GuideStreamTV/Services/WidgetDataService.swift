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
//  previous session wrote real Leaving Soon data, we preserve it — we only
//  update the counts. This prevents the widget from flashing empty on every
//  fresh app launch.
//

import Foundation
import WidgetKit

// MARK: - Codable payload types (must match the widget target's decoding keys)

nonisolated struct WidgetLeavingSoonItem: Codable, Sendable {
    let id: String
    let title: String
    let platform: String
    let platformColorHex: String
    let posterUrl: String?
    let daysRemaining: Int
    let expireDate: String

    enum CodingKeys: String, CodingKey {
        case id, title, platform, platformColorHex, posterUrl, daysRemaining, expireDate
    }
}

nonisolated struct WidgetPayload: Codable, Sendable {
    let leavingSoon: [WidgetLeavingSoonItem]
    let watchlistCount: Int
    let newEpisodeCount: Int
    let lastUpdated: Date

    enum CodingKeys: String, CodingKey {
        case leavingSoon, watchlistCount, newEpisodeCount, lastUpdated
    }
}

// MARK: - Service

@MainActor
final class WidgetDataService {
    static let shared = WidgetDataService()
    private init() {}

    private let appGroupId = "group.app.rork.guidestream-tv"
    private let payloadFileName = "widget_payload_v1.json"
    private let userDefaultsKey = "gs.widgetPayload.v1"

    /// Cached leaving-soon items from the last full push so `pushCounts()`
    /// (called from ContentView / StreamsViewModel on every change) can
    /// preserve them without needing Watchmode data.
    private var cachedLeavingSoon: [WidgetLeavingSoonItem] = []

    // MARK: - Full push (called from HomeView after Watchmode resolves)

    func push(
        expiringItems: [(tmdbId: Int, title: String, daysLeft: Int, sourceId: String)],
        posterUrls: [Int: String],
        watchlistCount: Int,
        newEpisodeCount: Int
    ) {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let items: [WidgetLeavingSoonItem] = expiringItems
            .filter { $0.daysLeft <= 14 }
            .prefix(12)
            .map { item in
                let platform = Platform.from(providerName: item.sourceId)
                let colorHex = platform?.colorHex ?? "#F5821F"
                let platformName = platform?.name ?? item.sourceId.uppercased()
                let expireDate = Calendar.current.date(
                    byAdding: .day, value: item.daysLeft, to: Date()
                ) ?? Date()
                return WidgetLeavingSoonItem(
                    id: String(item.tmdbId),
                    title: item.title,
                    platform: platformName,
                    platformColorHex: colorHex,
                    posterUrl: posterUrls[item.tmdbId],
                    daysRemaining: item.daysLeft,
                    expireDate: formatter.string(from: expireDate)
                )
            }

        cachedLeavingSoon = items
        writePayload(
            leavingSoon: items,
            watchlistCount: watchlistCount,
            newEpisodeCount: newEpisodeCount
        )
    }

    // MARK: - Counts-only push (called early from ContentView / StreamsViewModel)

    /// Updates watchlist and new-episode counts without overwriting any
    /// Leaving Soon data that was written by a previous session. If the
    /// in-memory cache is empty (first launch), we try to recover the
    /// Leaving Soon items already stored in the shared container so the
    /// widget doesn't blink back to empty.
    func pushCounts(watchlistCount: Int, newEpisodeCount: Int) {
        // Preserve in-memory cache if we have one
        var leavingSoon = cachedLeavingSoon

        // If cache is cold, try to recover from the shared container so
        // the widget doesn't lose its Leaving Soon data on a fresh launch.
        if leavingSoon.isEmpty {
            if let existing = loadExistingPayload(),
               !existing.leavingSoon.isEmpty {
                leavingSoon = existing.leavingSoon
                cachedLeavingSoon = existing.leavingSoon
            }
        }

        writePayload(
            leavingSoon: leavingSoon,
            watchlistCount: watchlistCount,
            newEpisodeCount: newEpisodeCount
        )
    }

    // MARK: - Diagnostics

    /// Snapshot of the shared-container health, used by the in-app Widget
    /// setup screen to show ground truth instead of guessing.
    struct Diagnostics {
        let fileContainerReachable: Bool
        let userDefaultsReachable: Bool
        let hasPayload: Bool
        let leavingSoonCount: Int
        let watchlistCount: Int
        let newEpisodeCount: Int
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
            leavingSoonCount: payload?.leavingSoon.count ?? 0,
            watchlistCount: payload?.watchlistCount ?? 0,
            newEpisodeCount: payload?.newEpisodeCount ?? 0,
            lastUpdated: payload?.lastUpdated
        )
    }

    /// Writes a known sample payload so the user can confirm the transport
    /// end-to-end without depending on Watchmode data. If the widget shows
    /// this sample, the App Group container works and the real issue is
    /// upstream (no expiring titles / empty watchlist).
    func pushTestData() {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let sample: [WidgetLeavingSoonItem] = [
            ("Stranger Things", "NETFLIX", "#E50914", 3),
            ("The Last of Us", "HBO", "#5A1FCB", 5),
            ("Severance", "Apple TV+", "#101010", 8),
        ].enumerated().map { idx, t in
            let expire = Calendar.current.date(byAdding: .day, value: t.3, to: Date()) ?? Date()
            return WidgetLeavingSoonItem(
                id: "sample-\(idx)",
                title: t.0,
                platform: t.1,
                platformColorHex: t.2,
                posterUrl: nil,
                daysRemaining: t.3,
                expireDate: formatter.string(from: expire)
            )
        }
        cachedLeavingSoon = sample
        writePayload(leavingSoon: sample, watchlistCount: 12, newEpisodeCount: 3)
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
        leavingSoon: [WidgetLeavingSoonItem],
        watchlistCount: Int,
        newEpisodeCount: Int
    ) {
        let payload = WidgetPayload(
            leavingSoon: leavingSoon,
            watchlistCount: watchlistCount,
            newEpisodeCount: newEpisodeCount,
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

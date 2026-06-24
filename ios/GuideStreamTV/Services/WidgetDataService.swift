//
//  WidgetDataService.swift
//  GuideStreamTV
//
//  Writes a WidgetPayload JSON file into the App Group shared container
//  every time the home screen refreshes its leaving-soon, watchlist, or
//  new-episode data. The widget reads this file to render up-to-date
//  cards without ever hitting the network itself.
//
//  Uses FileManager.containerURL (not UserDefaults(suiteName:)) because
//  the container URL API is more explicit and avoids subtle entitlement /
//  sandbox issues that can cause UserDefaults to silently return nil in
//  either the main app or the widget extension.
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

    /// Cached leaving-soon items from the last full push so `pushCounts()`
    /// (called from ContentView / StreamsViewModel on every change) can
    /// preserve them without needing Watchmode data.
    private var cachedLeavingSoon: [WidgetLeavingSoonItem] = []

    // MARK: - Full push (called from HomeView after Watchmode resolves)

    /// Serialises the full app state — leaving-soon titles, watchlist count,
    /// and new episode count — into the App Group shared container.
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

    // MARK: - Counts-only push (called from ContentView / StreamsViewModel)

    /// Writes updated counts while preserving whatever leaving-soon items
    /// were last pushed. Safe to call from any point in the app lifecycle
    /// — no Watchmode data required. This is the call that ensures the
    /// widget has data immediately after login, not just after the home
    /// screen finishes its network round-trips.
    func pushCounts(watchlistCount: Int, newEpisodeCount: Int) {
        writePayload(
            leavingSoon: cachedLeavingSoon,
            watchlistCount: watchlistCount,
            newEpisodeCount: newEpisodeCount
        )
    }

    // MARK: - File-based write

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

        // Primary path: write JSON file to the App Group shared container.
        // This is more reliable than UserDefaults(suiteName:) because it
        // uses the explicit container URL API.
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) {
            let fileURL = containerURL.appendingPathComponent(payloadFileName)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            do {
                let data = try encoder.encode(payload)
                try data.write(to: fileURL, options: .atomic)
                print("[WidgetData] Wrote \(leavingSoon.count) leaving-soon, \(watchlistCount) watchlist, \(newEpisodeCount) new eps → \(fileURL.path)")
            } catch {
                print("[WidgetData] File write failed: \(error.localizedDescription)")
            }
        } else {
            print("[WidgetData] containerURL returned nil for \(appGroupId) — check entitlements & provisioning profile")
        }

        // Always reload widget timelines after writing.
        WidgetCenter.shared.reloadTimelines(ofKind: "GuideStreamWidget")
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

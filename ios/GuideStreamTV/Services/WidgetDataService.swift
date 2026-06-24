//
//  WidgetDataService.swift
//  GuideStreamTV
//
//  Writes a WidgetPayload to the App Group shared UserDefaults every time
//  the home screen refreshes its leaving-soon, watchlist, or new-episode data.
//  The widget reads this payload to render up-to-date cards without ever
//  hitting the network itself.
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
    private let payloadKey = "gs.widgetPayload.v1"

    /// Serialise the current app state into the shared container so the
    /// widget can display leaving-soon titles, watchlist count, and new
    /// episode count on its next timeline refresh.
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

        let payload = WidgetPayload(
            leavingSoon: items,
            watchlistCount: watchlistCount,
            newEpisodeCount: newEpisodeCount,
            lastUpdated: Date()
        )

        guard let shared = UserDefaults(suiteName: appGroupId) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(payload) {
            shared.set(data, forKey: payloadKey)
            WidgetCenter.shared.reloadTimelines(ofKind: "GuideStreamWidget")
        }
    }
}

// MARK: - Platform color mapping

extension Platform {
    var colorHex: String {
        // Match the hex values used in the widget. We read the Color's
        // component values and serialise them so the widget (which doesn't
        // import the main app) can reconstruct the exact same tints.
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

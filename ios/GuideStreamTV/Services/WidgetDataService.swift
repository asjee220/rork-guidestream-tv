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

nonisolated struct WidgetNewEpisodeItem: Codable, Sendable {
    let id: String
    let title: String
    let episodeLabel: String
    let platform: String
    let platformColorHex: String

    enum CodingKeys: String, CodingKey {
        case id, title, episodeLabel, platform, platformColorHex
    }
}

nonisolated struct WidgetPayload: Codable, Sendable {
    let leavingSoon: [WidgetLeavingSoonItem]
    let watchlistCount: Int
    let newEpisodeCount: Int
    let lastUpdated: Date
    let newEpisodes: [WidgetNewEpisodeItem]?

    enum CodingKeys: String, CodingKey {
        case leavingSoon, watchlistCount, newEpisodeCount, lastUpdated, newEpisodes
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
    /// Cached new-episode items, preserved across `pushCounts()` calls the
    /// same way `cachedLeavingSoon` is.
    private var cachedNewEpisodes: [WidgetNewEpisodeItem] = []

    // MARK: - Full push (called from HomeView after Watchmode resolves)

    func push(
        expiringItems: [(tmdbId: Int, title: String, daysLeft: Int, sourceId: String)],
        posterUrls: [Int: String],
        watchlistCount: Int,
        newEpisodeCount: Int,
        newEpisodeRows: [NewEpisodeRow] = []
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

        let mappedNewEpisodes = Self.mapNewEpisodes(newEpisodeRows)

        // --- Wipe-bug fix: preserve good data on transient empty results ---
        // If the freshly mapped leaving-soon list is empty (e.g. a transient
        // Watchmode failure), keep the previously written items as long as
        // they are less than 48h old — mirroring the preservation logic in
        // `pushCounts()`.
        var leavingSoon = items
        if leavingSoon.isEmpty {
            if let existing = loadExistingPayload(),
               !existing.leavingSoon.isEmpty,
               let lastUpdated = existing.lastUpdated as Date?,
               Date().timeIntervalSince(lastUpdated) < 48 * 60 * 60 {
                leavingSoon = existing.leavingSoon
                cachedLeavingSoon = existing.leavingSoon
            }
        } else {
            cachedLeavingSoon = items
        }

        // Carry existing newEpisodes forward only when the incoming list is
        // empty, using the same loadExistingPayload pattern.
        var newEpisodes = mappedNewEpisodes
        if newEpisodes.isEmpty {
            if let existing = loadExistingPayload(),
               let existingNew = existing.newEpisodes,
               !existingNew.isEmpty,
               let lastUpdated = existing.lastUpdated as Date?,
               Date().timeIntervalSince(lastUpdated) < 48 * 60 * 60 {
                newEpisodes = existingNew
                cachedNewEpisodes = existingNew
            }
        } else {
            cachedNewEpisodes = mappedNewEpisodes
        }

        writePayload(
            leavingSoon: leavingSoon,
            watchlistCount: watchlistCount,
            newEpisodeCount: newEpisodeCount,
            newEpisodes: newEpisodes
        )
    }

    // MARK: - Counts-only push (called early from ContentView / StreamsViewModel)

    /// Updates watchlist and new-episode counts without overwriting any
    /// Leaving Soon data that was written by a previous session. If the
    /// in-memory cache is empty (first launch), we try to recover the
    /// Leaving Soon items already stored in the shared container so the
    /// widget doesn't blink back to empty.
    func pushCounts(
        watchlistCount: Int,
        newEpisodeCount: Int,
        newEpisodeRows: [NewEpisodeRow] = []
    ) {
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

        // Map incoming new-episode rows; preserve the cached/existing items
        // when the incoming list is empty so a counts-only refresh doesn't
        // wipe a good new-episodes payload.
        var newEpisodes = cachedNewEpisodes
        if newEpisodeRows.isEmpty {
            if newEpisodes.isEmpty,
               let existing = loadExistingPayload(),
               let existingNew = existing.newEpisodes,
               !existingNew.isEmpty {
                newEpisodes = existingNew
                cachedNewEpisodes = existingNew
            }
        } else {
            newEpisodes = Self.mapNewEpisodes(newEpisodeRows)
            cachedNewEpisodes = newEpisodes
        }

        writePayload(
            leavingSoon: leavingSoon,
            watchlistCount: watchlistCount,
            newEpisodeCount: newEpisodeCount,
            newEpisodes: newEpisodes
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
        writePayload(leavingSoon: sample, watchlistCount: 12, newEpisodeCount: 3, newEpisodes: [])
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
        newEpisodeCount: Int,
        newEpisodes: [WidgetNewEpisodeItem]
    ) {
        let payload = WidgetPayload(
            leavingSoon: leavingSoon,
            watchlistCount: watchlistCount,
            newEpisodeCount: newEpisodeCount,
            lastUpdated: Date(),
            newEpisodes: newEpisodes
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

    // MARK: - New-episode mapping

    /// Maps up to 8 `NewEpisodeRow` values to widget-ready items, preserving
    /// row order. Title falls back to `episodeTitle` then `titleId`; episode
    /// label is `S{season} E{episode}` when both are non-nil (matching the
    /// convention in ShowDetailScreen/HomeView), otherwise `episodeTitle`,
    /// otherwise "New episode". Platform/color resolve via the same
    /// `Platform.from(providerName:)` + `colorHex` used by `push()`.
    private static func mapNewEpisodes(_ rows: [NewEpisodeRow]) -> [WidgetNewEpisodeItem] {
        rows.prefix(8).map { row in
            let title = row.title ?? row.episodeTitle ?? row.titleId
            let episodeLabel: String
            if let season = row.season, let episode = row.episode {
                episodeLabel = "S\(season) E\(episode)"
            } else if let epTitle = row.episodeTitle, !epTitle.isEmpty {
                episodeLabel = epTitle
            } else {
                episodeLabel = "New episode"
            }
            let platform = Platform.from(providerName: row.platform)
            let colorHex = platform?.colorHex ?? "#F5821F"
            let platformName = platform?.name ?? (row.platform?.uppercased() ?? "STREAM")
            return WidgetNewEpisodeItem(
                id: row.id,
                title: title,
                episodeLabel: episodeLabel,
                platform: platformName,
                platformColorHex: colorHex
            )
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

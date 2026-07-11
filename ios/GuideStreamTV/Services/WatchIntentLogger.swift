//
//  WatchIntentLogger.swift
//  GuideStreamTV
//

import Foundation
import Supabase

enum IntentEventType: String {
    case cardTapped = "card_tapped"
    case deeplinkFired = "deeplink_fired"
    case notificationOpened = "notification_opened"
    case searchQuery = "search_query"
    case trailerWatched = "trailer_watched"
    case trailerSkipped = "trailer_skipped"
    case streamAdded = "stream_added"
    case streamRemoved = "stream_removed"
    case bingeAlertOpened = "binge_alert_opened"
    case askStreamQuery = "ask_stream_query"
    case playOnDeviceChosen = "play_on_device_chosen"
    case episodeDetailViewed = "episode_detail_viewed"
    case continueWatching = "continue_watching_tapped"
    case widgetSetupTapped = "widget_setup_tapped"
    case affiliateLinkTapped = "affiliate_link_tapped"
    case sponsoredReelViewed = "sponsored_reel_viewed"
    case sponsoredReelTapped = "sponsored_reel_tapped"
    case adImpression = "ad_impression"
    case trailerViewed = "trailer_viewed"
    case trailerLiked = "trailer_liked"
    case notifyReleaseTapped = "notify_release_tapped"
    case commentsOpened = "comments_opened"
    case muteToggled = "mute_toggled"
    case watchlistAdded = "watchlist_added"
    case watchlistRemoved = "watchlist_removed"
    case watchedToggled = "watched_toggled"

    // Lifecycle events — fire whether signed in or not so we capture every device.
    case sessionStarted = "session_started"
    case authSignedIn = "auth_signed_in"
    case guestStarted = "guest_started"
    case onboardingCompleted = "onboarding_completed"
    case serviceSelected = "service_selected"
    case appOpened = "app_opened"
}

/// Captured error entry — surfaced in the in-app diagnostics screen so the
/// user can see *exactly* why a Supabase write failed (RLS, missing table,
/// network, etc.) instead of guessing.
nonisolated struct LoggerError: Identifiable, Sendable {
    let id: UUID = UUID()
    let timestamp: Date
    let eventType: String
    let message: String
}

/// Fire-and-forget logger that writes a row to `watch_intent_events` for every
/// meaningful user action — **whether the user is signed in or a guest**.
///
/// Every payload includes:
/// - `event_type` — the action being recorded.
/// - `user_id` — the Supabase auth user id when signed in (omitted for guests).
/// - `device_id` — stable per-device UUID, populated for every user. Lets us
///    attribute guest activity to a real device install.
/// - `metadata.device_id` / `metadata.is_guest` — also mirrored into the JSON
///    metadata blob in case the table doesn't yet have a top-level `device_id`
///    column. Mirroring guarantees the data is captured either way.
///
/// Errors are logged to the console *verbosely* and kept in a ring buffer so
/// the `SupabaseDiagnosticsView` can show the last few failures.
@MainActor
final class WatchIntentLogger {
    static let shared = WatchIntentLogger()
    private init() {}

    /// Last N error messages. Kept on the main actor so SwiftUI views can
    /// observe it directly via `@State`/`@Observable` patterns.
    private(set) var recentErrors: [LoggerError] = []

    /// Total number of insert attempts (success or failure) since launch.
    private(set) var totalAttempts: Int = 0
    /// Total number of successful inserts since launch.
    private(set) var totalSuccesses: Int = 0

    private let maxErrors: Int = 20

    func log(
        eventType: IntentEventType,
        titleId: String? = nil,
        platformId: String? = nil,
        metadata: [String: Any]? = nil,
        watchDurationSeconds: Double? = nil
    ) {
        // Snapshot state synchronously on the main actor before hopping to a
        // background Task — keeps everything Sendable.
        let userId = AuthViewModel.shared.currentUser?.id.uuidString
        let isGuest = AuthViewModel.shared.isGuest && userId == nil
        let deviceId = DeviceIdentity.shared.deviceId
        let event = eventType.rawValue
        let titleIdCopy = titleId
        let platformIdCopy = platformId

        // Build merged metadata up front (still on MainActor — no Sendable
        // captures of [String: Any] across the Task boundary).
        var mergedMeta: [String: Any] = metadata ?? [:]
        mergedMeta["device_id"] = deviceId
        mergedMeta["is_guest"] = isGuest
        mergedMeta["is_authenticated"] = userId != nil
        if let duration = watchDurationSeconds {
            mergedMeta["watch_duration_seconds"] = duration
        }
        let metadataJSON: AnyJSON? = Self.toAnyJSON(mergedMeta)

        totalAttempts += 1

        Task { [weak self] in
            var payload: [String: AnyJSON] = [
                "event_type": .string(event),
                "device_id": .string(deviceId)
            ]
            if let userId { payload["user_id"] = .string(userId) }
            if let titleIdCopy { payload["title_id"] = .string(titleIdCopy) }
            if let platformIdCopy { payload["platform_id"] = .string(platformIdCopy) }
            if let metadataJSON { payload["metadata"] = metadataJSON }

            do {
                try await SupabaseManager.shared.client
                    .from("watch_intent_events")
                    .insert(payload)
                    .execute()
                await self?.recordSuccess()
                // Notify observers so Profile stats refresh reactively.
                await self?.postStatsNotification()
            } catch {
                // If the table is missing a top-level `device_id` column,
                // Postgres will reject the insert with a 400/column error.
                // Retry once with `device_id` dropped — the metadata still
                // carries it so the data isn't lost.
                let message = Self.describe(error)
                let columnIssue = message.localizedCaseInsensitiveContains("device_id")
                    && (message.localizedCaseInsensitiveContains("column")
                        || message.localizedCaseInsensitiveContains("schema")
                        || message.localizedCaseInsensitiveContains("could not find"))
                if columnIssue {
                    var fallback = payload
                    fallback.removeValue(forKey: "device_id")
                    do {
                        try await SupabaseManager.shared.client
                            .from("watch_intent_events")
                            .insert(fallback)
                            .execute()
                        await self?.recordSuccess()
                        await self?.postStatsNotification()
                        return
                    } catch {
                        self?.recordError(event: event, error: error)
                        return
                    }
                }
                self?.recordError(event: event, error: error)
            }
        }
    }

    private func recordSuccess() {
        totalSuccesses += 1
    }

    /// Posts a notification so `ProfileStatsService` knows new engagement
    /// data is available and can refresh without a manual pull.
    private func postStatsNotification() {
        NotificationCenter.default.post(
            name: Notification.Name("ProfileStatsNeedsRefresh"),
            object: nil
        )
    }

    private func recordError(event: String, error: Error) {
        let message = Self.describe(error)
        print("[WatchIntent ERROR] \(event): \(message)")
        let entry = LoggerError(timestamp: Date(), eventType: event, message: message)
        recentErrors.insert(entry, at: 0)
        if recentErrors.count > maxErrors {
            recentErrors.removeLast(recentErrors.count - maxErrors)
        }
    }

    /// Manually fire a test event from the diagnostics screen — returns the
    /// resulting error message (if any) so the UI can render it inline.
    func logTestEvent() async -> String? {
        let deviceId = DeviceIdentity.shared.deviceId
        let userId = AuthViewModel.shared.currentUser?.id.uuidString
        let isGuest = AuthViewModel.shared.isGuest && userId == nil
        var payload: [String: AnyJSON] = [
            "event_type": .string("diagnostic_ping"),
            "device_id": .string(deviceId)
        ]
        if let userId { payload["user_id"] = .string(userId) }
        let meta: [String: Any] = [
            "device_id": deviceId,
            "is_guest": isGuest,
            "is_authenticated": userId != nil,
            "source": "diagnostics"
        ]
        if let metaJSON = Self.toAnyJSON(meta) { payload["metadata"] = metaJSON }

        totalAttempts += 1
        do {
            try await SupabaseManager.shared.client
                .from("watch_intent_events")
                .insert(payload)
                .execute()
            totalSuccesses += 1
            return nil
        } catch {
            let message = Self.describe(error)
            recordError(event: "diagnostic_ping", error: error)
            return message
        }
    }

    /// Lowercases and dashes a free-form title into a stable id slug, e.g.
    /// "Stranger Things" → "tt-stranger-things".
    static func titleSlug(_ title: String) -> String {
        let lower = title.lowercased()
        let allowed = lower.map { ch -> Character in
            if ch.isLetter || ch.isNumber { return ch }
            return "-"
        }
        var slug = String(allowed)
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "tt-\(slug)"
    }

    // MARK: - AnyJSON conversion

    nonisolated private static func toAnyJSON(_ value: Any) -> AnyJSON? {
        switch value {
        case let s as String: return .string(s)
        case let b as Bool: return .bool(b)
        case let i as Int: return .integer(i)
        case let d as Double: return .double(d)
        case let f as CGFloat: return .double(Double(f))
        case let arr as [Any]:
            return .array(arr.compactMap { toAnyJSON($0) })
        case let dict as [String: Any]:
            var out: [String: AnyJSON] = [:]
            for (k, v) in dict {
                if let j = toAnyJSON(v) { out[k] = j }
            }
            return .object(out)
        default:
            return .string(String(describing: value))
        }
    }

    /// Produce a verbose human-readable description for an error, including
    /// Postgres response details when present.
    nonisolated private static func describe(_ error: Error) -> String {
        let ns = error as NSError
        var parts: [String] = [ns.localizedDescription]
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error {
            parts.append("underlying: \((underlying as NSError).localizedDescription)")
        }
        for key in ["message", "hint", "details", "code"] {
            if let value = ns.userInfo[key] as? String, !value.isEmpty {
                parts.append("\(key)=\(value)")
            }
        }
        return parts.joined(separator: " | ")
    }
}

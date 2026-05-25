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
}

/// Fire-and-forget logger that writes a row to `watch_intent_events` for every
/// meaningful user action. Never throws and never blocks the UI — silent fail only.
final class WatchIntentLogger {
    static let shared = WatchIntentLogger()
    private init() {}

    func log(
        eventType: IntentEventType,
        titleId: String? = nil,
        platformId: String? = nil,
        metadata: [String: Any]? = nil
    ) {
        // Snapshot user id and a Sendable metadata representation synchronously.
        let userId = AuthViewModel.shared.currentUser?.id.uuidString
        let metadataJSON: AnyJSON? = metadata.flatMap { Self.toAnyJSON($0) }
        let event = eventType.rawValue
        let titleIdCopy = titleId
        let platformIdCopy = platformId

        Task {
            var payload: [String: AnyJSON] = [
                "event_type": .string(event)
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
            } catch {
                // Silent fail — analytics must never affect UX.
            }
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

    private static func toAnyJSON(_ value: Any) -> AnyJSON? {
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
}

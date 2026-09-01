//
//  TVWatchIntentLogger.swift
//  GuideStreamTVTV
//
//  Writes user-intent events to the shared Supabase `watch_intent_events`
//  table — the same table the iOS app writes to. Fires from a detached
//  Task so the insert never blocks the main thread or throws into the UI.
//  Guests and signed-out viewers are silently skipped (no user_id means
//  no row). Device id is resolved from TVDeviceIdentity, the same source
//  used everywhere else in this target.
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
    case sessionStarted = "session_started"
    case authSignedIn = "auth_signed_in"
    case guestStarted = "guest_started"
    case onboardingCompleted = "onboarding_completed"
    case serviceSelected = "service_selected"
    case appOpened = "app_opened"
    case watchedToggled = "watched_toggled"
}

/// Fire-and-forget logger that inserts a row into `watch_intent_events`
/// for every meaningful user action. Only fires for authenticated users —
/// guests and signed-out viewers are silently skipped. All failures are
/// swallowed so the UI is never affected by an analytics write.
@MainActor
final class WatchIntentLogger {
    static let shared = WatchIntentLogger()
    private init() {}

    func log(
        eventType: IntentEventType,
        titleId: String? = nil,
        platformId: String? = nil,
        metadata: [String: Any]? = nil
    ) {
        // Skip entirely when the viewer is a guest or signed out — no
        // user_id means no insert.
        let userId = AuthViewModel.shared.currentUser?.id.uuidString
        guard let userId, !userId.isEmpty, !AuthViewModel.shared.isGuest else { return }

        let deviceId = TVDeviceIdentity.shared.deviceId
        let event = eventType.rawValue
        let titleIdCopy = titleId
        let platformIdCopy: String? = {
            guard let raw = platformId, !raw.isEmpty else { return platformId }
            return raw.lowercased()
        }()

        // Build merged metadata on the main actor so the [String: Any]
        // dict never crosses the Sendable boundary as-is.
        var mergedMeta: [String: Any] = metadata ?? [:]

        // Stamp the resolved TMDB id and media type whenever the title id
        // encodes them. The Jump Back In rail is built from these rows and
        // can only include a title it can resolve to a TMDB id, so leaving
        // this to individual call sites is how launches go missing from it.
        // Sports slugs ("tt-chw-phi-mlb") and creator ids ("yt:UC...")
        // parse to nil and are left untouched, exactly as before. A value
        // the caller passed explicitly always wins.
        if let tmdbId = TVTitleID.tmdbId(from: titleId), mergedMeta["tmdb_id"] == nil {
            mergedMeta["tmdb_id"] = tmdbId
        }
        if let media = TVTitleID.mediaType(from: titleId), mergedMeta["media_type"] == nil {
            mergedMeta["media_type"] = media
        }

        mergedMeta["device_id"] = deviceId
        mergedMeta["is_guest"] = false
        mergedMeta["is_authenticated"] = true
        let metadataJSON: AnyJSON? = Self.toAnyJSON(mergedMeta)

        Task.detached {
            var payload: [String: AnyJSON] = [
                "event_type": .string(event),
                "device_id": .string(deviceId),
                "user_id": .string(userId)
            ]
            if let titleIdCopy { payload["title_id"] = .string(titleIdCopy) }
            if let platformIdCopy { payload["platform_id"] = .string(platformIdCopy) }
            if let metadataJSON { payload["metadata"] = metadataJSON }

            // Silent — never block, never throw into the UI, never log
            // to the console.
            do {
                try await SupabaseManager.shared.client
                    .from("watch_intent_events")
                    .insert(payload)
                    .execute()
            } catch { }
        }
    }

    /// Lowercases and dashes a free-form title into a stable id slug.
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
}

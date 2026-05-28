//
//  TVWatchIntentLogger.swift
//  GuideStreamTVTV
//
//  No-op stub for tvOS — WatchIntentLogger records user actions to Supabase,
//  but on Apple TV the interaction surface is watched directly on the device
//  so the analytics pipeline isn't needed. Kept as a stub so shared views
//  compile cleanly.
//

import Foundation

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
}

/// Fire-and-forget stub — all calls silently succeed. The real iOS
/// implementation writes to a Supabase `watch_intent_events` table.
@MainActor
final class WatchIntentLogger {
    static let shared = WatchIntentLogger()
    private init() {}

    func log(
        eventType: IntentEventType,
        titleId: String? = nil,
        platformId: String? = nil,
        metadata: [String: Any]? = nil
    ) {}

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
}

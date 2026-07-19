//
//  PendingRouteInbox.swift
//  GuideStreamTV
//

import Foundation

/// Launch-safe buffer for push/deep-link routes that arrive before SwiftUI
/// has committed its `NotificationCenter` subscribers.
///
/// On a cold launch from a notification tap, `AppDelegate`'s
/// `userNotificationCenter(_:didReceive:)` runs before `ContentView`'s
/// `.onReceive` modifiers are subscribed, so the posted route is discarded.
/// The delegate writes the same route here first; `ContentView` drains the
/// inbox on first appearance (`.onAppear` + the start of its `.task`) and
/// forwards it to `AppRouter`. Take-once semantics guarantee a route is
/// consumed exactly once, so the simultaneous `NotificationCenter` post
/// (warm path) and inbox write can never double-present.
///
/// Not `@Observable` — this is a plain synchronous handoff buffer with no
/// SwiftUI dependency beyond what `PendingTitleRoute` already carries.
@MainActor
final class PendingRouteInbox {
    static let shared = PendingRouteInbox()

    private var pendingTitle: PendingTitleRoute?
    private var pendingGameId: String?

    private init() {}

    /// Stores a title route, replacing any previously buffered one. Two
    /// rapid taps therefore keep only the most recent route (no queueing).
    func setTitle(_ route: PendingTitleRoute) {
        pendingTitle = route
    }

    /// Returns and clears the buffered title route. A second call returns
    /// `nil`, ensuring the route is forwarded to `AppRouter` exactly once.
    func takeTitle() -> PendingTitleRoute? {
        let route = pendingTitle
        pendingTitle = nil
        return route
    }

    /// Stores a sports game id, replacing any previously buffered one.
    func setGameId(_ id: String) {
        pendingGameId = id
    }

    /// Returns and clears the buffered game id. A second call returns `nil`.
    func takeGameId() -> String? {
        let id = pendingGameId
        pendingGameId = nil
        return id
    }
}

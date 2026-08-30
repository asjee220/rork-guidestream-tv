//
//  StopTrackingGameIntent.swift
//  GuideStreamTV
//
//  Backs the "Stop tracking" button on the sports Live Activity. Like
//  SportsActivityAttributes this file is a member of BOTH the GuideStreamTV
//  app target and the GuideStreamWidget extension target — the widget builds
//  the Button, the app performs the intent — so it must not reference any
//  app-only type.
//
//  LiveActivityIntent runs in the APP's process, in the background: tapping
//  the button on the Lock Screen ends the activity in place and never brings
//  the app forward. (A Link cannot do this — it can only open a URL, which
//  means launching the app just to dismiss a card.)
//
//  Deliberately ActivityKit-only. Ending here does not stamp `ended_at` on the
//  `live_activities` row, and it does not need to: the row is closed by either
//  of two paths that already exist —
//    * SportsLiveActivityController.reconcile(), which runs on every return to
//      the foreground and stamps ended_at for any activity that is gone, and
//    * sports_poll_and_notify, whose next push to the dead token gets a 410
//      from APNs and stamps ended_at itself.
//

import ActivityKit
import AppIntents

struct StopTrackingGameIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop tracking"
    static let description = IntentDescription("Stops tracking this game's live score.")

    /// Keeps it out of Shortcuts and Spotlight — it is only ever invoked from
    /// the Live Activity's own button.
    static let isDiscoverable: Bool = false

    @Parameter(title: "Game")
    var gameId: String

    init() {}

    init(gameId: String) {
        self.gameId = gameId
    }

    func perform() async throws -> some IntentResult {
        // Match on gameId rather than ending everything: the user asked to
        // stop THIS game, and only one activity per game is ever requested.
        for activity in Activity<SportsActivityAttributes>.activities
        where activity.attributes.gameId == gameId {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        return .result()
    }
}

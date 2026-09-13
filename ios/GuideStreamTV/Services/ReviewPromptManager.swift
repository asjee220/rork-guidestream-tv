//
//  ReviewPromptManager.swift
//  GuideStreamTV
//
//  Decides when to ask for an App Store rating, per the plan in
//  claude/in-app-review-prompt-plan-aug30-2026.md.
//
//  Two rules shape everything here:
//
//  1. NO PRE-PROMPT, EVER. Both stores prohibit review gating — no "do you
//     like the app?", no star row, nothing overlaid on the system card. This
//     type never renders UI; it only decides *when* the native sheet should be
//     asked for. If a future change adds a custom question in front of it,
//     that is a policy violation, not a design choice.
//
//  2. COUNTERS ARE PER INSTALL, NOT PER ACCOUNT. 810 of 1,083 devices in the
//     telemetry have never signed in. Keying any of this on user_id would
//     halve the eligible population at every gate, so everything below lives
//     in UserDefaults against the install.
//
//  The API itself is quota-limited and silent: Apple allows at most 3 prompts
//  per user per 365 days, never reports whether the sheet appeared, and never
//  shows it in TestFlight. That is why nothing user-visible may depend on it,
//  and why the manual "Rate GuideStream TV" row opens the store URL instead of
//  calling this.
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class ReviewPromptManager {
    static let shared = ReviewPromptManager()

    /// The success moment that armed the current request. Nil when nothing is
    /// pending. The root view observes this, calls the SwiftUI
    /// `requestReview` action, then calls `didPresent()`.
    private(set) var pendingTrigger: Trigger?

    enum Trigger: String {
        /// Came back to the app after a deep link — the core promise kept.
        case deepLinkReturn = "deeplink_return"
        /// Accumulated habit, no interruption cost.
        case watchedMilestone = "watched_milestone"
        /// A new-episode alert led straight to watching it. Highest peak.
        case alertToWatch = "alert_to_watch"
        /// A cast to Roku / Tizen started. Rarest, kept at the user's request.
        case castStarted = "cast_started"
        /// Came back on a third separate day, having actually used the app.
        case returnVisit = "return_visit"
    }

    // MARK: Thresholds

    private let minInstallDays = 3
    private let minSessions = 3
    private let deepLinkThreshold = 2
    private let watchedThreshold = 5
    /// Separate calendar days the app has been opened, for `.returnVisit`.
    private let activeDayThreshold = 3
    /// 90 days is the industry floor between prompts. The annual cap is now
    /// Apple's own 3 rather than a self-imposed 2: the API silently no-ops
    /// over quota, so holding one back buys no goodwill — it forfeits a
    /// prompt, which at this install volume is a real cost.
    private let cooldownDays = 90
    private let maxPerYear = 3

    // MARK: Storage (per install)

    private let defaults = UserDefaults.standard
    private let firstLaunchKey = "gs.reviewPrompt.firstLaunch"
    private let sessionsKey = "gs.reviewPrompt.sessions"
    private let deepLinksKey = "gs.reviewPrompt.deepLinks"
    private let watchedKey = "gs.reviewPrompt.watched"
    private let shownDatesKey = "gs.reviewPrompt.shownDates"
    private let armedKey = "gs.reviewPrompt.armedDeepLink"
    private let activeDaysKey = "gs.reviewPrompt.activeDays"
    private let lastActiveDayKey = "gs.reviewPrompt.lastActiveDay"

    private init() {
        if defaults.object(forKey: firstLaunchKey) == nil {
            defaults.set(Date(), forKey: firstLaunchKey)
        }
    }

    // MARK: - Signals
    //
    // Fed from WatchIntentLogger.log, which already sees every one of these.
    // Hooking there rather than at each call site means a new success moment
    // cannot be added to the app and silently miss this.

    func noteSessionStarted() { bump(sessionsKey) }

    /// A deep link fired. Deliberately does NOT arm the prompt: the success is
    /// coming *back*, and a sheet presented at tap time would be buried under
    /// the launching app. `appDidBecomeActive()` closes the loop.
    func noteDeepLinkFired() {
        bump(deepLinksKey)
        defaults.set(true, forKey: armedKey)
    }

    func noteWatchedToggled() {
        bump(watchedKey)
        // Every fifth, not every toggle past the fifth — matches Android.
        let count = defaults.integer(forKey: watchedKey)
        if count >= watchedThreshold, count % watchedThreshold == 0 {
            consider(.watchedMilestone)
        }
    }

    func noteCastStarted() { consider(.castStarted) }

    func noteAlertOpened() { defaults.set(true, forKey: armedKey) }

    /// Called when the app returns to the foreground. If a deep link or an
    /// alert took the user out, coming back is the moment the promise was
    /// kept.
    func appDidBecomeActive() {
        noteActiveDay()

        if defaults.bool(forKey: armedKey) {
            defaults.set(false, forKey: armedKey)
            if defaults.integer(forKey: deepLinksKey) >= deepLinkThreshold {
                consider(.deepLinkReturn)
                return
            }
        }

        // Coming back on a third separate day is as strong a satisfaction
        // signal as a run of deep links, and far more people clear it: in the
        // twelve days after this shipped, only 16 iOS devices fired a deep
        // link at all. It still requires one real action on the install, so
        // presence alone never asks.
        guard defaults.integer(forKey: activeDaysKey) >= activeDayThreshold,
              defaults.integer(forKey: deepLinksKey) >= 1
                || defaults.integer(forKey: watchedKey) >= 1
        else { return }
        consider(.returnVisit)
    }

    /// One increment per calendar day the app is opened.
    private func noteActiveDay() {
        let today = Self.dayStamp()
        guard defaults.string(forKey: lastActiveDayKey) != today else { return }
        defaults.set(today, forKey: lastActiveDayKey)
        bump(activeDaysKey)
    }

    private static func dayStamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    // MARK: - Gating

    private func consider(_ trigger: Trigger) {
        guard pendingTrigger == nil, isEligible else { return }
        pendingTrigger = trigger
    }

    private var isEligible: Bool {
        // Never in TestFlight: Apple does not show the sheet there, so asking
        // would burn a trigger and teach us nothing.
        if isTestFlight { return false }
        guard installedDays >= minInstallDays else { return false }
        guard sessionsForGate >= minSessions else { return false }
        // Never stack on top of other modal UI.
        guard CoachMarkManager.shared.homeTourDone else { return false }
        guard AppUpdateGate.shared.prompt == nil else { return false }
        // Do not ask for a rating in a session that has already gone wrong.
        guard WatchIntentLogger.shared.recentErrors.isEmpty else { return false }
        let recent = shownDates
        guard recent.count < maxPerYear else { return false }
        if let last = recent.max(),
           Date().timeIntervalSince(last) < Double(cooldownDays) * 86_400 {
            return false
        }
        return true
    }

    /// The local counter starts at zero on the launch where this file first
    /// shipped, so it under-reports someone who has been here for months.
    /// DeviceSessionService keeps the same per-install number from the day the
    /// app was installed — take whichever is larger, so the gate does not make
    /// a returning user re-earn their history because they updated.
    private var sessionsForGate: Int {
        max(defaults.integer(forKey: sessionsKey), DeviceSessionService.shared.sessionCount)
    }

    private var installedDays: Int {
        guard let first = defaults.object(forKey: firstLaunchKey) as? Date else { return 0 }
        return Int(Date().timeIntervalSince(first) / 86_400)
    }

    /// A sandbox receipt means TestFlight (or a simulator build).
    private var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    /// Prompt dates inside the last 365 days, pruned on read.
    private var shownDates: [Date] {
        let cutoff = Date().addingTimeInterval(-365 * 86_400)
        return (defaults.array(forKey: shownDatesKey) as? [Date] ?? []).filter { $0 > cutoff }
    }

    // MARK: - Presentation

    /// Called by the root view immediately after invoking `requestReview`.
    /// Neither store reports whether the card appeared or what the user did,
    /// so this event count against the store's rating count is the only
    /// measurement available.
    func didPresent() {
        guard let trigger = pendingTrigger else { return }
        pendingTrigger = nil
        defaults.set(shownDates + [Date()], forKey: shownDatesKey)
        WatchIntentLogger.shared.log(
            eventType: .reviewPromptRequested,
            metadata: ["trigger": trigger.rawValue]
        )
    }

    private func bump(_ key: String) {
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
    }

    // MARK: - Store URL (the manual entry point)

    /// The App Store write-review page. The manual "Rate GuideStream TV" row
    /// opens THIS rather than calling `requestReview`: over quota, or in
    /// TestFlight, the API is a silent no-op and the row reads as a broken
    /// button. A user reported exactly that in GS-01008.
    static let writeReviewURL = URL(string: "https://apps.apple.com/app/id6773443577?action=write-review")!
}

//
//  AppUpdateGate.swift
//  GuideStreamTV
//
//  Decides what — if anything — to show the user about app versions when the
//  app opens (GUI-43).
//
//  Three states, one system, in strict precedence:
//
//    .required   installed < `min`    a blocking screen with no dismiss. The
//                                     only lever that can retire a client that
//                                     talks to an endpoint we have since
//                                     changed, which is the operational reason
//                                     this file exists at all.
//    .available  installed < `latest` a dismissible sheet, shown at most once
//                                     a week per released version so a user who
//                                     is happy where they are is not nagged.
//    .whatsNew   installed > the      the release notes, once, after the update
//                version last seen    has already happened. No store trip.
//
//  Everything is driven by one `app_update` row in `app_config`, which both
//  platforms already read and cache on launch, so shipping a floor is an edit
//  to one row rather than a release.
//
//  A first-ever install records its version and shows nothing: there is no
//  "what's new" for someone who has not been here before.
//

import Foundation

// MARK: - Remote shape

/// Per-platform half of the `app_update` config row.
nonisolated struct RemoteAppUpdatePlatform: Codable, Sendable {
    /// Versions below this cannot run. Absent or empty = no floor.
    let min: String?
    /// The newest released version. Absent or empty = no nudge.
    let latest: String?
    /// Store URL the update buttons open.
    let url: String?
}

/// Release notes shown after the user has updated.
nonisolated struct RemoteAppUpdateNotes: Codable, Sendable {
    let title: String?
    let items: [String]?
}

nonisolated struct RemoteAppUpdate: Codable, Sendable {
    let ios: RemoteAppUpdatePlatform?
    let android: RemoteAppUpdatePlatform?
    let notes: RemoteAppUpdateNotes?
}

// MARK: - Decision

enum AppUpdatePrompt: Equatable {
    /// Below the floor. Blocking, no dismiss.
    case required(storeURL: URL?)
    /// A newer version exists. Dismissible.
    case available(version: String, storeURL: URL?, notes: [String])
    /// The user just updated into this version.
    case whatsNew(version: String, title: String, notes: [String])
}

// MARK: - Gate

@MainActor
@Observable
final class AppUpdateGate {
    static let shared = AppUpdateGate()

    /// Non-nil when something should be on screen. The root view binds to it.
    private(set) var prompt: AppUpdatePrompt?

    /// The version this install was last seen running. Written on every
    /// evaluation, read once to detect "the user just updated".
    private let lastSeenKey = "gs.appUpdate.lastSeenVersion"
    /// ISO8601 timestamp of the last dismissible nudge, per target version, so
    /// the weekly rate limit survives relaunches.
    private let nudgedKey = "gs.appUpdate.lastNudge"
    /// Versions whose What's New sheet has already been shown.
    private let notesShownKey = "gs.appUpdate.notesShownFor"

    /// A user who dismissed the nudge should not see it again for a week.
    private let nudgeInterval: TimeInterval = 7 * 24 * 60 * 60

    private let defaults = UserDefaults.standard

    private init() {}

    /// The running app's marketing version ("1.0.10").
    static var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    /// Evaluates the three states against the loaded remote config. Safe to
    /// call on every launch; it is the caller's only entry point.
    func evaluate(config: RemoteAppUpdate?) {
        let current = Self.currentVersion
        let previous = defaults.string(forKey: lastSeenKey)
        // Record first so a crash inside the presentation cannot replay a
        // What's New sheet on every launch.
        defaults.set(current, forKey: lastSeenKey)

        guard let platform = config?.ios else { return }
        let storeURL = platform.url.flatMap { URL(string: $0) }
        let notes = config?.notes?.items ?? []

        // 1. Hard floor.
        if let min = platform.min, !min.isEmpty,
           Self.compare(current, min) == .orderedAscending {
            prompt = .required(storeURL: storeURL)
            return
        }

        // 2. Newer version available — dismissible, rate limited.
        if let latest = platform.latest, !latest.isEmpty,
           Self.compare(current, latest) == .orderedAscending {
            if shouldNudge(for: latest) {
                prompt = .available(version: latest, storeURL: storeURL, notes: notes)
            }
            return
        }

        // 3. The user just updated into this version. Requires a recorded
        // previous version, so a fresh install shows nothing.
        if let previous, !previous.isEmpty,
           Self.compare(previous, current) == .orderedAscending,
           !notes.isEmpty,
           notesShown(for: current) == false {
            markNotesShown(for: current)
            prompt = .whatsNew(
                version: current,
                title: config?.notes?.title ?? "What's new",
                notes: notes
            )
        }
    }

    /// True while a required update is on screen — the root view uses a
    /// full-screen cover for this state rather than a sheet, because a sheet
    /// can be swiped away.
    var isBlocking: Bool {
        if case .required = prompt { return true }
        return false
    }

    /// Dismisses whichever dismissible prompt is showing. A required update
    /// ignores this — there is nothing to dismiss to.
    func dismissCurrent() {
        switch prompt {
        case .available: dismissNudge()
        case .whatsNew: dismissNotes()
        case .required, .none: break
        }
    }

    /// Called when the user dismisses the "available" sheet. Starts the
    /// weekly clock for that version.
    func dismissNudge() {
        if case .available(let version, _, _) = prompt {
            var stamps = defaults.dictionary(forKey: nudgedKey) as? [String: String] ?? [:]
            stamps[version] = ISO8601DateFormatter().string(from: Date())
            defaults.set(stamps, forKey: nudgedKey)
        }
        prompt = nil
    }

    /// Called when the user dismisses the What's New sheet.
    func dismissNotes() { prompt = nil }

    // MARK: - Rate limiting

    private func shouldNudge(for version: String) -> Bool {
        let stamps = defaults.dictionary(forKey: nudgedKey) as? [String: String] ?? [:]
        guard let raw = stamps[version],
              let last = ISO8601DateFormatter().date(from: raw) else { return true }
        return Date().timeIntervalSince(last) >= nudgeInterval
    }

    private func notesShown(for version: String) -> Bool {
        let shown = defaults.stringArray(forKey: notesShownKey) ?? []
        return shown.contains(version)
    }

    private func markNotesShown(for version: String) {
        var shown = defaults.stringArray(forKey: notesShownKey) ?? []
        guard !shown.contains(version) else { return }
        shown.append(version)
        // Only the recent tail matters; the list is a "have we shown this"
        // check, not history.
        defaults.set(Array(shown.suffix(10)), forKey: notesShownKey)
    }

    // MARK: - Version comparison

    /// Compares dotted numeric versions component by component, tolerating
    /// different component counts ("1.1" < "1.1.1") and non-numeric junk,
    /// which sorts as zero rather than throwing the comparison out.
    ///
    /// `String.compare(options: .numeric)` was not used: it compares "1.10"
    /// against "1.9" correctly but has no notion of component count, so
    /// "1.1" and "1.1.0" do not compare equal.
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let l = lhs.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        let r = rhs.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        for i in 0..<max(l.count, r.count) {
            let a = i < l.count ? l[i] : 0
            let b = i < r.count ? r[i] : 0
            if a < b { return .orderedAscending }
            if a > b { return .orderedDescending }
        }
        return .orderedSame
    }
}

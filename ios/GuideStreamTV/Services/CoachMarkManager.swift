//
//  CoachMarkManager.swift
//  GuideStreamTV
//
//  Manages first-run coach mark tour state: which marks the user has seen,
//  which tour is active, and persistence to UserDefaults + Supabase.
//  The stored value is a flat JSON object mapping each seen key to the
//  ISO8601 timestamp it was dismissed, plus the tour-level keys
//  `home_tour_done` and `detail_tour_done`.
//

import Foundation
import SwiftUI
import Supabase

// MARK: - Coach Mark Definitions

struct CoachMark: Identifiable {
    let id: String
    let key: String
    let title: String
    let body: String
    /// Target keys this mark cuts holes around. One key = single cutout,
    /// two keys = dual cutout drawn from a single mask.
    let targetKeys: [String]
    /// `true` for the Ask FAB and the watchlist circle button — use a
    /// fully circular hole instead of a rounded rect.
    var isCircular: Bool { key == "ask" || key == "watchlist_add" }
    /// `true` when this is the last mark in its tour (card shows "Done").
    var isLastInTour: Bool { key == "genre" || key == "play_on" }

    static let homeTour: [CoachMark] = [
        CoachMark(id: "search", key: "search", title: "Find anything, fast",
                  body: "Search shows, movies, creators and podcasts across every service at once.",
                  targetKeys: ["search"]),
        CoachMark(id: "reels", key: "reels", title: "Reels",
                  body: "Swipe trailers for what is new. Tap once to start watching.",
                  targetKeys: ["reels"]),
        CoachMark(id: "sports", key: "sports", title: "Sports",
                  body: "Live games, scores and the channel carrying them. Star a team to follow it.",
                  targetKeys: ["sports"]),
        CoachMark(id: "ask", key: "ask", title: "AI Enabled Ask Stream",
                  body: "Describe what you feel like and get picks you can actually watch tonight.",
                  targetKeys: ["ask"]),
        CoachMark(id: "genre", key: "genre", title: "Browse by genre",
                  body: "Pick a genre and the rail underneath refills with titles in it.",
                  targetKeys: ["genre", "because_you_watch"]),
    ]

    static let detailTour: [CoachMark] = [
        CoachMark(id: "where_to_watch", key: "where_to_watch", title: "Pick your service",
                  body: "Tap a service to switch where this plays. The Watch button follows your choice.",
                  targetKeys: ["where_to_watch", "watch_button"]),
        CoachMark(id: "watchlist_add", key: "watchlist_add", title: "Add to watch list",
                  body: "Save it and we will notify you the moment a new episode drops.",
                  targetKeys: ["watchlist_add"]),
        CoachMark(id: "play_on", key: "play_on", title: "Send it to the TV",
                  body: "Open this on your Apple TV, Roku or Samsung without touching the remote.",
                  targetKeys: ["play_on"]),
    ]
}

// MARK: - CoachMarkManager

@MainActor
@Observable
final class CoachMarkManager {
    static let shared = CoachMarkManager()

    /// Keys the user has seen, merged with tour-done markers. Each value
    /// is an ISO8601 timestamp string.
    private(set) var seenKeys: [String: String] = [:]

    /// The currently active tour marks (home or detail). Empty when no
    /// tour is running.
    private(set) var activeTour: [CoachMark] = []

    /// Index into `activeTour` for the currently displayed mark.
    private(set) var currentIndex: Int = 0

    /// `true` when the overlay should be visible.
    private(set) var isShowing: Bool = false

    /// Measured frames for the current mark's targets, in global screen
    /// coordinates. Set by the host from anchor preferences.
    private(set) var measuredRects: [String: CGRect] = [:]

    /// Scroll request for the hosting view to act on. When non-nil, the
    /// host should scroll to this id, wait 350ms, then clear it so anchors
    /// can be re-measured on the settled layout.
    var scrollRequest: String? = nil

    /// Set to true by the host after it has completed the scroll + settle
    /// delay, signalling that measuredRects are now valid for this mark.
    var scrollSettled: Bool = false

    /// `true` while the genre mark is active so HomeView can bind
    /// `genreHighlighted` to it.
    var genreHighlightActive: Bool = false

    private let defaults = UserDefaults.standard
    private let storageKey = "gs.coachMarks"

    /// Bump to force a one-time clear of stored coach mark state on every
    /// install. Version 2 clears keys written by the broken auto-advance
    /// path, which persisted marks the user never actually saw.
    private let coachMarkResetVersion = 2
    private let resetVersionKey = "gs.coachMarkResetVersion"
    /// Persisted so a launch where the user never signs in does not lose the
    /// pending authoritative remote clear.
    private let pendingRemoteResetKey = "gs.coachMarkPendingRemoteReset"

    private init() {
        applyOneTimeResetIfNeeded()
        loadFromUserDefaults()
    }

    /// Runs at most once per install per `coachMarkResetVersion`. Clears the
    /// local store before `loadFromUserDefaults` can populate `seenKeys`, and
    /// flags the remote copy for an authoritative clear on next hydrate.
    private func applyOneTimeResetIfNeeded() {
        let stored = defaults.integer(forKey: resetVersionKey)
        guard stored < coachMarkResetVersion else { return }
        defaults.removeObject(forKey: storageKey)
        seenKeys = [:]
        defaults.set(coachMarkResetVersion, forKey: resetVersionKey)
        defaults.set(true, forKey: pendingRemoteResetKey)
    }

    // MARK: - Local persistence

    private func loadFromUserDefaults() {
        if let data = defaults.data(forKey: storageKey),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            seenKeys = dict
        }
    }

    private func saveToUserDefaults() {
        if let data = try? JSONEncoder().encode(seenKeys) {
            defaults.set(data, forKey: storageKey)
        }
    }

    // MARK: - Tour gating

    var homeTourDone: Bool { seenKeys["home_tour_done"] != nil }
    var detailTourDone: Bool { seenKeys["detail_tour_done"] != nil }

    /// Returns true if the home tour should fire now.
    func shouldStartHomeTour(isSignedIn: Bool, hasCompletedOnboarding: Bool,
                             homeContentReady: Bool, tabBarVisible: Bool) -> Bool {
        guard isSignedIn, hasCompletedOnboarding, homeContentReady,
              tabBarVisible, !homeTourDone, !isShowing else { return false }
        let unseen = CoachMark.homeTour.filter { seenKeys[$0.key] == nil }
        return !unseen.isEmpty
    }

    /// Returns true if the detail tour should fire now.
    func shouldStartDetailTour(sourcesResolved: Bool) -> Bool {
        guard !detailTourDone, !isShowing, sourcesResolved else { return false }
        let unseen = CoachMark.detailTour.filter { seenKeys[$0.key] == nil }
        return !unseen.isEmpty
    }

    // MARK: - Tour control

    func startHomeTour() {
        let unseen = CoachMark.homeTour.filter { seenKeys[$0.key] == nil }
        guard !unseen.isEmpty else { return }
        activeTour = unseen
        currentIndex = 0
        measuredRects = [:]
        scrollSettled = false
        isShowing = true
        handleScrollForCurrentMark()
    }

    func startDetailTour() {
        let unseen = CoachMark.detailTour.filter { seenKeys[$0.key] == nil }
        guard !unseen.isEmpty else { return }
        activeTour = unseen
        currentIndex = 0
        measuredRects = [:]
        scrollSettled = false
        isShowing = true
        handleScrollForCurrentMark()
    }

    var currentMark: CoachMark? {
        guard currentIndex >= 0, currentIndex < activeTour.count else { return nil }
        return activeTour[currentIndex]
    }

    /// Advances to the next mark. If this was the last mark, marks the
    /// tour as done and dismisses.
    func advance() {
        guard let mark = currentMark else { return }
        markAsSeen(mark.key)

        if currentIndex + 1 >= activeTour.count {
            // Tour complete — mark the tour-level done key
            let isHomeTour = activeTour.contains(where: { $0.key == "genre" })
            let isDetailTour = activeTour.contains(where: { $0.key == "play_on" })
            if isHomeTour { markAsSeen("home_tour_done") }
            if isDetailTour { markAsSeen("detail_tour_done") }
            genreHighlightActive = false
            dismissTour()
        } else {
            currentIndex += 1
            measuredRects = [:]
            scrollSettled = false
            genreHighlightActive = false
            handleScrollForCurrentMark()
        }
    }

    /// Skips the entire current tour, marking all remaining keys as seen.
    func skipTour() {
        let remaining = activeTour[currentIndex...]
        for mark in remaining {
            markAsSeen(mark.key)
        }
        let isHomeTour = activeTour.contains(where: { $0.key == "genre" })
        let isDetailTour = activeTour.contains(where: { $0.key == "play_on" })
        if isHomeTour { markAsSeen("home_tour_done") }
        if isDetailTour { markAsSeen("detail_tour_done") }
        genreHighlightActive = false
        dismissTour()
    }

    /// Called when the app backgrounds mid-tour — persists the current
    /// mark as seen and dismisses so the next unseen mark resumes on return.
    func handleBackground() {
        if isShowing {
            if let mark = currentMark {
                markAsSeen(mark.key)
            }
            genreHighlightActive = false
            dismissTour()
        }
    }

    private func dismissTour() {
        isShowing = false
        activeTour = []
        currentIndex = 0
        measuredRects = [:]
        scrollRequest = nil
        scrollSettled = false
    }

    /// Moves past the current mark *without* persisting it, so a mark whose
    /// anchor could not be measured is retried on a later session instead of
    /// being burned. When it is the last mark, the tour is dismissed without
    /// writing either the mark key or the tour-level done key.
    func skipUnmeasurableMark() {
        guard currentMark != nil else { return }
        if currentIndex + 1 >= activeTour.count {
            genreHighlightActive = false
            dismissTour()
        } else {
            currentIndex += 1
            measuredRects = [:]
            scrollSettled = false
            genreHighlightActive = false
            handleScrollForCurrentMark()
        }
    }

    /// If a target's measured frame is zero or missing, skip that single
    /// mark and advance rather than drawing a cutout at the origin.
    func currentMarkHasValidFrames() -> Bool {
        guard let mark = currentMark else { return false }
        for key in mark.targetKeys {
            guard let rect = measuredRects[key], !rect.isEmpty else {
                return false
            }
        }
        return true
    }

    func setMeasuredRects(_ rects: [String: CGRect]) {
        measuredRects = rects
    }

    func clearScrollRequest() {
        scrollRequest = nil
    }

    /// Called by the host after it has completed the scroll + 350ms settle
    /// delay, signalling that measuredRects are now valid for this mark.
    func markScrollSettled() {
        scrollSettled = true
        scrollRequest = nil
    }

    // MARK: - Scroll coordination

    private func handleScrollForCurrentMark() {
        guard let mark = currentMark else { return }
        genreHighlightActive = (mark.key == "genre")
        switch mark.key {
        case "genre":
            scrollRequest = "browseByGenre"
        case "where_to_watch":
            scrollRequest = "cmWhereToWatch"
        case "play_on":
            scrollRequest = "cmSynopsis"
        default:
            scrollSettled = true // no scroll needed
        }
    }

    // MARK: - Seen-key persistence

    func markAsSeen(_ key: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        seenKeys[key] = ts
        saveToUserDefaults()
        pushToSupabase()
    }

    // MARK: - Supabase sync

    /// Read-merge-write: fetch the current `coach_marks_seen` from the
    /// users row, union with local, write the merged object back. Mirrors
    /// the shape of `setUserTimezone` in AuthViewModel.
    func pushToSupabase() {
        guard let userId = AuthViewModel.shared.currentUser?.id.uuidString else { return }
        let localCopy = seenKeys
        Task {
            do {
                let rows: [CoachMarksRow] = try await SupabaseManager.shared.client
                    .from("users")
                    .select("coach_marks_seen")
                    .eq("id", value: userId)
                    .limit(1)
                    .execute()
                    .value
                let remote = rows.first?.coach_marks_seen ?? [:]
                var merged = remote
                for (k, v) in localCopy {
                    if merged[k] == nil { merged[k] = v }
                }
                try await SupabaseManager.shared.client
                    .from("users")
                    .update(["coach_marks_seen": merged])
                    .eq("id", value: userId)
                    .execute()
                await MainActor.run {
                    self.seenKeys = merged
                    self.saveToUserDefaults()
                }
            } catch {
                #if DEBUG
                print("[CoachMark] Supabase push failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    /// Hydrate on sign-in / session restore: read `coach_marks_seen`,
    /// union with local storage, write the union back up, store locally.
    func hydrateFromSupabase(userId: String) async {
        // One-time reset: overwrite the remote copy authoritatively instead of
        // merging, otherwise the stale remote keys would be pulled straight
        // back down and the local clear undone.
        if defaults.bool(forKey: pendingRemoteResetKey) {
            do {
                let empty: [String: String] = [:]
                try await SupabaseManager.shared.client
                    .from("users")
                    .update(["coach_marks_seen": empty])
                    .eq("id", value: userId)
                    .execute()
                defaults.set(false, forKey: pendingRemoteResetKey)
            } catch {
                #if DEBUG
                print("[CoachMark] remote reset failed: \(error.localizedDescription)")
                #endif
            }
            return
        }
        do {
            let rows: [CoachMarksRow] = try await SupabaseManager.shared.client
                .from("users")
                .select("coach_marks_seen")
                .eq("id", value: userId)
                .limit(1)
                .execute()
                .value
            let remote = rows.first?.coach_marks_seen ?? [:]
            var merged = seenKeys
            for (k, v) in remote {
                merged[k] = v
            }
            seenKeys = merged
            saveToUserDefaults()
            try await SupabaseManager.shared.client
                .from("users")
                .update(["coach_marks_seen": merged])
                .eq("id", value: userId)
                .execute()
        } catch {
            #if DEBUG
            print("[CoachMark] hydrateFromSupabase failed: \(error.localizedDescription)")
            #endif
        }
    }

    func clearForSignOut() {
        dismissTour()
    }
}

// MARK: - Supabase decode helper

private struct CoachMarksRow: Codable {
    let coach_marks_seen: [String: String]?
}

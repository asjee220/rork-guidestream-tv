//
//  ProfileStatsService.swift
//  GuideStreamTV
//
//  Aggregates the headline stats shown on the Profile screen pills:
//  - servicesCount  → live from `AuthViewModel.selectedServices`
//  - showsCount     → distinct `title_id`s from `watch_intent_events` — scoped
//                     by user_id when authenticated, device_id for guests
//  - hoursWatched   → actual watch duration summed from `metadata->>
//                     'watch_duration_seconds'` across engagement events.
//                     Falls back to an estimated 5-min-per-event average
//                     for legacy rows that lack duration metadata.
//  - devicesCount   → rows in `device_sessions` for the current user
//
//  Refreshes reactively via `Notification.Name.ProfileStatsNeedsRefresh` so
//  the pills update within ~1 s of a new engagement event being logged.
//

import Foundation
import Supabase

extension Notification.Name {
    /// Posted by `WatchIntentLogger` after every successful engagement insert.
    /// `ProfileStatsService` listens and refreshes on a short debounce.
    static let ProfileStatsNeedsRefresh = Notification.Name("ProfileStatsNeedsRefresh")
}

@MainActor
@Observable
final class ProfileStatsService {
    static let shared = ProfileStatsService()

    /// Distinct shows the user has tapped, opened, or watched a trailer for.
    var showsCount: Int = UserDefaults.standard.integer(forKey: "gs.stats.showsCount")
    /// Total hours of content actually consumed (sum of watch_duration_seconds
    /// from metadata). Falls back to an estimate for legacy rows without duration.
    var hoursWatched: Double = UserDefaults.standard.double(forKey: "gs.stats.hoursWatched")
    /// Number of devices the user is signed in on (1 for guests / offline).
    var devicesCount: Int = max(1, UserDefaults.standard.integer(forKey: "gs.stats.devicesCount"))
    var isRefreshing: Bool = false
    var lastError: String?

    private var refreshTask: Task<Void, Never>?

    private init() {
        // Listen for engagement inserts so stats stay live without a manual
        // pull-to-refresh. Debounced to avoid hammering Supabase on rapid
        // actions (e.g. swiping through reels quickly).
        NotificationCenter.default.addObserver(
            forName: .ProfileStatsNeedsRefresh,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleDebouncedRefresh()
        }
    }

    /// Clears all cached stats and removes the UserDefaults keys. Called from
    /// `AuthViewModel.signOut()` so the next user sees fresh stats.
    func clearCache() {
        refreshTask?.cancel()
        self.showsCount = 0
        self.hoursWatched = 0
        self.devicesCount = 1
        UserDefaults.standard.removeObject(forKey: "gs.stats.showsCount")
        UserDefaults.standard.removeObject(forKey: "gs.stats.hoursWatched")
        UserDefaults.standard.removeObject(forKey: "gs.stats.devicesCount")
    }

    /// Live count, no fetch required.
    var servicesCount: Int {
        AuthViewModel.shared.selectedServices.count
    }

    /// Hits Supabase to refresh shows/hours/devices in parallel. Persists the
    /// last good values so the UI never flashes back to zero on the next
    /// cold launch.
    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        async let shows: () = refreshEngagement()
        async let devices: () = refreshDevices()
        _ = await (shows, devices)
    }

    // MARK: - Private

    /// Debounced refresh — waits 1.5 s after the last notification before
    /// actually hitting Supabase. Cancels any pending debounce when a new
    /// notification arrives, so rapid-fire events (swiping reels) only
    /// trigger one refresh after the user pauses.
    private func scheduleDebouncedRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func refreshEngagement() async {
        let deviceId = DeviceIdentity.shared.deviceId
        let auth = AuthViewModel.shared
        let userId = auth.currentUser?.id.uuidString
        let isAuthenticated = auth.isAuthenticated

        do {
            // Scoped query: user_id for authenticated users (captures all
            // their devices), device_id for guests.
            // `.eq()` must be called on the PostgrestFilterBuilder (after
            // `.select()`) BEFORE `.limit()` which returns a TransformBuilder.
            let baseQuery = SupabaseManager.shared.client
                .from("watch_intent_events")
                .select("title_id, event_type, metadata")

            let filteredQuery: PostgrestFilterBuilder
            if isAuthenticated, let uid = userId {
                filteredQuery = baseQuery.eq("user_id", value: uid)
            } else {
                filteredQuery = baseQuery.eq("device_id", value: deviceId)
            }

            let rows: [ProfileEventRow] = try await filteredQuery.limit(2000).execute().value

            let engagementTypes: Set<String> = [
                IntentEventType.cardTapped.rawValue,
                IntentEventType.episodeDetailViewed.rawValue,
                IntentEventType.continueWatching.rawValue,
                IntentEventType.trailerWatched.rawValue,
                IntentEventType.playOnDeviceChosen.rawValue,
                IntentEventType.deeplinkFired.rawValue,
                IntentEventType.trailerViewed.rawValue
            ]

            let engagementRows = rows.filter { engagementTypes.contains($0.event_type ?? "") }
            let uniqueTitleIds = Set(engagementRows.compactMap { $0.title_id }.filter { !$0.isEmpty })

            // Sum real watch durations from metadata. For legacy rows without
            // watch_duration_seconds, fall back to 5-minute estimates.
            var totalSeconds: Double = 0
            for row in engagementRows {
                if let meta = row.metadata,
                   case .object(let dict) = meta,
                   let durationJSON = dict["watch_duration_seconds"] {
                    switch durationJSON {
                    case .double(let d):
                        totalSeconds += d
                    case .integer(let i):
                        totalSeconds += Double(i)
                    case .string(let s):
                        totalSeconds += Double(s) ?? 0
                    default:
                        totalSeconds += 300 // 5 min fallback for legacy rows
                    }
                } else {
                    totalSeconds += 300 // 5 min fallback for legacy rows
                }
            }

            self.showsCount = uniqueTitleIds.count
            self.hoursWatched = (totalSeconds / 3600.0).roundedToDecimals(1)

            UserDefaults.standard.set(showsCount, forKey: "gs.stats.showsCount")
            UserDefaults.standard.set(hoursWatched, forKey: "gs.stats.hoursWatched")
            lastError = nil
            _ = userId // silence unused warning when guard-let shadows it
        } catch {
            lastError = error.localizedDescription
            print("[ProfileStats] engagement refresh failed: \(error.localizedDescription)")
        }
    }

    private func refreshDevices() async {
        guard let uid = AuthViewModel.shared.currentUser?.id.uuidString else {
            self.devicesCount = 1
            UserDefaults.standard.set(1, forKey: "gs.stats.devicesCount")
            return
        }
        do {
            let rows: [DeviceCountRow] = try await SupabaseManager.shared.client
                .from("device_sessions")
                .select("device_id")
                .eq("user_id", value: uid)
                .execute()
                .value
            let count = max(1, rows.count)
            self.devicesCount = count
            UserDefaults.standard.set(count, forKey: "gs.stats.devicesCount")
        } catch {
            lastError = error.localizedDescription
            print("[ProfileStats] devices refresh failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Decoding helpers

nonisolated struct ProfileEventRow: Decodable, Sendable {
    let title_id: String?
    let event_type: String?
    let metadata: AnyJSON?
}

nonisolated struct DeviceCountRow: Decodable, Sendable {
    let device_id: String
}

// MARK: - Math

nonisolated private extension Double {
    func roundedToDecimals(_ places: Int) -> Double {
        let multiplier = pow(10.0, Double(places))
        return (self * multiplier).rounded() / multiplier
    }
}

//
//  ProfileStatsService.swift
//  GuideStreamTV
//
//  Aggregates the headline stats shown on the Profile screen pills:
//  - servicesCount  → live from `AuthViewModel.selectedServices`
//  - showsCount     → server-computed via the `get_profile_stats` Postgres
//                     function — scoped by user_id when authenticated,
//                     device_id for guests
//  - hoursWatched   → server-computed by the same RPC (numeric, one decimal)
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
    /// Total hours of content actually consumed, computed server-side by the
    /// `get_profile_stats` RPC (numeric, one decimal).
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
        let auth = AuthViewModel.shared

        // The `get_profile_stats` function declares both parameters with null
        // defaults, so only the key relevant to the current auth state is sent.
        let params: [String: String]
        if auth.isAuthenticated, let uid = auth.currentUser?.id.uuidString {
            params = ["p_user_id": uid]
        } else {
            params = ["p_device_id": DeviceIdentity.shared.deviceId]
        }

        do {
            let rows: [ProfileStatsRow] = try await SupabaseManager.shared.client
                .rpc("get_profile_stats", params: params)
                .execute()
                .value

            guard let stats = rows.first else {
                lastError = "get_profile_stats returned no rows"
                print("[ProfileStats] engagement refresh failed: empty RPC result")
                return
            }

            self.showsCount = stats.shows_count
            self.hoursWatched = stats.hours_watched

            UserDefaults.standard.set(showsCount, forKey: "gs.stats.showsCount")
            UserDefaults.standard.set(hoursWatched, forKey: "gs.stats.hoursWatched")
            lastError = nil
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

/// Single row returned by the `get_profile_stats` Postgres function.
nonisolated private struct ProfileStatsRow: Decodable, Sendable {
    let shows_count: Int
    let hours_watched: Double
}

nonisolated struct DeviceCountRow: Decodable, Sendable {
    let device_id: String
}

//
//  ProfileStatsService.swift
//  GuideStreamTV
//
//  Aggregates the headline stats shown on the Profile screen pills:
//  - servicesCount  → live from `AuthViewModel.selectedServices`
//  - showsCount     → distinct `title_id`s from `watch_intent_events` for this
//                     device (and user, if signed in)
//  - hoursWatched   → engagement-event count × ~9 min average
//  - devicesCount   → rows in `device_sessions` for the current user
//
//  All Supabase reads silently fail to cached / zero values so the Profile UI
//  always renders something sensible — even on a fresh install or offline.
//

import Foundation
import Supabase

@MainActor
@Observable
final class ProfileStatsService {
    static let shared = ProfileStatsService()

    /// Distinct shows the user has tapped, opened, or watched a trailer for.
    var showsCount: Int = UserDefaults.standard.integer(forKey: "gs.stats.showsCount")
    /// Rough total hours the user has spent in the app interacting with media.
    var hoursWatched: Double = UserDefaults.standard.double(forKey: "gs.stats.hoursWatched")
    /// Number of devices the user is signed in on (1 for guests / offline).
    var devicesCount: Int = max(1, UserDefaults.standard.integer(forKey: "gs.stats.devicesCount"))
    var isRefreshing: Bool = false
    var lastError: String?

    private init() {}

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

    private func refreshEngagement() async {
        let deviceId = DeviceIdentity.shared.deviceId
        let userId = AuthViewModel.shared.currentUser?.id.uuidString

        do {
            let query = SupabaseManager.shared.client
                .from("watch_intent_events")
                .select("title_id, event_type")
                .eq("device_id", value: deviceId)
                .limit(1000)
            let rows: [ProfileEventRow] = try await query.execute().value

            let engagementTypes: Set<String> = [
                IntentEventType.cardTapped.rawValue,
                IntentEventType.episodeDetailViewed.rawValue,
                IntentEventType.continueWatching.rawValue,
                IntentEventType.trailerWatched.rawValue,
                IntentEventType.playOnDeviceChosen.rawValue,
                IntentEventType.deeplinkFired.rawValue,
                IntentEventType.trailerViewed.rawValue
            ]
            let engagementCount = rows.filter { engagementTypes.contains($0.event_type ?? "") }.count
            let uniqueTitleIds = Set(rows.compactMap { $0.title_id }.filter { !$0.isEmpty })

            self.showsCount = uniqueTitleIds.count
            // ~9 minute average per engagement event → quick approximation
            // until we wire real watch-duration telemetry.
            self.hoursWatched = (Double(engagementCount) * 0.15)
                .roundedToDecimals(1)

            UserDefaults.standard.set(showsCount, forKey: "gs.stats.showsCount")
            UserDefaults.standard.set(hoursWatched, forKey: "gs.stats.hoursWatched")
            lastError = nil
            _ = userId // silence unused warning — query is device-scoped today
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

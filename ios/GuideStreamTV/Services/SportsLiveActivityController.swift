//
//  SportsLiveActivityController.swift
//  GuideStreamTV
//
//  Owns the live-scores Live Activity: starts it when the user tracks a game
//  from the sports watch sheet, ends it on stop or switch, and mirrors the
//  activity's APNs push token into the `live_activities` Supabase table so
//  the backend can push score updates while the app is closed.
//
//  The table client is WRITE-ONLY — upsert on conflict activity_id, never
//  SELECT. Guests write user_id null.
//

import ActivityKit
import Foundation
import Supabase

@MainActor
@Observable
final class SportsLiveActivityController {
    static let shared = SportsLiveActivityController()

    /// The game id of the currently tracked Live Activity; nil when idle.
    private(set) var trackedGameId: String?

    /// Human-readable error from the most recent start attempt, if any.
    private(set) var lastStartError: String?

    /// Push-token observers keyed by activity id. The observer does not
    /// survive process death — `reconcile()` re-attaches them on launch.
    private var tokenObservers: [String: Task<Void, Never>] = [:]

    private init() {}

    /// Whether Live Activities can be started right now.
    var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // MARK: - Start

    /// Starts a Live Activity for `game`. Ends every running activity first
    /// (stamping ended_at on their rows), awaits the activity's FIRST push
    /// token — a placeholder token is never written — and only then inserts
    /// the row. A throwing request leaves `trackedGameId` nil (idle) and
    /// publishes a user-facing error message.
    func start(game: SportsGame, broadcast: String) async {
        await endRunningActivities()
        lastStartError = nil

        let homeScore = Int(game.home.score) ?? 0
        let awayScore = Int(game.away.score) ?? 0
        let attributes = SportsActivityAttributes(
            gameId: game.id,
            sport: game.sport,
            leagueShort: game.leagueShort,
            homeAbbr: game.home.abbreviation,
            awayAbbr: game.away.abbreviation,
            homeShortName: game.home.shortName,
            awayShortName: game.away.shortName,
            homeHex: game.home.primaryHex ?? "#F5821F",
            awayHex: game.away.primaryHex ?? "#F5821F",
            broadcast: broadcast
        )
        let initialState = SportsActivityAttributes.ContentState(
            homeScore: homeScore,
            awayScore: awayScore,
            statusDetail: game.statusDetail,
            state: game.state.rawValue
        )

        let activity: Activity<SportsActivityAttributes>
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: initialState, staleDate: nil),
                pushType: .token
            )
        } catch {
            let message = "[LiveActivity] request failed: \(error.localizedDescription)"
            print(message)
            lastStartError = "Live score tracking is unavailable. Make sure Live Activities are turned on in Settings > Face ID & Passcode."
            trackedGameId = nil
            return
        }

        trackedGameId = game.id

        var tokenHex: String?
        for await data in activity.pushTokenUpdates {
            tokenHex = Self.hexEncoded(data)
            break
        }
        guard let tokenHex else { return }
        attachTokenObserver(activity)

        do {
            try await insertRow(
                activityId: activity.id,
                gameId: game.id,
                tokenHex: tokenHex,
                homeScore: homeScore,
                awayScore: awayScore,
                statusDetail: game.statusDetail,
                stateValue: game.state.rawValue
            )
        } catch {
            print("[LiveActivity] insert failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Stop

    /// Ends the current activity and stamps ended_at on its row.
    func stop() async {
        await endRunningActivities()
        trackedGameId = nil
        lastStartError = nil
    }

    /// Clears the user-facing error so the UI can dismiss it.
    func clearLastError() {
        lastStartError = nil
    }

    // MARK: - Reconcile

    /// Re-attaches push-token observers to still-running activities after a
    /// process relaunch (observers do not survive process death) and restores
    /// `trackedGameId`; clears it when nothing is running.
    func reconcile() async {
        let running = runningActivities()
        for activity in running {
            attachTokenObserver(activity)
        }
        trackedGameId = running.first?.attributes.gameId
    }

    // MARK: - Private

    private func runningActivities() -> [Activity<SportsActivityAttributes>] {
        Activity<SportsActivityAttributes>.activities
            .filter { $0.activityState == .active || $0.activityState == .stale }
    }

    /// Ends every active/stale activity immediately and stamps ended_at on
    /// each row before any new one is requested. User-dismissed activities
    /// are left alone.
    private func endRunningActivities() async {
        for activity in runningActivities() {
            tokenObservers.removeValue(forKey: activity.id)?.cancel()
            await activity.end(dismissalPolicy: .immediate)
            await stampEnded(activityId: activity.id)
        }
    }

    /// Keeps consuming token updates so rotations UPDATE push_token in place.
    private func attachTokenObserver(_ activity: Activity<SportsActivityAttributes>) {
        let activityId = activity.id
        guard tokenObservers[activityId] == nil else { return }
        tokenObservers[activityId] = Task.detached { [weak self] in
            for await data in activity.pushTokenUpdates {
                await self?.updatePushToken(
                    activityId: activityId,
                    tokenHex: Self.hexEncoded(data)
                )
            }
        }
    }

    private nonisolated static func hexEncoded(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private func insertRow(
        activityId: String,
        gameId: String,
        tokenHex: String,
        homeScore: Int,
        awayScore: Int,
        statusDetail: String,
        stateValue: String
    ) async throws {
        var payload: [String: AnyJSON] = [
            "activity_id": .string(activityId),
            "game_id": .string(gameId),
            "push_token": .string(tokenHex),
            "device_id": .string(DeviceIdentity.shared.deviceId),
            "platform": .string("ios"),
            "last_state": .string(stateValue),
            "last_home_score": .integer(homeScore),
            "last_away_score": .integer(awayScore),
            "started_at": .string(Date().ISO8601Format()),
            "updated_at": .string(Date().ISO8601Format())
        ]
        if !statusDetail.isEmpty {
            payload["last_status_detail"] = .string(statusDetail)
        }
        // Guests write user_id null.
        if let userId = AuthViewModel.shared.currentUser?.id {
            payload["user_id"] = .string(userId.uuidString)
        }
        try await SupabaseManager.shared.client
            .from("live_activities")
            .upsert(payload, onConflict: "activity_id")
            .execute()
    }

    private func updatePushToken(activityId: String, tokenHex: String) async {
        let payload: [String: AnyJSON] = [
            "activity_id": .string(activityId),
            "push_token": .string(tokenHex),
            "updated_at": .string(Date().ISO8601Format())
        ]
        do {
            try await SupabaseManager.shared.client
                .from("live_activities")
                .upsert(payload, onConflict: "activity_id")
                .execute()
        } catch {
            print("[LiveActivity] token rotation update failed: \(error.localizedDescription)")
        }
    }

    private func stampEnded(activityId: String) async {
        let payload: [String: AnyJSON] = [
            "activity_id": .string(activityId),
            "ended_at": .string(Date().ISO8601Format()),
            "updated_at": .string(Date().ISO8601Format())
        ]
        do {
            try await SupabaseManager.shared.client
                .from("live_activities")
                .upsert(payload, onConflict: "activity_id")
                .execute()
        } catch {
            print("[LiveActivity] ended_at stamp failed: \(error.localizedDescription)")
        }
    }
}

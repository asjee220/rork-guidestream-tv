//
//  DeviceSessionService.swift
//  GuideStreamTV
//

import Foundation
import UIKit
import Supabase

/// Upserts a single row per install into `device_sessions` — the guest
/// "profile" equivalent. Even a user who taps through onboarding without
/// signing in produces exactly one row that updates on launch, sign-in/out,
/// onboarding completion, and any service / notification preference change.
///
/// Suggested Supabase schema:
/// ```sql
/// create table device_sessions (
///   device_id text primary key,
///   user_id uuid,
///   is_guest boolean,
///   is_authenticated boolean,
///   email text,
///   services text[],
///   service_count int,
///   notify_push boolean,
///   notify_sms boolean,
///   onboarding_complete boolean,
///   session_count int,
///   app_version text,
///   build_number text,
///   os_version text,
///   device_model text,
///   first_seen_at timestamptz default now(),
///   last_seen_at timestamptz default now()
/// );
///
/// alter table device_sessions enable row level security;
/// create policy "Anyone can upsert their device row"
///   on device_sessions for all
///   using (true) with check (true);
/// ```
///
/// The upsert is keyed on `device_id` so the row is created on first launch
/// and overwritten on every subsequent call. If the live table is missing any
/// of the optional columns the logger automatically retries with the offending
/// keys dropped, so existing schemas keep working.
@MainActor
final class DeviceSessionService {
    static let shared = DeviceSessionService()

    /// Cached hardware identifier (e.g. "iPhone16,2") computed once at init.
    /// Falls back to the high-level model name when uname returns empty.
    private let deviceModel: String

    private init() {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machineMirror = Mirror(reflecting: sysinfo.machine)
        let identifier = machineMirror.children.reduce("") { partial, element in
            guard let value = element.value as? Int8, value != 0 else { return partial }
            return partial + String(UnicodeScalar(UInt8(value)))
        }
        self.deviceModel = identifier.isEmpty ? UIDevice.current.model : identifier
    }

    /// Most recent error message from a device_sessions upsert. `nil` when
    /// the last attempt succeeded.
    private(set) var lastError: String?
    /// When the most recent successful upsert completed.
    private(set) var lastSuccessAt: Date?
    /// When the most recent attempt (success or failure) was made.
    private(set) var lastAttemptAt: Date?
    /// Total upserts since launch.
    private(set) var totalUpserts: Int = 0
    /// Successful upserts since launch.
    private(set) var totalSuccesses: Int = 0
    /// Reason string from the most recent upsert call ("session_started",
    /// "onboarding_completed", etc.). Useful in diagnostics so the user can
    /// see which trigger fired last.
    private(set) var lastReason: String?

    /// Per-install session counter. Increments once per cold launch via
    /// `incrementSessionAndUpsert()`.
    private let sessionCountKey = "gs.sessionCount"
    var sessionCount: Int {
        UserDefaults.standard.integer(forKey: sessionCountKey)
    }

    /// Bump the session counter and upsert. Called once per cold launch from
    /// `ContentView.task`.
    func incrementSessionAndUpsert() {
        let next = sessionCount + 1
        UserDefaults.standard.set(next, forKey: sessionCountKey)
        upsert(reason: "session_started")
    }

    /// Fire-and-forget upsert. Reason is logged to the console for tracing
    /// and surfaced in the diagnostics screen.
    func upsert(reason: String) {
        let payload = makePayload()
        totalUpserts += 1
        lastAttemptAt = Date()
        lastReason = reason

        Task { [weak self] in
            guard let self else { return }
            await self.performUpsert(payload: payload, attempt: 0, reason: reason)
        }
    }

    /// Manual fire from the diagnostics screen — awaits the result and
    /// returns the error string (if any) so the UI can render it inline.
    func upsertNowReturningError(reason: String = "diagnostic") async -> String? {
        let payload = makePayload()
        totalUpserts += 1
        lastAttemptAt = Date()
        lastReason = reason
        do {
            try await SupabaseManager.shared.client
                .from("device_sessions")
                .upsert(payload, onConflict: "device_id")
                .execute()
            recordSuccess()
            return nil
        } catch {
            let message = Self.describe(error)
            if let trimmed = Self.dropMissingColumns(from: payload, error: message) {
                do {
                    try await SupabaseManager.shared.client
                        .from("device_sessions")
                        .upsert(trimmed, onConflict: "device_id")
                        .execute()
                    recordSuccess()
                    return nil
                } catch {
                    let retryMsg = Self.describe(error)
                    recordError(message: retryMsg)
                    return retryMsg
                }
            }
            recordError(message: message)
            return message
        }
    }

    // MARK: - Private

    private func performUpsert(
        payload: [String: AnyJSON],
        attempt: Int,
        reason: String
    ) async {
        do {
            try await SupabaseManager.shared.client
                .from("device_sessions")
                .upsert(payload, onConflict: "device_id")
                .execute()
            recordSuccess()
            print("[DeviceSession] upsert ok (\(reason))")
        } catch {
            let message = Self.describe(error)
            if attempt < 1, let trimmed = Self.dropMissingColumns(from: payload, error: message) {
                await performUpsert(payload: trimmed, attempt: attempt + 1, reason: reason)
                return
            }
            recordError(message: "\(reason): \(message)")
        }
    }

    private func recordSuccess() {
        totalSuccesses += 1
        lastSuccessAt = Date()
        lastError = nil
    }

    private func recordError(message: String) {
        print("[DeviceSession ERROR] \(message)")
        lastError = message
    }

    private func makePayload() -> [String: AnyJSON] {
        let auth = AuthViewModel.shared
        let userId = auth.currentUser?.id.uuidString
        let isAuth = userId != nil
        let nowString = Date().ISO8601Format()

        var payload: [String: AnyJSON] = [
            "device_id": .string(DeviceIdentity.shared.deviceId),
            "is_guest": .bool(auth.isGuest && !isAuth),
            "is_authenticated": .bool(isAuth),
            "services": .array(Array(auth.selectedServices).map { .string($0) }),
            "service_count": .integer(auth.selectedServices.count),
            "notify_push": .bool(auth.notifyPushEnabled),
            "notify_sms": .bool(auth.notifySMSEnabled),
            "notify_new_episodes": .bool(auth.notifyNewEpisodesEnabled),
            "notify_watchlist": .bool(auth.notifyWatchlistEnabled),
            "notify_live": .bool(auth.notifyLiveEnabled),
            "notify_sports": .bool(auth.notifySportsEnabled),
            "notify_movie_releases": .bool(auth.notifyMovieReleasesEnabled),
            "onboarding_complete": .bool(auth.hasCompletedOnboarding),
            "session_count": .integer(sessionCount),
            "last_seen_at": .string(nowString),
            "os_version": .string(UIDevice.current.systemVersion),
            "device_model": .string(deviceModel)
        ]
        if let userId { payload["user_id"] = .string(userId) }
        if let email = auth.currentUser?.email, !email.isEmpty {
            payload["email"] = .string(email)
        }
        if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            payload["app_version"] = .string(appVersion)
        }
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            payload["build_number"] = .string(build)
        }
        return payload
    }

    // MARK: - Helpers

    /// Drop any payload keys that appear in a column-not-found Postgres
    /// error so a retry can succeed with the columns the table *does* have.
    /// `device_id` is never dropped — it's the conflict key.
    nonisolated private static func dropMissingColumns(
        from payload: [String: AnyJSON],
        error: String
    ) -> [String: AnyJSON]? {
        let lowered = error.lowercased()
        guard lowered.contains("column")
            || lowered.contains("schema")
            || lowered.contains("could not find") else { return nil }
        var trimmed = payload
        var didDrop = false
        for key in Array(payload.keys) where key != "device_id" {
            if lowered.contains(key.lowercased()) {
                trimmed.removeValue(forKey: key)
                didDrop = true
            }
        }
        return didDrop ? trimmed : nil
    }

    nonisolated private static func describe(_ error: Error) -> String {
        let ns = error as NSError
        var parts: [String] = [ns.localizedDescription]
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error {
            parts.append("underlying: \((underlying as NSError).localizedDescription)")
        }
        for key in ["message", "hint", "details", "code"] {
            if let value = ns.userInfo[key] as? String, !value.isEmpty {
                parts.append("\(key)=\(value)")
            }
        }
        return parts.joined(separator: " | ")
    }
}

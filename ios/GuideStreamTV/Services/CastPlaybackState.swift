//
//  CastPlaybackState.swift
//  GuideStreamTV
//
//  Global, observable record of the currently-active cast session — what's
//  playing, on which TV, and on which streaming app. Drives the persistent
//  "Playing on [Device]" pill that appears at the top of the home feed
//  after a successful cast handoff and stays visible until the user
//  dismisses it or starts a new playback.
//

import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class CastPlaybackState {
    static let shared = CastPlaybackState()

    /// Most recent successful cast session. `nil` when no playback is active
    /// (initial app launch, after user taps Stop, or after the session
    /// auto-expires).
    private(set) var current: ActiveSession?

    /// Cancelable auto-expire task — clears `current` after an hour of
    /// inactivity so a stale session doesn't linger forever.
    @ObservationIgnored private var expireTask: Task<Void, Never>?

    private init() {}

    struct ActiveSession: Equatable, Identifiable {
        let id: String
        let title: String
        let platform: String
        let deviceName: String
        let deviceKind: TVDeviceKind
        let host: String?
        let port: UInt16?
        let startedAt: Date

        var canSendKeypress: Bool {
            // Only Roku supports ECP keypress today. Other device protocols
            // will be added via server-side Supabase Edge Functions.
            deviceKind == .roku && host != nil && port != nil
        }
    }

    /// Records a fresh cast handoff. Replaces any previous session — the
    /// banner always reflects the most recent thing the user sent to the
    /// TV.
    func start(
        title: String,
        platform: String,
        deviceName: String,
        deviceKind: TVDeviceKind,
        host: String?,
        port: UInt16?
    ) {
        let session = ActiveSession(
            id: UUID().uuidString,
            title: title,
            platform: platform,
            deviceName: deviceName,
            deviceKind: deviceKind,
            host: host,
            port: port,
            startedAt: Date()
        )
        current = session
        scheduleAutoExpire()
    }

    /// Dismisses the active session. The home banner disappears on the
    /// next render.
    func stop() {
        expireTask?.cancel()
        expireTask = nil
        current = nil
    }

    /// Sends `Home` to the active Roku so the TV returns to its main
    /// dashboard. Best-effort — failures are silent (Limited mode on
    /// Roku OS 14.1+ will block this without "Permissive" or "Enabled"
    /// network access).
    func sendHomeToRoku() {
        guard let session = current,
              session.deviceKind == .roku,
              let host = session.host,
              let port = session.port else { return }
        Task.detached {
            _ = await RokuECPClient.keypress(host: host, port: port, key: "Home")
        }
    }

    /// Opens the iOS Roku Remote app, with retries to survive cases where
    /// the app-switch race against a sheet dismissal causes the first
    /// `open` to be queued and dropped by iOS.
    ///
    /// Order of attempts:
    ///   1. `roku://` — the documented native scheme; lands directly on the
    ///      Roku Remote screen when the official Roku app is installed.
    ///   2. Same scheme one more time after a 600ms delay — fixes the
    ///      "sheet was still dismissing during the first open" race.
    ///   3. Universal link to the Roku app on the App Store — when neither
    ///      attempt succeeded, the user almost certainly doesn't have the
    ///      app, so this hands them a one-tap install path.
    func openRokuRemote() {
        Task { @MainActor in
            // Give the system a beat to settle any pending UI dismiss before
            // the URL open. Without this, calling `open` while a sheet is
            // mid-dismiss frequently no-ops on iOS 18+.
            try? await Task.sleep(for: .milliseconds(120))

            if await tryOpenRokuApp() { return }

            // First attempt didn't land — wait, then retry once. The retry
            // is what fixes the common "tapped from inside a sheet" failure.
            try? await Task.sleep(for: .milliseconds(600))
            if await tryOpenRokuApp() { return }

            // Still nothing — the Roku app isn't installed (or iOS refused
            // both opens). Send the user to the App Store listing as the
            // graceful final fallback. We use the completion-handler form
            // (which is non-async on iOS 18) so this branch doesn't have to
            // suspend on a result we don't need.
            if let store = URL(string: "https://apps.apple.com/app/the-roku-app-official/id482066631") {
                UIApplication.shared.open(store, options: [:], completionHandler: nil)
            }
        }
    }

    /// Attempts to open `roku://`. Returns whether iOS reported success —
    /// `true` means the foreground handoff actually went through; `false`
    /// means the Roku app is missing OR iOS dropped the request (window
    /// not foregrounded, scene inactive, etc.).
    @MainActor
    private func tryOpenRokuApp() async -> Bool {
        guard let url = URL(string: "roku://") else { return false }
        return await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { success in
                continuation.resume(returning: success)
            }
        }
    }

    /// Schedules a 60-minute auto-clear so a forgotten session doesn't
    /// haunt the home feed indefinitely. Replaces any pending expire.
    private func scheduleAutoExpire() {
        expireTask?.cancel()
        expireTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60 * 60))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.current = nil
            }
        }
    }
}

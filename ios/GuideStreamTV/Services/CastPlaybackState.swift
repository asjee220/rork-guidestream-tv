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
    /// dashboard. Best-effort — failures are silent.
    func sendHomeToRoku() {
        guard let session = current,
              session.deviceKind == .roku,
              let host = session.host,
              let port = session.port else { return }
        Task.detached {
            _ = await RokuECPClient.keypress(host: host, port: port, key: "Home")
        }
    }

    /// Opens the iOS Roku Remote app. Falls back to the App Store listing
    /// when the user doesn't have the app installed. Safe to call from any
    /// actor — UIApplication APIs are dispatched to the main actor.
    func openRokuRemote() {
        Task { @MainActor in
            guard let url = URL(string: "roku://") else { return }
            UIApplication.shared.open(url, options: [:]) { success in
                if success { return }
                // Roku app missing — fall back to its App Store listing so
                // the user has a one-tap install path.
                if let store = URL(string: "https://apps.apple.com/app/the-roku-app-official/id482066631") {
                    Task { @MainActor in
                        UIApplication.shared.open(store)
                    }
                }
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

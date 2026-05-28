//
//  TVPlayCommandListener.swift
//  GuideStreamTVTV
//
//  Subscribes to a Supabase realtime channel on launch so the Apple TV
//  can receive "Play on TV" commands pushed from the iPhone companion
//  app. When a message arrives with a deviceId matching this Apple TV's
//  stored identity, TVOSDeepLinker opens the streaming app.
//
//  Channel:  play-commands:{userId}
//  Event:    play-command
//  Payload:  { platform, title, contentURL, deviceId }
//

import Foundation
import Supabase

/// Decodable payload arriving over the Supabase realtime broadcast channel.
nonisolated struct PlayCommandPayload: Decodable, Sendable {
    let platform: String
    let title: String
    let contentURL: String?
    let deviceId: String
}

/// Singleton that subscribes to the `play-commands:{userId}` realtime
/// channel on the Apple TV and forwards matching commands to the tvOS deep
/// linker. Start once on cold launch; the subscription lives for the app
/// session and reconnects automatically via Supabase's WebSocket heartbeat.
@MainActor
final class TVPlayCommandListener {
    static let shared = TVPlayCommandListener()

    private var channel: RealtimeChannelV2?
    private var listeningTask: Task<Void, Never>?

    private init() {}

    // MARK: - Public

    /// Start listening for commands from the iPhone. Safe to call multiple
    /// times — subsequent calls are no-ops while already subscribed.
    func start() {
        guard listeningTask == nil else { return }
        listeningTask = Task { @MainActor in
            await connectAndListen()
        }
    }

    /// Tear down the subscription (e.g. on sign-out).
    func stop() {
        listeningTask?.cancel()
        listeningTask = nil
        Task { @MainActor [channel] in
            await channel?.unsubscribe()
        }
    }

    // MARK: - Private

    private func connectAndListen() async {
        let client = TVSupabaseManager.shared.client
        let deviceId = TVDeviceIdentity.shared.deviceId

        // Use the Supabase user id when signed in; fall back to "guest"
        // so commands still reach the TV even before sign-in completes
        // (the device row is keyed on deviceId, not user id).
        let userId: String
        do {
            let session = try await client.auth.session
            userId = session.user.id.uuidString
        } catch {
            userId = "guest"
        }

        let ch = client.realtimeV2.channel("play-commands:\(userId)")
        self.channel = ch

        #if DEBUG
        print("[TVPlayCommand] subscribing to play-commands:\(userId) deviceId=\(deviceId)")
        #endif

        let stream = ch.broadcastStream(event: "play-command")
        await ch.subscribe()

        #if DEBUG
        print("[TVPlayCommand] subscribed status=\(ch.status)")
        #endif

        // Run the channel status monitor in a detached task so it never
        // blocks the main listening loop.
        Task { @MainActor in
            for await status in ch.statusChange {
                #if DEBUG
                print("[TVPlayCommand] channel status → \(status)")
                #endif
            }
        }

        for await event in stream {
            guard !Task.isCancelled else { break }
            await handle(event: event, myDeviceId: deviceId)
        }
    }

    private func handle(event: RealtimeMessageV2, myDeviceId: String) async {
        let payload: PlayCommandPayload
        do {
            payload = try event.decode(as: PlayCommandPayload.self)
        } catch {
            #if DEBUG
            print("[TVPlayCommand] decode failed: \(error.localizedDescription)")
            #endif
            return
        }

        // Ignore commands meant for other devices.
        guard payload.deviceId == myDeviceId else {
            #if DEBUG
            print("[TVPlayCommand] ignoring command for \(payload.deviceId) (we are \(myDeviceId))")
            #endif
            return
        }

        #if DEBUG
        print("[TVPlayCommand] received: platform=\(payload.platform) title=\(payload.title) contentURL=\(payload.contentURL ?? "nil")")
        #endif

        let contentURL: URL? = {
            guard let s = payload.contentURL,
                  !s.isEmpty,
                  let u = URL(string: s) else { return nil }
            return u
        }()

        TVOSDeepLinker.open(
            platform: payload.platform,
            title: payload.title,
            contentURL: contentURL
        )
    }
}

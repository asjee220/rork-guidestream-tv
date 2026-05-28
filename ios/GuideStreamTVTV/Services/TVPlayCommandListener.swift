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
nonisolated struct PlayCommandPayload: Sendable {
    let platform: String
    let title: String
    let contentURL: String?
    let targetName: String
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

    // MARK: - JSONObject decoding

    private func decodePayload(from json: JSONObject) -> PlayCommandPayload? {
        guard case .string(let platform) = json["platform"],
              case .string(let title) = json["title"],
              case .string(let targetName) = json["target_name"] else {
            return nil
        }
        let contentURL: String? = {
            guard case .string(let s) = json["contentURL"], !s.isEmpty else { return nil }
            return s
        }()
        return PlayCommandPayload(platform: platform, title: title, contentURL: contentURL, targetName: targetName)
    }

    private func handle(event: JSONObject, myDeviceId: String) async {
        guard let payload = decodePayload(from: event) else {
            #if DEBUG
            print("[TVPlayCommand] decode failed")
            #endif
            return
        }

        let myName = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetName = payload.targetName.trimmingCharacters(in: .whitespacesAndNewlines)

        // Case-insensitive name comparison so "Living Room" == "living room".
        guard myName.caseInsensitiveCompare(targetName) == .orderedSame else {
            #if DEBUG
            print("[TVPlayCommand] ignoring command for '\(targetName)' (we are '\(myName)')")
            #endif
            // Log the filtered event to debug_logs so mismatches are visible.
            Task { @MainActor in
                await logFilteredEvent(targetName: targetName, myName: myName, payload: payload)
            }
            return
        }

        #if DEBUG
        print("[TVPlayCommand] received: platform=\(payload.platform) title=\(payload.title) contentURL=\(payload.contentURL ?? "nil")")
        #endif

        // Log the successful match.
        Task { @MainActor in
            await logReceivedEvent(payload: payload, matched: true)
        }

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

    // MARK: - Debug logging

    private func logReceivedEvent(payload: PlayCommandPayload, matched: Bool) async {
        guard let userId = try? await TVSupabaseManager.shared.client.auth.session.user.id.uuidString else { return }
        let deviceName = UIDevice.current.name
        let payloadDict: [String: AnyJSON] = [
            "event": .string("play_command_received"),
            "user_id": .string(userId),
            "device_name": .string(deviceName),
            "target_name": .string(payload.targetName),
            "matched": .bool(matched),
            "platform": .string(payload.platform),
            "title": .string(payload.title)
        ]
        try? await TVSupabaseManager.shared.client
            .from("debug_logs")
            .insert(payloadDict)
            .execute()
    }

    private func logFilteredEvent(targetName: String, myName: String, payload: PlayCommandPayload) async {
        guard let userId = try? await TVSupabaseManager.shared.client.auth.session.user.id.uuidString else { return }
        let payloadDict: [String: AnyJSON] = [
            "event": .string("play_command_filtered"),
            "user_id": .string(userId),
            "device_name": .string(myName),
            "target_name": .string(targetName),
            "matched": .bool(false),
            "platform": .string(payload.platform),
            "title": .string(payload.title)
        ]
        try? await TVSupabaseManager.shared.client
            .from("debug_logs")
            .insert(payloadDict)
            .execute()
    }
}

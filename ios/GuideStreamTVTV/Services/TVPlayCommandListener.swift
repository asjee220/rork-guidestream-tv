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
import UIKit
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
    /// Set by `wake()` so the supervisor retries immediately rather than
    /// serving out whatever backoff the last failure earned.
    private var reconnectNow = false

    private init() {}

    // MARK: - Public

    /// Start listening for commands from the iPhone. Safe to call multiple
    /// times — subsequent calls are no-ops while the supervisor is running.
    func start() {
        guard listeningTask == nil else { return }
        listeningTask = Task { @MainActor [weak self] in
            await self?.supervise()
            self?.listeningTask = nil
        }
    }

    /// Called when the app comes back to the foreground.
    ///
    /// tvOS suspends the app and the WebSocket dies with it. Ending the
    /// current channel makes the broadcast stream finish, which drops the
    /// supervisor into an immediate reconnect — cheaper and more certain than
    /// asking the socket whether it is still alive.
    func wake() {
        guard listeningTask != nil else {
            start()
            return
        }
        reconnectNow = true
        Task { @MainActor [channel] in await channel?.unsubscribe() }
    }

    /// Reconnect for as long as the app is running.
    ///
    /// `connectAndListen` returns when the broadcast stream ends, and a
    /// dropped socket is exactly what that looks like from here. Before this
    /// existed, that return left `listeningTask` non-nil forever, so `start()`
    /// became a permanent no-op and the TV never listened again until the
    /// process was killed and cold-launched. The Apple TV would sit on the
    /// home screen with the app open, subscribed to nothing.
    private func supervise() async {
        var backoff: Double = 2
        while !Task.isCancelled {
            let began = Date()
            let connected = await connectAndListen()
            guard !Task.isCancelled else { return }
            // Signed out: there is no channel to listen on and no amount of
            // retrying makes one. Exit rather than spin — ContentView's
            // isSignedIn observer starts us again the moment a session lands.
            guard connected else { return }
            // A connection that held for a while is not a failing one; only
            // a fast drop should slow the next attempt down.
            if Date().timeIntervalSince(began) > 60 || reconnectNow {
                backoff = 2
            }
            reconnectNow = false
            try? await Task.sleep(for: .seconds(backoff))
            backoff = min(backoff * 2, 30)
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

    /// Returns false when there is no session to listen on, so the supervisor
    /// can stand down instead of retrying something that cannot succeed.
    @discardableResult
    private func connectAndListen() async -> Bool {
        let client = TVSupabaseManager.shared.client
        let deviceId = TVDeviceIdentity.shared.deviceId

        // Signed-in only. This used to fall back to "play-commands:guest",
        // which is one topic shared by every signed-out install everywhere —
        // and the RLS policies grant anon read and write on it, so any
        // stranger's TV could be told what to open. A signed-out TV simply
        // does not listen.
        guard let session = try? await client.auth.session else {
            #if DEBUG
            print("[TVPlayCommand] no session — not subscribing")
            #endif
            return false
        }
        let userId = session.user.id.uuidString

        try? await client.realtimeV2.setAuth(session.accessToken)

        let ch = client.realtimeV2.channel("play-commands:\(userId)") { config in config.isPrivate = true }
        self.channel = ch

        #if DEBUG
        print("[TVPlayCommand] subscribing to play-commands:\(userId) deviceId=\(deviceId)")
        #endif

        let stream = ch.broadcastStream(event: "play-command")
        await ch.subscribe()

        // Tell the account this TV is listening, and under what name. The
        // phone's cast sheet reads these rows to spot a TV that is signed
        // into a different account — the failure that looks like nothing
        // happening at all. Detached so a slow AirPlay name probe or a
        // failed write never delays the listening loop.
        Task { @MainActor in await TVReceiverRegistry.register(userId: userId) }

        #if DEBUG
        // Subscribe tracing is a debug aid, not shipping behaviour — this
        // wrote a debug_logs row on every reconnect in build 16.
        try? await TVSupabaseManager.shared.client
            .from("debug_logs")
            .insert([
                "event": .string("tv_listener_subscribed"),
                "user_id": .string(userId),
                "device_name": .string("status=\(ch.status)"),
                "target_name": .string("play-commands:\(userId)")
            ] as [String: AnyJSON])
            .execute()
        #endif

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
        // The stream ended: the socket dropped, or wake() cut the channel.
        // Either way there was a session, so the supervisor should reconnect.
        return true
    }

    // MARK: - JSONObject decoding

    /// Pull the command out of a broadcast frame.
    ///
    /// Supabase hands the subscriber the whole envelope —
    /// `{"type":"broadcast","event":"play-command","payload":{...}}` — not the
    /// bare message, and that is true for a phone broadcast and a server-side
    /// `realtime.send()` alike. This used to read `json["platform"]` off the
    /// envelope, which is always nil, so every command that arrived was
    /// dropped in silence. Both shapes are accepted now so an older sender
    /// still works.
    private func decodePayload(from json: JSONObject) -> PlayCommandPayload? {
        let body: JSONObject = {
            if case .object(let inner) = json["payload"] { return inner }
            return json
        }()
        guard case .string(let platform) = body["platform"],
              case .string(let title) = body["title"],
              case .string(let targetName) = body["target_name"] else {
            return nil
        }
        let contentURL: String? = {
            guard case .string(let s) = body["contentURL"], !s.isEmpty else { return nil }
            return s
        }()
        return PlayCommandPayload(platform: platform, title: title, contentURL: contentURL, targetName: targetName)
    }

    private func handle(event: JSONObject, myDeviceId: String) async {
        guard let payload = decodePayload(from: event) else {
            #if DEBUG
            print("[TVPlayCommand] decode failed: \(event)")
            #endif
            // A silent decode failure is what hid this bug: the command was
            // arriving, nothing was logged, and the TV looked deaf.
            Task { @MainActor in await logDecodeFailure(event) }
            return
        }

        // Not UIDevice.current.name — on tvOS that is the model name, so
        // every command aimed at "Living Room 7" was filtered out as being
        // for somebody else. TVSelfName asks the Apple TV's own AirPlay
        // receiver, which is the same source the phone read the name from.
        await TVSelfName.shared.resolveNow()
        let myName = TVSelfName.shared.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetName = payload.targetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameMatched = myName.caseInsensitiveCompare(targetName) == .orderedSame

        #if DEBUG
        print("[TVPlayCommand] received: platform=\(payload.platform) title=\(payload.title) contentURL=\(payload.contentURL ?? "nil") matched=\(nameMatched)")
        #endif

        // Log every received command, matched or not — a mismatch is the
        // thing worth seeing, and both names are in the row.
        Task { @MainActor in
            await logReceivedEvent(payload: payload, matched: nameMatched)
        }

        // Only the TV that was picked acts on it. The broadcast reaches every
        // Apple TV signed into the account, and this used to open the title on
        // all of them — invisible with one TV in the house, wrong with two.
        // An empty target is treated as addressed to everyone, since an older
        // phone build sending no name should still work. So is a command this
        // TV cannot check, because the AirPlay probe never answered: acting on
        // it may open the title on a second Apple TV in the house, but
        // refusing everything we cannot verify is how this feature spent its
        // whole life doing nothing at all.
        guard nameMatched || targetName.isEmpty || !TVSelfName.shared.isResolved else { return }

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
        // Log the name we matched on, and whether it came from AirPlay or is
        // still the model-name fallback — a mismatch is unreadable without it.
        let deviceName = "\(TVSelfName.shared.name) (airplay=\(TVSelfName.shared.isResolved))"
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

    /// Record a broadcast the TV could not read, with the raw keys, so a
    /// shape change on the sending side is visible instead of invisible.
    private func logDecodeFailure(_ event: JSONObject) async {
        let keys = event.keys.sorted().joined(separator: ",")
        let payloadDict: [String: AnyJSON] = [
            "event": .string("play_command_undecodable"),
            "device_name": .string(UIDevice.current.name),
            "target_name": .string("keys=\(keys)"),
            "matched": .bool(false)
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

//
//  PlayCommandSender.swift
//  GuideStreamTV
//
//  Sends one "Play on TV" command to the tvOS companion app over the Supabase
//  realtime topic `play-commands:{userId}`.
//
//  Why this is no longer inline in CastToTVSheet: the sheet built a channel per
//  cast, broadcast on it, then called `unsubscribe()`. RealtimeClientV2 caches
//  channels by topic and `unsubscribe()` leaves the instance in that cache, so
//  the SECOND cast of an app session got the same dead channel back, did not
//  re-join it, and the command was dropped in silence — while the sheet had
//  already shown "Playing on <TV>". Measured on production builds 15 Sep 2026:
//  a cast 18s after a cold launch reached the Apple TV; the next cast 35s later
//  never arrived, and neither did any cast made after the app had been
//  backgrounded (iOS kills the WebSocket, and unlike the tvOS listener the
//  phone had no wake/rejoin path).
//
//  The send is now a stateless REST broadcast. `httpSend` has no channel
//  lifecycle to go stale, nothing to re-join after a backgrounding, and it
//  THROWS on failure. `broadcast(event:message:)` looks like it would do the
//  same — it falls back to REST when the channel is unsubscribed — but that
//  fallback runs through the non-throwing `JSONObject` overload, so a rejected
//  send returns normally and the caller cannot tell. That invisibility is the
//  bug being removed here, so the WebSocket path is kept only as a fallback for
//  Realtime servers older than 2.97.0, where `httpSend`'s per-event endpoint
//  does not exist.
//
//  The channel is deliberately never unsubscribed. It stays in the client's
//  cache, live, for the life of the process.
//

import Foundation
import Supabase

@MainActor
enum PlayCommandSender {

    /// Broadcasts one play command to the Apple TVs on the signed-in account.
    ///
    /// Returns `false` when the command could not be handed to Realtime —
    /// signed out, no access token, or the send was rejected. Callers must
    /// surface that rather than reporting success, because a dropped command
    /// is indistinguishable from a working one on the sofa.
    static func send(_ payload: PlayCommandOutgoing) async -> Bool {
        let client = SupabaseManager.shared.client

        // Signed-in only: `play-commands:{userId}` is owner-only under RLS, so
        // there is no topic for a signed-out sender to publish to.
        guard let session = try? await client.auth.session else {
            #if DEBUG
            print("[PlayCommandSender] no session — not sending")
            #endif
            return false
        }

        let userId = session.user.id.uuidString
        await client.realtimeV2.setAuth(session.accessToken)

        // `channel(_:options:)` returns the cached instance when one already
        // exists for this topic and ignores the options closure, which is
        // correct here: this is the only place in the iOS app that opens this
        // topic, so the cached channel always carries isPrivate = true.
        let channel = client.realtimeV2.channel("play-commands:\(userId)") { config in
            config.isPrivate = true
        }

        do {
            try await channel.httpSend(event: "play-command", message: payload)
            #if DEBUG
            print("[PlayCommandSender] httpSend ok → play-commands:\(userId) target=\(payload.target_name)")
            #endif
            return true
        } catch {
            #if DEBUG
            print("[PlayCommandSender] httpSend failed (\(error.localizedDescription)) — trying websocket")
            #endif
            return await sendOverWebSocket(payload, on: channel)
        }
    }

    /// Fallback for Realtime < 2.97.0, which has no per-event REST endpoint.
    ///
    /// Unlike the code this replaces, the channel is left subscribed on the way
    /// out, so a second cast in the same session finds a live channel instead
    /// of a cached dead one.
    private static func sendOverWebSocket(
        _ payload: PlayCommandOutgoing,
        on channel: RealtimeChannelV2
    ) async -> Bool {
        do {
            if channel.status != .subscribed {
                try await channel.subscribeWithError()
            }
            guard channel.status == .subscribed else { return false }
            try await channel.broadcast(event: "play-command", message: payload)
            return true
        } catch {
            #if DEBUG
            print("[PlayCommandSender] websocket broadcast failed: \(error.localizedDescription)")
            #endif
            return false
        }
    }
}

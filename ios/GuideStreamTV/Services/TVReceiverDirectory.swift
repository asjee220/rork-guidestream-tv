//
//  TVReceiverDirectory.swift
//  GuideStreamTV
//
//  The Apple TVs that are signed into *this* account, so the cast sheet can
//  tell a TV it can actually reach from one it cannot.
//
//  Bonjour finds every Apple TV on the Wi-Fi regardless of who is signed in
//  on it, and a play command goes out on `play-commands:{userId}`, which is
//  owner-only. Cast to a TV on another account and the broadcast lands on a
//  topic nothing is listening to: no error, no playback, no explanation.
//  That is exactly what happened on 2026-09-04 when the phone signed in with
//  Google while the Apple TV was still on the Apple ID account.
//
//  The tvOS app writes a `tv_receivers` row each time it subscribes. This
//  reads back the rows for the signed-in account. RLS keeps the read to the
//  caller's own rows, so this can never enumerate another household's TVs.
//

import Foundation
import Supabase

@MainActor
enum TVReceiverDirectory {

    private struct Row: Decodable {
        let displayName: String
        let lastSeenAt: Date?

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case lastSeenAt = "last_seen_at"
        }
    }

    /// What the account knows about one registered Apple TV.
    struct Registry {
        /// Every registered name, live or not. This stays the list's entry
        /// test: a TV that has ever registered is a real Apple TV on this
        /// account, and hiding it because it is asleep would be worse than
        /// showing it and saying so.
        let all: Set<String>
        /// The subset whose heartbeat is recent enough to still be listening.
        let live: Set<String>

        func isRegistered(_ name: String) -> Bool { all.contains(name) }
        func isLive(_ name: String) -> Bool { live.contains(name) }
    }

    /// How stale a heartbeat may be before the TV is treated as asleep. The
    /// TV re-registers every 5 minutes while subscribed, so 15 tolerates two
    /// missed beats without calling a live TV dead.
    private static let liveWindow: TimeInterval = 15 * 60

    /// Names of the Apple TVs registered to the signed-in account, already
    /// normalised through `CastToTVSheet.castName` and lowercased so they can
    /// be compared straight against a discovered device.
    ///
    /// Returns `nil` — not an empty set — when the answer is unknown: signed
    /// out, or the query failed. Callers must treat `nil` as "say nothing",
    /// because warning on missing information is worse than staying quiet.
    static func registeredNames() async -> Set<String>? {
        await registry()?.all
    }

    /// Registered names split by whether the TV is currently listening.
    ///
    /// Registration alone only ever meant "this TV was listening on this
    /// account at some point". A TV that subscribed last night and then slept
    /// kept its row, so the phone offered it, published to a topic nobody was
    /// on, and showed a success toast — which is exactly what "Send to TV
    /// doesn't work" looks like from the sofa. `last_seen_at` is now a
    /// heartbeat, so freshness separates the two.
    static func registry() async -> Registry? {
        guard (try? await SupabaseManager.shared.client.auth.session) != nil else { return nil }
        guard let rows: [Row] = try? await SupabaseManager.shared.client
            .from("tv_receivers")
            .select("display_name,last_seen_at")
            .execute()
            .value
        else { return nil }

        let cutoff = Date().addingTimeInterval(-liveWindow)
        var all = Set<String>()
        var live = Set<String>()
        for row in rows {
            let key = CastToTVSheet.castName(row.displayName).lowercased()
            all.insert(key)
            if let seen = row.lastSeenAt, seen >= cutoff { live.insert(key) }
        }
        return Registry(all: all, live: live)
    }
}

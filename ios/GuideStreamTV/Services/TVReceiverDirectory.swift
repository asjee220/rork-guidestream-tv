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

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
        }
    }

    /// Names of the Apple TVs registered to the signed-in account, already
    /// normalised through `CastToTVSheet.castName` and lowercased so they can
    /// be compared straight against a discovered device.
    ///
    /// Returns `nil` — not an empty set — when the answer is unknown: signed
    /// out, or the query failed. Callers must treat `nil` as "say nothing",
    /// because warning on missing information is worse than staying quiet.
    static func registeredNames() async -> Set<String>? {
        guard (try? await SupabaseManager.shared.client.auth.session) != nil else { return nil }
        guard let rows: [Row] = try? await SupabaseManager.shared.client
            .from("tv_receivers")
            .select("display_name")
            .execute()
            .value
        else { return nil }
        return Set(rows.map { CastToTVSheet.castName($0.displayName).lowercased() })
    }
}

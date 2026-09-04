//
//  TVReceiverRegistry.swift
//  GuideStreamTVTV
//
//  Tells the account which Apple TVs are actually listening for play
//  commands, and what each one is called.
//
//  The phone finds Apple TVs over Bonjour, which knows nothing about
//  accounts, so it will happily offer a TV that is signed into a different
//  account — and since `play-commands:{userId}` is owner-only, that cast is
//  published to a topic the TV is not on and vanishes without an error. On
//  2026-09-04 the phone moved to the Google account while the TV stayed on
//  the Apple one, and Play on TV went silent with no clue why.
//
//  So the TV writes a row here every time it subscribes: device id, the
//  account it is on, and the name the phone will match against. The phone
//  reads its own account's rows and marks anything it cannot see.
//

import Foundation
import Supabase

@MainActor
enum TVReceiverRegistry {

    /// Upserts this Apple TV's row for `userId`. Called right after the
    /// play-command channel subscribes, so a row here means "this TV was
    /// listening on this account", not merely "this app is installed".
    ///
    /// Failures are swallowed: registration is a hint for the phone's cast
    /// sheet, and a TV that cannot write the row still listens perfectly
    /// well. It must never take the listener down with it.
    static func register(userId: String) async {
        // The phone matches on the AirPlay name, so resolve it before
        // writing — an unresolved TV would register itself as the
        // placeholder "Apple TV" and never match what the phone sends.
        await TVSelfName.shared.resolveNow()
        let name = TVSelfName.shared.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let info = Bundle.main.infoDictionary
        var row: [String: AnyJSON] = [
            "device_id": .string(TVDeviceIdentity.shared.deviceId),
            "user_id": .string(userId),
            "display_name": .string(name),
            "name_resolved": .bool(TVSelfName.shared.isResolved),
            "last_seen_at": .string(ISO8601DateFormatter().string(from: Date()))
        ]
        if let version = info?["CFBundleShortVersionString"] as? String {
            row["app_version"] = .string(version)
        }
        if let build = info?["CFBundleVersion"] as? String {
            row["build_number"] = .string(build)
        }

        try? await TVSupabaseManager.shared.client
            .from("tv_receivers")
            .upsert(row, onConflict: "device_id")
            .execute()
    }
}

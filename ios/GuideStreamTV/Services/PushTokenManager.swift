//
//  PushTokenManager.swift
//  GuideStreamTV
//

import Foundation
import Supabase

/// Persists the APNs device token to Supabase so the backend can deliver pushes.
/// Silent-fail by design — push registration must never block UX.
@MainActor
final class PushTokenManager {
    static let shared = PushTokenManager()

    private init() {}

    func saveToken(_ token: String) async {
        guard let userId = SupabaseManager.shared.client.auth.currentUser?.id else { return }
        let payload = PushTokenPayload(
            user_id: userId.uuidString,
            apns_token: token,
            device_type: "ios"
        )
        do {
            try await SupabaseManager.shared.client
                .from("push_tokens")
                .upsert(payload, onConflict: "apns_token")
                .execute()
        } catch {
            print("[Push] saveToken failed: \(error.localizedDescription)")
        }
    }

    func clearToken() async {
        guard let userId = SupabaseManager.shared.client.auth.currentUser?.id else { return }
        do {
            try await SupabaseManager.shared.client
                .from("push_tokens")
                .delete()
                .eq("user_id", value: userId.uuidString)
                .execute()
        } catch {
            print("[Push] clearToken failed: \(error.localizedDescription)")
        }
    }
}

nonisolated struct PushTokenPayload: Encodable, Sendable {
    let user_id: String
    let apns_token: String
    let device_type: String
}

//
//  PushTokenManager.swift
//  GuideStreamTV (SHARED — compiles into both iOS and tvOS)
//
//  Persists the APNs device token to Supabase so the backend can deliver
//  pushes. Caches the token locally so it survives auth-state gaps — when
//  a guest enables push then signs in later, the cached token is re-saved
//  under the new user id.
//

import Foundation
import Supabase

/// Persists the APNs device token to Supabase so the backend can deliver pushes.
/// Silent-fail by design — push registration must never block UX.
@MainActor
final class PushTokenManager {
    static let shared = PushTokenManager()

    private let cachedTokenKey = "gs.pushTokenCache"

    private init() {}

    /// Save (or update) the APNs token. Always caches the raw token in
    /// UserDefaults so it can be re-saved when a user signs in later.
    /// If a Supabase user is already signed in the token is upserted
    /// immediately.
    func saveToken(_ token: String) async {
        // Always cache so we don't lose the token during auth transitions
        UserDefaults.standard.set(token, forKey: cachedTokenKey)

        guard let userId = SupabaseManager.shared.client.auth.currentUser?.id else {
            print("[Push] token cached, no authenticated user yet — will resave on sign-in")
            return
        }
        await upsertToken(token, userId: userId.uuidString)
    }

    /// Re-saves any cached token under the current user's id. Call this
    /// after a successful sign-in so push tokens registered during guest
    /// mode are attached to the authenticated user.
    func resaveCachedToken() async {
        guard let token = UserDefaults.standard.string(forKey: cachedTokenKey),
              !token.isEmpty else { return }
        guard let userId = SupabaseManager.shared.client.auth.currentUser?.id else { return }

        await upsertToken(token, userId: userId.uuidString)
        print("[Push] cached token re-saved for \(userId.uuidString)")
    }

    /// Remove the local cache (keeps the token — it's only cleared so
    /// a re-save doesn't fire on the next sign-in with the same token).
    func clearCache() {
        UserDefaults.standard.removeObject(forKey: cachedTokenKey)
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
        // Also clear the local cache so a stale token isn't re-saved
        clearCache()
    }

    // MARK: - Private

    private func upsertToken(_ token: String, userId: String) async {
        let payload = PushTokenPayload(
            user_id: userId,
            apns_token: token,
            device_type: "ios"
        )
        do {
            try await SupabaseManager.shared.client
                .from("push_tokens")
                .upsert(payload, onConflict: "apns_token")
                .execute()
            print("[Push] token upserted for \(userId)")
        } catch {
            print("[Push] upsert failed: \(error.localizedDescription)")
        }
    }
}

nonisolated struct PushTokenPayload: Encodable, Sendable {
    let user_id: String
    let apns_token: String
    let device_type: String
}

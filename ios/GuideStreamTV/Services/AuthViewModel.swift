//
//  AuthViewModel.swift
//  GuideStreamTV
//

import Foundation
import SwiftUI
import AuthenticationServices
import CryptoKit
import Supabase
import Auth

@MainActor
@Observable
final class AuthViewModel {
    static let shared = AuthViewModel()

    var currentUser: Supabase.User?
    var isAuthenticating: Bool = false
    var lastError: String?
    var isGuest: Bool = UserDefaults.standard.bool(forKey: "gs.isGuest")
    var hasCompletedOnboarding: Bool = UserDefaults.standard.bool(forKey: "gs.onboardingComplete")
    var selectedServices: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "gs.selectedServices") ?? [])
    var notifyPushEnabled: Bool = UserDefaults.standard.bool(forKey: "gs.notifyPush")
    var notifySMSEnabled: Bool = UserDefaults.standard.bool(forKey: "gs.notifySMS")

    /// True when there is a real Supabase user or the user chose "Get Started Free".
    var isSignedIn: Bool { currentUser != nil || isGuest }
    var isAuthenticated: Bool { currentUser != nil }

    private var currentNonce: String?

    /// Bootstrap from any persisted session (Supabase persists in Keychain by default).
    func restoreSession() async {
        do {
            let session = try await SupabaseManager.shared.client.auth.session
            self.currentUser = session.user
        } catch {
            self.currentUser = nil
        }
    }

    // MARK: - Apple Sign-In

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
        isAuthenticating = true
        defer { isAuthenticating = false }

        switch result {
        case .failure(let err):
            lastError = err.localizedDescription
            print("[Auth ERROR] Apple sign-in failed: \(err.localizedDescription)")
            return
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                lastError = "Missing Apple identity token"
                print("[Auth ERROR] Missing Apple identity token")
                return
            }

            do {
                let session = try await SupabaseManager.shared.client.auth.signInWithIdToken(
                    credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
                )
                self.currentUser = session.user
                self.isGuest = false
                UserDefaults.standard.set(false, forKey: "gs.isGuest")

                let displayName = Self.composeName(credential.fullName)
                await upsertProfile(
                    userId: session.user.id.uuidString,
                    displayName: displayName,
                    email: credential.email ?? session.user.email
                )
                WatchIntentLogger.shared.log(
                    eventType: .authSignedIn,
                    metadata: [
                        "provider": "apple",
                        "user_id": session.user.id.uuidString,
                        "has_email": (credential.email ?? session.user.email) != nil
                    ]
                )
            } catch {
                lastError = error.localizedDescription
                print("[Auth ERROR] signInWithIdToken (apple) failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Onboarding persistence

    func setSelectedServices(_ services: Set<String>) {
        self.selectedServices = services
        UserDefaults.standard.set(Array(services), forKey: "gs.selectedServices")
    }

    func setNotificationPreferences(push: Bool, sms: Bool) {
        self.notifyPushEnabled = push
        self.notifySMSEnabled = sms
        UserDefaults.standard.set(push, forKey: "gs.notifyPush")
        UserDefaults.standard.set(sms, forKey: "gs.notifySMS")
    }

    func completeOnboarding() {
        self.hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "gs.onboardingComplete")

        // Always log the onboarding completion as an analytics event — runs
        // for guests *and* authenticated users, so we capture every install.
        WatchIntentLogger.shared.log(
            eventType: .onboardingCompleted,
            metadata: [
                "services": Array(selectedServices),
                "service_count": selectedServices.count,
                "notify_push": notifyPushEnabled,
                "notify_sms": notifySMSEnabled
            ]
        )

        // Authenticated users get a richer row in `users` keyed by their
        // Supabase auth uuid. Guests skip this — most schemas FK `users.id`
        // back to `auth.users`, so writing a guest row would fail.
        guard let userId = currentUser?.id.uuidString else { return }
        let prefs = OnboardingPrefsUpsert(
            id: userId,
            services: Array(selectedServices),
            notify_push: notifyPushEnabled,
            notify_sms: notifySMSEnabled
        )
        Task {
            do {
                try await SupabaseManager.shared.client
                    .from("users")
                    .upsert(prefs, onConflict: "id")
                    .execute()
                print("[Auth] onboarding prefs saved for user \(userId)")
            } catch {
                let msg = error.localizedDescription
                self.lastError = msg
                print("[Auth ERROR] onboarding prefs upsert failed: \(msg)")
            }
        }
    }

    func signOut() async {
        // Clear push token before tearing down the session (needs the user id)
        await PushTokenManager.shared.clearToken()
        do {
            try await SupabaseManager.shared.client.auth.signOut()
        } catch {
            // Even if remote sign-out fails, clear local state
        }
        self.currentUser = nil
        self.isGuest = false
        self.hasCompletedOnboarding = false
        UserDefaults.standard.set(false, forKey: "gs.isGuest")
        UserDefaults.standard.set(false, forKey: "gs.onboardingComplete")
    }

    // MARK: - Guest mode

    func continueAsGuest() {
        self.isGuest = true
        UserDefaults.standard.set(true, forKey: "gs.isGuest")
        WatchIntentLogger.shared.log(
            eventType: .guestStarted,
            metadata: [
                "first_launch": DeviceIdentity.shared.isFirstLaunch
            ]
        )
    }

    // MARK: - Google Sign-In (Supabase OAuth via ASWebAuthenticationSession)

    func signInWithGoogle() async {
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            let session = try await SupabaseManager.shared.client.auth.signInWithOAuth(
                provider: .google,
                redirectTo: URL(string: "guidestream://auth-callback")
            )
            self.currentUser = session.user
            self.isGuest = false
            UserDefaults.standard.set(false, forKey: "gs.isGuest")
            await upsertProfile(
                userId: session.user.id.uuidString,
                displayName: nil,
                email: session.user.email
            )
            WatchIntentLogger.shared.log(
                eventType: .authSignedIn,
                metadata: [
                    "provider": "google",
                    "user_id": session.user.id.uuidString,
                    "has_email": session.user.email != nil
                ]
            )
        } catch {
            lastError = error.localizedDescription
            print("[Auth ERROR] Google sign-in failed: \(error.localizedDescription)")
        }
    }

    private func upsertProfile(userId: String, displayName: String?, email: String?) async {
        let payload = UserProfileUpsert(
            id: userId,
            display_name: displayName,
            avatar_url: nil,
            email: email
        )
        do {
            try await SupabaseManager.shared.client
                .from("users")
                .upsert(payload, onConflict: "id")
                .execute()
            print("[Auth] users row upserted for \(userId)")
        } catch {
            // Retry without `email` in case the column doesn't exist yet —
            // some installations only have id/display_name/avatar_url.
            let msg = error.localizedDescription
            if msg.localizedCaseInsensitiveContains("email")
                && msg.localizedCaseInsensitiveContains("column") {
                let minimal = UserProfileUpsert(
                    id: userId,
                    display_name: displayName,
                    avatar_url: nil,
                    email: nil
                )
                do {
                    try await SupabaseManager.shared.client
                        .from("users")
                        .upsert(minimal, onConflict: "id")
                        .execute()
                    print("[Auth] users row upserted (no email) for \(userId)")
                    return
                } catch {
                    self.lastError = error.localizedDescription
                    print("[Auth ERROR] users upsert (minimal) failed: \(error.localizedDescription)")
                    return
                }
            }
            self.lastError = msg
            print("[Auth ERROR] users upsert failed: \(msg)")
        }
    }

    // MARK: - Helpers

    private static func composeName(_ name: PersonNameComponents?) -> String? {
        guard let name else { return nil }
        let parts = [name.givenName, name.familyName].compactMap { $0 }
        let joined = parts.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if status != errSecSuccess { continue }
            for random in randoms where remaining > 0 {
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

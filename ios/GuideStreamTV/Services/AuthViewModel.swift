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
            return
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                lastError = "Missing Apple identity token"
                return
            }

            do {
                let session = try await SupabaseManager.shared.client.auth.signInWithIdToken(
                    credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
                )
                self.currentUser = session.user

                let displayName = Self.composeName(credential.fullName)
                await upsertProfile(userId: session.user.id.uuidString, displayName: displayName)
            } catch {
                lastError = error.localizedDescription
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

        // Best-effort upsert to Supabase (non-blocking, silent failure ok)
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
            } catch {
                print("[Auth] onboarding prefs upsert failed: \(error.localizedDescription)")
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
            await upsertProfile(userId: session.user.id.uuidString, displayName: nil)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func upsertProfile(userId: String, displayName: String?) async {
        let payload = UserProfileUpsert(
            id: userId,
            display_name: displayName,
            avatar_url: nil
        )
        do {
            try await SupabaseManager.shared.client
                .from("users")
                .upsert(payload, onConflict: "id")
                .execute()
        } catch {
            // Non-fatal: profile upsert can fail if table missing
            print("[Auth] users upsert failed: \(error.localizedDescription)")
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

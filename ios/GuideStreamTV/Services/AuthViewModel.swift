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
    var lastInfo: String?
    var isGuest: Bool = UserDefaults.standard.bool(forKey: "gs.isGuest")
    /// Cached `users.display_name` for the signed-in user. Lazy-loaded by
    /// `loadDisplayName()` and persisted to `UserDefaults` so the Profile
    /// avatar/name renders instantly on cold launch.
    var displayName: String? = UserDefaults.standard.string(forKey: "gs.displayName")
    var hasCompletedOnboarding: Bool = UserDefaults.standard.bool(forKey: "gs.onboardingComplete")
    var selectedServices: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "gs.selectedServices") ?? [])
    var notifyPushEnabled: Bool = UserDefaults.standard.bool(forKey: "gs.notifyPush")
    var notifySMSEnabled: Bool = UserDefaults.standard.bool(forKey: "gs.notifySMS")
    /// True after the user has completed at least one successful email sign-up.
    /// First-time visits to the email auth screen show the create-account flow;
    /// every visit afterwards defaults to the sign-in flow.
    var hasUsedEmailAuth: Bool = UserDefaults.standard.bool(forKey: "gs.hasUsedEmailAuth")

    /// True when there is a real Supabase user or the user chose "Get Started Free".
    var isSignedIn: Bool { currentUser != nil || isGuest }
    var isAuthenticated: Bool { currentUser != nil }

    private var currentNonce: String?

    /// Bootstrap from any persisted session (Supabase persists in Keychain by default).
    func restoreSession() async {
        do {
            let session = try await SupabaseManager.shared.client.auth.session
            self.currentUser = session.user
            await loadDisplayName()
        } catch {
            self.currentUser = nil
        }
    }

    /// Fetches the `display_name` column from the `users` table for the
    /// current Supabase user. Silently fails to the cached value when
    /// offline or when the row hasn't been upserted yet.
    func loadDisplayName() async {
        guard let uid = currentUser?.id.uuidString else { return }
        do {
            let rows: [UserProfileNameRow] = try await SupabaseManager.shared.client
                .from("users")
                .select("display_name")
                .eq("id", value: uid)
                .limit(1)
                .execute()
                .value
            if let name = rows.first?.display_name, !name.isEmpty {
                self.displayName = name
                UserDefaults.standard.set(name, forKey: "gs.displayName")
            }
        } catch {
            print("[Auth] loadDisplayName failed: \(error.localizedDescription)")
        }
    }

    /// Updates the user's display name in Supabase and caches it locally.
    /// Returns `true` on success.
    @discardableResult
    func updateDisplayName(_ name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let uid = currentUser?.id.uuidString else {
            return false
        }
        let payload = UserProfileUpsert(
            id: uid,
            display_name: trimmed,
            avatar_url: nil,
            email: currentUser?.email
        )
        do {
            try await SupabaseManager.shared.client
                .from("users")
                .upsert(payload, onConflict: "id")
                .execute()
            self.displayName = trimmed
            UserDefaults.standard.set(trimmed, forKey: "gs.displayName")
            return true
        } catch {
            self.lastError = error.localizedDescription
            print("[Auth] updateDisplayName failed: \(error.localizedDescription)")
            return false
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

                let appleName = Self.composeName(credential.fullName)
                await upsertProfile(
                    userId: session.user.id.uuidString,
                    displayName: appleName,
                    email: credential.email ?? session.user.email
                )
                if let appleName, !appleName.isEmpty {
                    self.displayName = appleName
                    UserDefaults.standard.set(appleName, forKey: "gs.displayName")
                } else {
                    await loadDisplayName()
                }
                WatchIntentLogger.shared.log(
                    eventType: .authSignedIn,
                    metadata: [
                        "provider": "apple",
                        "user_id": session.user.id.uuidString,
                        "has_email": (credential.email ?? session.user.email) != nil
                    ]
                )
                DeviceSessionService.shared.upsert(reason: "apple_signed_in")
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
        // Mirror the latest selection into device_sessions so the guest "profile"
        // stays in sync as the user toggles services during onboarding.
        DeviceSessionService.shared.upsert(reason: "services_changed")
    }

    func setNotificationPreferences(push: Bool, sms: Bool) {
        self.notifyPushEnabled = push
        self.notifySMSEnabled = sms
        UserDefaults.standard.set(push, forKey: "gs.notifyPush")
        UserDefaults.standard.set(sms, forKey: "gs.notifySMS")
        DeviceSessionService.shared.upsert(reason: "notifications_changed")
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
        // Sync the device row with the final selection — fires for guests
        // too so a "signed-out" install still gets a complete row.
        DeviceSessionService.shared.upsert(reason: "onboarding_completed")

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
        self.displayName = nil
        UserDefaults.standard.set(false, forKey: "gs.isGuest")
        UserDefaults.standard.removeObject(forKey: "gs.displayName")
        // NOTE: `hasCompletedOnboarding` is *not* reset on sign-out — a user
        // who has already chosen their services on this device should not be
        // forced through onboarding again when their session expires or they
        // sign back in with a different method.
        // Update the device row to reflect the signed-out state so the
        // server stops attributing future events to the old user_id.
        DeviceSessionService.shared.upsert(reason: "signed_out")
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
        DeviceSessionService.shared.upsert(reason: "guest_started")
    }

    // MARK: - Email auth (Supabase email + password)

    /// Create a new account with email + password. Sends a confirmation email
    /// when the project has "Confirm email" turned on; in that case `session`
    /// is nil and the caller should surface a "check your inbox" message.
    /// Returns `true` when a session was issued and the user is fully signed
    /// in, `false` when email confirmation is pending.
    @discardableResult
    func signUpWithEmail(email: String, password: String) async -> Bool {
        isAuthenticating = true
        lastError = nil
        lastInfo = nil
        defer { isAuthenticating = false }
        do {
            let response = try await SupabaseManager.shared.client.auth.signUp(
                email: email,
                password: password
            )
            UserDefaults.standard.set(true, forKey: "gs.hasUsedEmailAuth")
            self.hasUsedEmailAuth = true
            if let session = response.session {
                self.currentUser = session.user
                self.isGuest = false
                UserDefaults.standard.set(false, forKey: "gs.isGuest")
                await upsertProfile(
                    userId: session.user.id.uuidString,
                    displayName: nil,
                    email: session.user.email
                )
                await loadDisplayName()
                WatchIntentLogger.shared.log(
                    eventType: .authSignedIn,
                    metadata: [
                        "provider": "email",
                        "flow": "sign_up",
                        "user_id": session.user.id.uuidString
                    ]
                )
                DeviceSessionService.shared.upsert(reason: "email_signed_up")
                return true
            }
            // Session is nil — Supabase requires email confirmation. The user
            // must tap the magic link before they can sign in. We treat this
            // as a successful registration but *not* a successful sign-in.
            self.lastInfo = "Check your inbox to confirm your email, then come back and sign in."
            print("[Auth] email sign-up pending confirmation for \(email)")
            return false
        } catch {
            let message = error.localizedDescription
            // "User already registered" — fall back to sign in with the same
            // password. Common when a returning user lands in the create flow
            // because we haven't yet flipped `hasUsedEmailAuth` on this device.
            if message.localizedCaseInsensitiveContains("already") {
                print("[Auth] user already exists — attempting sign-in fallback")
                let ok = await signInWithEmail(email: email, password: password)
                if ok {
                    UserDefaults.standard.set(true, forKey: "gs.hasUsedEmailAuth")
                    self.hasUsedEmailAuth = true
                }
                return ok
            }
            lastError = message
            print("[Auth ERROR] email sign-up failed: \(message)")
            return false
        }
    }

    /// Sign in an existing user with email + password. Returns `true` on
    /// success. Surfaces a friendly error in `lastError` on failure.
    @discardableResult
    func signInWithEmail(email: String, password: String) async -> Bool {
        isAuthenticating = true
        lastError = nil
        lastInfo = nil
        defer { isAuthenticating = false }
        do {
            let session = try await SupabaseManager.shared.client.auth.signIn(
                email: email,
                password: password
            )
            self.currentUser = session.user
            self.isGuest = false
            UserDefaults.standard.set(false, forKey: "gs.isGuest")
            UserDefaults.standard.set(true, forKey: "gs.hasUsedEmailAuth")
            self.hasUsedEmailAuth = true
            await upsertProfile(
                userId: session.user.id.uuidString,
                displayName: nil,
                email: session.user.email
            )
            await loadDisplayName()
            WatchIntentLogger.shared.log(
                eventType: .authSignedIn,
                metadata: [
                    "provider": "email",
                    "flow": "sign_in",
                    "user_id": session.user.id.uuidString
                ]
            )
            DeviceSessionService.shared.upsert(reason: "email_signed_in")
            return true
        } catch {
            let message = error.localizedDescription
            // Map Supabase's verbose messages to something a user understands.
            if message.localizedCaseInsensitiveContains("invalid login credentials")
                || message.localizedCaseInsensitiveContains("invalid_grant") {
                lastError = "That email or password doesn't match. Try again or reset your password."
            } else if message.localizedCaseInsensitiveContains("email not confirmed") {
                lastError = "Check your inbox to confirm your email before signing in."
            } else {
                lastError = message
            }
            print("[Auth ERROR] email sign-in failed: \(message)")
            return false
        }
    }

    /// Send a password-reset email. Supabase generates a one-time recovery
    /// link that lands back in the app via the `guidestream://` URL scheme.
    /// Returns `true` if the email was dispatched, `false` if the call
    /// failed (e.g. unknown address — Supabase intentionally returns 200 for
    /// most cases to avoid leaking which emails are registered).
    @discardableResult
    func sendPasswordReset(email: String) async -> Bool {
        isAuthenticating = true
        lastError = nil
        lastInfo = nil
        defer { isAuthenticating = false }
        do {
            try await SupabaseManager.shared.client.auth.resetPasswordForEmail(
                email,
                redirectTo: URL(string: "guidestream://auth-callback")
            )
            self.lastInfo = "If that address is registered, we just sent a recovery link. Check your inbox."
            print("[Auth] password reset dispatched for \(email)")
            return true
        } catch {
            let message = error.localizedDescription
            lastError = message
            print("[Auth ERROR] password reset failed: \(message)")
            return false
        }
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
            await loadDisplayName()
            WatchIntentLogger.shared.log(
                eventType: .authSignedIn,
                metadata: [
                    "provider": "google",
                    "user_id": session.user.id.uuidString,
                    "has_email": session.user.email != nil
                ]
            )
            DeviceSessionService.shared.upsert(reason: "google_signed_in")
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

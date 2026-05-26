//
//  TVAuthViewModel.swift
//  GuideStreamTVTV
//
//  Auth gate for the Apple TV experience. Supports:
//   * Sign in with Apple (native on tvOS via AuthenticationServices)
//   * "Continue as guest" — falls back to device_id ownership for the
//     watch list, matching the phone app.
//
//  Sessions are persisted by the Supabase SDK (Keychain), so the user
//  doesn't need to sign in again on cold launch.
//

import Foundation
import SwiftUI
import AuthenticationServices
import CryptoKit
import Supabase
import Auth

@MainActor
@Observable
final class TVAuthViewModel {
    static let shared = TVAuthViewModel()

    var currentUser: Supabase.User?
    var isAuthenticating: Bool = false
    var lastError: String?
    var isGuest: Bool = UserDefaults.standard.bool(forKey: "gs.tv.isGuest")
    var displayName: String? = UserDefaults.standard.string(forKey: "gs.tv.displayName")
    var firstName: String? = UserDefaults.standard.string(forKey: "gs.tv.firstName")
    var lastName: String? = UserDefaults.standard.string(forKey: "gs.tv.lastName")

    /// True when there's a real Supabase user OR the user explicitly chose
    /// guest mode. The home screen renders for either state.
    var isSignedIn: Bool { currentUser != nil || isGuest }
    var isAuthenticated: Bool { currentUser != nil }

    private var currentNonce: String?

    /// Loads any persisted Supabase session from Keychain. Called on app
    /// launch so a returning user lands directly on Home.
    func restoreSession() async {
        do {
            let session = try await TVSupabaseManager.shared.client.auth.session
            self.currentUser = session.user
            await loadDisplayName()
            // Refresh the watch list using the real user_id.
            Task { await TVStreamsViewModel.shared.fetchUserStreams() }
        } catch {
            self.currentUser = nil
        }
    }

    func continueAsGuest() {
        self.isGuest = true
        UserDefaults.standard.set(true, forKey: "gs.tv.isGuest")
    }

    func signOut() async {
        do { try await TVSupabaseManager.shared.client.auth.signOut() } catch { }
        self.currentUser = nil
        self.isGuest = false
        self.displayName = nil
        UserDefaults.standard.set(false, forKey: "gs.tv.isGuest")
        UserDefaults.standard.removeObject(forKey: "gs.tv.displayName")
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
            print("[TVAuth ERROR] Apple sign-in failed: \(err.localizedDescription)")
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
                let session = try await TVSupabaseManager.shared.client.auth.signInWithIdToken(
                    credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
                )
                self.currentUser = session.user
                self.isGuest = false
                UserDefaults.standard.set(false, forKey: "gs.tv.isGuest")

                let firstApple = credential.fullName?.givenName
                let lastApple = credential.fullName?.familyName
                let appleName = Self.composeName(credential.fullName)
                if let firstApple, !firstApple.isEmpty {
                    self.firstName = firstApple
                    UserDefaults.standard.set(firstApple, forKey: "gs.tv.firstName")
                }
                if let lastApple, !lastApple.isEmpty {
                    self.lastName = lastApple
                    UserDefaults.standard.set(lastApple, forKey: "gs.tv.lastName")
                }
                if let appleName, !appleName.isEmpty {
                    self.displayName = appleName
                    UserDefaults.standard.set(appleName, forKey: "gs.tv.displayName")
                }
                await loadDisplayName()
                Task { await TVStreamsViewModel.shared.fetchUserStreams() }
            } catch {
                lastError = error.localizedDescription
                print("[TVAuth ERROR] signInWithIdToken (apple) failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Profile

    private func loadDisplayName() async {
        guard let uid = currentUser?.id.uuidString else { return }
        do {
            let rows: [TVUserProfileNameRow] = try await TVSupabaseManager.shared.client
                .from("users")
                .select("display_name, first_name, last_name")
                .eq("id", value: uid)
                .limit(1)
                .execute()
                .value
            if let row = rows.first {
                if let n = row.display_name, !n.isEmpty {
                    self.displayName = n
                    UserDefaults.standard.set(n, forKey: "gs.tv.displayName")
                }
                if let f = row.first_name, !f.isEmpty {
                    self.firstName = f
                    UserDefaults.standard.set(f, forKey: "gs.tv.firstName")
                }
                if let l = row.last_name, !l.isEmpty {
                    self.lastName = l
                    UserDefaults.standard.set(l, forKey: "gs.tv.lastName")
                }
            }
        } catch {
            print("[TVAuth] loadDisplayName failed: \(error.localizedDescription)")
        }
    }

    /// Convenience for the avatar pill on the Account tab.
    var initials: String {
        let first = (firstName ?? "").prefix(1).uppercased()
        let last = (lastName ?? "").prefix(1).uppercased()
        let combined = first + last
        if !combined.isEmpty { return combined }
        if let name = displayName, let initial = name.first { return String(initial).uppercased() }
        return "G"
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

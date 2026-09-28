//
//  MacAuthViewModel.swift
//  GuideStreamTVMac
//
//  Session state for the Mac app. Same Supabase project and `users` table
//  as iPhone and Apple TV, so signing in with the same Apple ID or email
//  brings the same watchlist and services. AuthViewModel (ported from the
//  tvOS target) forwards to this type, exactly as it forwards to
//  TVAuthViewModel on Apple TV.
//
//  Nonce rule (standing instruction): Apple gets SHA256(nonce) on the
//  request, Supabase gets the raw nonce.
//

import Foundation
import SwiftUI
import AuthenticationServices
import CryptoKit
import Supabase
import Auth

/// The services ported from tvOS read the session as TVAuthViewModel.shared.
typealias TVAuthViewModel = MacAuthViewModel

@MainActor
@Observable
final class MacAuthViewModel {
    static let shared = MacAuthViewModel()

    var currentUser: Supabase.User?
    var isAuthenticating: Bool = false
    var lastError: String?
    var isGuest: Bool = UserDefaults.standard.bool(forKey: "gs.isGuest")
    var displayName: String? = UserDefaults.standard.string(forKey: "gs.displayName")
    var firstName: String? = UserDefaults.standard.string(forKey: "gs.firstName")
    var lastName: String? = UserDefaults.standard.string(forKey: "gs.lastName")

    var isAuthenticated: Bool { currentUser != nil }
    var isSignedIn: Bool { currentUser != nil || isGuest }

    var initials: String {
        let source = [firstName, lastName].compactMap { $0?.first }.map(String.init).joined()
        if !source.isEmpty { return source.uppercased() }
        if let name = displayName, let f = name.first { return String(f).uppercased() }
        if let email = currentUser?.email, let f = email.first { return String(f).uppercased() }
        return "G"
    }

    private var currentNonce: String?
    private var appleDelegate: AppleSignInDelegate?
    private var client: SupabaseClient { SupabaseManager.shared.client }

    private init() {}

    // MARK: - Session

    func restoreSession() async {
        do {
            let session = try await client.auth.session
            currentUser = session.user
            isGuest = false
            await loadDisplayName()
        } catch {
            currentUser = nil
        }
    }

    func continueAsGuest() {
        isGuest = true
        UserDefaults.standard.set(true, forKey: "gs.isGuest")
    }

    func signOut() async {
        do { try await client.auth.signOut() } catch {
            print("[MacAuth] signOut failed: \(error.localizedDescription)")
        }
        currentUser = nil
        isGuest = false
        UserDefaults.standard.set(false, forKey: "gs.isGuest")
    }

    // MARK: - Email

    @discardableResult
    func signInWithEmail(email: String, password: String) async -> Bool {
        isAuthenticating = true
        lastError = nil
        defer { isAuthenticating = false }
        do {
            let session = try await client.auth.signIn(email: email, password: password)
            await didSignIn(session.user, provider: "email", first: nil, last: nil)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Sign in with Apple

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let err):
            if (err as? ASAuthorizationError)?.code != .canceled {
                lastError = err.localizedDescription
            }
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                lastError = "Missing Apple identity token"
                return
            }
            isAuthenticating = true
            defer { isAuthenticating = false }
            do {
                let session = try await client.auth.signInWithIdToken(
                    credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
                )
                await didSignIn(
                    session.user,
                    provider: "apple",
                    first: credential.fullName?.givenName,
                    last: credential.fullName?.familyName
                )
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Drives Sign in with Apple without a SignInWithAppleButton.
    func performAppleSignIn(onComplete: @escaping () -> Void) {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        prepareAppleRequest(request)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        let delegate = AppleSignInDelegate { [weak self] result in
            Task { @MainActor in
                await self?.handleAppleCompletion(result)
                onComplete()
            }
        }
        appleDelegate = delegate
        controller.delegate = delegate
        controller.performRequests()
    }

    // MARK: - Shared post-sign-in

    private func didSignIn(_ user: Supabase.User, provider: String, first: String?, last: String?) async {
        currentUser = user
        isGuest = false
        UserDefaults.standard.set(false, forKey: "gs.isGuest")
        if let first, !first.isEmpty {
            firstName = first
            UserDefaults.standard.set(first, forKey: "gs.firstName")
        }
        if let last, !last.isEmpty {
            lastName = last
            UserDefaults.standard.set(last, forKey: "gs.lastName")
        }
        // Only the columns we actually know are written, so an existing
        // display name or avatar set on the phone is never blanked.
        var payload: [String: AnyJSON] = ["id": .string(user.id.uuidString)]
        if let email = user.email { payload["email"] = .string(email) }
        if let first, !first.isEmpty { payload["first_name"] = .string(first) }
        if let last, !last.isEmpty { payload["last_name"] = .string(last) }
        let composed = [first, last].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        if !composed.isEmpty { payload["display_name"] = .string(composed) }
        do {
            try await client.from("users").upsert(payload, onConflict: "id").execute()
        } catch {
            print("[MacAuth] users upsert failed: \(error.localizedDescription)")
        }
        await loadDisplayName()
        WatchIntentLogger.shared.log(
            eventType: .authSignedIn,
            metadata: ["provider": provider, "flow": "sign_in", "user_id": user.id.uuidString]
        )
    }

    private func loadDisplayName() async {
        guard let uid = currentUser?.id.uuidString else { return }
        struct Row: Decodable { let display_name: String?; let first_name: String?; let last_name: String? }
        do {
            let rows: [Row] = try await client.from("users")
                .select("display_name, first_name, last_name")
                .eq("id", value: uid)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else { return }
            if let d = row.display_name, !d.isEmpty {
                displayName = d
                UserDefaults.standard.set(d, forKey: "gs.displayName")
            }
            if let f = row.first_name, !f.isEmpty { firstName = f }
            if let l = row.last_name, !l.isEmpty { lastName = l }
        } catch {
            print("[MacAuth] loadDisplayName failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Nonce

    private static func randomNonceString(length: Int = 32) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            guard SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms) == errSecSuccess else { continue }
            for random in randoms where remaining > 0 && random < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// ASAuthorizationController delegate + window anchor for the Mac.
final class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let completion: (Result<ASAuthorization, Error>) -> Void

    init(completion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.completion = completion
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        completion(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        completion(.failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? NSWindow()
    }
}

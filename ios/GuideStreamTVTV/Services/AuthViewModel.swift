//
//  AuthViewModel.swift
//  GuideStreamTVTV
//
//  tvOS bridge that wraps TVAuthViewModel and adds email-auth stubs so
//  shared views (EmailAuthView, OnboardingFlow, etc.) compile cleanly.
//  Real auth on tvOS goes through Sign in with Apple via TVAuthViewModel.
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

    // MARK: - Delegated to TVAuthViewModel

    var currentUser: Supabase.User? {
        get { TVAuthViewModel.shared.currentUser }
        set { TVAuthViewModel.shared.currentUser = newValue }
    }
    var isAuthenticating: Bool {
        get { TVAuthViewModel.shared.isAuthenticating }
        set { TVAuthViewModel.shared.isAuthenticating = newValue }
    }
    var lastError: String? {
        get { TVAuthViewModel.shared.lastError }
        set { TVAuthViewModel.shared.lastError = newValue }
    }
    var isGuest: Bool {
        get { TVAuthViewModel.shared.isGuest }
        set { TVAuthViewModel.shared.isGuest = newValue }
    }
    var displayName: String? {
        get { TVAuthViewModel.shared.displayName }
        set { TVAuthViewModel.shared.displayName = newValue }
    }
    var firstName: String? {
        get { TVAuthViewModel.shared.firstName }
        set { TVAuthViewModel.shared.firstName = newValue }
    }
    var lastName: String? {
        get { TVAuthViewModel.shared.lastName }
        set { TVAuthViewModel.shared.lastName = newValue }
    }
    var isSignedIn: Bool { TVAuthViewModel.shared.isSignedIn }
    var isAuthenticated: Bool { TVAuthViewModel.shared.isAuthenticated }
    var initials: String { TVAuthViewModel.shared.initials }

    // MARK: - Onboarding state (stored locally since TVAuthViewModel doesn't carry these)

    var hasCompletedOnboarding: Bool = UserDefaults.standard.bool(forKey: "gs.onboardingComplete")
    var selectedServices: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "gs.selectedServices") ?? [])
    var notifyPushEnabled: Bool = UserDefaults.standard.bool(forKey: "gs.notifyPush")
    var notifySMSEnabled: Bool = UserDefaults.standard.bool(forKey: "gs.notifySMS")
    var hasUsedEmailAuth: Bool = UserDefaults.standard.bool(forKey: "gs.hasUsedEmailAuth")

    /// Only populated on the email-auth path; tvOS uses Apple Sign-In so this stays nil.
    var lastInfo: String?

    private init() {}

    // MARK: - Session management (delegated)

    func restoreSession() async {
        await TVAuthViewModel.shared.restoreSession()
    }

    func loadDisplayName() async {
        // TVAuthViewModel loads display name in restoreSession
    }

    @discardableResult
    func updateDisplayName(_ name: String) async -> Bool { return false }

    func continueAsGuest() {
        TVAuthViewModel.shared.continueAsGuest()
    }

    func signOut() async {
        await TVAuthViewModel.shared.signOut()
    }

    // MARK: - Apple Sign-In (delegated)

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        TVAuthViewModel.shared.prepareAppleRequest(request)
    }

    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
        await TVAuthViewModel.shared.handleAppleCompletion(result)
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
        WatchIntentLogger.shared.log(
            eventType: .onboardingCompleted,
            metadata: [
                "services": Array(selectedServices),
                "service_count": selectedServices.count,
                "notify_push": notifyPushEnabled,
                "notify_sms": notifySMSEnabled
            ]
        )
    }

    // MARK: - Email auth stubs (not supported on tvOS)

    @discardableResult
    func signUpWithEmail(email: String, password: String, firstName: String, lastName: String) async -> Bool {
        lastError = "Email sign-up is not available on Apple TV. Use Sign in with Apple instead."
        return false
    }

    @discardableResult
    func signInWithEmail(email: String, password: String) async -> Bool {
        lastError = "Email sign-in is not available on Apple TV. Use Sign in with Apple instead."
        return false
    }

    @discardableResult
    func sendPasswordReset(email: String) async -> Bool {
        lastError = "Password reset is not available on Apple TV."
        return false
    }
}

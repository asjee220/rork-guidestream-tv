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

    // MARK: - Per-category notification preferences

    var notifyNewEpisodesEnabled: Bool = (UserDefaults.standard.object(forKey: "gs.notifyNewEpisodes") as? Bool) ?? true {
        didSet {
            guard !isApplyingCategoryPrefs else { return }
            UserDefaults.standard.set(notifyNewEpisodesEnabled, forKey: "gs.notifyNewEpisodes")
            syncNewEpisodesPreference()
        }
    }
    var notifyWatchlistEnabled: Bool = (UserDefaults.standard.object(forKey: "gs.notifyWatchlist") as? Bool) ?? true {
        didSet {
            guard !isApplyingCategoryPrefs else { return }
            UserDefaults.standard.set(notifyWatchlistEnabled, forKey: "gs.notifyWatchlist")
            syncWatchlistPreference()
        }
    }
    var notifyLiveEnabled: Bool = (UserDefaults.standard.object(forKey: "gs.notifyLive") as? Bool) ?? true {
        didSet {
            guard !isApplyingCategoryPrefs else { return }
            UserDefaults.standard.set(notifyLiveEnabled, forKey: "gs.notifyLive")
            syncLivePreference()
        }
    }
    var notifySportsEnabled: Bool = (UserDefaults.standard.object(forKey: "gs.notifySports") as? Bool) ?? true {
        didSet {
            guard !isApplyingCategoryPrefs else { return }
            UserDefaults.standard.set(notifySportsEnabled, forKey: "gs.notifySports")
            syncSportsPreference()
        }
    }
    var notifyMovieReleasesEnabled: Bool = (UserDefaults.standard.object(forKey: "gs.notifyMovieReleases") as? Bool) ?? true {
        didSet {
            guard !isApplyingCategoryPrefs else { return }
            UserDefaults.standard.set(notifyMovieReleasesEnabled, forKey: "gs.notifyMovieReleases")
            syncMovieReleasePreference()
        }
    }

    private var isApplyingCategoryPrefs = false

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

    // MARK: - Per-category preference sync

    private func syncNewEpisodesPreference() {
        guard let userId = currentUser?.id.uuidString else { return }
        let enabled = notifyNewEpisodesEnabled
        Task {
            do {
                try await SupabaseManager.shared.client
                    .from("users")
                    .update(["notify_new_episodes": enabled])
                    .eq("id", value: userId)
                    .execute()
                print("[AuthViewModel] synced notify_new_episodes=\(enabled)")
            } catch {
                print("[AuthViewModel] sync notify_new_episodes failed: \(error.localizedDescription)")
            }
        }
    }

    private func syncWatchlistPreference() {
        guard let userId = currentUser?.id.uuidString else { return }
        let enabled = notifyWatchlistEnabled
        Task {
            do {
                try await SupabaseManager.shared.client
                    .from("users")
                    .update(["notify_watchlist": enabled])
                    .eq("id", value: userId)
                    .execute()
                print("[AuthViewModel] synced notify_watchlist=\(enabled)")
            } catch {
                print("[AuthViewModel] sync notify_watchlist failed: \(error.localizedDescription)")
            }
        }
    }

    private func syncLivePreference() {
        guard let userId = currentUser?.id.uuidString else { return }
        let enabled = notifyLiveEnabled
        Task {
            do {
                try await SupabaseManager.shared.client
                    .from("users")
                    .update(["notify_live": enabled])
                    .eq("id", value: userId)
                    .execute()
                print("[AuthViewModel] synced notify_live=\(enabled)")
            } catch {
                print("[AuthViewModel] sync notify_live failed: \(error.localizedDescription)")
            }
        }
    }

    private func syncSportsPreference() {
        guard let userId = currentUser?.id.uuidString else { return }
        let enabled = notifySportsEnabled
        Task {
            do {
                try await SupabaseManager.shared.client
                    .from("users")
                    .update(["notify_sports": enabled])
                    .eq("id", value: userId)
                    .execute()
                print("[AuthViewModel] synced notify_sports=\(enabled)")
            } catch {
                print("[AuthViewModel] sync notify_sports failed: \(error.localizedDescription)")
            }
        }
    }

    private func syncMovieReleasePreference() {
        guard let userId = currentUser?.id.uuidString else { return }
        let enabled = notifyMovieReleasesEnabled
        Task {
            do {
                try await SupabaseManager.shared.client
                    .from("users")
                    .update(["notify_movie_releases": enabled])
                    .eq("id", value: userId)
                    .execute()
                print("[AuthViewModel] synced notify_movie_releases=\(enabled)")
            } catch {
                print("[AuthViewModel] sync notify_movie_releases failed: \(error.localizedDescription)")
            }
        }
    }

    /// Loads all five per-category notification booleans from the shared `users`
    /// row without triggering write-backs. Guests keep their cached local values.
    func loadNotificationCategoryPreferences() async {
        guard let uid = currentUser?.id.uuidString else { return }
        do {
            let rows: [NotificationCategoryRow] = try await SupabaseManager.shared.client
                .from("users")
                .select("notify_new_episodes, notify_watchlist, notify_live, notify_sports, notify_movie_releases")
                .eq("id", value: uid)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else { return }

            isApplyingCategoryPrefs = true
            if let val = row.notify_new_episodes { notifyNewEpisodesEnabled = val; UserDefaults.standard.set(val, forKey: "gs.notifyNewEpisodes") }
            if let val = row.notify_watchlist { notifyWatchlistEnabled = val; UserDefaults.standard.set(val, forKey: "gs.notifyWatchlist") }
            if let val = row.notify_live { notifyLiveEnabled = val; UserDefaults.standard.set(val, forKey: "gs.notifyLive") }
            if let val = row.notify_sports { notifySportsEnabled = val; UserDefaults.standard.set(val, forKey: "gs.notifySports") }
            if let val = row.notify_movie_releases { notifyMovieReleasesEnabled = val; UserDefaults.standard.set(val, forKey: "gs.notifyMovieReleases") }
            isApplyingCategoryPrefs = false
            print("[AuthViewModel] loaded notification category preferences")
        } catch {
            print("[AuthViewModel] loadNotificationCategoryPreferences failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Apple Sign-In (delegated)

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        TVAuthViewModel.shared.prepareAppleRequest(request)
    }

    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
        await TVAuthViewModel.shared.handleAppleCompletion(result)
    }

    func performAppleSignIn(onComplete: @escaping () -> Void) {
        TVAuthViewModel.shared.performAppleSignIn(onComplete: onComplete)
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

    /// Read-only brand-aware check for whether the viewer subscribes to a given
    /// service name. Maps common brand aliases (HBO/Max, Prime/Amazon, etc.) to
    /// the entries stored in `selectedServices`. Does not mutate any state.
    func subscribesToService(named name: String) -> Bool {
        let key = name.lowercased()
        return selectedServices.contains { rawEntry in
            let entry = rawEntry.lowercased()
            if key.contains("netflix") { return entry.contains("netflix") }
            if key.contains("hbo") || key.contains("max") { return entry.contains("max") || entry.contains("hbo") }
            if key.contains("hulu") { return entry.contains("hulu") }
            if key.contains("disney") { return entry.contains("disney") }
            if key.contains("apple") { return entry.contains("apple") }
            if key.contains("prime") || key.contains("amazon") { return entry.contains("amazon") || entry.contains("prime") }
            if key.contains("paramount") { return entry.contains("paramount") }
            if key.contains("peacock") { return entry.contains("peacock") }
            if key.contains("youtube") { return entry.contains("youtube") }
            return entry.contains(key) || key.contains(entry)
        }
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

    /// Google sign-in is not available on tvOS — we route everyone through
    /// Sign in with Apple. Surfaces an inline error so the UI can react.
    func signInWithGoogle() async {
        lastError = "Google sign-in is not available on Apple TV. Use Sign in with Apple instead."
    }
}

// MARK: - NotificationCategoryRow

private struct NotificationCategoryRow: Decodable {
    let notify_new_episodes: Bool?
    let notify_watchlist: Bool?
    let notify_live: Bool?
    let notify_sports: Bool?
    let notify_movie_releases: Bool?
}

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
    /// Raw `users.avatar_url`: a public Storage URL uploaded from a phone,
    /// "preset:<id>", or nil for the initials monogram. Cached locally so the
    /// profile header draws immediately on launch.
    var avatarUrl: String? = UserDefaults.standard.string(forKey: "gs.avatarUrl")
    /// Parsed form of `avatarUrl`, which is what the views render.
    var avatar: UserAvatar? { UserAvatar.parse(avatarUrl) }
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
        await restoreSelectedServices()
    }

    /// Re-hydrates `selectedServices` from `users.services` on cold launch, so
    /// the Apple TV shows the same subscriptions the phone does. Safe only
    /// because `setSelectedServices` now writes that column too — a read
    /// against a column nothing keeps current would revert local picks.
    ///
    /// This is what `subscribedServices` in every `watchmode_resolve` call is
    /// built from (TVTitleSheet), so a stale set here silently sends the wrong
    /// personalisation to the server and the Watch button opens the wrong app.
    ///
    /// An empty or missing row is left alone: a first launch on this Apple TV
    /// before the account has ever saved services must not wipe a local pick.
    func restoreSelectedServices() async {
        guard let uid = currentUser?.id.uuidString else { return }
        do {
            let rows: [TVUserServicesRow] = try await SupabaseManager.shared.client
                .from("users")
                .select("services, avatar_url")
                .eq("id", value: uid)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else { return }
            applyAvatarUrl(row.avatar_url)
            guard let services = row.services, !services.isEmpty else { return }
            selectedServices = Set(services)
            UserDefaults.standard.set(services, forKey: "gs.selectedServices")
            print("[AuthViewModel] restored services (\(services.count))")
        } catch {
            print("[AuthViewModel] restoreSelectedServices failed: \(error.localizedDescription)")
        }
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
                .select("notify_push, notify_new_episodes, notify_watchlist, notify_live, notify_sports, notify_movie_releases")
                .eq("id", value: uid)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else { return }

            // `notify_push` is the user's *intent*, not the tvOS grant. It has
            // to be restored from the server because a delete/reinstall wipes
            // the `gs.notifyPush` UserDefaults cache the toggle reads from,
            // which silently reset the master toggle to off on reinstall.
            if let val = row.notify_push {
                notifyPushEnabled = val
                UserDefaults.standard.set(val, forKey: "gs.notifyPush")
            }
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
        syncSelectedServices()
    }

    // MARK: - Avatar

    /// Applies a raw `users.avatar_url` locally and caches it.
    private func applyAvatarUrl(_ raw: String?) {
        self.avatarUrl = raw
        if let raw, !raw.isEmpty {
            UserDefaults.standard.set(raw, forKey: "gs.avatarUrl")
        } else {
            UserDefaults.standard.removeObject(forKey: "gs.avatarUrl")
        }
    }

    /// Re-reads `users.avatar_url`.
    ///
    /// tvOS is read-only here by design: there is no photo library and no file
    /// picker on this platform, so the avatar is whatever the viewer chose on
    /// their phone. This is how a change made there reaches the TV without
    /// waiting for the next cold launch — `restoreSession` covers launch, this
    /// covers the profile screen being opened.
    func refreshAccountAvatar() async {
        guard let uid = currentUser?.id.uuidString else { return }
        do {
            let rows: [TVUserServicesRow] = try await SupabaseManager.shared.client
                .from("users")
                .select("services, avatar_url")
                .eq("id", value: uid)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else { return }
            applyAvatarUrl(row.avatar_url)
        } catch {
            print("[AuthViewModel] refreshAccountAvatar failed: \(error.localizedDescription)")
        }
    }

    /// Writes the current selection to `users.services` for signed-in accounts,
    /// mirroring the iOS target. Before this, tvOS neither read nor wrote that
    /// column: `selectedServices` was purely local UserDefaults seeded by tvOS
    /// onboarding, so the Apple TV never learned about a service added on the
    /// phone and never told the phone about one added here. Guests are skipped
    /// (`users.id` FKs back to `auth.users`).
    private func syncSelectedServices() {
        guard let userId = currentUser?.id.uuidString else { return }
        let services = Array(selectedServices)
        Task {
            do {
                try await SupabaseManager.shared.client
                    .from("users")
                    .update(["services": services])
                    .eq("id", value: userId)
                    .execute()
                print("[AuthViewModel] synced services (\(services.count))")
            } catch {
                print("[AuthViewModel] sync services failed: \(error.localizedDescription)")
            }
        }
    }

    func setNotificationPreferences(push: Bool, sms: Bool) {
        self.notifyPushEnabled = push
        self.notifySMSEnabled = sms
        UserDefaults.standard.set(push, forKey: "gs.notifyPush")
        UserDefaults.standard.set(sms, forKey: "gs.notifySMS")
        syncPushPreference()
    }

    /// Mirrors the push/SMS intent into `users` for signed-in accounts so it
    /// survives a delete/reinstall. tvOS previously never wrote `notify_push`
    /// to the server at all — not even at onboarding completion — so the value
    /// lived only in UserDefaults. Guests keep the local cache only.
    private func syncPushPreference() {
        guard let userId = currentUser?.id.uuidString else { return }
        let push = notifyPushEnabled
        let sms = notifySMSEnabled
        Task {
            do {
                try await SupabaseManager.shared.client
                    .from("users")
                    .update(["notify_push": push, "notify_sms": sms])
                    .eq("id", value: userId)
                    .execute()
                print("[AuthViewModel] synced notify_push=\(push)")
            } catch {
                print("[AuthViewModel] sync notify_push failed: \(error.localizedDescription)")
            }
        }
    }

    /// Read-only brand-aware check for whether the viewer subscribes to a given
    /// service name. Resolves the incoming name through `Platform.from` to
    /// obtain a catalog_id, applies the hbo/max equivalence, and tests
    /// membership in `selectedServices`. Returns false when the name does not
    /// resolve. Does not mutate any state.
    func subscribesToService(named name: String) -> Bool {
        guard let platform = Platform.from(providerName: name),
              let catalogId = platform.catalogId else { return false }
        let normalized = Platform.normalizeCatalogId(catalogId)
        return selectedServices.contains { Platform.normalizeCatalogId($0) == normalized }
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

private struct TVUserServicesRow: Decodable {
    let services: [String]?
    /// Public Storage URL for an uploaded photo, or "preset:<id>". Optional so
    /// a project without the column still decodes.
    let avatar_url: String?
}

private struct NotificationCategoryRow: Decodable {
    let notify_push: Bool?
    let notify_new_episodes: Bool?
    let notify_watchlist: Bool?
    let notify_live: Bool?
    let notify_sports: Bool?
    let notify_movie_releases: Bool?
}

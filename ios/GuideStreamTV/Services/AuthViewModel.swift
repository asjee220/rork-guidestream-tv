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
    /// Cached phone number (formatted display value) for the user. Lazy-loaded
    /// by `loadDisplayName()` and persisted to `UserDefaults`.
    var phoneNumber: String? = UserDefaults.standard.string(forKey: "gs.phoneNumber")
    /// First name captured from Apple/Google/email signup. Persisted so the
    /// Profile avatar can use first+last initials on cold launch.
    var firstName: String? = UserDefaults.standard.string(forKey: "gs.firstName")
    /// Last name captured from Apple/Google/email signup.
    var lastName: String? = UserDefaults.standard.string(forKey: "gs.lastName")
    var hasCompletedOnboarding: Bool = UserDefaults.standard.bool(forKey: "gs.onboardingComplete")
    var selectedServices: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "gs.selectedServices") ?? [])
    var notifyPushEnabled: Bool = UserDefaults.standard.bool(forKey: "gs.notifyPush")
    var notifySMSEnabled: Bool = UserDefaults.standard.bool(forKey: "gs.notifySMS")
    /// Whether the user wants a push alert when a saved *movie* becomes
    /// available on one of their connected services. Backed by
    /// `users.notify_movie_releases` (defaults true server-side). Changing it
    /// caches locally and upserts to Supabase for the signed-in user.
    var notifyMovieReleasesEnabled: Bool = (UserDefaults.standard.object(forKey: "gs.notifyMovieReleases") as? Bool) ?? true {
        didSet {
            guard !isApplyingMovieReleasePref else { return }
            UserDefaults.standard.set(notifyMovieReleasesEnabled, forKey: "gs.notifyMovieReleases")
            syncMovieReleasePreference()
        }
    }
    /// Guards `notifyMovieReleasesEnabled.didSet` so loading the persisted
    /// value from Supabase doesn't trigger a redundant write-back.
    private var isApplyingMovieReleasePref = false
    /// True after the user has completed at least one successful email sign-up.
    /// First-time visits to the email auth screen show the create-account flow;
    /// every visit afterwards defaults to the sign-in flow.
    var hasUsedEmailAuth: Bool = UserDefaults.standard.bool(forKey: "gs.hasUsedEmailAuth")

    /// True when there is a real Supabase user or the user chose "Get Started Free".
    var isSignedIn: Bool { currentUser != nil || isGuest }
    var isAuthenticated: Bool { currentUser != nil }
    /// Stable string identifier for the current user. Works for both
    /// authenticated users and guests (returns "guest" fallback).
    var currentUserId: String { currentUser?.id.uuidString ?? "guest" }

    private var currentNonce: String?

    /// Bootstrap from any persisted session (Supabase persists in Keychain by default).
    func restoreSession() async {
        do {
            let session = try await SupabaseManager.shared.client.auth.session
            self.currentUser = session.user
            await loadDisplayName()
            // Pick up any guest-era watch list rows and refresh from Supabase
            // so the list is in sync on cold launch.
            Task { await StreamsViewModel.shared.syncLocalToSupabase() }
        } catch {
            self.currentUser = nil
        }
    }

    /// Fetches the `display_name`, `first_name`, `last_name`, and `phone` columns from
    /// the `users` table for the current Supabase user. Silently falls back
    /// to display_name only when the optional columns don't exist on older
    /// installations. After loading, persists any locally-cached phone number
    /// (from a guest session) to the users table.
    func loadDisplayName() async {
        guard let uid = currentUser?.id.uuidString else { return }
        let select = "display_name, first_name, last_name, phone"
        let fallbackSelect = "display_name"
        do {
            let rows: [UserProfileNameRow] = try await SupabaseManager.shared.client
                .from("users")
                .select(select)
                .eq("id", value: uid)
                .limit(1)
                .execute()
                .value
            applyLoadedName(rows.first)
        } catch {
            // Retry with just display_name in case the new columns aren't on
            // this Supabase project yet.
            do {
                let rows: [UserProfileNameRow] = try await SupabaseManager.shared.client
                    .from("users")
                    .select(fallbackSelect)
                    .eq("id", value: uid)
                    .limit(1)
                    .execute()
                    .value
                applyLoadedName(rows.first)
            } catch {
                print("[Auth] loadDisplayName failed: \(error.localizedDescription)")
            }
        }
        // Persist a locally-cached phone number entered during a guest session
        // so it is written to the users table after sign-in.
        if let cachedPhone = UserDefaults.standard.string(forKey: "gs.phoneNumber"), !cachedPhone.isEmpty {
            let _ = await updatePhoneNumber(cachedPhone)
        }
    }

    /// Merges the loaded row into the cached name state and writes it back
    /// to UserDefaults so the next cold launch renders instantly.
    private func applyLoadedName(_ row: UserProfileNameRow?) {
        if let first = row?.first_name, !first.isEmpty {
            self.firstName = first
            UserDefaults.standard.set(first, forKey: "gs.firstName")
        }
        if let last = row?.last_name, !last.isEmpty {
            self.lastName = last
            UserDefaults.standard.set(last, forKey: "gs.lastName")
        }
        if let name = row?.display_name, !name.isEmpty {
            self.displayName = name
            UserDefaults.standard.set(name, forKey: "gs.displayName")
        } else if let composed = composedFullName() {
            self.displayName = composed
            UserDefaults.standard.set(composed, forKey: "gs.displayName")
        }
        if let phone = row?.phone, !phone.isEmpty {
            let display = Self.formatUSPhoneDisplay(phone)
            self.phoneNumber = display
            UserDefaults.standard.set(display, forKey: "gs.phoneNumber")
        }
    }

    /// Builds `"First Last"` from the cached first/last name when available.
    private func composedFullName() -> String? {
        let first = (firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [first, last].filter { !$0.isEmpty }
        let joined = parts.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    /// Updates the user's display name in Supabase and caches it locally.
    /// Also splits the value into first/last so the avatar initials stay
    /// in sync without a separate edit step. Returns `true` on success.
    @discardableResult
    func updateDisplayName(_ name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let uid = currentUser?.id.uuidString else {
            return false
        }
        let split = Self.splitName(trimmed)
        let payload = UserProfileUpsert(
            id: uid,
            display_name: trimmed,
            first_name: split.first,
            last_name: split.last,
            avatar_url: nil,
            email: currentUser?.email
        )
        let ok = await runUserUpsert(payload)
        if ok {
            self.displayName = trimmed
            self.firstName = split.first
            self.lastName = split.last
            UserDefaults.standard.set(trimmed, forKey: "gs.displayName")
            UserDefaults.standard.set(split.first ?? "", forKey: "gs.firstName")
            UserDefaults.standard.set(split.last ?? "", forKey: "gs.lastName")
        }
        return ok
    }

    /// Splits a full name into first/last parts. "Mary Anne Smith" → first
    /// "Mary", last "Smith". Single-word names keep `last` nil so the
    /// initials helper can fall back gracefully.
    static func splitName(_ name: String) -> (first: String?, last: String?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, nil) }
        let parts = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if parts.count == 1 { return (parts[0], nil) }
        return (parts.first, parts.last)
    }

    /// Internal upsert helper used by all signup flows. Retries once with
    /// the optional `first_name`/`last_name`/`email` columns dropped if the
    /// table doesn't yet have them, so older Supabase projects still work.
    @discardableResult
    private func runUserUpsert(_ payload: UserProfileUpsert) async -> Bool {
        do {
            try await SupabaseManager.shared.client
                .from("users")
                .upsert(payload, onConflict: "id")
                .execute()
            return true
        } catch {
            let msg = error.localizedDescription.lowercased()
            // Strip optional fields one at a time and retry.
            if msg.contains("first_name") || msg.contains("last_name") || msg.contains("email") {
                let stripped = UserProfileUpsert(
                    id: payload.id,
                    display_name: payload.display_name,
                    first_name: nil,
                    last_name: nil,
                    avatar_url: payload.avatar_url,
                    email: nil
                )
                do {
                    try await SupabaseManager.shared.client
                        .from("users")
                        .upsert(stripped, onConflict: "id")
                        .execute()
                    return true
                } catch {
                    self.lastError = error.localizedDescription
                    print("[Auth ERROR] users upsert (minimal) failed: \(error.localizedDescription)")
                    return false
                }
            }
            self.lastError = error.localizedDescription
            print("[Auth ERROR] users upsert failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Timezone

    /// Captures the device's IANA timezone (e.g. "America/New_York") and
    /// syncs it to Supabase so episode notifications can be scheduled in the
    /// user's local time. Signed-in users write to `users.timezone`; guests
    /// write to `device_sessions.timezone` keyed on the stable device id.
    /// Called on app launch, after every successful sign-in, and after
    /// onboarding completes.
    func setUserTimezone() {
        let tz = TimeZone.current.identifier
        if let userId = currentUser?.id.uuidString {
            Task {
                do {
                    try await SupabaseManager.shared.client
                        .from("users")
                        .update(["timezone": tz])
                        .eq("id", value: userId)
                        .execute()
                    print("[Auth] timezone \(tz) saved for user \(userId)")
                } catch {
                    print("[Auth ERROR] users timezone update failed: \(error.localizedDescription)")
                }
            }
        } else {
            let deviceId = DeviceIdentity.shared.deviceId
            Task {
                do {
                    try await SupabaseManager.shared.client
                        .from("device_sessions")
                        .upsert(["device_id": deviceId, "timezone": tz], onConflict: "device_id")
                        .execute()
                    print("[Auth] timezone \(tz) saved for device \(deviceId)")
                } catch {
                    print("[Auth ERROR] device_sessions timezone upsert failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Upserts the movie-release notification preference to
    /// `users.notify_movie_releases` for the signed-in user. Guests have no
    /// `users` row (it FKs `auth.users`), so this is a no-op for them — their
    /// choice stays cached locally until they sign in.
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
                print("[Auth] notify_movie_releases \(enabled) saved for user \(userId)")
            } catch {
                print("[Auth ERROR] notify_movie_releases update failed: \(error.localizedDescription)")
            }
        }
    }

    /// Loads `users.notify_movie_releases` into `notifyMovieReleasesEnabled`
    /// for the signed-in user without re-triggering the upsert. Guests keep
    /// their locally-cached value.
    func loadMovieReleasePreference() async {
        guard let uid = currentUser?.id.uuidString else { return }
        do {
            let rows: [UserMovieReleaseRow] = try await SupabaseManager.shared.client
                .from("users")
                .select("notify_movie_releases")
                .eq("id", value: uid)
                .limit(1)
                .execute()
                .value
            if let value = rows.first?.notify_movie_releases {
                isApplyingMovieReleasePref = true
                notifyMovieReleasesEnabled = value
                isApplyingMovieReleasePref = false
                UserDefaults.standard.set(value, forKey: "gs.notifyMovieReleases")
            }
        } catch {
            // Column may be missing on older projects — keep the cached value.
            print("[Auth] loadMovieReleasePreference failed: \(error.localizedDescription)")
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
                await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }

                // Apple only returns fullName on the very first sign-in; cache
                // it locally so it survives the next launch.
                let firstApple = credential.fullName?.givenName
                let lastApple = credential.fullName?.familyName
                let appleName = Self.composeName(credential.fullName)
                if let firstApple, !firstApple.isEmpty {
                    self.firstName = firstApple
                    UserDefaults.standard.set(firstApple, forKey: "gs.firstName")
                }
                if let lastApple, !lastApple.isEmpty {
                    self.lastName = lastApple
                    UserDefaults.standard.set(lastApple, forKey: "gs.lastName")
                }
                await upsertProfile(
                    userId: session.user.id.uuidString,
                    displayName: appleName,
                    firstName: firstApple ?? self.firstName,
                    lastName: lastApple ?? self.lastName,
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
                        "has_email": (credential.email ?? session.user.email) != nil,
                        "has_name": appleName != nil
                    ]
                )
                DeviceSessionService.shared.upsert(reason: "apple_signed_in")
                setUserTimezone()
                // Promote any guest-era watch list rows and push token to the new user.
                Task { await StreamsViewModel.shared.syncLocalToSupabase() }
                Task { await PushTokenManager.shared.resaveCachedToken() }
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

        // Capture the device timezone now that onboarding is done — writes to
        // `users.timezone` for signed-in users, `device_sessions.timezone`
        // for guests.
        setUserTimezone()

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

        // ── In-memory state ───────────────────────────────────────────
        self.currentUser = nil
        self.isGuest = false
        self.displayName = nil
        self.phoneNumber = nil
        self.firstName = nil
        self.lastName = nil
        self.hasCompletedOnboarding = false
        self.selectedServices = []
        self.notifyPushEnabled = false
        self.notifySMSEnabled = false
        self.hasUsedEmailAuth = false

        // ── UserDefaults — remove every user-scoped key so the next
        //    sign-in starts completely fresh. ─────────────────────────
        for key in [
            "gs.isGuest",
            "gs.displayName",
            "gs.phoneNumber",
            "gs.firstName",
            "gs.lastName",
            "gs.onboardingComplete",
            "gs.selectedServices",
            "gs.notifyPush",
            "gs.notifySMS",
            "gs.hasUsedEmailAuth"
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }

        // ── Dependent services — wipe their local caches so the next
        //    user doesn't inherit the previous user's watchlist, likes,
        //    stats, or profiles. ──────────────────────────────────────
        StreamsViewModel.shared.clearLocalCache()
        SocialViewModel.shared.clearLocalCache()
        ProfileStatsService.shared.clearCache()
        AppProfileManager.shared.clearAll()

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

    /// Create a new account with email + password. Captures the user's
    /// first and last name so the Profile avatar can show real initials
    /// (matching what Apple/Google provide automatically). Sends a confirmation
    /// email when the project has "Confirm email" turned on; in that case
    /// `session` is nil and the caller should surface a "check your inbox"
    /// message. Returns `true` when a session was issued and the user is
    /// fully signed in, `false` when email confirmation is pending.
    @discardableResult
    func signUpWithEmail(email: String, password: String, firstName: String, lastName: String) async -> Bool {
        isAuthenticating = true
        lastError = nil
        lastInfo = nil
        defer { isAuthenticating = false }
        let trimmedFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLast = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let composedName: String? = {
            let parts = [trimmedFirst, trimmedLast].filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        }()
        // Persist locally so even before the Supabase round-trip, the
        // initials line up — and so guests who land here get name caching.
        if !trimmedFirst.isEmpty {
            self.firstName = trimmedFirst
            UserDefaults.standard.set(trimmedFirst, forKey: "gs.firstName")
        }
        if !trimmedLast.isEmpty {
            self.lastName = trimmedLast
            UserDefaults.standard.set(trimmedLast, forKey: "gs.lastName")
        }
        if let composedName {
            self.displayName = composedName
            UserDefaults.standard.set(composedName, forKey: "gs.displayName")
        }
        do {
            let response = try await SupabaseManager.shared.client.auth.signUp(
                email: email,
                password: password,
                redirectTo: URL(string: "guidestream://auth-callback")
            )
            UserDefaults.standard.set(true, forKey: "gs.hasUsedEmailAuth")
            self.hasUsedEmailAuth = true
            if let session = response.session {
                self.currentUser = session.user
                self.isGuest = false
                UserDefaults.standard.set(false, forKey: "gs.isGuest")
                await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
                await upsertProfile(
                    userId: session.user.id.uuidString,
                    displayName: composedName,
                    firstName: trimmedFirst.isEmpty ? nil : trimmedFirst,
                    lastName: trimmedLast.isEmpty ? nil : trimmedLast,
                    email: session.user.email
                )
                await loadDisplayName()
                WatchIntentLogger.shared.log(
                    eventType: .authSignedIn,
                    metadata: [
                        "provider": "email",
                        "flow": "sign_up",
                        "user_id": session.user.id.uuidString,
                        "has_name": composedName != nil
                    ]
                )
                DeviceSessionService.shared.upsert(reason: "email_signed_up")
                setUserTimezone()
                Task { await StreamsViewModel.shared.syncLocalToSupabase() }
                Task { await PushTokenManager.shared.resaveCachedToken() }
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
                    // Existing account — also push the freshly-captured name
                    // up so users who created the row before this column
                    // change still get their initials.
                    if let uid = currentUser?.id.uuidString {
                        await upsertProfile(
                            userId: uid,
                            displayName: composedName,
                            firstName: trimmedFirst.isEmpty ? nil : trimmedFirst,
                            lastName: trimmedLast.isEmpty ? nil : trimmedLast,
                            email: currentUser?.email
                        )
                    }
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
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            UserDefaults.standard.set(true, forKey: "gs.hasUsedEmailAuth")
            self.hasUsedEmailAuth = true
            await upsertProfile(
                userId: session.user.id.uuidString,
                displayName: nil,
                firstName: nil,
                lastName: nil,
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
            setUserTimezone()
            Task { await StreamsViewModel.shared.syncLocalToSupabase() }
            Task { await PushTokenManager.shared.resaveCachedToken() }
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
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }

            // Pull first/last name out of Google's `user_metadata` (Supabase
            // forwards the OAuth profile fields). Google supplies
            // `given_name` / `family_name`, with `name` as the joined form.
            let (googleFirst, googleLast, googleFull) = Self.extractGoogleName(from: session.user)
            if let googleFirst, !googleFirst.isEmpty {
                self.firstName = googleFirst
                UserDefaults.standard.set(googleFirst, forKey: "gs.firstName")
            }
            if let googleLast, !googleLast.isEmpty {
                self.lastName = googleLast
                UserDefaults.standard.set(googleLast, forKey: "gs.lastName")
            }
            if let googleFull, !googleFull.isEmpty {
                self.displayName = googleFull
                UserDefaults.standard.set(googleFull, forKey: "gs.displayName")
            }

            await upsertProfile(
                userId: session.user.id.uuidString,
                displayName: googleFull,
                firstName: googleFirst,
                lastName: googleLast,
                email: session.user.email
            )
            await loadDisplayName()
            WatchIntentLogger.shared.log(
                eventType: .authSignedIn,
                metadata: [
                    "provider": "google",
                    "user_id": session.user.id.uuidString,
                    "has_email": session.user.email != nil,
                    "has_name": googleFull != nil
                ]
            )
            DeviceSessionService.shared.upsert(reason: "google_signed_in")
            setUserTimezone()
            Task { await StreamsViewModel.shared.syncLocalToSupabase() }
            Task { await PushTokenManager.shared.resaveCachedToken() }
        } catch {
            lastError = error.localizedDescription
            print("[Auth ERROR] Google sign-in failed: \(error.localizedDescription)")
        }
    }

    /// Best-effort extraction of given/family/full names from Supabase's
    /// `User.userMetadata` dictionary. Google's OIDC payload typically
    /// contains `given_name`, `family_name`, and `name`. Returns nil for
    /// any field that isn't present.
    private static func extractGoogleName(from user: Supabase.User) -> (first: String?, last: String?, full: String?) {
        let meta = user.userMetadata
        func lookup(_ key: String) -> String? {
            guard let value = meta[key] else { return nil }
            // user_metadata values come through as AnyJSON. Pull the string
            // case out; ignore everything else.
            if case .string(let s) = value {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            return nil
        }
        let first = lookup("given_name") ?? lookup("first_name")
        let last = lookup("family_name") ?? lookup("last_name")
        let full: String? = {
            if let direct = lookup("name") ?? lookup("full_name") { return direct }
            let parts = [first, last].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        }()
        return (first, last, full)
    }

    private func upsertProfile(
        userId: String,
        displayName: String?,
        firstName: String?,
        lastName: String?,
        email: String?
    ) async {
        let payload = UserProfileUpsert(
            id: userId,
            display_name: displayName,
            first_name: firstName,
            last_name: lastName,
            avatar_url: nil,
            email: email
        )
        let ok = await runUserUpsert(payload)
        if ok {
            print("[Auth] users row upserted for \(userId)")
        }
    }

    // MARK: - Phone

    /// Validates and normalises a raw US phone string to canonical E.164
    /// (`+1XXXXXXXXXX`). Returns `nil` when the input cannot form a valid
    /// 10-digit North American number. Enforces NANP numbering rules:
    /// area-code and exchange first digits must each be 2–9.
    static func normalizeUSPhone(_ raw: String) -> String? {
        let digits = raw.filter { $0.isNumber }
        var cleaned: String
        if digits.count == 11, digits.hasPrefix("1") {
            cleaned = String(digits.dropFirst())
        } else {
            cleaned = digits
        }
        guard cleaned.count == 10 else { return nil }
        // Area-code first digit (index 0) must be 2–9.
        guard let aFirst = Int(String(cleaned[cleaned.startIndex])), (2...9).contains(aFirst) else { return nil }
        // Exchange first digit (index 3) must be 2–9.
        let exIdx = cleaned.index(cleaned.startIndex, offsetBy: 3)
        guard let eFirst = Int(String(cleaned[exIdx])), (2...9).contains(eFirst) else { return nil }
        return "+1\(cleaned)"
    }

    /// Formats a raw phone string into a progressive `(XXX) XXX-XXXX` display
    /// value suitable for live typing. Strips non-digits, drops a leading `1`
    /// when 11 digits, and caps at 10 digits.
    static func formatUSPhoneDisplay(_ raw: String) -> String {
        let digits = raw.filter { $0.isNumber }
        let cleaned: String = {
            if digits.count == 11, digits.hasPrefix("1") {
                return String(digits.dropFirst())
            }
            return digits
        }()
        let capped = String(cleaned.prefix(10))
        var result = ""
        for (i, ch) in capped.enumerated() {
            if i == 0 { result += "(" }
            result.append(ch)
            if i == 2 { result += ") " }
            if i == 5 { result += "-" }
        }
        return result
    }

    /// Validates, caches, and persists a US phone number. Returns `true` on
    /// success (including guest mode where only local caching happens).
    @discardableResult
    func updatePhoneNumber(_ raw: String) async -> Bool {
        guard let e164 = Self.normalizeUSPhone(raw) else { return false }
        self.notifySMSEnabled = true
        let display = Self.formatUSPhoneDisplay(raw)
        self.phoneNumber = display
        UserDefaults.standard.set(display, forKey: "gs.phoneNumber")
        // Persist to Supabase for authenticated users.
        if let uid = currentUser?.id.uuidString {
            let payload = PhoneUpsert(
                id: uid,
                phone: e164,
                sms_consent_at: ISO8601DateFormatter().string(from: Date()),
                notify_sms: true
            )
            do {
                try await SupabaseManager.shared.client
                    .from("users")
                    .upsert(payload, onConflict: "id")
                    .execute()
                return true
            } catch {
                print("[Auth] phone upsert failed: \(error.localizedDescription)")
                return false
            }
        }
        // Guest — cached locally, considered success.
        return true
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

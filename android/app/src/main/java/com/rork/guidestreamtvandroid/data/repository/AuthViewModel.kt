package com.rork.guidestreamtvandroid.data.repository

import android.content.Context
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rork.guidestreamtvandroid.data.local.DeviceIdentity
import com.rork.guidestreamtvandroid.data.local.DeviceSessionService
import com.rork.guidestreamtvandroid.data.remote.GoogleCredentialSignIn
import com.rork.guidestreamtvandroid.data.remote.SupabaseManager
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.Google
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.auth.providers.builtin.IDToken
import io.github.jan.supabase.auth.user.UserInfo
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.util.TimeZone

/**
 * Auth view model — mirrors iOS AuthViewModel.swift.
 * Handles session restore, Google/email sign-in, guest mode,
 * onboarding prefs, display name caching, timezone sync, sign-out.
 */
class AuthViewModel private constructor(private val context: Context) : ViewModel() {

    @Serializable
    data class UserProfileNameRow(
        @SerialName("display_name") val displayName: String? = null,
        @SerialName("first_name") val firstName: String? = null,
        @SerialName("last_name") val lastName: String? = null,
        val phone: String? = null,
    )

    @Serializable
    data class UserProfileUpsert(
        val id: String,
        @SerialName("display_name") val displayName: String? = null,
        @SerialName("first_name") val firstName: String? = null,
        @SerialName("last_name") val lastName: String? = null,
        @SerialName("avatar_url") val avatarUrl: String? = null,
        val email: String? = null,
    )

    @Serializable
    data class OnboardingPrefsUpsert(
        val id: String,
        val services: List<String>,
        @SerialName("notify_push") val notifyPush: Boolean,
        @SerialName("notify_sms") val notifySms: Boolean,
        @SerialName("onboarding_complete") val onboardingComplete: Boolean,
    )

    /**
     * Minimal decoder for re-hydrating onboarding state and notification
     * preferences from the `users` row after sign-in. Every field is nullable
     * so older projects missing columns still decode cleanly.
     */
    @Serializable
    data class OnboardingStateRow(
        @SerialName("onboarding_complete") val onboardingComplete: Boolean? = null,
        val services: List<String>? = null,
        @SerialName("notify_push") val notifyPush: Boolean? = null,
        @SerialName("notify_sms") val notifySms: Boolean? = null,
        @SerialName("notify_new_episodes") val notifyNewEpisodes: Boolean? = null,
        @SerialName("notify_watchlist") val notifyWatchlist: Boolean? = null,
        @SerialName("notify_live") val notifyLive: Boolean? = null,
        @SerialName("notify_sports") val notifySports: Boolean? = null,
        @SerialName("notify_movie_releases") val notifyMovieReleases: Boolean? = null,
    )

    private val prefs = context.getSharedPreferences("gs_prefs", Context.MODE_PRIVATE)

    private val _currentUser = MutableStateFlow<UserInfo?>(null)
    val currentUser: StateFlow<UserInfo?> = _currentUser.asStateFlow()

    private val _isAuthenticating = MutableStateFlow(false)
    val isAuthenticating: StateFlow<Boolean> = _isAuthenticating.asStateFlow()

    private val _lastError = MutableStateFlow<String?>(null)
    val lastError: StateFlow<String?> = _lastError.asStateFlow()

    private val _lastInfo = MutableStateFlow<String?>(null)
    val lastInfo: StateFlow<String?> = _lastInfo.asStateFlow()

    private val _isGuest = MutableStateFlow(prefs.getBoolean("gs.isGuest", false))
    val isGuest: StateFlow<Boolean> = _isGuest.asStateFlow()

    private val _displayName = MutableStateFlow<String?>(prefs.getString("gs.displayName", null))
    val displayName: StateFlow<String?> = _displayName.asStateFlow()

    private val _phoneNumber = MutableStateFlow<String?>(prefs.getString("gs.phoneNumber", null))
    val phoneNumber: StateFlow<String?> = _phoneNumber.asStateFlow()

    private val _firstName = MutableStateFlow<String?>(prefs.getString("gs.firstName", null))
    val firstName: StateFlow<String?> = _firstName.asStateFlow()

    private val _lastName = MutableStateFlow<String?>(prefs.getString("gs.lastName", null))
    val lastName: StateFlow<String?> = _lastName.asStateFlow()

    private val _hasCompletedOnboarding = MutableStateFlow(prefs.getBoolean("gs.onboardingComplete", false))
    val hasCompletedOnboarding: StateFlow<Boolean> = _hasCompletedOnboarding.asStateFlow()

    private val _selectedServices = MutableStateFlow<Set<String>>(
        prefs.getStringSet("gs.selectedServices", emptySet()) ?: emptySet(),
    )
    val selectedServices: StateFlow<Set<String>> = _selectedServices.asStateFlow()

    private val _notifyPushEnabled = MutableStateFlow(prefs.getBoolean("gs.notifyPush", true))
    val notifyPushEnabled: StateFlow<Boolean> = _notifyPushEnabled.asStateFlow()

    private val _notifySMSEnabled = MutableStateFlow(prefs.getBoolean("gs.notifySMS", false))
    val notifySMSEnabled: StateFlow<Boolean> = _notifySMSEnabled.asStateFlow()

    private val _notifyMovieReleasesEnabled = MutableStateFlow(
        prefs.getBoolean("gs.notifyMovieReleases", true),
    )
    val notifyMovieReleasesEnabled: StateFlow<Boolean> = _notifyMovieReleasesEnabled.asStateFlow()

    private val _notifyNewEpisodesEnabled = MutableStateFlow(
        prefs.getBoolean("gs.notifyNewEpisodes", true),
    )
    val notifyNewEpisodesEnabled: StateFlow<Boolean> = _notifyNewEpisodesEnabled.asStateFlow()

    private val _notifyWatchlistEnabled = MutableStateFlow(
        prefs.getBoolean("gs.notifyWatchlist", true),
    )
    val notifyWatchlistEnabled: StateFlow<Boolean> = _notifyWatchlistEnabled.asStateFlow()

    private val _notifyLiveEnabled = MutableStateFlow(prefs.getBoolean("gs.notifyLive", true))
    val notifyLiveEnabled: StateFlow<Boolean> = _notifyLiveEnabled.asStateFlow()

    private val _notifySportsEnabled = MutableStateFlow(prefs.getBoolean("gs.notifySports", true))
    val notifySportsEnabled: StateFlow<Boolean> = _notifySportsEnabled.asStateFlow()

    private val _hasUsedEmailAuth = MutableStateFlow(prefs.getBoolean("gs.hasUsedEmailAuth", false))
    val hasUsedEmailAuth: StateFlow<Boolean> = _hasUsedEmailAuth.asStateFlow()

    private val _sessionRestored = MutableStateFlow(false)
    val sessionRestored: StateFlow<Boolean> = _sessionRestored.asStateFlow()

    /**
     * True when a Supabase recovery callback has imported a session and the
     * app should present the set-new-password screen. Cleared when
     * [UpdatePasswordScreen] is dismissed or the password is updated.
     */
    private val _showPasswordRecovery = MutableStateFlow(false)
    val showPasswordRecovery: StateFlow<Boolean> = _showPasswordRecovery.asStateFlow()

    fun setShowPasswordRecovery(value: Boolean) {
        _showPasswordRecovery.value = value
    }

    fun clearPasswordRecovery() {
        _showPasswordRecovery.value = false
    }

    // ── Convenience StateFlows for UI gating ──────────────────────────

    /** True when there is a real Supabase user or the user chose "Get Started Free". */
    private val _isSignedIn = MutableStateFlow(false)
    val isSignedIn: StateFlow<Boolean> = _isSignedIn.asStateFlow()

    /** True when there is a real Supabase user (not guest). */
    private val _isAuthenticated = MutableStateFlow(false)
    val isAuthenticated: StateFlow<Boolean> = _isAuthenticated.asStateFlow()

    private fun updateSignedInState() {
        _isAuthenticated.value = _currentUser.value != null
        _isSignedIn.value = _currentUser.value != null || _isGuest.value
    }

    val currentUserId: String? get() = _currentUser.value?.id
    val email: String? get() = _currentUser.value?.email

    companion object {
        private const val TAG = "AuthViewModel"

        @Volatile private var instance: AuthViewModel? = null

        fun init(context: Context): AuthViewModel =
            instance ?: synchronized(this) {
                instance ?: AuthViewModel(context.applicationContext).also {
                    instance = it
                    it.updateSignedInState()
                    // Initialize CoachMarkManager so it shares the same prefs
                    CoachMarkManager.init(context)
                }
            }

        fun get(): AuthViewModel =
            instance ?: error("AuthViewModel not initialized")

        /** Validates and normalises a raw US phone string to canonical E.164. */
        fun normalizeUSPhone(raw: String): String? {
            val digits = raw.filter { it.isDigit() }
            val cleaned = if (digits.length == 11 && digits.startsWith("1")) digits.drop(1) else digits
            if (cleaned.length != 10) return null
            val aFirst = cleaned[0].digitToIntOrNull() ?: return null
            if (aFirst < 2 || aFirst > 9) return null
            val eFirst = cleaned[3].digitToIntOrNull() ?: return null
            if (eFirst < 2 || eFirst > 9) return null
            return "+1$cleaned"
        }

        /** Formats a raw phone string into (XXX) XXX-XXXX display. */
        fun formatUSPhoneDisplay(raw: String): String {
            val digits = raw.filter { it.isDigit() }
            val cleaned = if (digits.length == 11 && digits.startsWith("1")) digits.drop(1) else digits
            val capped = cleaned.take(10)
            val result = StringBuilder()
            for ((i, ch) in capped.withIndex()) {
                if (i == 0) result.append("(")
                result.append(ch)
                if (i == 2) result.append(") ")
                if (i == 5) result.append("-")
            }
            return result.toString()
        }
    }

    /** Bootstrap from any persisted session. */
    fun restoreSession() {
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val auth = SupabaseManager.client.auth
                // The SDK loads the persisted session from storage asynchronously.
                // Wait for that to finish before reading it, otherwise a valid
                // email/password session reads back as null on cold launch.
                auth.awaitInitialization()
                val session = auth.currentSessionOrNull()
                if (session != null) {
                    _currentUser.value = session.user
                    // Run the five independent Supabase round-trips concurrently
                    // so cold launch isn't gated on five sequential network calls.
                    // Each job catches its own errors so a single failure stays
                    // non-fatal and never aborts the others.
                    val jobs = listOf(
                        async(Dispatchers.IO) { try { loadDisplayName() } catch (_: Exception) {} },
                        async(Dispatchers.IO) { try { restoreOnboardingState() } catch (_: Exception) {} },
                        // Claim any guest-era rows on this device before the first
                        // fetch so they are attributed to this account.
                        async(Dispatchers.IO) { try { StreamsViewModel.get().claimDeviceRows() } catch (_: Exception) {} },
                        // flushPendingToken and resaveCachedToken stay sequential
                        // inside one shared job, in that order.
                        async(Dispatchers.IO) {
                            try {
                                PushTokenManager.get().flushPendingToken()
                                PushTokenManager.get().resaveCachedToken()
                            } catch (_: Exception) {}
                        },
                        async(Dispatchers.IO) {
                            try {
                                CoachMarkManager.get()
                                    .hydrateFromSupabase(session.user!!.id, session.user!!.email)
                            } catch (_: Exception) {}
                        }
                    )
                    jobs.awaitAll()
                    // Pick up any guest-era watch list rows and refresh from
                    // Supabase so the list is in sync on cold launch. Fires
                    // only after awaitAll() returns so it still follows
                    // claimDeviceRows.
                    launch(Dispatchers.IO) {
                        StreamsViewModel.get().syncLocalToSupabase()
                    }
                }
            } catch (_: Throwable) {
                _currentUser.value = null
            } finally {
                updateSignedInState()
                _sessionRestored.value = true
            }
        }
    }

    suspend fun loadDisplayName() {
        val uid = currentUserId ?: return
        try {
            val rows = SupabaseManager.client.postgrest
                .from("users")
                .select {
                    filter { eq("id", uid) }
                    limit(1)
                }
                .decodeList<UserProfileNameRow>()
            applyLoadedName(rows.firstOrNull())
        } catch (_: Exception) {
            // Fallback — keep cached value
        }
    }

    /**
     * Re-hydrates onboarding completion, connected services, and notification
     * preferences from the `users` row for the signed-in user. Called after
     * every authenticated session so returning users and cross-device sign-ins
     * land straight in the main app with their settings intact. Guests are
     * skipped (no `users` row). Failures leave local state as-is so brand-new
     * users still go through onboarding normally.
     */
    suspend fun restoreOnboardingState() {
        val uid = currentUserId ?: return
        try {
            val rows = SupabaseManager.client.postgrest
                .from("users")
                .select(
                    columns = Columns.raw(
                        "onboarding_complete, services, notify_push, notify_sms, " +
                            "notify_new_episodes, notify_watchlist, notify_live, " +
                            "notify_sports, notify_movie_releases",
                    ),
                ) {
                    filter { eq("id", uid) }
                    limit(1)
                }
                .decodeList<OnboardingStateRow>()
            val row = rows.firstOrNull() ?: return
            val services = row.services ?: emptyList()
            if (row.onboardingComplete == true || services.isNotEmpty()) {
                _hasCompletedOnboarding.value = true
                prefs.edit().putBoolean("gs.onboardingComplete", true).apply()
            }
            // The fetched services value always wins — assign unconditionally
            // (including when empty) so the previous account's selection
            // cannot survive a cross-account sign-in on the same install.
            val serviceSet = services.toSet()
            _selectedServices.value = serviceSet
            prefs.edit().putStringSet("gs.selectedServices", serviceSet).apply()
            row.notifyPush?.let {
                _notifyPushEnabled.value = it
                prefs.edit().putBoolean("gs.notifyPush", it).apply()
            }
            row.notifySms?.let {
                _notifySMSEnabled.value = it
                prefs.edit().putBoolean("gs.notifySMS", it).apply()
            }
            row.notifyNewEpisodes?.let {
                _notifyNewEpisodesEnabled.value = it
                prefs.edit().putBoolean("gs.notifyNewEpisodes", it).apply()
            }
            row.notifyWatchlist?.let {
                _notifyWatchlistEnabled.value = it
                prefs.edit().putBoolean("gs.notifyWatchlist", it).apply()
            }
            row.notifyLive?.let {
                _notifyLiveEnabled.value = it
                prefs.edit().putBoolean("gs.notifyLive", it).apply()
            }
            row.notifySports?.let {
                _notifySportsEnabled.value = it
                prefs.edit().putBoolean("gs.notifySports", it).apply()
            }
            row.notifyMovieReleases?.let {
                _notifyMovieReleasesEnabled.value = it
                prefs.edit().putBoolean("gs.notifyMovieReleases", it).apply()
            }
        } catch (_: Exception) {
            // Columns may be missing on older projects — keep local defaults.
        }
    }

    private fun applyLoadedName(row: UserProfileNameRow?) {
        if (!row?.firstName.isNullOrEmpty()) {
            _firstName.value = row?.firstName
            prefs.edit().putString("gs.firstName", row?.firstName).apply()
        }
        if (!row?.lastName.isNullOrEmpty()) {
            _lastName.value = row?.lastName
            prefs.edit().putString("gs.lastName", row?.lastName).apply()
        }
        if (!row?.displayName.isNullOrEmpty()) {
            _displayName.value = row?.displayName
            prefs.edit().putString("gs.displayName", row?.displayName).apply()
        } else {
            val composed = composedFullName()
            if (composed != null) {
                _displayName.value = composed
                prefs.edit().putString("gs.displayName", composed).apply()
            }
        }
        if (!row?.phone.isNullOrEmpty()) {
            val display = formatUSPhoneDisplay(row?.phone ?: "")
            _phoneNumber.value = display
            prefs.edit().putString("gs.phoneNumber", display).apply()
        }
    }

    private fun composedFullName(): String? {
        val first = (_firstName.value ?: "").trim()
        val last = (_lastName.value ?: "").trim()
        val parts = listOf(first, last).filter { it.isNotEmpty() }
        val joined = parts.joinToString(" ")
        return joined.ifEmpty { null }
    }

    /** Updates display name in Supabase and caches locally. Returns true on success. */
    suspend fun updateDisplayName(name: String): Boolean {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return false
        val uid = currentUserId ?: return false
        val (first, last) = splitName(trimmed)
        val payload = UserProfileUpsert(
            id = uid,
            displayName = trimmed,
            firstName = first,
            lastName = last,
            avatarUrl = null,
            email = email,
        )
        val ok = runUserUpsert(payload)
        if (ok) {
            _displayName.value = trimmed
            _firstName.value = first
            _lastName.value = last
            prefs.edit()
                .putString("gs.displayName", trimmed)
                .putString("gs.firstName", first ?: "")
                .putString("gs.lastName", last ?: "")
                .apply()
        }
        return ok
    }

    private fun splitName(name: String): Pair<String?, String?> {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return null to null
        val parts = trimmed.split(Regex("\\s+"))
        return if (parts.size == 1) parts[0] to null else parts.first() to parts.last()
    }

    private suspend fun runUserUpsert(payload: UserProfileUpsert): Boolean {
        // Serialize manually with buildJsonObject so nil optional fields are
        // omitted from the payload entirely (instead of being emitted as JSON
        // null, which would overwrite the account's existing name fields on
        // every sign-in that passes nil for those values — e.g.
        // signInWithEmail). `id` is always present; the five optional fields
        // are only included when non-null.
        val jsonPayload = buildJsonObject {
            put("id", payload.id)
            payload.displayName?.let { put("display_name", it) }
            payload.firstName?.let { put("first_name", it) }
            payload.lastName?.let { put("last_name", it) }
            payload.avatarUrl?.let { put("avatar_url", it) }
            payload.email?.let { put("email", it) }
        }
        return try {
            SupabaseManager.client.postgrest
                .from("users")
                .upsert(jsonPayload) { onConflict = "id" }
            true
        } catch (e: Exception) {
            val msg = e.message?.lowercase() ?: ""
            if (msg.contains("first_name") || msg.contains("last_name") || msg.contains("email")) {
                try {
                    // Retry with just id + display_name + avatar_url (strip
                    // the three optional columns that may be missing on older
                    // projects).
                    val stripped = buildJsonObject {
                        put("id", payload.id)
                        payload.displayName?.let { put("display_name", it) }
                        payload.avatarUrl?.let { put("avatar_url", it) }
                    }
                    SupabaseManager.client.postgrest
                        .from("users")
                        .upsert(stripped) { onConflict = "id" }
                    true
                } catch (e2: Exception) {
                    _lastError.value = e2.message
                    false
                }
            } else {
                _lastError.value = e.message
                false
            }
        }
    }

    /** Captures device timezone and syncs to Supabase. */
    fun setUserTimezone() {
        val tz = TimeZone.getDefault().id
        val userId = currentUserId
        viewModelScope.launch(Dispatchers.IO) {
            if (userId != null) {
                try {
                    SupabaseManager.client.postgrest
                        .from("users")
                        .update(buildJsonObject { put("timezone", tz) }) {
                            filter { eq("id", userId) }
                        }
                } catch (_: Exception) {}
            } else {
                try {
                    val deviceId = DeviceIdentity.get().deviceId
                    SupabaseManager.client.postgrest
                        .from("device_sessions")
                        .upsert(buildJsonObject {
                            put("device_id", deviceId)
                            put("timezone", tz)
                        }) { onConflict = "device_id" }
                } catch (_: Exception) {}
            }
        }
    }

    // ── Google Sign-In (OAuth via Supabase) ──────────────────────────

    /**
     * Native Google sign-in via the Credential Manager account sheet.
     *
     * Preferred path on Android: the user picks an account already on the
     * device, Google returns an ID token, and that token is exchanged for a
     * Supabase session in-process — no browser hop.
     *
     * Falls back to the browser OAuth flow ([signInWithGoogleBrowser]) when
     * Credential Manager has nothing to offer (no Google account on the
     * device, Play Services missing/outdated, or the token exchange fails).
     * A user-initiated dismissal of the sheet is not an error and simply
     * cancels the attempt.
     *
     * @param context an Activity context — required to present the sheet.
     */
    fun signInWithGoogle(context: Context) {
        _isAuthenticating.value = true
        _lastError.value = null
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val token = GoogleCredentialSignIn.requestIdToken(context)
                Log.i(TAG, "Google ID token obtained; exchanging with Supabase")
                try {
                    SupabaseManager.client.auth.signInWith(IDToken) {
                        this.idToken = token.idToken
                        this.provider = Google
                        this.nonce = token.rawNonce
                    }
                } catch (e: Exception) {
                    // The token itself was fine — Supabase rejected the exchange
                    // (typically the web client ID missing from the provider's
                    // Authorized Client IDs). Surface it; a browser hop would
                    // just mask the misconfiguration.
                    Log.w(TAG, "Supabase ID-token exchange failed", e)
                    _lastError.value = "Google sign-in failed: ${e.message}"
                    _isAuthenticating.value = false
                    return@launch
                }
                // Session is live in-process; reuse the shared post-sign-in
                // path so profile upsert, name extraction, row claiming and
                // analytics behave exactly as they do for the browser flow.
                _isAuthenticating.value = false
                handleOAuthCallback()
            } catch (e: GoogleCredentialSignIn.CancelledException) {
                // User dismissed the sheet — silent, no error banner.
                _isAuthenticating.value = false
            } catch (e: GoogleCredentialSignIn.UnavailableException) {
                Log.w(TAG, "Credential Manager unavailable (${e.cause?.message}); using browser OAuth", e)
                signInWithGoogleBrowser()
            } catch (e: Exception) {
                Log.w(TAG, "Native Google sign-in failed; using browser OAuth", e)
                signInWithGoogleBrowser()
            }
        }
    }

    /**
     * Browser (Custom Tab) OAuth fallback. Returns immediately; the session is
     * imported when the `guidestream://auth-callback` deep link returns and
     * [handleOAuthCallback] runs, so completion is not signalled here.
     */
    private fun signInWithGoogleBrowser() {
        _isAuthenticating.value = true
        _lastError.value = null
        viewModelScope.launch(Dispatchers.IO) {
            try {
                SupabaseManager.client.auth.signInWith(Google)
                _isAuthenticating.value = false
            } catch (e: Exception) {
                _lastError.value = e.message
                _isAuthenticating.value = false
            }
        }
    }

    /**
     * Best-effort extraction of given/family/full names from Supabase's
     * `UserInfo.userMetadata`. Google's OIDC payload typically contains
     * `given_name`, `family_name`, and `name`. Mirrors iOS `extractGoogleName`.
     * Returns nulls for any field that isn't present.
     */
    private fun extractGoogleName(user: UserInfo): Triple<String?, String?, String?> {
        val meta = user.userMetadata
        fun lookup(key: String): String? {
            val value = meta?.get(key) as? JsonPrimitive ?: return null
            if (!value.isString) return null
            val trimmed = value.content.trim()
            return trimmed.ifEmpty { null }
        }
        val first = lookup("given_name") ?: lookup("first_name")
        val last = lookup("family_name") ?: lookup("last_name")
        val full = lookup("name") ?: lookup("full_name")
            ?: listOfNotNull(first, last).joinToString(" ").ifEmpty { null }
        return Triple(first, last, full)
    }

    /** Called after OAuth redirect returns with a session. */
    fun handleOAuthCallback(onComplete: (Boolean) -> Unit = {}) {
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val session = SupabaseManager.client.auth.currentSessionOrNull()
                if (session != null) {
                    val user = session.user
                    _currentUser.value = user
                    _isGuest.value = false
                    prefs.edit().putBoolean("gs.isGuest", false).apply()
                    updateSignedInState()
                    if (user != null) {
                        // Pull first/last name out of Google's user_metadata
                        // (Supabase forwards the OAuth profile fields), matching iOS.
                        val (googleFirst, googleLast, googleFull) = extractGoogleName(user)
                        if (!googleFirst.isNullOrEmpty()) {
                            _firstName.value = googleFirst
                            prefs.edit().putString("gs.firstName", googleFirst).apply()
                        }
                        if (!googleLast.isNullOrEmpty()) {
                            _lastName.value = googleLast
                            prefs.edit().putString("gs.lastName", googleLast).apply()
                        }
                        if (!googleFull.isNullOrEmpty()) {
                            _displayName.value = googleFull
                            prefs.edit().putString("gs.displayName", googleFull).apply()
                        }
                        upsertProfile(
                            userId = user.id,
                            displayName = googleFull,
                            firstName = googleFirst,
                            lastName = googleLast,
                            email = user.email,
                        )
                        WatchIntentLogger.get().log(
                            WatchIntentLogger.IntentEventType.AUTH_SIGNED_IN,
                            metadata = mapOf("provider" to "google", "user_id" to user.id),
                        )
                    }
                    loadDisplayName()
                    restoreOnboardingState()
                    DeviceSessionService.get().upsert("google_signed_in")
                    setUserTimezone()
                    // Claim any guest-era rows on this device before the first
                    // fetch so they are attributed to this account.
                    StreamsViewModel.get().claimDeviceRows()
                    launch { StreamsViewModel.get().syncLocalToSupabase() }
                    if (user != null) {
                        CoachMarkManager.get().hydrateFromSupabase(user.id, user.email)
                    }
                    PushTokenManager.get().resaveCachedToken()
                    onComplete(true)
                } else {
                    onComplete(false)
                }
            } catch (e: Exception) {
                _lastError.value = e.message
                onComplete(false)
            }
        }
    }

    // ── Password recovery (update) ─────────────────────────────

    /**
     * Updates the signed-in user's password via GoTrue `auth.updateUser`.
     * Used by [UpdatePasswordScreen] after a recovery callback imported a
     * session. On success sets `_lastInfo` to a short confirmation and returns
     * true; on failure sets `_lastError` and returns false. Follows the same
     * `isAuthenticating` / `lastError` / `lastInfo` conventions as
     * [sendPasswordReset].
     */
    suspend fun updatePassword(newPassword: String): Boolean {
        _isAuthenticating.value = true
        _lastError.value = null
        _lastInfo.value = null
        return try {
            SupabaseManager.client.auth.updateUser {
                this.password = newPassword
            }
            // Refresh the cached user from the current session so the app
            // lands signed in after the update.
            val session = SupabaseManager.client.auth.currentSessionOrNull()
            if (session != null) {
                _currentUser.value = session.user
                _isGuest.value = false
                prefs.edit().putBoolean("gs.isGuest", false).apply()
                updateSignedInState()
            }
            _lastInfo.value = "Your password has been updated. You're signed in."
            _isAuthenticating.value = false
            true
        } catch (e: Exception) {
            _lastError.value = e.message
            _isAuthenticating.value = false
            false
        }
    }

    // ── Email auth ───────────────────────────────────────────────────

    /** Create a new account with email + password. Returns true when session issued. */
    suspend fun signUpWithEmail(
        email: String,
        password: String,
        firstName: String,
        lastName: String,
    ): Boolean {
        _isAuthenticating.value = true
        _lastError.value = null
        _lastInfo.value = null
        val trimmedFirst = firstName.trim()
        val trimmedLast = lastName.trim()
        val composedName = listOf(trimmedFirst, trimmedLast)
            .filter { it.isNotEmpty() }
            .joinToString(" ")
            .ifEmpty { null }

        if (trimmedFirst.isNotEmpty()) {
            _firstName.value = trimmedFirst
            prefs.edit().putString("gs.firstName", trimmedFirst).apply()
        }
        if (trimmedLast.isNotEmpty()) {
            _lastName.value = trimmedLast
            prefs.edit().putString("gs.lastName", trimmedLast).apply()
        }
        if (composedName != null) {
            _displayName.value = composedName
            prefs.edit().putString("gs.displayName", composedName).apply()
        }

        return try {
            SupabaseManager.client.auth.signUpWith(Email) {
                this.email = email
                this.password = password
                data = buildJsonObject {
                    if (trimmedFirst.isNotEmpty()) put("first_name", trimmedFirst)
                    if (trimmedLast.isNotEmpty()) put("last_name", trimmedLast)
                    if (composedName != null) put("display_name", composedName)
                }
            }
            prefs.edit().putBoolean("gs.hasUsedEmailAuth", true).apply()
            _hasUsedEmailAuth.value = true
            // After signUp, check if a session was issued (email confirmation may be required)
            val session = SupabaseManager.client.auth.currentSessionOrNull()
            if (session != null) {
                val user = session.user
                _currentUser.value = user
                _isGuest.value = false
                prefs.edit().putBoolean("gs.isGuest", false).apply()
                updateSignedInState()
                if (user != null) {
                    upsertProfile(
                        userId = user.id,
                        displayName = composedName,
                        firstName = trimmedFirst.ifEmpty { null },
                        lastName = trimmedLast.ifEmpty { null },
                        email = user.email,
                    )
                    WatchIntentLogger.get().log(
                        WatchIntentLogger.IntentEventType.AUTH_SIGNED_IN,
                        metadata = mapOf(
                            "provider" to "email",
                            "flow" to "sign_up",
                            "user_id" to user.id,
                        ),
                    )
                }
                loadDisplayName()
                restoreOnboardingState()
                DeviceSessionService.get().upsert("email_signed_up")
                setUserTimezone()
                // Claim any guest-era rows on this device before the first
                // fetch so they are attributed to this account.
                StreamsViewModel.get().claimDeviceRows()
                PushTokenManager.get().resaveCachedToken()
                if (user != null) { CoachMarkManager.get().hydrateFromSupabase(user.id) }
                _isAuthenticating.value = false
                true
            } else {
                _lastInfo.value = "Check your inbox to confirm your email, then come back and sign in."
                _isAuthenticating.value = false
                false
            }
        } catch (e: Exception) {
            val message = e.message ?: ""
            if (message.contains("already", ignoreCase = true)) {
                val ok = signInWithEmail(email, password)
                if (ok && composedName != null) {
                    currentUserId?.let { uid ->
                        upsertProfile(
                            userId = uid,
                            displayName = composedName,
                            firstName = trimmedFirst.ifEmpty { null },
                            lastName = trimmedLast.ifEmpty { null },
                            email = email,
                        )
                    }
                    prefs.edit().putBoolean("gs.hasUsedEmailAuth", true).apply()
                    _hasUsedEmailAuth.value = true
                }
                _isAuthenticating.value = false
                ok
            } else {
                _lastError.value = message
                _isAuthenticating.value = false
                false
            }
        }
    }

    /** Sign in an existing user with email + password. */
    suspend fun signInWithEmail(email: String, password: String): Boolean {
        _isAuthenticating.value = true
        _lastError.value = null
        _lastInfo.value = null
        return try {
            SupabaseManager.client.auth.signInWith(Email) {
                this.email = email
                this.password = password
            }
            val session = SupabaseManager.client.auth.currentSessionOrNull()
            _currentUser.value = session?.user
            _isGuest.value = false
            prefs.edit().putBoolean("gs.isGuest", false).apply()
            prefs.edit().putBoolean("gs.hasUsedEmailAuth", true).apply()
            _hasUsedEmailAuth.value = true
            updateSignedInState()
            if (session != null) {
                val user = session.user
                if (user != null) {
                    upsertProfile(
                        userId = user.id,
                        displayName = null,
                        firstName = null,
                        lastName = null,
                        email = user.email,
                    )
                    WatchIntentLogger.get().log(
                        WatchIntentLogger.IntentEventType.AUTH_SIGNED_IN,
                        metadata = mapOf(
                            "provider" to "email",
                            "flow" to "sign_in",
                            "user_id" to user.id,
                        ),
                    )
                }
                loadDisplayName()
                restoreOnboardingState()
                DeviceSessionService.get().upsert("email_signed_in")
                setUserTimezone()
                // Claim any guest-era rows on this device before the first
                // fetch so they are attributed to this account.
                StreamsViewModel.get().claimDeviceRows()
                PushTokenManager.get().resaveCachedToken()
                viewModelScope.launch { StreamsViewModel.get().syncLocalToSupabase() }
                if (user != null) { CoachMarkManager.get().hydrateFromSupabase(user.id) }
            }
            _isAuthenticating.value = false
            session != null
        } catch (e: Exception) {
            val message = e.message ?: ""
            _lastError.value = when {
                message.contains("invalid login credentials", ignoreCase = true) ||
                    message.contains("invalid_grant", ignoreCase = true) ->
                    "That email or password doesn't match. Try again or reset your password."
                message.contains("email not confirmed", ignoreCase = true) ->
                    "Check your inbox to confirm your email before signing in."
                else -> message
            }
            _isAuthenticating.value = false
            false
        }
    }

    /** Send a password-reset email. */
    suspend fun sendPasswordReset(email: String): Boolean {
        _isAuthenticating.value = true
        _lastError.value = null
        _lastInfo.value = null
        return try {
            SupabaseManager.client.auth.resetPasswordForEmail(email, redirectUrl = "guidestream://auth-callback?flow=recovery")
            _lastInfo.value = "If that address is registered, we just sent a recovery link. Check your inbox."
            _isAuthenticating.value = false
            true
        } catch (e: Exception) {
            _lastError.value = e.message
            _isAuthenticating.value = false
            false
        }
    }

    // ── Onboarding persistence ───────────────────────────────────────

    fun setSelectedServices(services: Set<String>) {
        _selectedServices.value = services
        prefs.edit().putStringSet("gs.selectedServices", services).apply()
        DeviceSessionService.get().upsert("services_changed")
    }

    fun setNotificationPreferences(push: Boolean, sms: Boolean) {
        _notifyPushEnabled.value = push
        _notifySMSEnabled.value = sms
        prefs.edit()
            .putBoolean("gs.notifyPush", push)
            .putBoolean("gs.notifySMS", sms)
            .apply()
        DeviceSessionService.get().upsert("notifications_changed")
    }

    // ── Per-category notification preferences ────────────────────────

    /** Master push toggle from the Notifications settings screen. */
    fun setNotifyPushEnabled(enabled: Boolean) {
        _notifyPushEnabled.value = enabled
        persistCategoryPref("gs.notifyPush", "notify_push", enabled)
    }

    fun setNotifyNewEpisodesEnabled(enabled: Boolean) {
        _notifyNewEpisodesEnabled.value = enabled
        persistCategoryPref("gs.notifyNewEpisodes", "notify_new_episodes", enabled)
    }

    fun setNotifyWatchlistEnabled(enabled: Boolean) {
        _notifyWatchlistEnabled.value = enabled
        persistCategoryPref("gs.notifyWatchlist", "notify_watchlist", enabled)
    }

    fun setNotifyLiveEnabled(enabled: Boolean) {
        _notifyLiveEnabled.value = enabled
        persistCategoryPref("gs.notifyLive", "notify_live", enabled)
    }

    fun setNotifySportsEnabled(enabled: Boolean) {
        _notifySportsEnabled.value = enabled
        persistCategoryPref("gs.notifySports", "notify_sports", enabled)
    }

    fun setNotifyMovieReleasesEnabled(enabled: Boolean) {
        _notifyMovieReleasesEnabled.value = enabled
        persistCategoryPref("gs.notifyMovieReleases", "notify_movie_releases", enabled)
    }

    /**
     * Writes a single notification-category preference to SharedPreferences and,
     * for signed-in users, mirrors it to the matching `users` column. Failures
     * are swallowed so a missing column on older projects never blocks the UI —
     * the local value stays authoritative.
     */
    private fun persistCategoryPref(prefKey: String, column: String, enabled: Boolean) {
        prefs.edit().putBoolean(prefKey, enabled).apply()
        DeviceSessionService.get().upsert("notifications_changed")
        val userId = currentUserId ?: return
        viewModelScope.launch(Dispatchers.IO) {
            try {
                SupabaseManager.client.postgrest
                    .from("users")
                    .update(buildJsonObject { put(column, JsonPrimitive(enabled)) }) {
                        filter { eq("id", userId) }
                    }
            } catch (e: Exception) {
                Log.w("Auth", "$column update failed: ${e.message}")
            }
        }
    }

    fun completeOnboarding() {
        _hasCompletedOnboarding.value = true
        prefs.edit().putBoolean("gs.onboardingComplete", true).apply()
        updateSignedInState()

        WatchIntentLogger.get().log(
            WatchIntentLogger.IntentEventType.ONBOARDING_COMPLETED,
            metadata = mapOf(
                "services" to _selectedServices.value.toList(),
                "service_count" to _selectedServices.value.size,
                "notify_push" to _notifyPushEnabled.value,
                "notify_sms" to _notifySMSEnabled.value,
            ),
        )
        DeviceSessionService.get().upsert("onboarding_completed")
        setUserTimezone()

        val userId = currentUserId ?: return
        val prefsPayload = OnboardingPrefsUpsert(
            id = userId,
            services = _selectedServices.value.toList(),
            notifyPush = _notifyPushEnabled.value,
            notifySms = _notifySMSEnabled.value,
            onboardingComplete = true,
        )
        viewModelScope.launch(Dispatchers.IO) {
            try {
                SupabaseManager.client.postgrest
                    .from("users")
                    .upsert(prefsPayload) { onConflict = "id" }
            } catch (_: Exception) {}
        }
    }

    // ── Guest mode ───────────────────────────────────────────────────

    fun continueAsGuest() {
        _isGuest.value = true
        prefs.edit().putBoolean("gs.isGuest", true).apply()
        updateSignedInState()
        WatchIntentLogger.get().log(
            WatchIntentLogger.IntentEventType.GUEST_STARTED,
            metadata = mapOf("first_launch" to DeviceIdentity.get().isFirstLaunch),
        )
        DeviceSessionService.get().upsert("guest_started")
    }

    // ── Sign out ─────────────────────────────────────────────────────

    fun signOut() {
        viewModelScope.launch(Dispatchers.IO) {
            try { PushTokenManager.get().clearToken() } catch (_: Exception) {}
            try { SupabaseManager.client.auth.signOut() } catch (_: Exception) {}

            _currentUser.value = null
            _isGuest.value = false
            _displayName.value = null
            _phoneNumber.value = null
            _firstName.value = null
            _lastName.value = null
            _hasCompletedOnboarding.value = false
            _selectedServices.value = emptySet()
            _notifyPushEnabled.value = false
            _notifySMSEnabled.value = false
            _hasUsedEmailAuth.value = false
            // Reset the five notification category flags to their documented
            // server-side defaults (true) so the previous account's toggles
            // don't carry into the next account and get written onto its
            // users row.
            _notifyNewEpisodesEnabled.value = true
            _notifyWatchlistEnabled.value = true
            _notifyLiveEnabled.value = true
            _notifySportsEnabled.value = true
            _notifyMovieReleasesEnabled.value = true
            updateSignedInState()

            prefs.edit().apply {
                listOf(
                    "gs.isGuest", "gs.displayName", "gs.phoneNumber",
                    "gs.firstName", "gs.lastName", "gs.onboardingComplete",
                    "gs.selectedServices", "gs.notifyPush", "gs.notifySMS",
                    "gs.notifyNewEpisodes", "gs.notifyWatchlist", "gs.notifyLive",
                    "gs.notifySports", "gs.notifyMovieReleases", "gs.hasUsedEmailAuth",
                ).forEach { remove(it) }
            }.apply()

            StreamsViewModel.get().clearLocalCache()
            SocialViewModel.get().clearLocalCache()
            ReleaseReminderService.get().clearLocalCache()
            TeamFavoritesService.get().clearLocalCache()
            CoachMarkManager.get().clearForSignOut()
            DeviceSessionService.get().upsert("signed_out")
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────

    private suspend fun upsertProfile(
        userId: String,
        displayName: String?,
        firstName: String?,
        lastName: String?,
        email: String?,
    ) {
        val payload = UserProfileUpsert(
            id = userId,
            displayName = displayName,
            firstName = firstName,
            lastName = lastName,
            avatarUrl = null,
            email = email,
        )
        runUserUpsert(payload)
    }

    /** Returns true when the user subscribes to the streaming service. */
    fun subscribesToService(name: String): Boolean {
        val key = name.lowercase()
        val owned = _selectedServices.value
        return owned.any { svc ->
            val s = svc.lowercase()
            when {
                key.contains("netflix") -> s.contains("netflix")
                key.contains("hbo") || key.contains("max") -> s.contains("max") || s.contains("hbo")
                key.contains("hulu") -> s.contains("hulu")
                key.contains("disney") -> s.contains("disney")
                key.contains("apple") -> s.contains("apple")
                key.contains("prime") || key.contains("amazon") -> s.contains("amazon") || s.contains("prime")
                key.contains("paramount") -> s.contains("paramount")
                key.contains("peacock") -> s.contains("peacock")
                key.contains("youtube") -> s.contains("youtube")
                else -> s.contains(key) || key.contains(s)
            }
        }
    }
}

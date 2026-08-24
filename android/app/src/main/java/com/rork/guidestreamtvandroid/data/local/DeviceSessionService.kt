package com.rork.guidestreamtvandroid.data.local

import android.content.Context
import android.os.Build
import androidx.core.content.pm.PackageInfoCompat
import com.rork.guidestreamtvandroid.data.remote.SupabaseManager
import com.rork.guidestreamtvandroid.data.repository.WatchIntentLogger
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Upserts a single row per install into `device_sessions` — the guest
 * "profile" equivalent. Mirrors iOS DeviceSessionService.swift.
 */
class DeviceSessionService private constructor(private val context: Context) {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    var lastError: String? = null
        private set
    var lastSuccessAtMs: Long = 0
        private set
    var totalUpserts: Int = 0
        private set
    var totalSuccesses: Int = 0
        private set
    var lastReason: String? = null
        private set

    @Volatile private var coldLaunchCounted = false

    @Volatile private var lastForegroundTouchMs: Long = 0L

    private val prefs by lazy { context.getSharedPreferences("gs_prefs", Context.MODE_PRIVATE) }

    private val sessionCountKey = "gs.sessionCount"
    private val lastBackgroundedAtKey = "gs.lastBackgroundedAt"
    val sessionCount: Int get() = prefs.getInt(sessionCountKey, 0)

    private val deviceModel: String = run {
        val manufacturer = Build.MANUFACTURER?.replaceFirstChar { it.uppercase() } ?: ""
        val model = Build.MODEL ?: ""
        if (model.startsWith(manufacturer, ignoreCase = true)) model else "$manufacturer $model"
    }

    companion object {
        @Volatile private var instance: DeviceSessionService? = null
        fun init(context: Context): DeviceSessionService =
            instance ?: synchronized(this) {
                instance ?: DeviceSessionService(context.applicationContext).also { instance = it }
            }
        fun get(): DeviceSessionService =
            instance ?: error("DeviceSessionService not initialized")
    }

    fun incrementSessionAndUpsert() {
        val next = sessionCount + 1
        prefs.edit().putInt(sessionCountKey, next).apply()
        upsert("session_started")
    }

    /** Record the moment the app enters the background. Read by [handleForeground]
     * on the next return to determine whether enough time has passed to start
     * a new session. */
    fun noteBackgrounded() {
        prefs.edit().putLong(lastBackgroundedAtKey, System.currentTimeMillis()).apply()
    }

    /** Called on every foreground transition (activity start 0→1). The first
     * call in a process is a no-op so the cold-launch increment in
     * [GuideStreamTVApp.onCreate] remains the only initial session count
     * bump. Subsequent calls check the background duration: 30+ minutes
     * starts a new session; under 30 minutes issues a `foreground_touch`
     * upsert at most once every 5 minutes. */
    fun handleForeground() {
        if (!coldLaunchCounted) {
            coldLaunchCounted = true
            return
        }

        val backgroundedAtMs = prefs.getLong(lastBackgroundedAtKey, 0L)
        if (backgroundedAtMs == 0L) return
        prefs.edit().remove(lastBackgroundedAtKey).apply()

        val nowMs = System.currentTimeMillis()
        val elapsedSeconds = (nowMs - backgroundedAtMs) / 1000

        if (elapsedSeconds >= 1800) {
            val next = sessionCount + 1
            prefs.edit().putInt(sessionCountKey, next).apply()
            upsert("session_resumed")
            lastForegroundTouchMs = nowMs
            WatchIntentLogger.get().log(WatchIntentLogger.IntentEventType.APP_OPENED)
        } else {
            val shouldTouch = if (lastForegroundTouchMs > 0L) {
                (nowMs - lastForegroundTouchMs) / 1000 > 300
            } else {
                true
            }
            if (shouldTouch) {
                lastForegroundTouchMs = nowMs
                upsert("foreground_touch")
            }
        }
    }

    fun upsert(reason: String) {
        val payload = makePayload()
        totalUpserts += 1
        lastReason = reason
        scope.launch {
            performUpsert(payload, attempt = 0, reason = reason)
        }
    }

    private suspend fun performUpsert(
        payload: JsonObject,
        attempt: Int,
        reason: String,
    ) {
        try {
            SupabaseManager.client.postgrest
                .from("device_sessions")
                .upsert(payload) {
                    onConflict = "device_id"
                }
            recordSuccess()
        } catch (e: Throwable) {
            if (e is CancellationException) throw e
            val message = e.message ?: "unknown error"
            if (attempt < 1) {
                val trimmed = dropMissingColumns(payload, message)
                if (trimmed != null) {
                    performUpsert(trimmed, attempt + 1, reason)
                    return
                }
            }
            recordError("$reason: $message")
        }
    }

    private fun recordSuccess() {
        totalSuccesses += 1
        lastSuccessAtMs = System.currentTimeMillis()
        lastError = null
    }

    private fun recordError(message: String) {
        lastError = message
    }

    private fun makePayload(): JsonObject {
        val auth = com.rork.guidestreamtvandroid.data.repository.AuthViewModel.get()
        val nowIso = isoUtcNow()
        return buildJsonObject {
            put("device_id", DeviceIdentity.get().deviceId)
            put("is_guest", auth.isGuest.value && !auth.isAuthenticated.value)
            put("is_authenticated", auth.isAuthenticated.value)
            put("services", JsonArray(auth.selectedServices.value.map { JsonPrimitive(it) }))
            put("service_count", auth.selectedServices.value.size)
            put("notify_push", auth.notifyPushEnabled.value)
            put("notify_sms", auth.notifySMSEnabled.value)
            put("notify_new_episodes", auth.notifyNewEpisodesEnabled.value)
            put("notify_watchlist", auth.notifyWatchlistEnabled.value)
            put("notify_live", auth.notifyLiveEnabled.value)
            put("notify_sports", auth.notifySportsEnabled.value)
            put("notify_movie_releases", auth.notifyMovieReleasesEnabled.value)
            put("onboarding_complete", auth.hasCompletedOnboarding.value)
            put("session_count", sessionCount)
            put("last_seen_at", nowIso)
            put("os_version", Build.VERSION.RELEASE)
            put("device_model", deviceModel)
            // Same IANA timezone column iOS writes so session rows carry the
            // device's zone for notification scheduling.
            put("timezone", java.util.TimeZone.getDefault().id)
            // Report the running build so device_sessions rows identify which
            // version each tester is on. On any lookup failure both keys are
            // simply omitted, matching the userId/email pattern below.
            try {
                val info = context.packageManager.getPackageInfo(context.packageName, 0)
                val versionName = info.versionName
                if (!versionName.isNullOrEmpty()) put("app_version", versionName)
                put("build_number", PackageInfoCompat.getLongVersionCode(info).toString())
            } catch (_: Throwable) {
                // Omit app_version and build_number when the lookup fails.
            }
            val userId = auth.currentUserId
            if (userId != null) put("user_id", userId)
            val email = auth.email
            if (!email.isNullOrEmpty()) put("email", email)
        }
    }

    /** ISO-8601 UTC timestamp that works on all API levels (no java.time / desugaring needed). */
    private fun isoUtcNow(): String {
        val formatter = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", java.util.Locale.US)
        formatter.timeZone = java.util.TimeZone.getTimeZone("UTC")
        return formatter.format(java.util.Date())
    }

    private fun dropMissingColumns(
        payload: JsonObject,
        error: String,
    ): JsonObject? {
        val lowered = error.lowercase()
        if (!lowered.contains("column") && !lowered.contains("schema") && !lowered.contains("could not find")) {
            return null
        }
        var didDrop = false
        val trimmed = payload.toMutableMap()
        for (key in payload.keys) {
            if (key == "device_id") continue
            if (lowered.contains(key.lowercase())) {
                trimmed.remove(key)
                didDrop = true
            }
        }
        return if (didDrop) JsonObject(trimmed) else null
    }
}

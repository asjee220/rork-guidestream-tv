package com.rork.guidestreamtvandroid.data.local

import android.content.Context
import android.os.Build
import com.rork.guidestreamtvandroid.data.remote.SupabaseManager
import io.github.jan.supabase.postgrest.postgrest
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

    private val prefs by lazy { context.getSharedPreferences("gs_prefs", Context.MODE_PRIVATE) }

    private val sessionCountKey = "gs.sessionCount"
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
        } catch (e: Exception) {
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
        val nowIso = java.time.Instant.now().toString()
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
            val userId = auth.currentUserId
            if (userId != null) put("user_id", userId)
            val email = auth.email
            if (!email.isNullOrEmpty()) put("email", email)
        }
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

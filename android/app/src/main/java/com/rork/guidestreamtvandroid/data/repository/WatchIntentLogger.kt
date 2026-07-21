package com.rork.guidestreamtvandroid.data.repository

import android.content.Context
import android.util.Log
import com.rork.guidestreamtvandroid.data.local.DeviceIdentity
import com.rork.guidestreamtvandroid.data.remote.SupabaseManager
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Fire-and-forget analytics logger — mirrors iOS WatchIntentLogger.swift.
 * Writes a row to `watch_intent_events` for every meaningful user action,
 * whether the user is signed in or a guest.
 */
class WatchIntentLogger private constructor(context: Context) {

    enum class IntentEventType(val value: String) {
        CARD_TAPPED("card_tapped"),
        DEEPLINK_FIRED("deeplink_fired"),
        NOTIFICATION_OPENED("notification_opened"),
        SEARCH_QUERY("search_query"),
        TRAILER_WATCHED("trailer_watched"),
        TRAILER_SKIPPED("trailer_skipped"),
        STREAM_ADDED("stream_added"),
        STREAM_REMOVED("stream_removed"),
        BINGE_ALERT_OPENED("binge_alert_opened"),
        ASK_STREAM_QUERY("ask_stream_query"),
        PLAY_ON_DEVICE_CHOSEN("play_on_device_chosen"),
        EPISODE_DETAIL_VIEWED("episode_detail_viewed"),
        CONTINUE_WATCHING("continue_watching_tapped"),
        WIDGET_SETUP_TAPPED("widget_setup_tapped"),
        AFFILIATE_LINK_TAPPED("affiliate_link_tapped"),
        SPONSORED_REEL_VIEWED("sponsored_reel_viewed"),
        SPONSORED_REEL_TAPPED("sponsored_reel_tapped"),
        AD_IMPRESSION("ad_impression"),
        TRAILER_VIEWED("trailer_viewed"),
        TRAILER_LIKED("trailer_liked"),
        NOTIFY_RELEASE_TAPPED("notify_release_tapped"),
        COMMENTS_OPENED("comments_opened"),
        MUTE_TOGGLED("mute_toggled"),
        WATCHLIST_ADDED("watchlist_added"),
        WATCHLIST_REMOVED("watchlist_removed"),
        SESSION_STARTED("session_started"),
        AUTH_SIGNED_IN("auth_signed_in"),
        GUEST_STARTED("guest_started"),
        ONBOARDING_COMPLETED("onboarding_completed"),
        SERVICE_SELECTED("service_selected"),
        APP_OPENED("app_opened"),
        WATCHED_TOGGLED("watched_toggled"),
    }

    data class LoggerError(
        val timestampMs: Long,
        val eventType: String,
        val message: String,
    )

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    val recentErrors = mutableListOf<LoggerError>()
    var totalAttempts: Int = 0
        private set
    var totalSuccesses: Int = 0
        private set

    companion object {
        private const val TAG = "WatchIntent"
        private const val MAX_ERRORS = 20

        @Volatile private var instance: WatchIntentLogger? = null
        fun init(context: Context): WatchIntentLogger =
            instance ?: synchronized(this) {
                instance ?: WatchIntentLogger(context.applicationContext).also { instance = it }
            }
        fun get(): WatchIntentLogger =
            instance ?: error("WatchIntentLogger not initialized")
    }

    fun log(
        eventType: IntentEventType,
        titleId: String? = null,
        platformId: String? = null,
        metadata: Map<String, Any?> = emptyMap(),
        watchDurationSeconds: Double? = null,
    ) {
        val auth = AuthViewModel.get()
        val userId = auth.currentUserId
        val isGuest = auth.isGuest.value && userId == null
        val deviceId = DeviceIdentity.get().deviceId
        val environment = DeviceIdentity.get().environment
        val event = eventType.value

        val mergedMeta = metadata.toMutableMap()
        mergedMeta["device_id"] = deviceId
        mergedMeta["environment"] = environment
        mergedMeta["is_guest"] = isGuest
        mergedMeta["is_authenticated"] = userId != null
        if (watchDurationSeconds != null) {
            mergedMeta["watch_duration_seconds"] = watchDurationSeconds
        }

        val metadataJson = toJsonObject(mergedMeta)

        totalAttempts += 1

        scope.launch {
            val payload = buildJsonObject {
                put("event_type", event)
                put("device_id", deviceId)
                put("environment", environment)
                if (userId != null) put("user_id", userId)
                if (titleId != null) put("title_id", titleId)
                if (platformId != null) put("platform_id", platformId)
                put("metadata", metadataJson)
            }
            try {
                SupabaseManager.client.postgrest
                    .from("watch_intent_events")
                    .insert(payload)
                synchronized(recentErrors) { totalSuccesses += 1 }
            } catch (e: Throwable) {
                if (e is CancellationException) throw e
                val message = e.message ?: "unknown"
                val columnIssue = message.contains("device_id", ignoreCase = true) &&
                    (message.contains("column", ignoreCase = true) ||
                        message.contains("schema", ignoreCase = true) ||
                        message.contains("could not find", ignoreCase = true))
                if (columnIssue) {
                    try {
                        val fallback = buildJsonObject {
                            put("event_type", event)
                            put("environment", environment)
                            if (userId != null) put("user_id", userId)
                            if (titleId != null) put("title_id", titleId)
                            if (platformId != null) put("platform_id", platformId)
                            put("metadata", metadataJson)
                        }
                        SupabaseManager.client.postgrest
                            .from("watch_intent_events")
                            .insert(fallback)
                        synchronized(recentErrors) { totalSuccesses += 1 }
                        return@launch
                    } catch (e2: Throwable) {
                        if (e2 is CancellationException) throw e2
                        recordError(event, e2.message ?: "unknown")
                        return@launch
                    }
                }
                recordError(event, message)
            }
        }
    }

    private fun recordError(event: String, message: String) {
        Log.e(TAG, "$event: $message")
        synchronized(recentErrors) {
            recentErrors.add(0, LoggerError(System.currentTimeMillis(), event, message))
            if (recentErrors.size > MAX_ERRORS) {
                recentErrors.subList(MAX_ERRORS, recentErrors.size).clear()
            }
        }
    }

    /**
     * Lowercases and dashes a free-form title into a stable id slug,
     * e.g. "Stranger Things" → "tt-stranger-things".
     */
    fun titleSlug(title: String): String {
        val lower = title.lowercase()
        val slug = lower.map { ch ->
            if (ch.isLetterOrDigit()) ch else '-'
        }.joinToString("")
            .replace("--", "-")
            .trim('-')
        return "tt-$slug"
    }

    private fun toJsonObject(map: Map<String, Any?>): JsonObject = buildJsonObject {
        for ((key, value) in map) {
            when (value) {
                null -> {}
                is String -> put(key, value)
                is Boolean -> put(key, value)
                is Int -> put(key, value)
                is Long -> put(key, value)
                is Double -> put(key, value)
                is Float -> put(key, value.toDouble())
                is List<*> -> put(key, toJsonArray(value))
                is Map<*, *> -> {
                    @Suppress("UNCHECKED_CAST")
                    put(key, toJsonObject(value as Map<String, Any?>))
                }
                else -> put(key, value.toString())
            }
        }
    }

    private fun toJsonArray(list: List<*>): JsonArray = JsonArray(
        list.mapNotNull { item ->
            when (item) {
                is String -> JsonPrimitive(item)
                is Boolean -> JsonPrimitive(item)
                is Int -> JsonPrimitive(item)
                is Long -> JsonPrimitive(item)
                is Double -> JsonPrimitive(item)
                is Map<*, *> -> {
                    @Suppress("UNCHECKED_CAST")
                    toJsonObject(item as Map<String, Any?>)
                }
                is List<*> -> toJsonArray(item)
                else -> null
            }
        },
    )
}

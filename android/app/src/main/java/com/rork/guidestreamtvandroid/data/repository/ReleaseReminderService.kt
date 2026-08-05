package com.rork.guidestreamtvandroid.data.repository

import android.content.Context
import com.rork.guidestreamtvandroid.data.local.DeviceIdentity
import com.rork.guidestreamtvandroid.data.remote.SupabaseManager
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Per-owner "remind me when this lands on streaming" signal stored in the
 * `release_reminders` table. Direct port of iOS ReleaseReminderService.swift:
 * local-first with Supabase write-through, mirroring [SocialViewModel]'s
 * ownership rules — signed-in users own rows via `user_id`, guests via
 * `device_id`. Toggling is idempotent thanks to the table's partial unique
 * index per owner.
 */
class ReleaseReminderService private constructor(context: Context) {

    @Serializable
    private data class ReminderRow(val id: String)

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @Suppress("unused")
    private val prefs = context.getSharedPreferences("gs_prefs", Context.MODE_PRIVATE)

    private val _remindedTitleIds = MutableStateFlow<Set<String>>(emptySet())

    /** Title ids the current owner has an active release reminder for. */
    val remindedTitleIds: StateFlow<Set<String>> = _remindedTitleIds.asStateFlow()

    private val currentUserId: String?
        get() = AuthViewModel.get().currentUserId

    companion object {
        @Volatile private var instance: ReleaseReminderService? = null
        fun init(context: Context): ReleaseReminderService =
            instance ?: synchronized(this) {
                instance ?: ReleaseReminderService(context.applicationContext).also { instance = it }
            }
        fun get(): ReleaseReminderService =
            instance ?: error("ReleaseReminderService not initialized")
    }

    /** True when [titleId] currently has a reminder set for this owner. */
    fun isReminded(titleId: String): Boolean =
        _remindedTitleIds.value.contains(titleId.trim())

    /**
     * Reads `release_reminders` for [titleId] under the current owner rule and
     * inserts or removes the trimmed id from [remindedTitleIds] accordingly.
     * Network failures leave existing local state untouched.
     */
    suspend fun refreshReminded(titleId: String) {
        val trimmed = titleId.trim()
        if (trimmed.isEmpty()) return
        try {
            withContext(Dispatchers.IO) {
                val deviceId = DeviceIdentity.get().deviceId
                val uid = currentUserId
                val rows = SupabaseManager.client.postgrest
                    .from("release_reminders")
                    .select {
                        filter {
                            eq("title_id", trimmed)
                            // Single-ownership: signed-in users match strictly
                            // by user_id; guests match by device_id AND
                            // user_id IS NULL so two accounts on one install
                            // never see each other's reminders.
                            if (uid != null) {
                                eq("user_id", uid)
                            } else {
                                eq("device_id", deviceId)
                                exact("user_id", null)
                            }
                        }
                    }
                    .decodeList<ReminderRow>()
                _remindedTitleIds.value = if (rows.isNotEmpty()) {
                    _remindedTitleIds.value + trimmed
                } else {
                    _remindedTitleIds.value - trimmed
                }
            }
        } catch (e: Throwable) {
            if (e is CancellationException) throw e
            // Never surface a reminder read failure — the local set stands.
        }
    }

    /**
     * Toggles the reminder for [titleId]. Local state flips immediately so the
     * UI reacts on the next frame; the Supabase write is best-effort and never
     * reverts the optimistic flip.
     */
    fun toggleReminder(
        titleId: String,
        tmdbId: Int? = null,
        source: String = "coming_to_streaming_sheet",
    ) {
        val trimmed = titleId.trim()
        if (trimmed.isEmpty()) return

        val wasReminded = _remindedTitleIds.value.contains(trimmed)
        // Optimistic local flip.
        _remindedTitleIds.value = if (wasReminded) {
            _remindedTitleIds.value - trimmed
        } else {
            _remindedTitleIds.value + trimmed
        }

        WatchIntentLogger.get().log(
            WatchIntentLogger.IntentEventType.NOTIFY_RELEASE_TAPPED,
            titleId = trimmed,
            metadata = mapOf("set" to !wasReminded, "source" to source),
        )

        scope.launch {
            val deviceId = DeviceIdentity.get().deviceId
            val uid = currentUserId
            if (wasReminded) {
                removeReminder(trimmed, uid, deviceId)
            } else {
                insertReminder(trimmed, uid, deviceId, tmdbId)
            }
        }
    }

    /**
     * Inserts one `release_reminders` row for this owner. `media_type` is the
     * literal "movie" because the `send_movie_releases` edge function filters
     * reminders with `media_type.eq.movie` or `media_type.is.null` — any other
     * value silently drops the enrollment. A duplicate-key error is success:
     * the partial unique index means the row already exists for this owner.
     */
    private suspend fun insertReminder(
        titleId: String,
        userId: String?,
        deviceId: String,
        tmdbId: Int?,
    ) {
        val payload = buildJsonObject {
            put("title_id", titleId)
            put("device_id", deviceId)
            put("media_type", "movie")
            if (userId != null) put("user_id", userId)
            if (tmdbId != null) put("tmdb_id", tmdbId)
        }
        try {
            SupabaseManager.client.postgrest
                .from("release_reminders")
                .insert(payload)
        } catch (e: Throwable) {
            if (e is CancellationException) throw e
            val msg = e.message?.lowercase() ?: ""
            if (msg.contains("duplicate") || msg.contains("23505")) return
            // Best-effort write — the optimistic local flip is kept.
        }
    }

    private suspend fun removeReminder(
        titleId: String,
        userId: String?,
        deviceId: String,
    ) {
        try {
            SupabaseManager.client.postgrest
                .from("release_reminders")
                .delete {
                    filter {
                        eq("title_id", titleId)
                        if (userId != null) {
                            eq("user_id", userId)
                        } else {
                            eq("device_id", deviceId)
                            exact("user_id", null)
                        }
                    }
                }
        } catch (e: Throwable) {
            if (e is CancellationException) throw e
            // Best-effort write — the optimistic local flip is kept.
        }
    }

    /**
     * Clears all in-memory reminder state. Called from [AuthViewModel.signOut]
     * so the next user starts empty instead of inheriting the previous
     * account's reminders. There is no disk cache.
     */
    fun clearLocalCache() {
        _remindedTitleIds.value = emptySet()
    }
}

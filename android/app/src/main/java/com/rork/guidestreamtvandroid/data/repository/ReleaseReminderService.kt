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
 * Per-owner "remind me" signal stored in the `release_reminders` table.
 * Direct port of iOS ReleaseReminderService.swift: local-first with Supabase
 * write-through, mirroring [SocialViewModel]'s ownership rules — signed-in
 * users own rows via `user_id`, guests via `device_id`. Toggling is idempotent
 * thanks to the table's partial unique indexes
 * (user_id, title_id, reminder_kind) and (device_id, title_id, reminder_kind).
 *
 * Two kinds share the table: [REMINDER_KIND_ARRIVAL] ("remind me when this
 * lands" — the original behavior) and [REMINDER_KIND_DEPARTURE] ("remind me
 * before a saved title leaves").
 */
class ReleaseReminderService private constructor(context: Context) {

    @Serializable
    private data class ReminderRow(val id: String)

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @Suppress("unused")
    private val prefs = context.getSharedPreferences("gs_prefs", Context.MODE_PRIVATE)

    private val _remindedTitleIds = MutableStateFlow<Set<String>>(emptySet())

    /** Title ids the current owner has an active *arrival* reminder for. */
    val remindedTitleIds: StateFlow<Set<String>> = _remindedTitleIds.asStateFlow()

    private val _departureRemindedTitleIds = MutableStateFlow<Set<String>>(emptySet())

    /** Title ids the current owner has an active *departure* reminder for. */
    val departureRemindedTitleIds: StateFlow<Set<String>> = _departureRemindedTitleIds.asStateFlow()

    private val currentUserId: String?
        get() = AuthViewModel.get().currentUserId

    companion object {
        const val REMINDER_KIND_ARRIVAL = "arrival"
        const val REMINDER_KIND_DEPARTURE = "departure"

        @Volatile private var instance: ReleaseReminderService? = null
        fun init(context: Context): ReleaseReminderService =
            instance ?: synchronized(this) {
                instance ?: ReleaseReminderService(context.applicationContext).also { instance = it }
            }
        fun get(): ReleaseReminderService =
            instance ?: error("ReleaseReminderService not initialized")
    }

    /** True when [titleId] currently has an *arrival* reminder for this owner. */
    fun isReminded(titleId: String): Boolean =
        isReminded(titleId, REMINDER_KIND_ARRIVAL)

    /** True when [titleId] currently has a reminder of [reminderKind] for this owner. */
    fun isReminded(titleId: String, reminderKind: String): Boolean =
        setFor(reminderKind).value.contains(titleId.trim())

    private fun setFor(reminderKind: String): MutableStateFlow<Set<String>> =
        if (reminderKind == REMINDER_KIND_DEPARTURE) _departureRemindedTitleIds
        else _remindedTitleIds

    /**
     * Reads `release_reminders` for [titleId] and [reminderKind] under the
     * current owner rule and inserts or removes the trimmed id from the
     * matching set accordingly. Network failures leave existing local state
     * untouched.
     */
    suspend fun refreshReminded(titleId: String, reminderKind: String = REMINDER_KIND_ARRIVAL) {
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
                            eq("reminder_kind", reminderKind)
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
                val set = setFor(reminderKind)
                set.value = if (rows.isNotEmpty()) {
                    set.value + trimmed
                } else {
                    set.value - trimmed
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
        reminderKind: String = REMINDER_KIND_ARRIVAL,
        mediaType: String = "movie",
    ) {
        val trimmed = titleId.trim()
        if (trimmed.isEmpty()) return

        val set = setFor(reminderKind)
        val wasReminded = set.value.contains(trimmed)
        // Optimistic local flip.
        set.value = if (wasReminded) {
            set.value - trimmed
        } else {
            set.value + trimmed
        }

        WatchIntentLogger.get().log(
            WatchIntentLogger.IntentEventType.NOTIFY_RELEASE_TAPPED,
            titleId = trimmed,
            metadata = mapOf(
                "set" to !wasReminded,
                "source" to source,
                "kind" to reminderKind,
            ),
        )

        scope.launch {
            val deviceId = DeviceIdentity.get().deviceId
            val uid = currentUserId
            if (wasReminded) {
                removeReminder(trimmed, uid, deviceId, reminderKind)
            } else {
                insertReminder(trimmed, uid, deviceId, tmdbId, reminderKind, mediaType)
            }
        }
    }

    /**
     * Inserts one `release_reminders` row for this owner with the given
     * `reminder_kind`. For arrival reminders `media_type` stays the literal
     * "movie" because the `send_movie_releases` edge function filters
     * reminders with `media_type.eq.movie` or `media_type.is.null` — any other
     * value silently drops the enrollment. Departure reminders pass the
     * title's real media type. A duplicate-key error is success: the partial
     * unique index means the row already exists for this owner and kind.
     */
    private suspend fun insertReminder(
        titleId: String,
        userId: String?,
        deviceId: String,
        tmdbId: Int?,
        reminderKind: String,
        mediaType: String,
    ) {
        val payload = buildJsonObject {
            put("title_id", titleId)
            put("device_id", deviceId)
            put("media_type", mediaType)
            put("reminder_kind", reminderKind)
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
        reminderKind: String,
    ) {
        try {
            SupabaseManager.client.postgrest
                .from("release_reminders")
                .delete {
                    filter {
                        eq("title_id", titleId)
                        eq("reminder_kind", reminderKind)
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
        _departureRemindedTitleIds.value = emptySet()
    }
}

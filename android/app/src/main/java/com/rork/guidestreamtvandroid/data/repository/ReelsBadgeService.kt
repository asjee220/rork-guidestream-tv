package com.rork.guidestreamtvandroid.data.repository

import android.content.Context
import com.rork.guidestreamtvandroid.data.remote.StreamingUpcomingService
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Unseen-content badge for the Reels tab. Fetches the current
 * streaming_upcoming titles and compares their tmdb_ids against a locally
 * stored "seen" set in SharedPreferences. Works for both signed-in and guest
 * users — no database column or RLS dependency.
 */
class ReelsBadgeService private constructor(private val prefs: android.content.SharedPreferences) {

    private val _hasUnseen = MutableStateFlow(false)
    val hasUnseen: StateFlow<Boolean> = _hasUnseen.asStateFlow()

    private val seenKey = "gs.reelsSeenIds"

    /**
     * Refreshes the badge state. Fetches streaming_upcoming rows and
     * compares against the locally stored seen-id set. Safe to call
     * repeatedly; never throws. Rethrows CancellationException.
     */
    suspend fun refresh() {
        try {
            val rows = StreamingUpcomingService.get().fetchUpcoming() ?: return
            val currentIds = rows.map { it.tmdbId }.toSet()
            val seenIds = loadSeenIds()
            val unseen = currentIds - seenIds
            _hasUnseen.value = unseen.isNotEmpty()
        } catch (e: Throwable) {
            if (e is CancellationException) throw e
            // Network failure — leave existing badge state untouched.
        }
    }

    /**
     * Marks all current upcoming titles as seen. Clears the badge
     * optimistically before persisting the full id set. Rethrows
     * CancellationException.
     */
    suspend fun markSeen() {
        _hasUnseen.value = false
        try {
            val rows = StreamingUpcomingService.get().fetchUpcoming() ?: return
            val currentIds = rows.map { it.tmdbId }.toSet()
            // Merge with existing so older rows that drop off don't re-trigger.
            val merged = loadSeenIds() + currentIds
            saveSeenIds(merged)
        } catch (e: Throwable) {
            if (e is CancellationException) throw e
        }
    }

    // ── Local persistence ─────────────────────────────────────────────

    private fun loadSeenIds(): Set<Int> {
        val arr = prefs.getStringSet(seenKey, emptySet()) ?: emptySet()
        return arr.mapNotNull { it.toIntOrNull() }.toSet()
    }

    private fun saveSeenIds(ids: Set<Int>) {
        prefs.edit().putStringSet(seenKey, ids.map { it.toString() }.toSet()).apply()
    }

    companion object {
        @Volatile private var instance: ReelsBadgeService? = null

        fun init(context: Context): ReelsBadgeService =
            instance ?: synchronized(this) {
                instance ?: ReelsBadgeService(
                    context.getSharedPreferences("gs_prefs", Context.MODE_PRIVATE)
                ).also { instance = it }
            }

        fun get(): ReelsBadgeService =
            instance ?: error("ReelsBadgeService not initialised — call init(context) first")
    }
}

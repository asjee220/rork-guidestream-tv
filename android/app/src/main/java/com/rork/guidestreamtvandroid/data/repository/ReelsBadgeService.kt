package com.rork.guidestreamtvandroid.data.repository

import com.rork.guidestreamtvandroid.data.remote.SupabaseManager
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Unseen-content badge for the Reels tab. Computes whether any streaming
 * upcoming titles appeared since the user last opened Reels. Guest users
 * never see a badge because RLS prevents them from reading their own users
 * row; cold-start users get reels_seen_at stamped on first refresh.
 */
class ReelsBadgeService private constructor() {

    private val _hasUnseen = MutableStateFlow(false)
    val hasUnseen: StateFlow<Boolean> = _hasUnseen.asStateFlow()

    /**
     * Refreshes the badge state. Safe to call repeatedly; never throws.
     * Rethrows CancellationException so coroutine cancellation is honoured.
     */
    suspend fun refresh() {
        val uid = AuthViewModel.get().currentUserId
        if (uid == null) {
            _hasUnseen.value = false
            return
        }

        try {
            val seenAt = SupabaseManager.client.postgrest["users"]
                .select {
                    filter { eq("id", uid) }
                }
                .decodeSingle<ReelsSeenRow>()
                .reelsSeenAt

            if (seenAt == null) {
                stampSeen(uid)
                _hasUnseen.value = false
                return
            }

            val count = countUnseenSince(seenAt)
            _hasUnseen.value = count > 0
        } catch (e: Throwable) {
            if (e is CancellationException) throw e
            _hasUnseen.value = false
        }
    }

    /**
     * Marks Reels as seen. Optimistically clears the badge before the network call.
     * Rethrows CancellationException so coroutine cancellation is honoured.
     */
    suspend fun markSeen() {
        val uid = AuthViewModel.get().currentUserId ?: return
        _hasUnseen.value = false
        try {
            stampSeen(uid)
        } catch (e: Throwable) {
            if (e is CancellationException) throw e
        }
    }

    private suspend fun stampSeen(userId: String) {
        val now = iso8601()
        SupabaseManager.client.postgrest["users"]
            .update({
                set("reels_seen_at", now)
            }) {
                filter { eq("id", userId) }
            }
    }

    private suspend fun countUnseenSince(seenAt: String): Int {
        return try {
            val rows = SupabaseManager.client.postgrest["streaming_upcoming"]
                .select {
                    filter { gt("created_at", seenAt) }
                }
                .decodeList<CreatedAtRow>()
            rows.size
        } catch (e: Throwable) {
            if (e is CancellationException) throw e
            0
        }
    }

    private fun iso8601(): String {
        val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
        fmt.timeZone = TimeZone.getTimeZone("UTC")
        return fmt.format(Date())
    }

    companion object {
        @Volatile private var instance: ReelsBadgeService? = null

        fun get(): ReelsBadgeService = instance ?: synchronized(this) {
            instance ?: ReelsBadgeService().also { instance = it }
        }
    }
}

@Serializable
private data class ReelsSeenRow(
    @SerialName("reels_seen_at") val reelsSeenAt: String? = null,
)

@Serializable
private data class CreatedAtRow(
    @SerialName("created_at") val createdAt: String? = null,
)

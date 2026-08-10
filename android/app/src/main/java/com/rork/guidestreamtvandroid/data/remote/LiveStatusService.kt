package com.rork.guidestreamtvandroid.data.remote

import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Read-only access to the public.live_status table. Returns the current live
 * state for a set of title ids so the Android widget feed can build its live
 * tier. The app never writes to this table — a plain fetch per home load is
 * the correct scope (no Realtime subscription on Android).
 */
class LiveStatusService {

    @Serializable
    data class LiveStatusRow(
        @SerialName("title_id") val titleId: String,
        @SerialName("is_live") val isLive: Boolean = false,
        @SerialName("stream_title") val streamTitle: String? = null,
        @SerialName("category") val category: String? = null,
        @SerialName("viewer_count") val viewerCount: Int? = null,
        @SerialName("started_at") val startedAt: String? = null,
    )

    /**
     * Fetches live_status rows for the given title ids. Returns null on any
     * failure so callers can leave the live tier empty rather than crashing.
     * Rethrows CancellationException so coroutine cancellation propagates.
     */
    suspend fun fetchLiveStatus(titleIds: List<String>): List<LiveStatusRow>? {
        if (titleIds.isEmpty()) return emptyList()
        return try {
            SupabaseManager.client.postgrest["live_status"]
                .select {
                    filter { isIn("title_id", titleIds) }
                }
                .decodeList<LiveStatusRow>()
        } catch (e: Throwable) {
            if (e is CancellationException) throw e
            null
        }
    }

    companion object {
        @Volatile private var instance: LiveStatusService? = null
        fun get(): LiveStatusService = instance ?: synchronized(this) {
            instance ?: LiveStatusService().also { instance = it }
        }
    }
}

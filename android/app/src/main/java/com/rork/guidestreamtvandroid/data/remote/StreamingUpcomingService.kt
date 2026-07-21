package com.rork.guidestreamtvandroid.data.remote

import com.rork.guidestreamtvandroid.data.models.TMDBResult
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Read-only access to the public.streaming_upcoming table (refreshed daily at
 * 04:00 UTC by the refresh_streaming_releases edge function on cron job 14).
 * Feeds the Reels "Coming Soon" tab with titles whose streaming release date
 * lands within the next thirty days. The server guarantees future dates and a
 * non-null poster on every row, so no client-side date or type filtering is
 * applied here. The app never writes to this table.
 */
class StreamingUpcomingService {

    @Serializable
    data class StreamingUpcomingRow(
        @SerialName("tmdb_id") val tmdbId: Int,
        @SerialName("tmdb_type") val tmdbType: String? = null,
        @SerialName("watchmode_id") val watchmodeId: Int? = null,
        @SerialName("title") val title: String? = null,
        @SerialName("poster_url") val posterUrl: String? = null,
        @SerialName("poster_path") val posterPath: String? = null,
        @SerialName("source_id") val sourceId: Int? = null,
        @SerialName("source_name") val sourceName: String? = null,
        @SerialName("is_original") val isOriginal: Boolean? = null,
        @SerialName("source_release_date") val sourceReleaseDate: String? = null,
        @SerialName("popularity") val popularity: Double? = null,
        @SerialName("vote_count") val voteCount: Int? = null,
        @SerialName("vote_average") val voteAverage: Double? = null,
    )

    /**
     * Fetches all upcoming streaming releases ordered by source release date
     * ascending so the soonest release appears first. Returns null on failure
     * so callers can leave the existing tab contents in place rather than
     * clearing them.
     */
    suspend fun fetchUpcoming(): List<StreamingUpcomingRow>? {
        return try {
            SupabaseManager.client.postgrest["streaming_upcoming"]
                .select {
                    order("source_release_date", Order.ASCENDING)
                }
                .decodeList<StreamingUpcomingRow>()
        } catch (e: Throwable) {
            if (e is CancellationException) throw e
            null
        }
    }

    companion object {
        @Volatile private var instance: StreamingUpcomingService? = null
        fun get(): StreamingUpcomingService = instance ?: synchronized(this) {
            instance ?: StreamingUpcomingService().also { instance = it }
        }
    }
}

/**
 * Maps an upcoming streaming row to the shared [TMDBResult] model so the
 * Coming Soon reel can reuse the existing trailer pipeline. Uses
 * [poster_path][StreamingUpcomingService.StreamingUpcomingRow.posterPath]
 * (not the full poster_url) because TMDBResult.posterUrl is a computed getter
 * that builds the CDN URL from posterPath.
 */
fun StreamingUpcomingService.StreamingUpcomingRow.toTMDBResult(): TMDBResult =
    TMDBResult(
        id = tmdbId,
        mediaType = tmdbType,
        name = title,
        title = title,
        posterPath = posterPath,
        voteAverage = voteAverage,
    )

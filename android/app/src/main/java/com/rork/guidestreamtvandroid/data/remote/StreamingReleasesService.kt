package com.rork.guidestreamtvandroid.data.remote

import com.rork.guidestreamtvandroid.data.models.TMDBResult
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Read-only access to the public.streaming_releases table (refreshed daily by
 * the refresh_streaming_releases edge function). Feeds the Home "New This Week"
 * rail with titles that genuinely landed on a subscription streaming service in
 * the last seven days. The app never writes to this table.
 */
class StreamingReleasesService {

    @Serializable
    data class StreamingReleaseRow(
        @SerialName("tmdb_id") val tmdbId: Int,
        @SerialName("tmdb_type") val tmdbType: String? = null,
        @SerialName("title") val title: String? = null,
        @SerialName("poster_path") val posterPath: String? = null,
        @SerialName("poster_url") val posterUrl: String? = null,
        @SerialName("source_name") val sourceName: String? = null,
        @SerialName("is_original") val isOriginal: Boolean? = null,
        @SerialName("popularity") val popularity: Double? = null,
        @SerialName("vote_count") val voteCount: Int? = null,
        @SerialName("vote_average") val voteAverage: Double? = null,
    )

    /**
     * Fetches all streaming releases ordered by popularity (desc). Returns null
     * on failure so callers can leave the existing rail contents in place rather
     * than clearing them.
     */
    suspend fun fetchReleases(): List<StreamingReleaseRow>? {
        return try {
            SupabaseManager.client.postgrest["streaming_releases"]
                .select {
                    order("popularity", Order.DESCENDING)
                }
                .decodeList<StreamingReleaseRow>()
        } catch (e: Throwable) {
            if (e is CancellationException) throw e
            null
        }
    }

    companion object {
        @Volatile private var instance: StreamingReleasesService? = null
        fun get(): StreamingReleasesService = instance ?: synchronized(this) {
            instance ?: StreamingReleasesService().also { instance = it }
        }
    }
}

/**
 * Maps a streaming release row to the shared [TMDBResult] model so the rail can
 * reuse the existing PosterSection composable. Uses [poster_path][StreamingReleasesService.StreamingReleaseRow.posterPath]
 * (not the full poster_url) because TMDBResult.posterUrl is a computed getter
 * that builds the CDN URL from posterPath.
 */
fun StreamingReleasesService.StreamingReleaseRow.toTMDBResult(): TMDBResult =
    TMDBResult(
        id = tmdbId,
        mediaType = tmdbType,
        name = title,
        title = title,
        posterPath = posterPath,
        voteAverage = voteAverage,
    )

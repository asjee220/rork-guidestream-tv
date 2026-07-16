package com.rork.guidestreamtvandroid.data.remote

import com.rork.guidestreamtvandroid.data.models.TMDBResult
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Read-only access to the public.expiring_titles table (refreshed daily by
 * the refresh_expiring_titles edge function). Feeds the Home "Leaving Soon"
 * rail with titles that are genuinely cycling off a streaming service soon.
 * The app never writes to this table.
 */
class ExpiringTitlesService {

    @Serializable
    data class ExpiringTitleRow(
        @SerialName("tmdb_id") val tmdbId: Int,
        @SerialName("tmdb_type") val tmdbType: String? = null,
        @SerialName("title") val title: String? = null,
        @SerialName("poster_path") val posterPath: String? = null,
        @SerialName("poster_url") val posterUrl: String? = null,
        @SerialName("service_name") val serviceName: String? = null,
        @SerialName("leaving_date") val leavingDate: String? = null,
        @SerialName("is_original") val isOriginal: Boolean? = null,
        @SerialName("popularity") val popularity: Double? = null,
        @SerialName("vote_count") val voteCount: Int? = null,
        @SerialName("vote_average") val voteAverage: Double? = null,
    )

    /**
     * Fetches all expiring titles ordered by leaving date (soonest first).
     * Returns null on failure so callers can leave the existing rail contents
     * in place rather than clearing them.
     */
    suspend fun fetchExpiring(): List<ExpiringTitleRow>? {
        return try {
            SupabaseManager.client.postgrest["expiring_titles"]
                .select {
                    order("leaving_date", Order.ASCENDING)
                }
                .decodeList<ExpiringTitleRow>()
        } catch (e: Throwable) {
            if (e is CancellationException) throw e
            null
        }
    }

    companion object {
        @Volatile private var instance: ExpiringTitlesService? = null
        fun get(): ExpiringTitlesService = instance ?: synchronized(this) {
            instance ?: ExpiringTitlesService().also { instance = it }
        }
    }
}

/**
 * Maps an expiring title row to the shared [TMDBResult] model so the rail can
 * reuse the existing PosterSection composable. Uses [poster_path][ExpiringTitlesService.ExpiringTitleRow.posterPath]
 * (not the full poster_url) because TMDBResult.posterUrl is a computed getter
 * that builds the CDN URL from posterPath.
 */
fun ExpiringTitlesService.ExpiringTitleRow.toTMDBResult(): TMDBResult =
    TMDBResult(
        id = tmdbId,
        mediaType = tmdbType,
        name = title,
        title = title,
        posterPath = posterPath,
        voteAverage = voteAverage,
    )

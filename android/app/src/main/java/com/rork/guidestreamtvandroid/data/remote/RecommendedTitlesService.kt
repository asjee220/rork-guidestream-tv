package com.rork.guidestreamtvandroid.data.remote

import com.rork.guidestreamtvandroid.SupabaseConfig
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.contentType
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

/**
 * One recommended title from the `recommend_titles` edge function.
 * Mirrors iOS `RecommendedTitle`.
 */
@Serializable
data class RecommendedTitle(
    @SerialName("tmdb_id") val tmdbId: Int = 0,
    @SerialName("media_type") val mediaType: String = "tv",
    val title: String = "",
    @SerialName("poster_path") val posterPath: String? = null,
    @SerialName("backdrop_path") val backdropPath: String? = null,
    @SerialName("vote_average") val voteAverage: Double? = null,
    @SerialName("match_percentage") val matchPercentage: Int = 0,
) {
    val isTv: Boolean get() = mediaType == "tv"

    /** Full TMDB poster URL at the width the other home rails request. */
    val posterUrl: String?
        get() = posterPath?.takeIf { it.isNotBlank() }?.let { "https://image.tmdb.org/t/p/w500$it" }
}

@Serializable
data class RecommendedTitlesResponse(
    val items: List<RecommendedTitle> = emptyList(),
    val cached: Boolean = false,
    @SerialName("seed_count") val seedCount: Int = 0,
    val reason: String? = null,
)

/**
 * Client for the `recommend_titles` edge function (deployed with
 * verify_jwt=false), which backs the "Recommended for You" home rail.
 * Companion to [RecommendedCreatorsService] and built the same way.
 *
 * The server reads the signals itself — watchlist, likes, watched, release
 * reminders, trailer engagement, browse events, favourite teams, followed
 * creators — so this client sends only identity and the subscribed-service set.
 * It never assembles a taste profile, which is what keeps iOS, tvOS and Android
 * ranking identically.
 *
 * Freshness is the server's job too: it caches per owner against a fingerprint
 * of that owner's signals, so calling this on every Home load is cheap. An
 * unchanged signal set returns the cached rail with no TMDB calls; a title saved
 * a moment ago rebuilds it on the very next call.
 */
object RecommendedTitlesService {

    /** The home rail's size. */
    const val RAIL_LIMIT = 20

    /**
     * @param userId Supabase auth uuid, or null for a guest.
     * @param deviceId Device identifier, used as the owner when signed out.
     * @param subscribedServices The viewer's saved services. The server filters
     *   every recommendation to these, so an empty set legitimately returns an
     *   empty rail rather than titles the viewer cannot watch.
     * @return the ranked titles, or an empty list on any failure — the rail is
     *   additive and must never be able to break Home.
     */
    suspend fun recommend(
        userId: String?,
        deviceId: String,
        subscribedServices: List<String>,
        limit: Int = RAIL_LIMIT,
    ): List<RecommendedTitle> {
        if (subscribedServices.isEmpty()) return emptyList()
        return try {
            val client = HttpClient {
                install(ContentNegotiation) { json(Json { ignoreUnknownKeys = true }) }
            }
            val url = "${SupabaseConfig.URL.trim()}/functions/v1/recommend_titles"
            val body = buildJsonObject {
                if (!userId.isNullOrBlank()) {
                    put("userId", JsonPrimitive(userId))
                } else {
                    put("deviceId", JsonPrimitive(deviceId))
                }
                put("subscribedServices", JsonArray(subscribedServices.map { JsonPrimitive(it) }))
                put("limit", JsonPrimitive(limit))
            }
            val response: HttpResponse = client.post(url) {
                contentType(ContentType.Application.Json)
                header(HttpHeaders.ContentType, "application/json")
                header("apikey", SupabaseConfig.ANON_KEY)
                header(HttpHeaders.Authorization, "Bearer ${SupabaseConfig.ANON_KEY}")
                setBody(body.toString())
            }
            if (response.status.value == 200) {
                response.body<RecommendedTitlesResponse>().items
            } else {
                emptyList()
            }
        } catch (_: Exception) {
            emptyList()
        }
    }
}

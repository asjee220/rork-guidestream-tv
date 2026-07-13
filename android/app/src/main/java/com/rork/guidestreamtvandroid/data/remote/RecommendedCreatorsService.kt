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
 * A single recommended creator/podcast from the `recommend_creators` edge
 * function. Mirrors iOS `RecommendedCreator`.
 */
@Serializable
data class RecommendedCreator(
    @SerialName("title_id") val titleId: String = "",
    @SerialName("display_name") val displayName: String = "",
    @SerialName("image_url") val imageUrl: String? = null,
    @SerialName("source_type") val sourceType: String = "",
    val category: String = "",
    @SerialName("match_percentage") val matchPercentage: Int = 0,
)

/**
 * Envelope for the `recommend_creators` edge function response.
 */
@Serializable
data class RecommendedCreatorsResponse(
    val items: List<RecommendedCreator> = emptyList(),
)

/**
 * Client for the `recommend_creators` edge function (deployed with
 * verify_jwt=false). Given the user's followed non-TMDB title ids, returns a
 * server-ranked list of creators/podcasts to recommend. Uses the same raw Ktor
 * anon-key POST pattern as `WatchmodeResolveService`. The edge function owns the
 * ranking algorithm; the client preserves the returned order.
 */
object RecommendedCreatorsService {

    suspend fun recommend(followedIds: List<String>): List<RecommendedCreator> {
        if (followedIds.isEmpty()) return emptyList()
        return try {
            val client = HttpClient {
                install(ContentNegotiation) { json(Json { ignoreUnknownKeys = true }) }
            }
            val url = "${SupabaseConfig.URL.trim()}/functions/v1/recommend_creators"
            val body = buildJsonObject {
                put("followedIds", JsonArray(followedIds.map { JsonPrimitive(it) }))
            }
            val response: HttpResponse = client.post(url) {
                contentType(ContentType.Application.Json)
                header(HttpHeaders.ContentType, "application/json")
                header("apikey", SupabaseConfig.ANON_KEY)
                header(HttpHeaders.Authorization, "Bearer ${SupabaseConfig.ANON_KEY}")
                setBody(body.toString())
            }
            if (response.status.value == 200) {
                val resp: RecommendedCreatorsResponse = response.body()
                resp.items
            } else {
                emptyList()
            }
        } catch (_: Exception) {
            emptyList()
        }
    }
}

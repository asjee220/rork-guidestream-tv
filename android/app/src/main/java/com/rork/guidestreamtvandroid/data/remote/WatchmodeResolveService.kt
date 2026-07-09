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
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

/**
 * A single US streaming source for a title, from the `watchmode_resolve` edge
 * function. Mirrors iOS `WatchmodeSource`.
 */
@Serializable
data class WatchmodeSrc(
    @SerialName("source_id") val sourceId: Int = 0,
    val name: String = "",
    val type: String = "",
    val region: String? = null,
    @SerialName("web_url") val webUrl: String? = null,
    @SerialName("ios_url") val iosUrl: String? = null,
    @SerialName("tvos_url") val tvosUrl: String? = null,
    @SerialName("roku_url") val rokuUrl: String? = null,
    val format: String? = null,
    @SerialName("end_date") val endDate: String? = null,
)

/**
 * Envelope for the `watchmode_resolve` edge function response.
 */
@Serializable
data class WatchmodeResolveResponse(
    @SerialName("primary_source") val primarySource: WatchmodeSrc? = null,
    @SerialName("us_sources") val usSources: List<WatchmodeSrc> = emptyList(),
    val overview: String? = null,
    @SerialName("provider_name_fallback") val providerNameFallback: String? = null,
    @SerialName("episode_source") val episodeSource: WatchmodeSrc? = null,
)

/**
 * Client for the `watchmode_resolve` edge function (deployed with
 * verify_jwt=false). Resolves a TMDB id to its US streaming sources for the
 * title-scoped Reels switcher. Uses the same raw Ktor anon-key POST pattern as
 * `AskStreamSheet`.
 */
object WatchmodeResolveService {

    suspend fun resolve(tmdbId: Int, isTV: Boolean): List<WatchmodeSrc> {
        return try {
            val client = HttpClient {
                install(ContentNegotiation) { json(Json { ignoreUnknownKeys = true }) }
            }
            val url = "${SupabaseConfig.URL.trim()}/functions/v1/watchmode_resolve"
            val body = buildJsonObject {
                put("tmdbId", JsonPrimitive(tmdbId))
                put("isTV", JsonPrimitive(isTV))
            }
            val response: HttpResponse = client.post(url) {
                contentType(ContentType.Application.Json)
                header(HttpHeaders.ContentType, "application/json")
                header("apikey", SupabaseConfig.ANON_KEY)
                header(HttpHeaders.Authorization, "Bearer ${SupabaseConfig.ANON_KEY}")
                setBody(body.toString())
            }
            if (response.status.value == 200) {
                val resp: WatchmodeResolveResponse = response.body()
                resp.usSources
            } else {
                emptyList()
            }
        } catch (_: Exception) {
            emptyList()
        }
    }
}

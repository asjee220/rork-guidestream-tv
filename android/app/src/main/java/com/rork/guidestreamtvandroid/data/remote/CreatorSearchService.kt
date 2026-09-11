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
 * One creator from the `search_creators` edge function, shaped like a
 * content_sources row so it renders with the same UI as a seeded creator.
 */
@Serializable
data class LiveCreatorResult(
    @SerialName("title_id") val titleId: String = "",
    @SerialName("source_type") val sourceType: String = "",
    @SerialName("display_name") val displayName: String = "",
    val handle: String? = null,
    @SerialName("image_url") val imageUrl: String? = null,
    @SerialName("channel_url") val channelUrl: String? = null,
    val category: String? = null,
    val description: String? = null,
    @SerialName("is_live") val isLive: Boolean = false,
    @SerialName("stream_title") val streamTitle: String? = null,
)

@Serializable
data class LiveCreatorSearchResponse(
    val ok: Boolean = false,
    val results: List<LiveCreatorResult> = emptyList(),
)

/**
 * Live creator search across YouTube, Twitch and podcasts.
 *
 * Android never had this. `SearchViewModel.fetchCreators` only queried
 * content_sources, so searching for any creator that had not already been
 * seeded returned nothing — "joe budden" found zero results on every platform
 * (iOS had the call but pointed it at a Cloudflare Worker that died with Rork).
 * The edge function also persists what it finds, stamped `discovered_at`, so a
 * result can be followed and opened immediately without appearing in the
 * browse or onboarding lists.
 */
object CreatorSearchService {

    /** Returns [] on any failure, so search degrades to local results. */
    suspend fun search(query: String, type: String = "all"): List<LiveCreatorResult> {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return emptyList()
        return try {
            val client = HttpClient {
                install(ContentNegotiation) { json(Json { ignoreUnknownKeys = true }) }
            }
            val url = "${SupabaseConfig.URL.trim()}/functions/v1/search_creators"
            val body = buildJsonObject {
                put("q", JsonPrimitive(trimmed))
                put("type", JsonPrimitive(type))
            }
            val response: HttpResponse = client.post(url) {
                contentType(ContentType.Application.Json)
                header(HttpHeaders.ContentType, "application/json")
                header("apikey", SupabaseConfig.ANON_KEY)
                header(HttpHeaders.Authorization, "Bearer ${SupabaseConfig.ANON_KEY}")
                setBody(body.toString())
            }
            if (response.status.value == 200) {
                val resp: LiveCreatorSearchResponse = response.body()
                if (resp.ok) resp.results else emptyList()
            } else {
                emptyList()
            }
        } catch (_: Exception) {
            emptyList()
        }
    }
}

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
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

/**
 * Envelope for the `trailer_resolve` edge function response.
 */
@Serializable
data class TrailerResolveResponse(
    val ok: Boolean = false,
    val cached: Boolean = false,
    val keys: List<String> = emptyList(),
)

/**
 * Client for the `trailer_resolve` edge function (deployed with
 * verify_jwt=false, so the anon key is sufficient and no user session is
 * needed).
 *
 * TMDB reports which trailer keys exist for a title but never whether a key
 * will actually play (embedding may be owner-disabled, the video private, or
 * region-blocked). This server-side resolver verifies each candidate against
 * the YouTube Data API and returns only keys that are embeddable, public,
 * processed, and not US-blocked, in rank order. Uses the same raw Ktor
 * anon-key POST pattern as [WatchmodeResolveService].
 */
object TrailerResolveService {

    /**
     * Resolves verified playable YouTube trailer keys for a title.
     *
     * The nullable return is load-bearing and the two cases must never be
     * conflated:
     *  * Returns the decoded keys list on HTTP 200 — **including an empty
     *    list**, which means the title has no playable trailer at all (the
     *    caller drops it from the feed).
     *  * Returns null only when the call itself fails (a non-200 status or any
     *    caught exception), so the caller can degrade to the unverified TMDB
     *    key rather than emptying the feed.
     */
    suspend fun resolve(tmdbId: Int, isTV: Boolean): List<String>? {
        return try {
            val client = HttpClient {
                install(ContentNegotiation) { json(Json { ignoreUnknownKeys = true }) }
            }
            val url = "${SupabaseConfig.URL.trim()}/functions/v1/trailer_resolve"
            val body = buildJsonObject {
                put("tmdb_id", JsonPrimitive(tmdbId))
                put("media_type", JsonPrimitive(if (isTV) "tv" else "movie"))
            }
            val response: HttpResponse = client.post(url) {
                contentType(ContentType.Application.Json)
                header(HttpHeaders.ContentType, "application/json")
                header("apikey", SupabaseConfig.ANON_KEY)
                header(HttpHeaders.Authorization, "Bearer ${SupabaseConfig.ANON_KEY}")
                setBody(body.toString())
            }
            if (response.status.value == 200) {
                val resp: TrailerResolveResponse = response.body()
                resp.keys
            } else {
                null
            }
        } catch (_: Exception) {
            null
        }
    }
}

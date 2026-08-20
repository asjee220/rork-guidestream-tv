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
import kotlinx.serialization.json.JsonObject
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
    @SerialName("android_url") val androidUrl: String? = null,
    @SerialName("android_tv_url") val androidTvUrl: String? = null,
    val price: Double? = null,
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
    /** Region codes where the title streams, so a title with no US sources
     *  can read as unavailable instead of an empty row. */
    @SerialName("availability_regions") val availabilityRegions: List<String> = emptyList(),
)

/**
 * Client for the `watchmode_resolve` edge function (deployed with
 * verify_jwt=false). Resolves a TMDB id to its US streaming sources for the
 * title-scoped Reels switcher. Uses the same raw Ktor anon-key POST pattern as
 * `AskStreamSheet`.
 */
object WatchmodeResolveService {

    suspend fun resolve(
        tmdbId: Int,
        isTV: Boolean,
        subscribedServices: List<String> = emptyList(),
        season: Int? = null,
        episode: Int? = null,
        episodePlatformHint: String? = null,
        sourceId: Int? = null,
    ): WatchmodeResolveResponse {
        return try {
            val client = HttpClient {
                install(ContentNegotiation) { json(Json { ignoreUnknownKeys = true }) }
            }
            try {
                val url = "${SupabaseConfig.URL.trim()}/functions/v1/watchmode_resolve"
                val decoded = post(client, url, buildBody(tmdbId, isTV, subscribedServices, season, episode, episodePlatformHint, sourceId))
                    ?: return WatchmodeResolveResponse()
                // A saved movie stored with the wrong media type resolves to
                // no sources at all — retry exactly once with isTV omitted so
                // the server probes TV then movie, and keep the retry only
                // when it found something.
                if (decoded.primarySource == null && decoded.usSources.isEmpty()) {
                    val retried = post(client, url, buildBody(tmdbId, null, subscribedServices, season, episode, episodePlatformHint, sourceId))
                    if (retried != null && (retried.primarySource != null || retried.usSources.isNotEmpty())) {
                        return retried
                    }
                }
                decoded
            } finally {
                client.close()
            }
        } catch (_: Exception) {
            WatchmodeResolveResponse()
        }
    }

    /**
     * Builds the request body, omitting null parameters rather than sending
     * nulls; a null [isTV] is omitted so the server probes both media types.
     */
    private fun buildBody(
        tmdbId: Int,
        isTV: Boolean?,
        subscribedServices: List<String>,
        season: Int?,
        episode: Int?,
        episodePlatformHint: String?,
        sourceId: Int?,
    ) = buildJsonObject {
        put("tmdbId", JsonPrimitive(tmdbId))
        if (isTV != null) put("isTV", JsonPrimitive(isTV))
        put("subscribedServices", JsonArray(subscribedServices.map { JsonPrimitive(it) }))
        if (season != null) put("season", JsonPrimitive(season))
        if (episode != null) put("episode", JsonPrimitive(episode))
        if (episodePlatformHint != null) put("episodePlatformHint", JsonPrimitive(episodePlatformHint))
        if (sourceId != null) put("sourceId", JsonPrimitive(sourceId))
    }

    /**
     * Single POST + decode. Returns null on transport failure, non-200
     * status, or decode failure so the caller never retries those.
     */
    private suspend fun post(client: HttpClient, url: String, payload: JsonObject): WatchmodeResolveResponse? {
        return try {
            val response: HttpResponse = client.post(url) {
                contentType(ContentType.Application.Json)
                header(HttpHeaders.ContentType, "application/json")
                header("apikey", SupabaseConfig.ANON_KEY)
                header(HttpHeaders.Authorization, "Bearer ${SupabaseConfig.ANON_KEY}")
                setBody(payload.toString())
            }
            if (response.status.value == 200) response.body() else null
        } catch (_: Exception) {
            null
        }
    }
}

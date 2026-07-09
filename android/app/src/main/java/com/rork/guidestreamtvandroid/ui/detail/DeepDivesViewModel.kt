package com.rork.guidestreamtvandroid.ui.detail

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rork.guidestreamtvandroid.SupabaseConfig
import com.rork.guidestreamtvandroid.data.models.DeepDiveCreator
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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

/**
 * Fetches YouTube creator channels that publish deep-dive / analysis content
 * about a show via the `youtube_show_creators` edge function. Mirrors iOS
 * `DeepDivesViewModel`. De-dupes on tmdb_id + media_type so the same title is
 * never re-fetched.
 */
class DeepDivesViewModel : ViewModel() {

    private val _creators = MutableStateFlow<List<DeepDiveCreator>>(emptyList())
    val creators: StateFlow<List<DeepDiveCreator>> = _creators.asStateFlow()

    private var loadedKey: String? = null

    @Serializable
    private data class DeepDivesResponse(
        val ok: Boolean = false,
        val cached: Boolean? = null,
        val creators: List<DeepDiveCreator>? = null,
    )

    fun load(tmdbId: Int, mediaType: String, showTitle: String) {
        val key = "$tmdbId-$mediaType"
        if (loadedKey == key || showTitle.isBlank()) return
        loadedKey = key
        // Clear stale creators from a previous title while the new one loads.
        _creators.value = emptyList()
        viewModelScope.launch(Dispatchers.IO) {
            _creators.value = fetch(tmdbId, mediaType, showTitle)
        }
    }

    private suspend fun fetch(tmdbId: Int, mediaType: String, showTitle: String): List<DeepDiveCreator> {
        return try {
            val client = HttpClient {
                install(ContentNegotiation) { json(Json { ignoreUnknownKeys = true }) }
            }
            val url = "${SupabaseConfig.URL.trim()}/functions/v1/youtube_show_creators"
            val body = buildJsonObject {
                put("tmdb_id", JsonPrimitive(tmdbId.toString()))
                put("media_type", JsonPrimitive(mediaType))
                put("show_title", JsonPrimitive(showTitle))
            }
            val response: HttpResponse = client.post(url) {
                contentType(ContentType.Application.Json)
                header(HttpHeaders.ContentType, "application/json")
                header("apikey", SupabaseConfig.ANON_KEY)
                header(HttpHeaders.Authorization, "Bearer ${SupabaseConfig.ANON_KEY}")
                setBody(body.toString())
            }
            if (response.status.value == 200) {
                val resp: DeepDivesResponse = response.body()
                if (resp.ok) resp.creators ?: emptyList() else emptyList()
            } else {
                emptyList()
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    companion object {
        @Volatile private var instance: DeepDivesViewModel? = null
        fun get(): DeepDivesViewModel = instance ?: synchronized(this) {
            instance ?: DeepDivesViewModel().also { instance = it }
        }
    }
}

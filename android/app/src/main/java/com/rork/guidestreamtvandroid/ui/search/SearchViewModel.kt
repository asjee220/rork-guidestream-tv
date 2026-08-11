package com.rork.guidestreamtvandroid.ui.search

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rork.guidestreamtvandroid.data.models.Platform
import com.rork.guidestreamtvandroid.data.models.SourceKind
import com.rork.guidestreamtvandroid.data.models.TMDBResult
import com.rork.guidestreamtvandroid.data.remote.LiveStatusService
import com.rork.guidestreamtvandroid.data.remote.SupabaseManager
import com.rork.guidestreamtvandroid.data.remote.TMDBService
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Search view model — mirrors iOS SearchViewModel.swift.
 * Debounced TMDB + creator search with scope filtering.
 */
class SearchViewModel : ViewModel() {

    @Serializable
    data class CreatorSearchRow(
        @SerialName("title_id") val titleId: String,
        @SerialName("display_name") val displayName: String,
        @SerialName("image_url") val imageUrl: String? = null,
        @SerialName("source_type") val sourceType: String,
        @SerialName("handle") val handle: String? = null,
        @SerialName("format") val format: String? = null,
        val category: String? = null,
    )

    data class SearchResult(
        val id: Int,
        val title: String,
        val isTV: Boolean,
        val posterUrl: String?,
        val backdropUrl: String?,
        val year: Int?,
        val platform: Platform?,
    )

    data class CreatorResult(
        val titleId: String,
        val displayName: String,
        val imageUrl: String?,
        val sourceType: String,
        val category: String?,
        val isLive: Boolean = false,
        val streamTitle: String? = null,
        val liveCategory: String? = null,
        val viewerCount: Int? = null,
        val handle: String? = null,
    )

    enum class Scope(val label: String) {
        ALL("All"), LIVE("Live"), SHOWS("Shows"), CREATORS("Creators"), PODCASTS("Podcasts")
    }

    private val tmdb = TMDBService.get()

    private val _query = MutableStateFlow("")
    val query: StateFlow<String> = _query.asStateFlow()

    private val _scope = MutableStateFlow(Scope.ALL)
    val scope: StateFlow<Scope> = _scope.asStateFlow()

    private val _isSearching = MutableStateFlow(false)
    val isSearching: StateFlow<Boolean> = _isSearching.asStateFlow()

    private val _tmdbResults = MutableStateFlow<List<SearchResult>>(emptyList())
    val tmdbResults: StateFlow<List<SearchResult>> = _tmdbResults.asStateFlow()

    private val _creatorResults = MutableStateFlow<List<CreatorResult>>(emptyList())
    val creatorResults: StateFlow<List<CreatorResult>> = _creatorResults.asStateFlow()

    private val _popular = MutableStateFlow<List<SearchResult>>(emptyList())
    val popular: StateFlow<List<SearchResult>> = _popular.asStateFlow()

    private var searchJob: Job? = null

    companion object {
        @Volatile private var instance: SearchViewModel? = null
        fun get(): SearchViewModel = instance ?: synchronized(this) {
            instance ?: SearchViewModel().also { instance = it }
        }
    }

    fun setQuery(q: String) {
        _query.value = q
        searchJob?.cancel()
        if (q.isBlank()) {
            _tmdbResults.value = emptyList()
            _creatorResults.value = emptyList()
            _isSearching.value = false
            return
        }
        searchJob = viewModelScope.launch(Dispatchers.IO) {
            delay(250)
            search(q)
        }
    }

    fun setScope(s: Scope) {
        _scope.value = s
        if (_query.value.isNotBlank()) setQuery(_query.value)
    }

    fun loadPopular() {
        if (_popular.value.isNotEmpty()) return
        viewModelScope.launch(Dispatchers.IO) {
            val tv = tmdb.getTrendingTV()
            val results = tv.take(18).mapNotNull { r ->
                val provider = tmdb.getTopWatchProvider(r.id)
                val platform = Platform.from(provider?.providerName)
                if (platform != null) SearchResult(
                    id = r.id,
                    title = r.displayName,
                    isTV = r.isTV,
                    posterUrl = r.posterUrl,
                    backdropUrl = r.backdropUrl,
                    year = r.year,
                    platform = platform,
                ) else null
            }
            _popular.value = results
        }
    }

    private suspend fun search(q: String) {
        _isSearching.value = true
        try {
            val scope = _scope.value
            val includeTMDB = scope == Scope.ALL || scope == Scope.SHOWS || scope == Scope.LIVE
            val includeCreators = scope == Scope.ALL || scope == Scope.CREATORS || scope == Scope.PODCASTS || scope == Scope.LIVE

            if (includeTMDB) {
                val results = tmdb.searchContent(q)
                _tmdbResults.value = results.map { r ->
                    SearchResult(
                        id = r.id,
                        title = r.displayName,
                        isTV = r.isTV,
                        posterUrl = r.posterUrl,
                        backdropUrl = r.backdropUrl,
                        year = r.year,
                        platform = null,
                    )
                }
            } else {
                _tmdbResults.value = emptyList()
            }

            if (includeCreators) {
                fetchCreators(q)
            } else {
                _creatorResults.value = emptyList()
            }
        } finally {
            _isSearching.value = false
        }
    }

    private suspend fun fetchCreators(q: String) {
        try {
            val rows = SupabaseManager.client.postgrest
                .from("content_sources")
                .select {
                    filter {
                        or {
                            ilike("display_name", "%$q%")
                            ilike("category", "%$q%")
                        }
                    }
                    limit(20)
                }
                .decodeList<CreatorSearchRow>()

            val liveIds = rows
                .map { it.titleId }
                .filter { SourceKind.from(it).isLivestream }
                .distinct()

            val liveMap: Map<String, LiveStatusService.LiveStatusRow> = if (liveIds.isNotEmpty()) {
                LiveStatusService.get().fetchLiveStatus(liveIds)
                    ?.filter { it.isLive }
                    ?.associateBy { it.titleId }
                    ?: emptyMap()
            } else emptyMap()

            var creators = rows.map { row ->
                val liveRow = liveMap[row.titleId]
                CreatorResult(
                    titleId = row.titleId,
                    displayName = row.displayName,
                    imageUrl = row.imageUrl,
                    sourceType = row.sourceType,
                    category = row.category,
                    isLive = liveRow != null,
                    streamTitle = liveRow?.streamTitle,
                    liveCategory = liveRow?.category,
                    viewerCount = liveRow?.viewerCount,
                    handle = row.handle,
                )
            }

            // Apply client-side scope filters for creators vs podcasts.
            val scope = _scope.value
            if (scope == Scope.CREATORS) {
                creators = creators.filter { SourceKind.from(it.titleId) != SourceKind.PODCAST }
            } else if (scope == Scope.PODCASTS) {
                creators = creators.filter { SourceKind.from(it.titleId) == SourceKind.PODCAST }
            }

            // Sort: live first, then case-insensitive by display name ascending.
            _creatorResults.value = creators.sortedWith(
                compareByDescending<CreatorResult> { it.isLive }
                    .thenBy { it.displayName.lowercase() }
            )
        } catch (_: Exception) {
            _creatorResults.value = emptyList()
        }
    }
}

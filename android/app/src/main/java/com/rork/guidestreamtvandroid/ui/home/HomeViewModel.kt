package com.rork.guidestreamtvandroid.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rork.guidestreamtvandroid.data.models.Platform
import com.rork.guidestreamtvandroid.data.models.StreamingCatalog
import com.rork.guidestreamtvandroid.data.models.TMDBResult
import com.rork.guidestreamtvandroid.data.remote.TMDBService
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.data.repository.StreamsViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Home feed view model — mirrors iOS HomeView state management.
 * Loads trending, on-air, top-rated, genre shows, and provider-scoped content.
 */
class HomeViewModel : ViewModel() {

    private val tmdb = TMDBService.get()

    private val _homeContentReady = MutableStateFlow(false)
    val homeContentReady: StateFlow<Boolean> = _homeContentReady.asStateFlow()

    private val _trending = MutableStateFlow<List<TMDBResult>>(emptyList())
    val trending: StateFlow<List<TMDBResult>> = _trending.asStateFlow()

    private val _onAir = MutableStateFlow<List<TMDBResult>>(emptyList())
    val onAir: StateFlow<List<TMDBResult>> = _onAir.asStateFlow()

    private val _topRated = MutableStateFlow<List<TMDBResult>>(emptyList())
    val topRated: StateFlow<List<TMDBResult>> = _topRated.asStateFlow()

    private val _nowPlaying = MutableStateFlow<List<TMDBResult>>(emptyList())
    val nowPlaying: StateFlow<List<TMDBResult>> = _nowPlaying.asStateFlow()

    private val _upcoming = MutableStateFlow<List<TMDBResult>>(emptyList())
    val upcoming: StateFlow<List<TMDBResult>> = _upcoming.asStateFlow()

    private val _bingeReady = MutableStateFlow<List<TMDBResult>>(emptyList())
    val bingeReady: StateFlow<List<TMDBResult>> = _bingeReady.asStateFlow()

    private val _genreShows = MutableStateFlow<List<TMDBResult>>(emptyList())
    val genreShows: StateFlow<List<TMDBResult>> = _genreShows.asStateFlow()

    private val _popularByService = MutableStateFlow<Map<String, List<TMDBResult>>>(emptyMap())
    val popularByService: StateFlow<Map<String, List<TMDBResult>>> = _popularByService.asStateFlow()

    /** TMDB provider IDs for streaming services (matches iOS). */
    private val providerIdMap = mapOf(
        "netflix" to 8,
        "prime" to 9,
        "disney" to 337,
        "hbo" to 1899,
        "hulu" to 15,
        "appletv" to 350,
        "paramount" to 531,
        "peacock" to 386,
        "starz" to 43,
        "showtime" to 37,
        "crunchyroll" to 283,
        "amc" to 526,
        "discovery" to 584,
        "mubi" to 11,
        "britbox" to 151,
        "fubo" to 257,
        "tubi" to 73,
        "pluto" to 300,
        "youtube" to 192,
    )

    /** Cached top US provider per TMDB id. */
    private val _providerByTmdb = MutableStateFlow<Map<Int, Platform>>(emptyMap())
    val providerByTmdb: StateFlow<Map<Int, Platform>> = _providerByTmdb.asStateFlow()

    companion object {
        @Volatile private var instance: HomeViewModel? = null
        fun get(): HomeViewModel = instance ?: synchronized(this) {
            instance ?: HomeViewModel().also { instance = it }
        }
    }

    /** Loads all home feed content in parallel. */
    fun loadAll() {
        if (_homeContentReady.value) return
        viewModelScope.launch(Dispatchers.IO) {
            val jobs = listOf(
                launch { _trending.value = tmdb.getTrendingTV() },
                launch { _onAir.value = tmdb.getOnTheAir() },
                launch { _topRated.value = tmdb.getTopRated() },
                launch { _nowPlaying.value = tmdb.getNowPlayingMovies() },
                launch { _upcoming.value = tmdb.getUpcomingMovies() },
                launch { _bingeReady.value = tmdb.getDiscoverEnded() },
                launch { _genreShows.value = tmdb.getDiscoverByGenre(80) }, // Crime
                launch {
                    val services = StreamingCatalog.ordered(AuthViewModel.get().selectedServices.value)
                    val entries = services
                        .mapNotNull { svc -> providerIdMap[svc.id]?.let { svc.id to it } }
                        .map { (serviceId, providerId) ->
                            launch(Dispatchers.IO) {
                                val results = tmdb.discoverByProvider(providerId)
                                if (results.isNotEmpty()) {
                                    _popularByService.value = _popularByService.value + (serviceId to results)
                                }
                            }
                        }
                    entries.forEach { it.join() }
                },
            )
            jobs.forEach { it.join() }

            // Resolve providers for trending shows
            resolveProviders(_trending.value)

            _homeContentReady.value = true

            // Refresh watchlist from Supabase
            StreamsViewModel.get().refreshAll()
        }
    }

    private suspend fun resolveProviders(shows: List<TMDBResult>) {
        val map = _providerByTmdb.value.toMutableMap()
        for (show in shows.take(20)) {
            if (map.containsKey(show.id)) continue
            val provider = tmdb.getTopWatchProvider(show.id)
            val platform = Platform.from(provider?.providerName)
            if (platform != null) {
                map[show.id] = platform
            }
        }
        _providerByTmdb.value = map
    }

    /** Refresh genre discovery for a new genre selection. */
    fun loadGenre(genreId: Int) {
        viewModelScope.launch(Dispatchers.IO) {
            _genreShows.value = tmdb.getDiscoverByGenre(genreId)
        }
    }
}

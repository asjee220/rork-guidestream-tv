package com.rork.guidestreamtvandroid.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rork.guidestreamtvandroid.data.models.Platform
import com.rork.guidestreamtvandroid.data.models.SourceKind
import com.rork.guidestreamtvandroid.data.models.StreamingCatalog
import com.rork.guidestreamtvandroid.data.models.TitleId
import com.rork.guidestreamtvandroid.data.models.TMDBResult
import com.rork.guidestreamtvandroid.data.remote.ExpiringTitlesService
import com.rork.guidestreamtvandroid.data.remote.RecommendedCreator
import com.rork.guidestreamtvandroid.data.remote.RecommendedCreatorsService
import com.rork.guidestreamtvandroid.data.remote.StreamingReleasesService
import com.rork.guidestreamtvandroid.data.remote.TMDBService
import com.rork.guidestreamtvandroid.data.remote.toTMDBResult
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.data.repository.StreamsViewModel
import com.rork.guidestreamtvandroid.widget.WidgetDataService
import com.rork.guidestreamtvandroid.widget.WidgetLeavingSoonItem
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.temporal.ChronoUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
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

    private val _newReleases = MutableStateFlow<List<TMDBResult>>(emptyList())
    val newReleases: StateFlow<List<TMDBResult>> = _newReleases.asStateFlow()

    /** Today's Pick — one raw row from streaming_releases, selected by day-of-year
     * rotation. Kept as the raw StreamingReleaseRow (not mapped through
     * toTMDBResult) so the spotlight can read source_name, is_original, and
     * poster_url — fields the toTMDBResult mapping drops. */
    private val _todaysPick = MutableStateFlow<StreamingReleasesService.StreamingReleaseRow?>(null)
    val todaysPick: StateFlow<StreamingReleasesService.StreamingReleaseRow?> = _todaysPick.asStateFlow()

    /** Leaving Soon — server-backed rows from the expiring_titles table. */
    private val _leavingSoon = MutableStateFlow<List<TMDBResult>>(emptyList())
    val leavingSoon: StateFlow<List<TMDBResult>> = _leavingSoon.asStateFlow()

    private val _upcoming = MutableStateFlow<List<TMDBResult>>(emptyList())
    val upcoming: StateFlow<List<TMDBResult>> = _upcoming.asStateFlow()

    private val _bingeReady = MutableStateFlow<List<TMDBResult>>(emptyList())
    val bingeReady: StateFlow<List<TMDBResult>> = _bingeReady.asStateFlow()

    private val _genreShows = MutableStateFlow<List<TMDBResult>>(emptyList())
    val genreShows: StateFlow<List<TMDBResult>> = _genreShows.asStateFlow()

    private val _selectedGenreId = MutableStateFlow(80)
    val selectedGenreId: StateFlow<Int> = _selectedGenreId.asStateFlow()

    private val _selectedGenreName = MutableStateFlow("Crime")
    val selectedGenreName: StateFlow<String> = _selectedGenreName.asStateFlow()

    private val _recommendedCreators = MutableStateFlow<List<RecommendedCreator>>(emptyList())
    val recommendedCreators: StateFlow<List<RecommendedCreator>> = _recommendedCreators.asStateFlow()

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
        "paramount" to 2303,
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

    /**
     * Taste signal: union of genre ids across the user's watched + saved titles.
     * Starts empty so Top Picks renders instantly on rating + service; the row
     * re-ranks once these resolve in the background.
     */
    private val _preferredGenres = MutableStateFlow<Set<Int>>(emptySet())
    val preferredGenres: StateFlow<Set<Int>> = _preferredGenres.asStateFlow()

    /** In-memory cache of resolved genre ids per TMDB id so a title is never looked up twice. */
    private val genreCache = mutableMapOf<Int, Set<Int>>()

    /** TMDB provider id for a service id, or null when the service has no mapping. */
    fun providerIdFor(serviceId: String): Int? = providerIdMap[serviceId]

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
                launch {
                    // Fetch two pages of trending and de-duplicate by id,
                    // preserving first-seen order (page 2 can repeat page 1).
                    val combined = tmdb.getTrendingTV(page = 1) + tmdb.getTrendingTV(page = 2)
                    val seen = mutableSetOf<Int>()
                    _trending.value = combined.filter { seen.add(it.id) }
                },
                launch { _onAir.value = tmdb.getOnTheAir() },
                launch { _topRated.value = tmdb.getTopRated() },
                launch {
                    val rows = StreamingReleasesService.get().fetchReleases()
                    if (rows != null) {
                        _newReleases.value = rows.map { it.toTMDBResult() }
                        // Compute Today's Pick from the raw rows (already
                        // popularity-descending from the query). Take the first
                        // 10, pick by day-of-year rotation, skip rows missing
                        // both posterUrl and posterPath.
                        val pool = rows.take(10)
                        if (pool.isNotEmpty()) {
                            val count = pool.size
                            var idx = LocalDate.now().dayOfYear % count
                            var chosen: StreamingReleasesService.StreamingReleaseRow? = null
                            for (i in 0 until count) {
                                val candidate = pool[idx]
                                if (!candidate.posterUrl.isNullOrEmpty() ||
                                    !candidate.posterPath.isNullOrEmpty()) {
                                    chosen = candidate
                                    break
                                }
                                idx = (idx + 1) % count
                            }
                            _todaysPick.value = chosen ?: pool[LocalDate.now().dayOfYear % count]
                        }
                    }
                },
                launch { loadLeavingSoon() },
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

            // Resolve the user's taste genres in the background. Additive and
            // best-effort — never blocks the Top Picks row from rendering.
            resolvePreferredGenres()

            // Resolve creator/podcast recommendations in the background. Additive
            // and best-effort — never blocks the feed from rendering.
            loadRecommendedCreators()
        }
    }

    /**
     * Best-effort creator/podcast recommendations. Collects the user's followed
     * non-TMDB title ids (yt:/pod:/tw:/kick:), returns early with an empty list
     * when none are followed, and otherwise asks the `recommend_creators` edge
     * function for a server-ranked list. Never blocks the feed.
     */
    fun loadRecommendedCreators() {
        viewModelScope.launch(Dispatchers.IO) {
            val followedIds = StreamsViewModel.get().userStreams.value
                .map { it.titleId }
                .filter { SourceKind.from(it).isNonTMDB }
            if (followedIds.isEmpty()) {
                _recommendedCreators.value = emptyList()
                return@launch
            }
            _recommendedCreators.value = RecommendedCreatorsService.recommend(followedIds)
        }
    }

    /**
     * Best-effort taste resolver. Gathers the user's library ids (numeric TMDB
     * title ids from the watchlist — skipping yt:/tw:/pod: creator ids — plus
     * watched ids), resolves each uncached id's genres via TV detail then falls
     * back to movie detail, caches them, and emits [preferredGenres] as the
     * union. Runs off the main thread and never blocks the feed.
     */
    private fun resolvePreferredGenres() {
        viewModelScope.launch(Dispatchers.IO) {
            val streams = StreamsViewModel.get()
            val libraryIds = buildSet {
                streams.userStreams.value.forEach { TitleId.tmdbId(it.titleId)?.let(::add) }
                streams.watchedIds.value.forEach { TitleId.tmdbId(it)?.let(::add) }
            }
            val pending = libraryIds.filter { !genreCache.containsKey(it) }
            for (id in pending) {
                val detail = tmdb.getTVDetail(id) ?: tmdb.getMovieDetail(id)
                genreCache[id] = detail?.genres?.map { it.id }?.toSet() ?: emptySet()
            }
            _preferredGenres.value = genreCache.values.flatten().toSet()
        }
    }

    /**
     * Loads the Leaving Soon rail from the server-backed expiring_titles table
     * (refreshed daily by the refresh_expiring_titles edge function). Keeps
     * rows leaving within 0..20 days, soonest first (max 20), resolves each
     * row's provider badge from its service_name, and pushes the kept rows to
     * the home-screen widget. An empty/failed fetch leaves the rail hidden and
     * never wipes recent widget data (push() is wipe-protected).
     */
    private suspend fun loadLeavingSoon() {
        val rows = ExpiringTitlesService.get().fetchExpiring() ?: return
        val today = LocalDate.now(ZoneOffset.UTC)
        val kept = rows.mapNotNull { row ->
            val date = row.leavingDate
                ?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
                ?: return@mapNotNull null
            val daysLeft = ChronoUnit.DAYS.between(today, date).toInt()
            if (daysLeft in 0..20) row to daysLeft else null
        }.sortedBy { it.second }.take(20)

        // Resolve provider badges from the table's service_name BEFORE the
        // list is emitted so the rail renders correct badges immediately
        // without waiting for TMDB provider hydration.
        val providerUpdates = kept.mapNotNull { (row, _) ->
            Platform.from(row.serviceName)?.let { row.tmdbId to it }
        }
        if (providerUpdates.isNotEmpty()) {
            _providerByTmdb.value = _providerByTmdb.value + providerUpdates
        }
        _leavingSoon.value = kept.map { (row, _) -> row.toTMDBResult() }

        // Push the kept rows to the home-screen widget.
        val widgetItems = kept.map { (row, daysLeft) ->
            val platform = Platform.from(row.serviceName)
            WidgetLeavingSoonItem(
                id = row.tmdbId.toString(),
                title = row.title ?: "Untitled",
                daysLeft = daysLeft,
                platform = platform?.name ?: (row.serviceName ?: "").uppercase(),
                platformColorHex = Platform.colorHex(platform),
                posterUrl = row.posterUrl,
            )
        }
        runCatching {
            val streams = StreamsViewModel.get()
            WidgetDataService.get().push(
                leavingSoon = widgetItems,
                watchlistCount = streams.userStreams.value.size,
                newEpisodeCount = streams.newEpisodes.value.size,
            )
        }
    }

    private suspend fun resolveProviders(shows: List<TMDBResult>) {
        val map = _providerByTmdb.value.toMutableMap()
        // Resolve providers for uncached shows in parallel, then fold the
        // non-null results into the map in one emit so no update is lost.
        val resolved = coroutineScope {
            shows.take(40)
                .filterNot { map.containsKey(it.id) }
                .map { show ->
                    async(Dispatchers.IO) {
                        show.id to Platform.from(tmdb.getTopWatchProvider(show.id)?.providerName)
                    }
                }
                .awaitAll()
        }
        for ((id, platform) in resolved) {
            if (platform != null) {
                map[id] = platform
            }
        }
        _providerByTmdb.value = map
    }

    /**
     * Refresh genre discovery for a new genre selection. Updates the selection
     * flows first so the "Because you watch" title never lags the tapped pill,
     * then loads by media type exactly as iOS does and resolves providers for the
     * new results so poster badges populate.
     */
    fun loadGenre(genreId: Int, genreName: String, mediaType: String) {
        _selectedGenreId.value = genreId
        _selectedGenreName.value = genreName
        viewModelScope.launch(Dispatchers.IO) {
            val results = when (mediaType) {
                "movie" -> tmdb.getDiscoverByGenre(genreId, "movie")
                "international" -> tmdb.getDiscoverInternational()
                else -> tmdb.getDiscoverByGenre(genreId)
            }
            _genreShows.value = results
            resolveProviders(results)
        }
    }
}

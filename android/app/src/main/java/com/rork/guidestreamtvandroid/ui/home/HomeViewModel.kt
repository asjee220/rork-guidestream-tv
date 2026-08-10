package com.rork.guidestreamtvandroid.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rork.guidestreamtvandroid.data.models.Platform
import com.rork.guidestreamtvandroid.data.models.SourceKind
import com.rork.guidestreamtvandroid.data.models.StreamingCatalog
import com.rork.guidestreamtvandroid.data.models.TitleId
import com.rork.guidestreamtvandroid.data.models.TMDBResult
import com.rork.guidestreamtvandroid.data.remote.ExpiringTitlesService
import com.rork.guidestreamtvandroid.data.remote.ProviderBrandMapService
import com.rork.guidestreamtvandroid.data.remote.RecommendedCreator
import com.rork.guidestreamtvandroid.data.remote.RecommendedCreatorsService
import com.rork.guidestreamtvandroid.data.models.StreamingService
import com.rork.guidestreamtvandroid.data.remote.StreamingReleasesService
import com.rork.guidestreamtvandroid.data.remote.StreamingUpcomingService
import com.rork.guidestreamtvandroid.data.remote.TMDBService
import com.rork.guidestreamtvandroid.data.remote.toTMDBResult
import com.rork.guidestreamtvandroid.data.repository.StreamsViewModel
import com.rork.guidestreamtvandroid.widget.WidgetDataService
import com.rork.guidestreamtvandroid.widget.WidgetLeavingSoonItem
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.temporal.ChronoUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Home feed view model — mirrors iOS HomeView state management.
 * Loads trending, on-air, top-rated, genre shows, and provider-scoped content.
 */
/**
 * One card in the "Now & Next on {service}" rail. Pairs the shared
 * [TMDBResult] with the pill state so the pill overlay stays owned by the
 * rail section and no field leaks into the shared model.
 */
data class NowNextEntry(
    val result: TMDBResult,
    /** Display poster — server poster_url first, then the posterPath-derived CDN url. */
    val posterUrl: String?,
    /** "Series"/"Movie" (+ " · Original") for server rows, "On {service}" for backfill. */
    val meta: String,
    /** "Aug 14" — set only for streaming_upcoming rows. */
    val dateText: String?,
    /** True for streaming_releases rows — renders the green NEW pill.
     * False with null [dateText] marks a TMDB backfill card (no pill). */
    val isNow: Boolean,
)

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

    /** Assembled "Now & Next on {service}" rail entries keyed by catalogue service id. */
    private val _nowNextByService = MutableStateFlow<Map<String, List<NowNextEntry>>>(emptyMap())
    val nowNextByService: StateFlow<Map<String, List<NowNextEntry>>> = _nowNextByService.asStateFlow()

    /** Raw streaming_releases rows kept from the home load's single fetch so
     * the Now & Next rails reuse them instead of refetching. */
    private var releaseRows: List<StreamingReleasesService.StreamingReleaseRow> = emptyList()

    /** streaming_upcoming rows fetched at most once per home load and shared
     * across every service rail. */
    private var upcomingRows: List<StreamingUpcomingService.StreamingUpcomingRow>? = null

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

    /**
     * Loads the home feed. Only the hero-critical work gates
     * [homeContentReady] — four trending pages, on-the-air, top-rated, the
     * default genre rail, and streaming releases (Today's Pick) — plus a
     * provider-resolution pass over the first 15 trending results so the hero
     * carousel can filter to badged items. Everything else (brand map,
     * Leaving Soon, upcoming, binge-ready, the remaining trending badges,
     * watchlist refresh, taste genres, creator recs) is fire-and-forget after
     * the flip, each isolated so one failure never blocks or cancels another.
     * If trending comes back empty the gate still flips: the hero renders
     * nothing and the rest of the feed stays reachable.
     */
    fun loadAll() {
        if (_homeContentReady.value) return
        viewModelScope.launch(Dispatchers.IO) {
            val jobs = listOf(
                launch {
                    // Fetch all four trending pages concurrently, concatenate
                    // in page order 1→4, then de-duplicate by id preserving
                    // first-seen order (later pages can repeat earlier) —
                    // byte-for-byte the same result as the old serial fetch.
                    val pages = coroutineScope {
                        (1..4).map { page ->
                            async(Dispatchers.IO) { tmdb.getTrendingTV(page = page) }
                        }.awaitAll()
                    }
                    val combined = pages[0] + pages[1] + pages[2] + pages[3]
                    val seen = mutableSetOf<Int>()
                    _trending.value = combined.filter { seen.add(it.id) }
                },
                launch { _onAir.value = tmdb.getOnTheAir() },
                launch { _topRated.value = tmdb.getTopRated() },
                launch {
                    val rows = StreamingReleasesService.get().fetchReleases()
                    if (rows != null) {
                        releaseRows = rows
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
                launch { _genreShows.value = tmdb.getDiscoverByGenre(80) }, // Crime
            )
            // Watchdog: never let a stalled request hold the skeleton. The
            // jobs were launched above, OUTSIDE this block, so a timeout
            // cancels only the joins — the in-flight jobs keep running and
            // keep populating their StateFlows, and their sections fill in
            // reactively once they arrive.
            withTimeoutOrNull(8_000L) {
                jobs.forEach { it.join() }
            }

            // Resolve providers for the first 15 trending results only — just
            // enough for the hero carousel's provider filter.
            resolveProviders(_trending.value.take(15))

            _homeContentReady.value = true

            // Deferred, non-blocking work. Each runs in its own sibling
            // coroutine (viewModelScope is a SupervisorJob) with its own
            // catch, so a failure in one never blocks or cancels another.
            launchDeferred { ProviderBrandMapService.get().refresh() }
            launchDeferred { loadLeavingSoon() }
            launchDeferred { _upcoming.value = tmdb.getUpcomingMovies() }
            launchDeferred { _bingeReady.value = tmdb.getDiscoverEnded() }
            // Second provider pass. The 8s watchdog can flip the gate while
            // trending is still empty, so first suspend until the list is
            // non-empty, then resolve the first 40. Idempotent:
            // resolveProviders skips ids already hydrated by the 15-item
            // pass, so nothing is ever re-fetched.
            launchDeferred {
                _trending.first { it.isNotEmpty() }
                resolveProviders(_trending.value.take(40))
            }
            launchDeferred { StreamsViewModel.get().refreshAll() }

            // Resolve the user's taste genres in the background. Additive and
            // best-effort — never blocks the Top Picks row from rendering.
            resolvePreferredGenres()

            // Resolve creator/podcast recommendations in the background. Additive
            // and best-effort — never blocks the feed from rendering.
            loadRecommendedCreators()
        }
    }

    /** Fire-and-forget background job: isolated failure, never crashes. */
    private fun launchDeferred(block: suspend () -> Unit) {
        viewModelScope.launch(Dispatchers.IO) {
            try {
                block()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                // Best-effort — the section simply stays hidden/unhydrated.
            }
        }
    }

    /**
     * Loads the "Popular on {service}" rails for the passed selection.
     *
     * Ids are mapped through [StreamingCatalog.ordered] so rails keep catalogue
     * order, then through [providerIdMap]; a service with no TMDB provider
     * mapping (espn, sling, youtubetv, mgm, …) is skipped silently and renders
     * no rail, exactly as on iOS. Each remaining service fetches its popular TV
     * shows and popular movies concurrently, keeps the first 10 shows and first
     * 5 movies, interleaves them show → movie → show → movie, drops duplicate
     * TMDB ids, and caps the rail at 12 items.
     *
     * A failed or throwing fetch yields an empty list for that one service and
     * never aborts the others. The freshly built map is assigned in a single
     * write so concurrent fetches cannot drop each other's entries, and so
     * services the user just deselected lose their rails instead of lingering
     * from the previous value.
     */
    suspend fun loadPopularByServices(serviceIds: Set<String>) {
        val mapped = StreamingCatalog.ordered(serviceIds)
            .mapNotNull { svc -> providerIdMap[svc.id]?.let { svc.id to it } }
        if (mapped.isEmpty()) {
            _popularByService.value = emptyMap()
            return
        }

        val collected = coroutineScope {
            mapped.map { (serviceId, providerId) ->
                async(Dispatchers.IO) {
                    val showsJob = async(Dispatchers.IO) {
                        try {
                            tmdb.getPopularOnService(providerId)
                        } catch (cancelled: CancellationException) {
                            throw cancelled
                        } catch (_: Exception) {
                            emptyList<TMDBResult>()
                        }
                    }
                    val moviesJob = async(Dispatchers.IO) {
                        try {
                            tmdb.getPopularMoviesOnService(providerId)
                        } catch (cancelled: CancellationException) {
                            throw cancelled
                        } catch (_: Exception) {
                            emptyList<TMDBResult>()
                        }
                    }
                    val shows = showsJob.await().take(10)
                    val movies = moviesJob.await().take(5)

                    val merged = mutableListOf<TMDBResult>()
                    val seen = mutableSetOf<Int>()
                    var showIndex = 0
                    var movieIndex = 0
                    while (merged.size < 12 && (showIndex < shows.size || movieIndex < movies.size)) {
                        if (showIndex < shows.size) {
                            val show = shows[showIndex++]
                            if (seen.add(show.id)) merged.add(show)
                        }
                        if (merged.size >= 12) break
                        if (movieIndex < movies.size) {
                            val movie = movies[movieIndex++]
                            if (seen.add(movie.id)) merged.add(movie)
                        }
                    }
                    serviceId to merged.toList()
                }
            }.awaitAll()
        }

        val next = LinkedHashMap<String, List<TMDBResult>>()
        for ((serviceId, items) in collected) {
            if (items.isNotEmpty()) next[serviceId] = items
        }
        _popularByService.value = next
    }

    /**
     * Builds the per-service "Now & Next on {service}" rails from the
     * already-fetched streaming_releases ("now") rows and the once-per-load
     * streaming_upcoming ("next") rows, then backfills below-capacity rails
     * from TMDB. Rebuilt fresh from the passed selection so a deselected
     * service loses its rail on the next load. All date comparisons run in
     * UTC against the stored date-only strings so the device timezone can
     * never shift a title across the 30-day horizon.
     */
    suspend fun loadNowAndNext(serviceIds: Set<String>) {
        val services = StreamingCatalog.ordered(serviceIds)
        if (services.isEmpty()) {
            _nowNextByService.value = emptyMap()
            return
        }

        // Reuse the home load's releases fetch; fetch upcoming at most once
        // per home load and share the rows across every service rail.
        val releases = releaseRows
        val upcoming = upcomingRows
            ?: StreamingUpcomingService.get().fetchUpcoming()?.also { upcomingRows = it }
            ?: emptyList()

        val today = LocalDate.now(ZoneOffset.UTC)
        val horizon = today.plusDays(30)
        val pillFmt = java.time.format.DateTimeFormatter.ofPattern("MMM d", java.util.Locale.US)

        // Group server rows by catalogue id through Platform.from(providerName)
        // — the app's single provider-name mapping. Unresolved source names
        // are dropped silently, never guessed at.
        val nowByService = HashMap<String, MutableList<StreamingReleasesService.StreamingReleaseRow>>()
        for (row in releases) {
            val catalogId = Platform.from(row.sourceName)?.catalogId ?: continue
            nowByService.getOrPut(catalogId) { mutableListOf() }.add(row)
        }
        val nextByService = HashMap<String, MutableList<Pair<StreamingUpcomingService.StreamingUpcomingRow, LocalDate>>>()
        for (row in upcoming) {
            val raw = row.sourceReleaseDate ?: continue
            if (raw.length < 10) continue
            val date = runCatching { LocalDate.parse(raw.take(10)) }.getOrNull() ?: continue
            if (date.isBefore(today) || date.isAfter(horizon)) continue
            val catalogId = Platform.from(row.sourceName)?.catalogId ?: continue
            nextByService.getOrPut(catalogId) { mutableListOf() }.add(row to date)
        }

        fun metaFor(mediaType: String, isOriginal: Boolean?): String =
            (if (mediaType == "tv") "Series" else "Movie") + (if (isOriginal == true) " · Original" else "")

        // Server entries per service: "now" first (the releases query is
        // already popularity-descending), then "next" (already date-ascending),
        // de-duplicated by tmdb type+id with the "now" entry winning. Fewer
        // than three mapped rows → no rail at all for that service.
        data class Gated(val service: StreamingService, val entries: List<NowNextEntry>)
        val gated = mutableListOf<Gated>()
        for (service in services) {
            val seenKeys = mutableSetOf<String>()
            val entries = mutableListOf<NowNextEntry>()
            for (row in nowByService[service.id].orEmpty()) {
                val mediaType = row.tmdbType ?: "tv"
                if (!seenKeys.add("$mediaType:${row.tmdbId}")) continue
                val result = TMDBResult(
                    id = row.tmdbId,
                    mediaType = mediaType,
                    name = row.title,
                    title = row.title,
                    posterPath = row.posterPath,
                    voteAverage = row.voteAverage,
                )
                entries.add(NowNextEntry(
                    result = result,
                    posterUrl = row.posterUrl ?: result.posterUrl,
                    meta = metaFor(mediaType, row.isOriginal),
                    dateText = null,
                    isNow = true,
                ))
            }
            for ((row, date) in nextByService[service.id].orEmpty()) {
                val mediaType = row.tmdbType ?: "tv"
                if (!seenKeys.add("$mediaType:${row.tmdbId}")) continue
                val result = TMDBResult(
                    id = row.tmdbId,
                    mediaType = mediaType,
                    name = row.title,
                    title = row.title,
                    posterPath = row.posterPath,
                    voteAverage = row.voteAverage,
                )
                entries.add(NowNextEntry(
                    result = result,
                    posterUrl = row.posterUrl ?: result.posterUrl,
                    meta = metaFor(mediaType, row.isOriginal),
                    dateText = date.format(pillFmt),
                    isNow = false,
                ))
            }
            if (entries.size < 3) continue
            gated.add(Gated(service, entries.take(12)))
        }
        if (gated.isEmpty()) {
            _nowNextByService.value = emptyMap()
            return
        }

        // Backfill below-capacity rails from TMDB concurrently. Backfill
        // never displaces a server row, and a failed backfill keeps whatever
        // server rows exist — it never blanks a rail that passed the gate.
        val collected = coroutineScope {
            gated.map { g ->
                async(Dispatchers.IO) {
                    var entries = g.entries
                    val providerId = providerIdMap[g.service.id]
                    if (entries.size < 12 && providerId != null) {
                        val backfill = try {
                            tmdb.getRecentlyAddedOnService(providerId)
                        } catch (cancelled: CancellationException) {
                            throw cancelled
                        } catch (_: Exception) {
                            emptyList()
                        }
                        val keys = entries.map { "${it.result.mediaType ?: "tv"}:${it.result.id}" }.toMutableSet()
                        val extra = mutableListOf<NowNextEntry>()
                        for (r in backfill) {
                            if (entries.size + extra.size >= 12) break
                            if (!keys.add("${r.mediaType ?: "tv"}:${r.id}")) continue
                            extra.add(NowNextEntry(
                                result = r,
                                posterUrl = r.posterUrl,
                                meta = "On ${g.service.name}",
                                dateText = null,
                                isNow = false,
                            ))
                        }
                        entries = entries + extra
                    }
                    g.service.id to entries
                }
            }.awaitAll()
        }
        val next = LinkedHashMap<String, List<NowNextEntry>>()
        for ((serviceId, entries) in collected) next[serviceId] = entries
        _nowNextByService.value = next
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
                        // Pass isTV explicitly: the parameter defaults to true,
                        // which sent movie ids to the tv watch-providers
                        // endpoint where they always 404 and lose their badge.
                        val provider = tmdb.getTopWatchProvider(show.id, isTV = show.isTV)
                        show.id to (Platform.fromProviderId(provider?.providerId ?: 0)
                            ?: Platform.from(provider?.providerName))
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

    /**
     * Pull-to-refresh variant of [loadAll]. Performs the same data work but
     * without the [_homeContentReady] gate and without ever writing false to
     * [_homeContentReady], so the feed never flashes back to shimmer
     * placeholders during a refresh. Each section is individually isolated so
     * one failing section never aborts the rest and this function never throws.
     */
    suspend fun refreshFeed() {
        coroutineScope {
            val jobs = listOf(
                launch(Dispatchers.IO) {
                    try {
                        val pages = coroutineScope {
                            (1..4).map { page ->
                                async(Dispatchers.IO) { tmdb.getTrendingTV(page = page) }
                            }.awaitAll()
                        }
                        val combined = pages[0] + pages[1] + pages[2] + pages[3]
                        val seen = mutableSetOf<Int>()
                        _trending.value = combined.filter { seen.add(it.id) }
                    } catch (c: CancellationException) { throw c }
                    catch (_: Exception) {}
                },
                launch(Dispatchers.IO) {
                    try { _onAir.value = tmdb.getOnTheAir() }
                    catch (c: CancellationException) { throw c }
                    catch (_: Exception) {}
                },
                launch(Dispatchers.IO) {
                    try { _topRated.value = tmdb.getTopRated() }
                    catch (c: CancellationException) { throw c }
                    catch (_: Exception) {}
                },
                launch(Dispatchers.IO) {
                    try {
                        val rows = StreamingReleasesService.get().fetchReleases()
                        if (rows != null) {
                            releaseRows = rows
                            _newReleases.value = rows.map { it.toTMDBResult() }
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
                    } catch (c: CancellationException) { throw c }
                    catch (_: Exception) {}
                },
                launch(Dispatchers.IO) {
                    try { _genreShows.value = tmdb.getDiscoverByGenre(_selectedGenreId.value) }
                    catch (c: CancellationException) { throw c }
                    catch (_: Exception) {}
                },
            )
            jobs.forEach { it.join() }

            try { resolveProviders(_trending.value.take(40)) }
            catch (c: CancellationException) { throw c }
            catch (_: Exception) {}
        }

        // Deferred, non-blocking work — each isolated so one failure never
        // aborts the rest. Runs on IO so SharedPreferences writes (widget
        // payload inside loadLeavingSoon), database reads, and JSON encoding
        // never hit the main thread during a pull-to-refresh.
        withContext(Dispatchers.IO) {
            try { loadLeavingSoon() } catch (c: CancellationException) { throw c } catch (_: Exception) {}
            launchDeferred { _upcoming.value = tmdb.getUpcomingMovies() }
            launchDeferred { _bingeReady.value = tmdb.getDiscoverEnded() }
            launchDeferred { ProviderBrandMapService.get().refresh() }
            launchDeferred { loadRecommendedCreators() }

            // Refresh the watchlist / watched / badges / new-episode counts.
            try { StreamsViewModel.get().refreshAllNow() }
            catch (c: CancellationException) { throw c }
            catch (_: Exception) {}
        }
    }
}

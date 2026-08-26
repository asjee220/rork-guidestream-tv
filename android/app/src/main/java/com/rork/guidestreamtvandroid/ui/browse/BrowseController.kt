package com.rork.guidestreamtvandroid.ui.browse

import com.rork.guidestreamtvandroid.data.models.BrowseFilterPill
import com.rork.guidestreamtvandroid.data.models.BrowseFilters
import com.rork.guidestreamtvandroid.data.models.BrowsePage
import com.rork.guidestreamtvandroid.data.models.TMDBResult
import com.rork.guidestreamtvandroid.data.remote.TMDBService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * The one filter whose removal brings the most titles back, offered on an
 * otherwise empty grid.
 */
data class BrowseRecovery(
    val kind: BrowseFilterPill.Kind,
    val label: String,
    val count: Int,
)

/**
 * Screen state for the browse results grid. Mirrors iOS `BrowseResultsModel`.
 *
 * Plain class rather than an AAC ViewModel: this state belongs to one visit to
 * one genre and dies with it, the same way the service-category browser's state
 * does.
 */
class BrowseController(
    private val scope: CoroutineScope,
    genreId: String,
    providerIds: List<Int>,
) {
    private val tmdb = TMDBService.get()

    private val _filters = MutableStateFlow(
        BrowseFilters(genreIds = setOf(genreId), providerIds = providerIds)
    )
    val filters: StateFlow<BrowseFilters> = _filters.asStateFlow()

    private val _results = MutableStateFlow<List<TMDBResult>>(emptyList())
    val results: StateFlow<List<TMDBResult>> = _results.asStateFlow()

    private val _totalResults = MutableStateFlow(0)
    val totalResults: StateFlow<Int> = _totalResults.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _isPaging = MutableStateFlow(false)
    val isPaging: StateFlow<Boolean> = _isPaging.asStateFlow()

    private val _recovery = MutableStateFlow<BrowseRecovery?>(null)
    val recovery: StateFlow<BrowseRecovery?> = _recovery.asStateFlow()

    private var page = 1
    private var totalPages = 1

    /**
     * First page per filter signature, so flipping back to a genre already
     * looked at is instant — the same trick the service browser uses.
     */
    private val cache = mutableMapOf<String, BrowsePage>()
    private var loadJob: Job? = null

    private val canPage: Boolean get() = page < totalPages && page < 500

    /** Providers are read from the auth store on first composition. */
    fun attachProviders(ids: List<Int>) {
        if (_filters.value.providerIds == ids) return
        _filters.value = _filters.value.copy(providerIds = ids)
    }

    fun reload() {
        loadJob?.cancel()
        val current = _filters.value
        val signature = current.signature
        _recovery.value = null

        cache[signature]?.let {
            apply(it, replacing = true)
            return
        }

        _isLoading.value = true
        loadJob = scope.launch {
            val fetched = tmdb.discoverBrowse(current, page = 1)
            cache[signature] = fetched
            apply(fetched, replacing = true)
            _isLoading.value = false
            if (fetched.results.isEmpty()) probeRecovery(current)
        }
    }

    fun loadNextPage() {
        if (!canPage || _isPaging.value || _isLoading.value) return
        _isPaging.value = true
        val next = page + 1
        scope.launch {
            try {
                apply(tmdb.discoverBrowse(_filters.value, page = next), replacing = false)
            } finally {
                _isPaging.value = false
            }
        }
    }

    private fun apply(browsePage: BrowsePage, replacing: Boolean) {
        _results.value = if (replacing) {
            browsePage.results
        } else {
            // TMDB pages overlap occasionally; never render the same id twice.
            val known = _results.value.map { it.id }.toSet()
            _results.value + browsePage.results.filter { it.id !in known }
        }
        page = browsePage.page
        totalPages = browsePage.totalPages
        _totalResults.value = browsePage.totalResults
    }

    /**
     * Walks the active filters from most to least restrictive and stops at the
     * first one whose removal recovers titles. Bounded to three calls, and it
     * only ever runs on an empty grid.
     */
    private suspend fun probeRecovery(current: BrowseFilters) {
        val priority = listOf(
            BrowseFilterPill.Kind.RATING,
            BrowseFilterPill.Kind.YEAR,
            BrowseFilterPill.Kind.MEDIA_TYPE,
            BrowseFilterPill.Kind.SERVICES,
        )
        val active = priority.filter { kind -> current.pills.any { it.kind == kind } }
        for (kind in active.take(3)) {
            val probe = tmdb.discoverBrowse(current.removing(kind), page = 1)
            if (probe.totalResults <= 0) continue
            _recovery.value = BrowseRecovery(
                kind = kind,
                label = current.pills.first { it.kind == kind }.label,
                count = probe.totalResults,
            )
            return
        }
    }

    // -----------------------------------------------------------------------
    // Mutation
    // -----------------------------------------------------------------------

    fun selectGenre(genreId: String) {
        if (_filters.value.genreIds == setOf(genreId)) return
        _filters.value = _filters.value.copy(genreIds = setOf(genreId))
        reload()
    }

    fun update(new: BrowseFilters) {
        if (new == _filters.value) return
        _filters.value = new
        reload()
    }

    fun remove(kind: BrowseFilterPill.Kind) {
        _filters.value = _filters.value.removing(kind)
        reload()
    }

    fun clearAll() {
        val current = _filters.value
        _filters.value = BrowseFilters(
            genreIds = current.genreIds,
            providerIds = current.providerIds,
            onlyMyServices = false,
        )
        reload()
    }
}

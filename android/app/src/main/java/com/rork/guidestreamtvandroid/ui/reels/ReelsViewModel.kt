package com.rork.guidestreamtvandroid.ui.reels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rork.guidestreamtvandroid.data.models.Platform
import com.rork.guidestreamtvandroid.data.models.TMDBResult
import com.rork.guidestreamtvandroid.data.remote.StreamingUpcomingService
import com.rork.guidestreamtvandroid.data.remote.TMDBService
import com.rork.guidestreamtvandroid.data.remote.TrailerResolveService
import com.rork.guidestreamtvandroid.data.remote.toTMDBResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit

/**
 * Reel tab enum — mirrors iOS ReelTab.
 */
enum class ReelTab(val key: String, val label: String) {
    FOR_YOU("for-you", "For You"),
    TRENDING("trending", "Trending"),
    NEW("new", "New"),
    COMING_SOON("coming-soon", "Coming Soon"),
}

/**
 * A single trailer reel item — mirrors iOS TrailerItem.
 */
data class TrailerItem(
    val id: String,
    val tmdbId: Int,
    val showName: String,
    val synopsis: String,
    val genre: String,
    val runtime: String,
    val platformId: String,
    val platformName: String,
    val platformColor: androidx.compose.ui.graphics.Color,
    val backdropUrl: String?,
    val posterUrl: String?,
    val trailerKey: String,
    /**
     * Ordered fallback YouTube video ids to try (in priority order) after the
     * first candidate raises a fatal embed error. Empty for single-candidate
     * reels, preserving the collapse-to-poster behavior for those. Excluded
     * from identity/dedupe (keyed off [trailerKey]).
     */
    val fallbackKeys: List<String> = emptyList(),
    val thumbnailUrl: String?,
    val voteAverage: Double,
    val tab: ReelTab,
    val isSponsored: Boolean = false,
    val isTV: Boolean = true,
    /** Title-scoped Reels (Trailers & Clips): TMDB video type, else null. */
    val videoType: String? = null,
    /** Title-scoped Reels: TMDB video name, else null. */
    val videoName: String? = null,
) {
    val youtubeUrl: String get() = "https://www.youtube.com/watch?v=$trailerKey"
    val deepLinkUrl: String? get() = if (platformId.isNotBlank()) "https://www.themoviedb.org/${if (isTV) "tv" else "movie"}/$tmdbId/watch" else null
}

/**
 * Reels view model — mirrors iOS ReelsViewModel.swift.
 * Loads trailers from TMDB (trending, on-air, upcoming), resolves trailer keys,
 * groups by tab, prefetches next reel.
 */
class ReelsViewModel : ViewModel() {

    private val tmdb = TMDBService.get()

    private val _trailers = MutableStateFlow<List<TrailerItem>>(emptyList())
    val trailers: StateFlow<List<TrailerItem>> = _trailers.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _currentTab = MutableStateFlow(ReelTab.FOR_YOU)
    val currentTab: StateFlow<ReelTab> = _currentTab.asStateFlow()

    private val _currentIndex = MutableStateFlow(0)
    val currentIndex: StateFlow<Int> = _currentIndex.asStateFlow()

    private val _swipeCount = MutableStateFlow(0)
    val swipeCount: StateFlow<Int> = _swipeCount.asStateFlow()

    companion object {
        /** Max titles resolved in parallel. Keeps TMDB/Supabase from being hammered. */
        private const val RESOLVE_CONCURRENCY = 6

        @Volatile private var instance: ReelsViewModel? = null
        fun get(): ReelsViewModel = instance ?: synchronized(this) {
            instance ?: ReelsViewModel().also { instance = it }
        }
    }

    fun loadTrailers() {
        if (_trailers.value.isNotEmpty() || _isLoading.value) return
        _isLoading.value = true
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val trending = tmdb.getTrendingTV()
                val onAir = tmdb.getOnTheAir()
                val upcoming = StreamingUpcomingService.get().fetchUpcoming()?.map { it.toTMDBResult() } ?: emptyList()

                // For You is the tab that opens first, so it is resolved and
                // published before the others. Every later tab is appended as
                // soon as it resolves instead of waiting for the whole feed,
                // so the user never stares at a spinner while three more tabs
                // finish resolving in the background.
                val forYouPool = (trending + onAir).distinctBy { it.id }
                val resolvedSoFar = mutableListOf<TrailerItem>()

                suspend fun publish(results: List<TMDBResult>, tab: ReelTab) {
                    resolvedSoFar += buildTrailers(results, tab)
                    // Dedupe within each tab (not globally): For You reuses the
                    // same trailer keys as Trending/New, so a global distinctBy
                    // would wipe out the tab-specific items.
                    _trailers.value = resolvedSoFar.distinctBy { it.tab to it.trailerKey }
                }

                publish(forYouPool, ReelTab.FOR_YOU)
                // Drop the spinner only once something is actually on screen,
                // otherwise an empty For You would flash "No trailers
                // available" while the other tabs are still resolving.
                if (resolvedSoFar.isNotEmpty()) _isLoading.value = false

                publish(trending, ReelTab.TRENDING)
                if (resolvedSoFar.isNotEmpty()) _isLoading.value = false

                publish(onAir, ReelTab.NEW)
                publish(upcoming, ReelTab.COMING_SOON)
            } finally {
                _isLoading.value = false
            }
        }
    }

    /**
     * Resolves a page of TMDB results into playable reels.
     *
     * Each title needs 2-3 network round-trips (trailer resolve, sometimes the
     * TMDB trailer key, then the top watch provider). Resolving titles one
     * after another meant ~20 titles x 3 serial requests per tab, which is
     * what stalled the feed. Titles are now resolved concurrently behind a
     * small permit gate so the API is not hammered, and the original rank
     * order is preserved by [awaitAll].
     */
    private suspend fun buildTrailers(
        results: List<TMDBResult>,
        tab: ReelTab,
    ): List<TrailerItem> = coroutineScope {
        val gate = Semaphore(RESOLVE_CONCURRENCY)
        results.take(20)
            .map { r -> async { gate.withPermit { buildTrailer(r, tab) } } }
            .awaitAll()
            .filterNotNull()
    }

    /** Resolves one TMDB result into a reel, or null when it has no playable trailer. */
    private suspend fun buildTrailer(r: TMDBResult, tab: ReelTab): TrailerItem? {
        // Server-verified playable keys in rank order. Three-way handling:
        //  * null → resolver unreachable; degrade to the unverified TMDB key
        //    so a brief Supabase outage doesn't empty the feed.
        //  * empty → title has no playable trailer at all; skip it entirely.
        //  * non-empty → first key is primary, the rest are fallbacks.
        val resolved = TrailerResolveService.resolve(r.id, r.isTV)
        val candidates: List<String> = when {
            resolved == null -> listOf(tmdb.getTrailerKey(r.id, r.isTV) ?: return null)
            resolved.isEmpty() -> return null
            else -> resolved
        }
        val key = candidates.firstOrNull() ?: return null
        val provider = tmdb.getTopWatchProvider(r.id, r.isTV)
        val platform = Platform.from(provider?.providerName)
        if (platform == null && tab != ReelTab.COMING_SOON) return null
        return TrailerItem(
            id = key,
            tmdbId = r.id,
            showName = r.displayName,
            synopsis = r.overview ?: "",
            genre = if (r.isTV) "Series" else "Movie",
            runtime = "",
            platformId = platform?.name?.lowercase() ?: "",
            platformName = platform?.name ?: "Streaming",
            platformColor = platform?.color ?: androidx.compose.ui.graphics.Color(0xFFF5821F),
            backdropUrl = r.backdropUrl,
            posterUrl = r.posterUrl,
            trailerKey = key,
            fallbackKeys = candidates.drop(1),
            thumbnailUrl = "https://img.youtube.com/vi/$key/hqdefault.jpg",
            // (fallbackKeys carries the remaining verified keys in rank order)
            voteAverage = r.voteAverage ?: 7.0,
            tab = tab,
            isTV = r.isTV,
        )
    }

    fun setTab(tab: ReelTab) {
        _currentTab.value = tab
    }

    fun setCurrentIndex(index: Int) {
        _currentIndex.value = index
        _swipeCount.value = _swipeCount.value + 1
    }

    /**
     * Trailers filtered by the current tab. For You is a real tab with its own
     * resolved items, so it filters like every other tab — returning the whole
     * list showed each video up to four times (once per tab that resolved it).
     */
    fun trailersForTab(tab: ReelTab): List<TrailerItem> =
        _trailers.value.filter { it.tab == tab }
}

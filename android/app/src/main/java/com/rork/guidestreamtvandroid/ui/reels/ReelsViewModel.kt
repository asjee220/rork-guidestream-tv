package com.rork.guidestreamtvandroid.ui.reels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rork.guidestreamtvandroid.data.models.Platform
import com.rork.guidestreamtvandroid.data.models.TMDBResult
import com.rork.guidestreamtvandroid.data.remote.TMDBService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

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
        @Volatile private var instance: ReelsViewModel? = null
        fun get(): ReelsViewModel = instance ?: synchronized(this) {
            instance ?: ReelsViewModel().also { instance = it }
        }
    }

    fun loadTrailers() {
        if (_trailers.value.isNotEmpty()) return
        _isLoading.value = true
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val trending = tmdb.getTrendingTV()
                val onAir = tmdb.getOnTheAir()
                val upcoming = tmdb.getUpcomingMovies()

                val all = mutableListOf<TrailerItem>()
                all.addAll(buildTrailers(trending, ReelTab.TRENDING, isTV = true))
                all.addAll(buildTrailers(onAir, ReelTab.NEW, isTV = true))
                all.addAll(buildTrailers(upcoming, ReelTab.COMING_SOON, isTV = false))

                // For You = merged trending + on-air, deduped
                val forYouPool = (trending + onAir).distinctBy { it.id }
                all.addAll(0, buildTrailers(forYouPool, ReelTab.FOR_YOU, isTV = true))

                // Dedupe within each tab (not globally): For You reuses the same
                // trailer keys as Trending/New, so a global distinctBy would wipe out
                // the tab-specific items and leave those tabs empty.
                _trailers.value = all.distinctBy { it.tab to it.trailerKey }
            } finally {
                _isLoading.value = false
            }
        }
    }

    private suspend fun buildTrailers(
        results: List<TMDBResult>,
        tab: ReelTab,
        isTV: Boolean,
    ): List<TrailerItem> {
        val items = mutableListOf<TrailerItem>()
        for (r in results.take(20)) {
            val key = tmdb.getTrailerKey(r.id) ?: continue
            val provider = tmdb.getTopWatchProvider(r.id)
            val platform = Platform.from(provider?.providerName)
            if (platform == null && tab != ReelTab.COMING_SOON) continue
            items.add(
                TrailerItem(
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
                    thumbnailUrl = "https://img.youtube.com/vi/$key/hqdefault.jpg",
                    voteAverage = r.voteAverage ?: 7.0,
                    tab = tab,
                    isTV = r.isTV,
                ),
            )
        }
        return items
    }

    fun setTab(tab: ReelTab) {
        _currentTab.value = tab
    }

    fun setCurrentIndex(index: Int) {
        _currentIndex.value = index
        _swipeCount.value = _swipeCount.value + 1
    }

    /** Trailers filtered by the current tab. */
    fun trailersForTab(tab: ReelTab): List<TrailerItem> {
        val all = _trailers.value
        return if (tab == ReelTab.FOR_YOU) all else all.filter { it.tab == tab }
    }
}

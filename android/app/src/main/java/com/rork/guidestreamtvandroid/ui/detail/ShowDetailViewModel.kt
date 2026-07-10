package com.rork.guidestreamtvandroid.ui.detail

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rork.guidestreamtvandroid.data.models.Platform
import com.rork.guidestreamtvandroid.data.remote.TMDBService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Show detail view model — mirrors iOS ShowDetailViewModel.swift.
 * Loads TMDB TV detail, season episodes, and watch providers.
 */
class ShowDetailViewModel : ViewModel() {

    private val tmdb = TMDBService.get()

    private val _detail = MutableStateFlow<TMDBService.TMDBTVDetail?>(null)
    val detail: StateFlow<TMDBService.TMDBTVDetail?> = _detail.asStateFlow()

    private val _season = MutableStateFlow<TMDBService.TMDBSeason?>(null)
    val season: StateFlow<TMDBService.TMDBSeason?> = _season.asStateFlow()

    private val _topProvider = MutableStateFlow<TMDBService.TMDBWatchProvider?>(null)
    val topProvider: StateFlow<TMDBService.TMDBWatchProvider?> = _topProvider.asStateFlow()

    private val _platform = MutableStateFlow<Platform?>(null)
    val platform: StateFlow<Platform?> = _platform.asStateFlow()

    private val _trailerKey = MutableStateFlow<String?>(null)
    val trailerKey: StateFlow<String?> = _trailerKey.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    private val _currentSeasonNumber = MutableStateFlow(1)
    val currentSeasonNumber: StateFlow<Int> = _currentSeasonNumber.asStateFlow()

    private var loadedTitleId: String? = null

    companion object {
        @Volatile private var instance: ShowDetailViewModel? = null
        fun get(): ShowDetailViewModel = instance ?: synchronized(this) {
            instance ?: ShowDetailViewModel().also { instance = it }
        }
    }

    fun loadIfNeeded(titleId: String, isTV: Boolean = true) {
        if (loadedTitleId == titleId) return
        loadedTitleId = titleId
        _isLoading.value = true
        _errorMessage.value = null
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val tmdbId = titleId.toIntOrNull()
                if (tmdbId == null) {
                    _errorMessage.value = "Invalid title id"
                    _isLoading.value = false
                    return@launch
                }
                if (isTV) {
                    val detailResult = tmdb.getTVDetail(tmdbId)
                    _detail.value = detailResult
                    val seasonNum = detailResult?.lastEpisodeToAir?.seasonNumber
                        ?.takeIf { it >= 1 } ?: maxOf(1, detailResult?.numberOfSeasons ?: 1)
                    _currentSeasonNumber.value = seasonNum
                    val seasonResult = tmdb.getSeason(tmdbId, seasonNum)
                    _season.value = seasonResult
                } else {
                    // Movie — load metadata from TMDB, mirroring the TV path.
                    _detail.value = tmdb.getMovieDetail(tmdbId)
                }
                val provider = tmdb.getTopWatchProvider(tmdbId)
                _topProvider.value = provider
                _platform.value = Platform.from(provider?.providerName)
                val trailer = tmdb.getTrailerKey(tmdbId)
                _trailerKey.value = trailer
            } catch (e: Exception) {
                _errorMessage.value = e.message ?: "Failed to load"
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun loadSeason(seasonNumber: Int) {
        val tmdbId = loadedTitleId?.toIntOrNull() ?: return
        _currentSeasonNumber.value = seasonNumber
        viewModelScope.launch(Dispatchers.IO) {
            val seasonResult = tmdb.getSeason(tmdbId, seasonNumber)
            _season.value = seasonResult
        }
    }

    fun reset() {
        loadedTitleId = null
        _detail.value = null
        _season.value = null
        _topProvider.value = null
        _platform.value = null
        _trailerKey.value = null
        _errorMessage.value = null
        _isLoading.value = false
        _currentSeasonNumber.value = 1
    }
}

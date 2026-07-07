package com.rork.guidestreamtvandroid.ui.sports

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rork.guidestreamtvandroid.data.models.SportsGame
import com.rork.guidestreamtvandroid.data.remote.SportsService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Sports view model — mirrors iOS SportsView state management.
 * Fetches games from ESPN and caches them with sport filtering.
 */
class SportsViewModel : ViewModel() {

    private val sportsService = SportsService.get()

    private val _games = MutableStateFlow<List<SportsGame>>(emptyList())
    val games: StateFlow<List<SportsGame>> = _games.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _selectedSport = MutableStateFlow<String?>(null)
    val selectedSport: StateFlow<String?> = _selectedSport.asStateFlow()

    /** Unique sport names available for filtering. */
    val availableSports: List<String> get() = _games.value.map { it.sport }.distinct().sorted()

    companion object {
        @Volatile private var instance: SportsViewModel? = null
        fun get(): SportsViewModel = instance ?: synchronized(this) {
            instance ?: SportsViewModel().also { instance = it }
        }
    }

    fun fetchGames() {
        if (_isLoading.value) return
        _isLoading.value = true
        viewModelScope.launch(Dispatchers.IO) {
            try {
                _games.value = sportsService.fetchAll()
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun setSport(sport: String?) {
        _selectedSport.value = sport
    }

    /** Games filtered by the selected sport (null = all). */
    fun filteredGames(): List<SportsGame> {
        val sport = _selectedSport.value ?: return _games.value
        return _games.value.filter { it.sport == sport }
    }
}

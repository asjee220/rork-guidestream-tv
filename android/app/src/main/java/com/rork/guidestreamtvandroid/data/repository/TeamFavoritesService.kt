package com.rork.guidestreamtvandroid.data.repository

import android.content.Context
import com.rork.guidestreamtvandroid.data.models.SportsGame
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Persists the user's favorited sports teams locally — mirrors iOS
 * TeamFavoritesService.swift. Keyed by ESPN team uid so a favorite survives
 * across game refreshes. Favorites persist across app launches via
 * SharedPreferences.
 */
class TeamFavoritesService private constructor(context: Context) {

    @Serializable
    data class FavoriteRow(
        val teamUid: String,
        val teamAbbr: String? = null,
        val teamName: String? = null,
        val league: String? = null,
        val sport: String? = null,
    )

    private val prefs = context.getSharedPreferences("gs.teamFavorites", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }

    private val _rows = MutableStateFlow<Map<String, FavoriteRow>>(loadFromDisk())
    val rows: StateFlow<Map<String, FavoriteRow>> = _rows.asStateFlow()

    /** Favorited team uids in insertion order. */
    fun favoriteUids(): List<String> = _rows.value.keys.toList()

    fun isFavorite(uid: String?): Boolean = uid != null && _rows.value.containsKey(uid)

    /** Toggles a team's favorite state. No-op if the team has no stable uid. */
    fun toggle(team: SportsGame.TeamSummary, league: String?, sport: String?) {
        val uid = team.uid ?: return
        val current = _rows.value.toMutableMap()
        if (current.containsKey(uid)) {
            current.remove(uid)
        } else {
            current[uid] = FavoriteRow(
                teamUid = uid,
                teamAbbr = team.abbreviation,
                teamName = team.shortName.ifEmpty { team.displayName.ifEmpty { team.name } },
                league = league,
                sport = sport,
            )
        }
        _rows.value = current
        saveToDisk(current)
    }

    private fun loadFromDisk(): Map<String, FavoriteRow> {
        val raw = prefs.getString(KEY, null) ?: return emptyMap()
        return try {
            json.decodeFromString<List<FavoriteRow>>(raw).associateBy { it.teamUid }
        } catch (_: Exception) {
            emptyMap()
        }
    }

    private fun saveToDisk(map: Map<String, FavoriteRow>) {
        try {
            val encoded = json.encodeToString(map.values.toList())
            prefs.edit().putString(KEY, encoded).apply()
        } catch (_: Exception) {
            // Persisting favorites is best-effort; ignore serialization failures.
        }
    }

    companion object {
        private const val KEY = "gs.teamFavorites.rows"

        @Volatile private var instance: TeamFavoritesService? = null
        fun init(context: Context): TeamFavoritesService =
            instance ?: synchronized(this) {
                instance ?: TeamFavoritesService(context.applicationContext).also { instance = it }
            }
        fun get(): TeamFavoritesService =
            instance ?: error("TeamFavoritesService not initialized")
    }
}

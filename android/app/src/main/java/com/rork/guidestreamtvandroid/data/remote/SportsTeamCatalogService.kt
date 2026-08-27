package com.rork.guidestreamtvandroid.data.remote

import android.util.Log
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Read-only accessor for public.sports_teams — the full roster for every
 * supported league, refreshed weekly server-side by the sports_teams_sync
 * edge function. Mirrors iOS SportsTeamCatalogService.swift.
 *
 * Why this exists: favorites could previously only be created by starring a
 * team that happened to appear on today's ESPN scoreboard, so out of season
 * most teams were unfavoritable. sports_games is not a substitute — it is a
 * record of games played, not a roster.
 *
 * Follows the ProviderBrandMapService pattern: singleton, in-memory cache,
 * never throws, callers degrade gracefully when the fetch fails.
 */
class SportsTeamCatalogService private constructor() {

    @Serializable
    data class SportsTeamRow(
        @SerialName("team_uid") val teamUid: String,
        @SerialName("team_id") val teamId: String? = null,
        @SerialName("team_abbr") val teamAbbr: String? = null,
        @SerialName("team_name") val teamName: String,
        @SerialName("short_name") val shortName: String? = null,
        val league: String,
        val sport: String,
        val color: String? = null,
        @SerialName("logo_url") val logoUrl: String? = null,
        @SerialName("sort_order") val sortOrder: Int = 0,
    ) {
        /** Label used on picker tiles — the short name where ESPN provides one
         * ("Knicks"), otherwise the full display name. */
        val displayLabel: String
            get() = shortName?.trim()?.takeIf { it.isNotEmpty() } ?: teamName

        /** Lowercased haystack for the picker's search field. */
        val searchHaystack: String
            get() = "$teamName ${shortName ?: ""} ${teamAbbr ?: ""}".lowercase()
    }

    private val _teams = MutableStateFlow<List<SportsTeamRow>>(emptyList())
    val teams: StateFlow<List<SportsTeamRow>> = _teams.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    /** Distinct sports in catalogue order, e.g. ["NFL", "NBA", "MLB", "Soccer"]. */
    fun sports(): List<String> = _teams.value.map { it.sport }.distinct()

    fun teamsForSport(sport: String): List<SportsTeamRow> =
        _teams.value.filter { it.sport == sport }

    /**
     * Fetches the catalogue. Skips the network entirely when a non-empty cache
     * already exists unless [force] is set, so opening the picker twice in one
     * session costs one round trip.
     */
    suspend fun load(force: Boolean = false) {
        if (!force && _teams.value.isNotEmpty()) return
        if (_isLoading.value) return
        _isLoading.value = true
        try {
            val rows = SupabaseManager.client.postgrest
                .from("sports_teams")
                .select {
                    filter { eq("is_active", true) }
                    order("league", Order.ASCENDING)
                    order("sort_order", Order.ASCENDING)
                }
                .decodeList<SportsTeamRow>()
            if (rows.isNotEmpty()) _teams.value = rows
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            Log.e(TAG, "load failed: ${e.message}", e)
            // Keep whatever is already cached.
        } finally {
            _isLoading.value = false
        }
    }

    companion object {
        private const val TAG = "SportsTeamCatalog"

        @Volatile private var instance: SportsTeamCatalogService? = null
        fun get(): SportsTeamCatalogService = instance ?: synchronized(this) {
            instance ?: SportsTeamCatalogService().also { instance = it }
        }
    }
}

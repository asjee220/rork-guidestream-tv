package com.rork.guidestreamtvandroid.data.repository

import android.content.Context
import android.util.Log
import com.rork.guidestreamtvandroid.data.local.DeviceIdentity
import com.rork.guidestreamtvandroid.data.models.SportsGame
import com.rork.guidestreamtvandroid.data.remote.SupabaseManager
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Persists the user's favorited sports teams — mirrors iOS
 * TeamFavoritesService.swift. Keyed by ESPN team uid so a favorite survives
 * across game refreshes.
 *
 * Favorites are written through to `public.team_favorites` on Supabase as well
 * as to SharedPreferences. The server copy is what `sports_poll_and_notify`
 * reads to send starting-soon / going-live / final-score pushes — without it,
 * Android favorites are invisible to the backend and generate no notifications.
 * Scoping matches StreamsViewModel exactly: signed-in rows are keyed by
 * `user_id`, guest rows by `device_id` with `user_id IS NULL`, so two accounts
 * on one install never read or delete each other's favorites.
 *
 * Local writes are optimistic and are never rolled back on a network failure,
 * matching the iOS behaviour and the StreamsViewModel pattern.
 */
class TeamFavoritesService private constructor(context: Context) {

    @Serializable
    data class FavoriteRow(
        val teamUid: String,
        val teamAbbr: String? = null,
        val teamName: String? = null,
        val league: String? = null,
        val sport: String? = null,
        val teamId: String? = null,
    )

    /** Wire shape of a public.team_favorites row. */
    @Serializable
    private data class RemoteFavoriteRow(
        @SerialName("team_uid") val teamUid: String? = null,
        @SerialName("team_id") val teamId: String? = null,
        @SerialName("team_abbr") val teamAbbr: String? = null,
        @SerialName("team_name") val teamName: String? = null,
        val league: String? = null,
        val sport: String? = null,
    )

    private val prefs = context.getSharedPreferences("gs.teamFavorites", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _rows = MutableStateFlow<Map<String, FavoriteRow>>(loadFromDisk())
    val rows: StateFlow<Map<String, FavoriteRow>> = _rows.asStateFlow()

    private val currentUserId: String? get() = AuthViewModel.get().currentUserId
    private val deviceId: String get() = DeviceIdentity.get().deviceId

    /** Favorited team uids in insertion order. */
    fun favoriteUids(): List<String> = _rows.value.keys.toList()

    fun isFavorite(uid: String?): Boolean = uid != null && _rows.value.containsKey(uid)

    /**
     * Loads the current owner's favorites from Supabase and replaces the local
     * cache with the result. Keeps the existing local cache on failure so the
     * chips never blank out because the network hiccuped.
     */
    suspend fun load() {
        try {
            val uid = currentUserId
            val remote = SupabaseManager.client.postgrest
                .from("team_favorites")
                .select {
                    filter {
                        if (uid != null) {
                            eq("user_id", uid)
                        } else {
                            eq("device_id", deviceId)
                            exact("user_id", null)
                        }
                    }
                }
                .decodeList<RemoteFavoriteRow>()

            val mapped = remote.mapNotNull { r ->
                val teamUid = r.teamUid ?: return@mapNotNull null
                teamUid to FavoriteRow(
                    teamUid = teamUid,
                    teamAbbr = r.teamAbbr,
                    teamName = r.teamName,
                    league = r.league,
                    sport = r.sport,
                    teamId = r.teamId,
                )
            }.toMap()

            _rows.value = mapped
            saveToDisk(mapped)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            Log.e(TAG, "load failed: ${e.message}", e)
            // Leave the local cache in place.
        }
    }

    /** Fire-and-forget wrapper for callers outside a coroutine scope. */
    fun refresh() {
        scope.launch { load() }
    }

    /** Toggles a team's favorite state. No-op if the team has no stable uid. */
    fun toggle(team: SportsGame.TeamSummary, league: String?, sport: String?) {
        val uid = team.uid ?: return
        val wasFavorited = _rows.value.containsKey(uid)
        val current = _rows.value.toMutableMap()

        if (wasFavorited) {
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

        val inserted = current[uid]
        scope.launch {
            if (wasFavorited || inserted == null) deleteRemote(uid) else insertRemote(listOf(inserted))
        }
    }

    /**
     * Adds several favorites in one pass — used by the team picker, which can
     * commit an arbitrary number of teams at once. Already-favorited uids are
     * skipped, so this is safe to call with a full selection.
     */
    suspend fun addMany(entries: List<FavoriteRow>) {
        val current = _rows.value.toMutableMap()
        val added = entries.filter { !current.containsKey(it.teamUid) }
        if (added.isEmpty()) return

        added.forEach { current[it.teamUid] = it }
        _rows.value = current
        saveToDisk(current)

        insertRemote(added)
    }

    /** Removes several favorites in one pass. Missing uids are ignored. */
    suspend fun removeMany(uids: List<String>) {
        val current = _rows.value.toMutableMap()
        val removed = uids.filter { current.remove(it) != null }
        if (removed.isEmpty()) return

        _rows.value = current
        saveToDisk(current)

        removed.forEach { deleteRemote(it) }
    }

    private suspend fun insertRemote(entries: List<FavoriteRow>) {
        if (entries.isEmpty()) return
        val uid = currentUserId
        val payloads = entries.map { row ->
            buildJsonObject {
                put("device_id", deviceId)
                put("team_uid", row.teamUid)
                if (uid != null) put("user_id", uid)
                row.teamId?.let { put("team_id", it) }
                row.teamAbbr?.takeIf { it.isNotBlank() && it != "\u2014" }?.let { put("team_abbr", it) }
                row.teamName?.let { put("team_name", it) }
                row.league?.let { put("league", it) }
                row.sport?.let { put("sport", it) }
            }
        }
        try {
            SupabaseManager.client.postgrest.from("team_favorites").insert(payloads)
            // A favorite is only useful if the backend can reach this device.
            PushTokenManager.get().resaveCachedToken()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            val msg = e.message?.lowercase() ?: ""
            if (msg.contains("duplicate") || msg.contains("23505")) {
                // Already saved — no-op.
            } else {
                Log.e(TAG, "insert failed: ${e.message}", e)
                // Keep the optimistic local state, matching iOS.
            }
        }
    }

    private suspend fun deleteRemote(teamUid: String) {
        val uid = currentUserId
        try {
            SupabaseManager.client.postgrest
                .from("team_favorites")
                .delete {
                    filter {
                        eq("team_uid", teamUid)
                        if (uid != null) {
                            eq("user_id", uid)
                        } else {
                            eq("device_id", deviceId)
                            exact("user_id", null)
                        }
                    }
                }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            Log.e(TAG, "delete failed: ${e.message}", e)
        }
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

    /**
     * Clears all in-memory team-favorite state and removes the local disk
     * cache. Called from [AuthViewModel.signOut] so the next user starts with
     * an empty favorites set instead of inheriting the previous user's teams.
     * Deliberately does NOT delete server rows.
     */
    fun clearLocalCache() {
        _rows.value = emptyMap()
        prefs.edit().remove(KEY).apply()
    }

    companion object {
        private const val TAG = "TeamFavorites"
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

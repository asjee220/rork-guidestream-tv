package com.rork.guidestreamtvandroid.data.repository

import android.content.Context
import com.rork.guidestreamtvandroid.data.local.DeviceIdentity
import com.rork.guidestreamtvandroid.data.models.NewEpisodeRow
import com.rork.guidestreamtvandroid.data.models.UserStream
import com.rork.guidestreamtvandroid.data.remote.SupabaseManager
import io.github.jan.supabase.postgrest.query.Order
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
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Watch list store with a local-first persistence strategy.
 * Mirrors iOS StreamsViewModel.swift.
 */
class StreamsViewModel private constructor(context: Context) {

    @Serializable
    private data class WatchedRow(
        @SerialName("title_id") val titleId: String,
    )

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val prefs = context.getSharedPreferences("gs_prefs", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    private val localCacheKey = "gs.watchList.localCache.v1"
    private val guestUserId = "guest"

    private val _userStreams = MutableStateFlow<List<UserStream>>(emptyList())
    val userStreams: StateFlow<List<UserStream>> = _userStreams.asStateFlow()

    private val _watchedIds = MutableStateFlow<Set<String>>(emptySet())
    val watchedIds: StateFlow<Set<String>> = _watchedIds.asStateFlow()

    private val _newEpisodes = MutableStateFlow<List<NewEpisodeRow>>(emptyList())
    val newEpisodes: StateFlow<List<NewEpisodeRow>> = _newEpisodes.asStateFlow()

    private val _isLoadingStreams = MutableStateFlow(false)
    val isLoadingStreams: StateFlow<Boolean> = _isLoadingStreams.asStateFlow()

    private val _isLoadingEpisodes = MutableStateFlow(false)
    val isLoadingEpisodes: StateFlow<Boolean> = _isLoadingEpisodes.asStateFlow()

    private val _lastError = MutableStateFlow<String?>(null)
    val lastError: StateFlow<String?> = _lastError.asStateFlow()

    private val currentUserId: String?
        get() = AuthViewModel.get().currentUserId

    companion object {
        @Volatile private var instance: StreamsViewModel? = null
        fun init(context: Context): StreamsViewModel =
            instance ?: synchronized(this) {
                instance ?: StreamsViewModel(context.applicationContext).also {
                    instance = it
                    it._userStreams.value = it.loadLocalCache()
                }
            }
        fun get(): StreamsViewModel =
            instance ?: error("StreamsViewModel not initialized")
    }

    fun refreshAll() {
        scope.launch {
            fetchUserStreams()
            fetchNewEpisodes()
        }
    }

    /** True when the series is flagged watched by the current owner. */
    fun isWatched(titleId: String): Boolean = _watchedIds.value.contains(titleId.trim())

    fun fetchUserStreams() {
        _isLoadingStreams.value = true
        scope.launch {
            try {
                val deviceId = DeviceIdentity.get().deviceId
                val uid = currentUserId
                val rows = SupabaseManager.client.postgrest
                    .from("user_streams")
                    .select {
                        filter {
                            if (uid != null) {
                                or {
                                    eq("user_id", uid)
                                    eq("device_id", deviceId)
                                }
                            } else {
                                eq("device_id", deviceId)
                            }
                        }
                        order("added_at", Order.DESCENDING)
                    }
                    .decodeList<UserStream>()
                val merged = mergeRemoteWithLocal(rows)
                _userStreams.value = merged
                saveLocalCache(merged)
            } catch (e: Throwable) {
                if (e is CancellationException) throw e
                _lastError.value = e.message
                _userStreams.value = loadLocalCache()
            } finally {
                _isLoadingStreams.value = false
            }
            fetchWatchedIds()
        }
    }

    /**
     * Hydrates the series-level watched set for the current owner. Runs on the
     * same pass as [fetchUserStreams] so the eye icons reflect server state on
     * launch. Failures leave the optimistic/local set untouched.
     */
    private suspend fun fetchWatchedIds() {
        try {
            val deviceId = DeviceIdentity.get().deviceId
            val uid = currentUserId
            val rows = SupabaseManager.client.postgrest
                .from("title_watched")
                .select {
                    filter {
                        if (uid != null) {
                            or {
                                eq("user_id", uid)
                                eq("device_id", deviceId)
                            }
                        } else {
                            eq("device_id", deviceId)
                        }
                    }
                }
                .decodeList<WatchedRow>()
            _watchedIds.value = rows.map { it.titleId }.toSet()
        } catch (e: Throwable) {
            if (e is CancellationException) throw e
            _lastError.value = e.message
        }
    }

    /**
     * Optimistically flips the single series-level watched flag and writes
     * through to `title_watched`. Mirrors the watchlist owner rules exactly:
     * signed-in rows use `user_id`, guests use `device_id`. One tap marks the
     * whole series — never per-episode.
     */
    fun toggleWatched(
        titleId: String,
        titleName: String? = null,
        mediaType: String? = null,
        tmdbId: Int? = null,
    ) {
        val trimmedId = titleId.trim()
        if (trimmedId.isEmpty()) return
        val wasWatched = _watchedIds.value.contains(trimmedId)

        // Optimistic flip
        _watchedIds.value = if (wasWatched) {
            _watchedIds.value - trimmedId
        } else {
            _watchedIds.value + trimmedId
        }

        WatchIntentLogger.get().log(
            WatchIntentLogger.IntentEventType.WATCHED_TOGGLED,
            titleId = trimmedId,
        )

        scope.launch {
            val deviceId = DeviceIdentity.get().deviceId
            val uid = currentUserId
            try {
                if (wasWatched) {
                    SupabaseManager.client.postgrest
                        .from("title_watched")
                        .delete {
                            filter {
                                eq("title_id", trimmedId)
                                if (uid != null) {
                                    or {
                                        eq("user_id", uid)
                                        eq("device_id", deviceId)
                                    }
                                } else {
                                    eq("device_id", deviceId)
                                }
                            }
                        }
                } else {
                    insertWatched(
                        userId = uid,
                        deviceId = deviceId,
                        titleId = trimmedId,
                        titleName = titleName,
                        mediaType = mediaType,
                        tmdbId = tmdbId,
                    )
                }
            } catch (e: Throwable) {
                if (e is CancellationException) throw e
                _lastError.value = e.message
            }
        }
    }

    private suspend fun insertWatched(
        userId: String?,
        deviceId: String,
        titleId: String,
        titleName: String?,
        mediaType: String?,
        tmdbId: Int?,
    ): Boolean {
        val payload = buildJsonObject {
            put("device_id", deviceId)
            put("title_id", titleId)
            if (userId != null) put("user_id", userId)
            if (titleName != null) put("title_name", titleName)
            if (mediaType != null) put("media_type", mediaType)
            if (tmdbId != null) put("tmdb_id", tmdbId)
        }
        return try {
            SupabaseManager.client.postgrest
                .from("title_watched")
                .insert(payload)
            true
        } catch (e: Throwable) {
            if (e is CancellationException) throw e
            val msg = e.message?.lowercase() ?: ""
            if (msg.contains("duplicate") || msg.contains("23505")) true
            else {
                _lastError.value = e.message
                false
            }
        }
    }

    fun fetchNewEpisodes() {
        _isLoadingEpisodes.value = true
        scope.launch {
            try {
                val deviceId = DeviceIdentity.get().deviceId
                val uid = currentUserId
                val mine = SupabaseManager.client.postgrest
                    .from("user_streams")
                    .select {
                        filter {
                            if (uid != null) {
                                or {
                                    eq("user_id", uid)
                                    eq("device_id", deviceId)
                                }
                            } else {
                                eq("device_id", deviceId)
                            }
                        }
                    }
                    .decodeList<UserStream>()
                val titleIds = mine.map { it.titleId }
                if (titleIds.isEmpty()) {
                    _newEpisodes.value = emptyList()
                    return@launch
                }
                val tmdbIds = titleIds.filter { it.trim().toIntOrNull() != null }
                val nonTmdbIds = titleIds.filter { it.trim().toIntOrNull() == null }
                val allRows = mutableListOf<NewEpisodeRow>()
                if (tmdbIds.isNotEmpty()) {
                    val tmdbRows = SupabaseManager.client.postgrest
                        .from("new_episodes")
                        .select {
                            filter {
                                isIn("title_id", tmdbIds)
                                eq("is_new", true)
                            }
                            order("released_at", Order.DESCENDING)
                            limit(20)
                        }
                        .decodeList<NewEpisodeRow>()
                    allRows.addAll(tmdbRows)
                }
                if (nonTmdbIds.isNotEmpty()) {
                    val nonTmdbRows = SupabaseManager.client.postgrest
                        .from("new_episodes")
                        .select {
                            filter { isIn("title_id", nonTmdbIds) }
                            order("released_at", Order.DESCENDING)
                            limit(20)
                        }
                        .decodeList<NewEpisodeRow>()
                    allRows.addAll(nonTmdbRows)
                }
                _newEpisodes.value = allRows.sortedByDescending { it.releasedAt }.take(20)
            } catch (e: Throwable) {
                if (e is CancellationException) throw e
                _lastError.value = e.message
            } finally {
                _isLoadingEpisodes.value = false
            }
        }
    }

    fun addToMyStreams(
        titleId: String,
        title: String? = null,
        posterUrl: String? = null,
        platform: String? = null,
    ) {
        val trimmedId = titleId.trim()
        if (trimmedId.isEmpty()) return
        val alreadySaved = _userStreams.value.any { it.titleId == trimmedId }
        if (!alreadySaved) {
            val optimistic = UserStream(
                id = java.util.UUID.randomUUID().toString(),
                userId = currentUserId ?: guestUserId,
                titleId = trimmedId,
                title = title,
                posterUrl = posterUrl,
                platform = platform,
                addedAt = null,
            )
            _userStreams.value = listOf(optimistic) + _userStreams.value
            saveLocalCache(_userStreams.value)
        }
        WatchIntentLogger.get().log(
            WatchIntentLogger.IntentEventType.STREAM_ADDED,
            titleId = trimmedId,
            platformId = platform?.lowercase(),
        )
        scope.launch {
            val didInsert = insertUserStream(
                userId = currentUserId,
                deviceId = DeviceIdentity.get().deviceId,
                titleId = trimmedId,
                title = title,
                posterUrl = posterUrl,
                platform = platform,
            )
            if (didInsert) fetchUserStreams()
        }
    }

    private suspend fun insertUserStream(
        userId: String?,
        deviceId: String,
        titleId: String,
        title: String?,
        posterUrl: String?,
        platform: String?,
    ): Boolean {
        val safeTitle = title ?: titleId
        val payload = buildJsonObject {
            put("device_id", deviceId)
            put("title_id", titleId)
            put("title_name", safeTitle)
            if (userId != null) put("user_id", userId)
            if (title != null) put("title", title)
            if (posterUrl != null) put("poster_url", posterUrl)
            if (platform != null) put("platform", platform)
        }
        return try {
            SupabaseManager.client.postgrest
                .from("user_streams")
                .insert(payload)
            true
        } catch (e: Throwable) {
            if (e is CancellationException) throw e
            val msg = e.message?.lowercase() ?: ""
            if (msg.contains("duplicate") || msg.contains("23505")) true
            else {
                _lastError.value = e.message
                false
            }
        }
    }

    fun removeFromMyStreams(titleId: String) {
        val trimmedId = titleId.trim()
        if (trimmedId.isEmpty()) return
        _userStreams.value = _userStreams.value.filter { it.titleId != trimmedId }
        saveLocalCache(_userStreams.value)
        WatchIntentLogger.get().log(
            WatchIntentLogger.IntentEventType.STREAM_REMOVED,
            titleId = trimmedId,
        )
        scope.launch {
            try {
                val deviceId = DeviceIdentity.get().deviceId
                val uid = currentUserId
                SupabaseManager.client.postgrest
                    .from("user_streams")
                    .delete {
                        filter {
                            eq("title_id", trimmedId)
                            if (uid != null) {
                                or {
                                    eq("user_id", uid)
                                    eq("device_id", deviceId)
                                }
                            } else {
                                eq("device_id", deviceId)
                            }
                        }
                    }
            } catch (e: Throwable) {
                if (e is CancellationException) throw e
                _lastError.value = e.message
            }
        }
    }

    fun syncLocalToSupabase() {
        scope.launch {
            val uid = currentUserId ?: return@launch
            val local = loadLocalCache()
            val pending = local.filter { it.userId == guestUserId }
            val deviceId = DeviceIdentity.get().deviceId
            for (row in pending) {
                insertUserStream(
                    userId = uid,
                    deviceId = deviceId,
                    titleId = row.titleId,
                    title = row.title,
                    posterUrl = row.posterUrl,
                    platform = row.platform,
                )
            }
            val remaining = local.filter { it.userId != guestUserId }
            saveLocalCache(remaining)
            fetchUserStreams()
        }
    }

    fun clearLocalCache() {
        _userStreams.value = emptyList()
        _newEpisodes.value = emptyList()
        prefs.edit().remove(localCacheKey).apply()
    }

    private fun loadLocalCache(): List<UserStream> {
        val data = prefs.getString(localCacheKey, null) ?: return emptyList()
        return try {
            json.decodeFromString<List<UserStream>>(data)
        } catch (_: Exception) { emptyList() }
    }

    private fun saveLocalCache(streams: List<UserStream>) {
        try {
            val data = json.encodeToString<List<UserStream>>(streams)
            prefs.edit().putString(localCacheKey, data).apply()
        } catch (_: Exception) {}
    }

    private fun mergeRemoteWithLocal(remote: List<UserStream>): List<UserStream> {
        val remoteIds = remote.map { it.titleId }.toSet()
        val pendingLocal = loadLocalCache().filter { it.titleId !in remoteIds }
        return remote + pendingLocal
    }
}

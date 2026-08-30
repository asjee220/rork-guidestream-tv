package com.rork.guidestreamtvandroid.data.repository

import android.content.Context
import com.rork.guidestreamtvandroid.data.local.DeviceIdentity
import com.rork.guidestreamtvandroid.data.models.NewEpisodeRow
import com.rork.guidestreamtvandroid.data.models.TitleId
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
import kotlinx.coroutines.coroutineScope
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

    @Serializable
    private data class TitleRecencyRow(
        @SerialName("title_id") val titleId: String = "",
        @SerialName("last_content_at") val lastContentAt: String? = null,
        @SerialName("content_kind") val contentKind: String? = null,
    )

    @Serializable
    private data class WatchlistSeenRow(
        @SerialName("title_id") val titleId: String = "",
        @SerialName("seen_content_at") val seenContentAt: String? = null,
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

    private val _latestContentAt = MutableStateFlow<Map<String, Long>>(emptyMap())
    val latestContentAt: StateFlow<Map<String, Long>> = _latestContentAt.asStateFlow()

    private val _latestContentKind = MutableStateFlow<Map<String, String>>(emptyMap())
    val latestContentKind: StateFlow<Map<String, String>> = _latestContentKind.asStateFlow()

    private val _seenContentAt = MutableStateFlow<Map<String, Long>>(emptyMap())
    val seenContentAt: StateFlow<Map<String, Long>> = _seenContentAt.asStateFlow()

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
            fetchLatestContentDates()
            fetchWatchlistSeen()
        }
    }

    /**
     * Awaitable variant of [refreshAll] for pull-to-refresh. Launches all four
     * fetches concurrently inside [coroutineScope], each individually isolated so
     * a thrown exception in one never cancels the others and never propagates
     * out of this function (CancellationException is rethrown). Returns when
     * all four have completed.
     */
    suspend fun refreshAllNow() {
        coroutineScope {
            val jobs = listOf(
                launch(Dispatchers.IO) {
                    try { fetchUserStreamsNow() }
                    catch (c: CancellationException) { throw c }
                    catch (_: Exception) {}
                },
                launch(Dispatchers.IO) {
                    try { fetchNewEpisodesNow() }
                    catch (c: CancellationException) { throw c }
                    catch (_: Exception) {}
                },
                launch(Dispatchers.IO) {
                    try { fetchLatestContentDates() }
                    catch (c: CancellationException) { throw c }
                    catch (_: Exception) {}
                },
                launch(Dispatchers.IO) {
                    try { fetchWatchlistSeen() }
                    catch (c: CancellationException) { throw c }
                    catch (_: Exception) {}
                },
            )
            jobs.forEach { it.join() }
        }
    }

    /** True when the series is flagged watched by the current owner. */
    fun isWatched(titleId: String): Boolean = _watchedIds.value.contains(titleId.trim())

    fun fetchUserStreams() {
        _isLoadingStreams.value = true
        scope.launch { fetchUserStreamsNow() }
    }

    private suspend fun fetchUserStreamsNow() {
        try {
            val deviceId = DeviceIdentity.get().deviceId
            val uid = currentUserId
            val rows = SupabaseManager.client.postgrest
                .from("user_streams")
                .select {
                    filter {
                        // Single-ownership scoping: signed-in users read
                        // strictly by user_id; guests read by device_id AND
                        // user_id IS NULL so two accounts on one install
                        // never see each other's rows.
                        if (uid != null) {
                            eq("user_id", uid)
                        } else {
                            eq("device_id", deviceId)
                            exact("user_id", null)
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
                            eq("user_id", uid)
                        } else {
                            eq("device_id", deviceId)
                            exact("user_id", null)
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
        if (!wasWatched) {
            markWatchlistSeenIfSaved(trimmedId)
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
                                    eq("user_id", uid)
                                } else {
                                    eq("device_id", deviceId)
                                    exact("user_id", null)
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
        scope.launch { fetchNewEpisodesNow() }
    }

    private suspend fun fetchNewEpisodesNow() {
        try {
            val deviceId = DeviceIdentity.get().deviceId
            val uid = currentUserId
            val mine = SupabaseManager.client.postgrest
                .from("user_streams")
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
                .decodeList<UserStream>()
            val titleIds = mine.map { it.titleId }
            if (titleIds.isEmpty()) {
                _newEpisodes.value = emptyList()
                return
            }
            val tmdbIds = titleIds.filter { TitleId.tmdbId(it) != null }
            val nonTmdbIds = titleIds.filter { TitleId.tmdbId(it) == null }
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
            _newEpisodes.value = allRows
                .filter { isNewForViewer(it) }
                .sortedByDescending { it.releasedAt }
                .take(20)
        } catch (e: Throwable) {
            if (e is CancellationException) throw e
            _lastError.value = e.message
        } finally {
            _isLoadingEpisodes.value = false
        }
    }

    /**
     * Whether a `new_episodes` row is still new for *this* viewer. `is_new` is
     * a shared, server-owned column, so on its own it can never reflect one
     * person having already watched (GUI-74). Three conditions, all required:
     * the server still considers the row new; the episode has actually landed
     * (a future `released_at` is a scheduled drop, not a new episode); and the
     * viewer has not opened the title since it landed.
     */
    fun isNewForViewer(row: NewEpisodeRow, nowMillis: Long = System.currentTimeMillis()): Boolean {
        if (row.isNew == false) return false
        val released = parseTimestampMillis(row.releasedAt) ?: return true
        if (released > nowMillis) return false
        val seen = _seenContentAt.value[row.titleId] ?: return true
        return seen < released
    }

    /** Parses an ISO-8601 timestamp the same way `fetchWatchlistSeen` does. */
    private fun parseTimestampMillis(raw: String?): Long? {
        if (raw.isNullOrBlank()) return null
        return try {
            java.time.Instant.parse(raw).toEpochMilli()
        } catch (_: Exception) {
            try {
                java.time.OffsetDateTime.parse(raw).toInstant().toEpochMilli()
            } catch (_: Exception) {
                null
            }
        }
    }

    fun addToMyStreams(
        titleId: String,
        title: String? = null,
        posterUrl: String? = null,
        platform: String? = null,
        isTv: Boolean? = null,
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
                isTv = isTv,
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
                isTv = isTv,
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
        isTv: Boolean? = null,
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
            if (isTv != null) put("is_tv", isTv)
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
                                eq("user_id", uid)
                            } else {
                                eq("device_id", deviceId)
                                exact("user_id", null)
                            }
                        }
                    }
            } catch (e: Throwable) {
                if (e is CancellationException) throw e
                _lastError.value = e.message
            }
        }
    }

    /**
     * Persists a corrected media type onto an existing user_streams row.
     * Called when the detail screen's legacy heal determines a saved title was
     * actually a movie (or show) so the row self-corrects permanently.
     */
    fun updateStreamMediaType(titleId: String, isTv: Boolean) {
        val trimmedId = titleId.trim()
        if (trimmedId.isEmpty()) return
        val current = _userStreams.value.firstOrNull { it.titleId == trimmedId } ?: return
        if (current.isTv == isTv) return
        _userStreams.value = _userStreams.value.map {
            if (it.titleId == trimmedId) it.copy(isTv = isTv) else it
        }
        saveLocalCache(_userStreams.value)
        scope.launch {
            try {
                val deviceId = DeviceIdentity.get().deviceId
                val uid = currentUserId
                SupabaseManager.client.postgrest
                    .from("user_streams")
                    .update({ set("is_tv", isTv) }) {
                        filter {
                            eq("title_id", trimmedId)
                            if (uid != null) {
                                eq("user_id", uid)
                            } else {
                                eq("device_id", deviceId)
                                exact("user_id", null)
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
                    isTv = row.isTv,
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
        _watchedIds.value = emptySet()
        _latestContentAt.value = emptyMap()
        _latestContentKind.value = emptyMap()
        _seenContentAt.value = emptyMap()
        prefs.edit().remove(localCacheKey).apply()
    }

    // MARK: - Ownership claiming

    /**
     * Promotes any guest-era rows on this device (user_id IS NULL,
     * device_id matches) to the signed-in user via the `claim_device_rows`
     * SECURITY DEFINER RPC. Called from [AuthViewModel] at every authenticated
     * entry point **before** [syncLocalToSupabase] so guest rows are
     * attributed to the new account before the first fetch. Silently swallows
     * errors (no session, network failure, zero guest rows) so it never
     * blocks or delays the subsequent fetch.
     */
    suspend fun claimDeviceRows() {
        try {
            SupabaseManager.client.postgrest
                .rpc(
                    function = "claim_device_rows",
                    parameters = buildJsonObject {
                        put("p_device_id", DeviceIdentity.get().deviceId)
                    },
                )
        } catch (e: Throwable) {
            if (e is CancellationException) throw e
            println("[Streams] claimDeviceRows failed: ${e.message}")
        }
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

    /**
     * Fetches the most-recent content timestamp for each saved title from the
     * `title_recency` table so sorters can promote freshly updated titles.
     * Titles without a row, or with an unparseable/null timestamp, keep their
     * existing added_at position. Failures leave the previous map untouched.
     */
    private suspend fun fetchLatestContentDates() {
        if (_userStreams.value.isEmpty()) {
            _latestContentAt.value = emptyMap()
            _latestContentKind.value = emptyMap()
            return
        }
        try {
            val titleIds = _userStreams.value.map { it.titleId }.distinct()
            val rows = SupabaseManager.client.postgrest
                .from("title_recency")
                .select {
                    filter { isIn("title_id", titleIds) }
                }
                .decodeList<TitleRecencyRow>()
            val dateMap = HashMap<String, Long>()
            val kindMap = HashMap<String, String>()
            for (row in rows) {
                val raw = row.lastContentAt
                if (raw != null) {
                    val millis: Long = try {
                        java.time.Instant.parse(raw).toEpochMilli()
                    } catch (_: Exception) {
                        try {
                            java.time.OffsetDateTime.parse(raw).toInstant().toEpochMilli()
                        } catch (_: Exception) {
                            0L
                        }
                    }
                    if (millis > 0L) dateMap[row.titleId] = millis
                }
                if (row.contentKind != null) {
                    kindMap[row.titleId] = row.contentKind
                }
            }
            _latestContentAt.value = dateMap
            _latestContentKind.value = kindMap
        } catch (e: Throwable) {
            if (e is CancellationException) throw e
            _lastError.value = e.message
        }
    }

    /**
     * Fetches `watchlist_seen` rows for the current owner and saved title_ids
     * so the watch-list badge can tell whether new content has arrived since
     * the user last opened a title. Owner is the signed-in user id when
     * authenticated, otherwise the device id — the same identity used for
     * `user_streams`.
     */
    suspend fun fetchWatchlistSeen() {
        if (_userStreams.value.isEmpty()) {
            _seenContentAt.value = emptyMap()
            return
        }
        try {
            val titleIds = _userStreams.value.map { it.titleId }.distinct()
            val owner = currentUserId ?: DeviceIdentity.get().deviceId
            val rows = SupabaseManager.client.postgrest
                .from("watchlist_seen")
                .select {
                    filter {
                        eq("owner", owner)
                        isIn("title_id", titleIds)
                    }
                }
                .decodeList<WatchlistSeenRow>()
            val map = HashMap<String, Long>()
            for (row in rows) {
                val raw = row.seenContentAt ?: continue
                val millis: Long = try {
                    java.time.Instant.parse(raw).toEpochMilli()
                } catch (_: Exception) {
                    try {
                        java.time.OffsetDateTime.parse(raw).toInstant().toEpochMilli()
                    } catch (_: Exception) {
                        continue
                    }
                }
                map[row.titleId] = millis
            }
            _seenContentAt.value = map
        } catch (e: Throwable) {
            if (e is CancellationException) throw e
            _lastError.value = e.message
        }
    }

    /**
     * Upserts a `watchlist_seen` row marking the title as seen now, and
     * optimistically updates `seenContentAt` so the badge disappears
     * immediately. Owner is the signed-in user id when authenticated,
     * otherwise the device id.
     */
    fun markWatchlistSeenIfSaved(titleId: String) {
        val trimmedId = titleId.trim()
        if (trimmedId.isEmpty()) return
        if (!_userStreams.value.any { it.titleId == trimmedId }) return
        markWatchlistSeen(trimmedId)
    }

    fun markWatchlistSeen(titleId: String) {
        val trimmedId = titleId.trim()
        if (trimmedId.isEmpty()) return
        val owner = currentUserId ?: DeviceIdentity.get().deviceId
        // Stamp at the latest known content date whenever that is ahead of now.
        // `title_recency.last_content_at` is frequently a date-only air date
        // stored at midnight UTC, so a show whose next episode lands later
        // today already carries a `last_content_at` in the future. Stamping a
        // plain `now` would leave `seen < last_content`, and `newBadgeText`
        // would keep the chip alive through the very tap meant to clear it.
        val now = maxOf(
            System.currentTimeMillis(),
            _latestContentAt.value[trimmedId] ?: Long.MIN_VALUE,
        )
        // Optimistic clear so the badge vanishes before the server responds.
        _seenContentAt.value = _seenContentAt.value + (trimmedId to now)
        scope.launch {
            try {
                val payload = buildJsonObject {
                    put("owner", owner)
                    put("title_id", trimmedId)
                    put("seen_content_at", java.time.Instant.ofEpochMilli(now).toString())
                }
                SupabaseManager.client.postgrest
                    .from("watchlist_seen")
                    .upsert(payload) { onConflict = "owner,title_id" }
            } catch (e: Throwable) {
                if (e is CancellationException) throw e
                _lastError.value = e.message
            }
        }
    }

    /**
     * Returns the watch-list new-content badge text for a saved title, or
     * null when no badge should show.
     *
     * A badge shows when `last_content_at` is non-null AND `content_kind` is
     * not "movie" AND `last_content_at` is strictly greater than the baseline,
     * where baseline = `seen_content_at` for that title if present, otherwise
     * that user_stream's `added_at` (so a freshly-saved old title never
     * badges, only content arriving after it was saved does).
     *
     * Returns "NEW EPISODE" when content_kind == "tv" and "NEW UPLOAD" for
     * every other non-movie kind (youtube, podcast, twitch, kick).
     */
    fun newBadgeText(
        stream: UserStream,
        latestContentAt: Map<String, Long>,
        latestContentKind: Map<String, String>,
        seenContentAt: Map<String, Long>,
    ): String? {
        val lastContent = latestContentAt[stream.titleId] ?: return null
        val kind = latestContentKind[stream.titleId] ?: "tv"
        if (kind == "movie") return null
        val sevenDaysAgo = System.currentTimeMillis() - 7L * 24 * 60 * 60 * 1000
        if (lastContent < sevenDaysAgo) return null
        val seenMs = seenContentAt[stream.titleId]
        if (seenMs != null && seenMs >= lastContent) return null
        return if (kind == "tv") "NEW EPISODE" else "NEW UPLOAD"
    }
}

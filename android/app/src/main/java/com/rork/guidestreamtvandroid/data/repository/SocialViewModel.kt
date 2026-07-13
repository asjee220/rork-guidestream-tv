package com.rork.guidestreamtvandroid.data.repository

import android.content.Context
import com.rork.guidestreamtvandroid.data.local.DeviceIdentity
import com.rork.guidestreamtvandroid.data.remote.SupabaseManager
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.text.SimpleDateFormat
import java.util.Collections
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

/**
 * Likes + comments store, local-first with optimistic writes.
 * Mirrors iOS SocialViewModel.swift. Reads/writes `title_likes` and
 * `title_comments` with the same owner rules as [StreamsViewModel]:
 * signed-in rows are owned by `user_id`, guests by `device_id`.
 */
class SocialViewModel private constructor(context: Context) {

    @Serializable
    data class TitleComment(
        val id: String,
        @SerialName("title_id") val titleId: String,
        @SerialName("user_id") val userId: String? = null,
        @SerialName("device_id") val deviceId: String? = null,
        val body: String,
        @SerialName("display_name") val displayName: String? = null,
        val initials: String? = null,
        @SerialName("created_at") val createdAt: String? = null,
    )

    @Serializable
    private data class LikeRow(
        val id: String,
        @SerialName("user_id") val userId: String? = null,
        @SerialName("device_id") val deviceId: String? = null,
    )

    @Serializable
    private data class CountRow(val id: String)

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @Suppress("unused")
    private val prefs = context.getSharedPreferences("gs_prefs", Context.MODE_PRIVATE)

    @Suppress("unused")
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    private val _likeCounts = MutableStateFlow<Map<String, Int>>(emptyMap())
    val likeCounts: StateFlow<Map<String, Int>> = _likeCounts.asStateFlow()

    private val _likedByMe = MutableStateFlow<Set<String>>(emptySet())
    val likedByMe: StateFlow<Set<String>> = _likedByMe.asStateFlow()

    private val _commentCounts = MutableStateFlow<Map<String, Int>>(emptyMap())
    val commentCounts: StateFlow<Map<String, Int>> = _commentCounts.asStateFlow()

    private val _commentsByTitle = MutableStateFlow<Map<String, List<TitleComment>>>(emptyMap())
    val commentsByTitle: StateFlow<Map<String, List<TitleComment>>> = _commentsByTitle.asStateFlow()

    private val _loadingComments = MutableStateFlow<Set<String>>(emptySet())
    val loadingComments: StateFlow<Set<String>> = _loadingComments.asStateFlow()

    private val _postingComment = MutableStateFlow<Set<String>>(emptySet())
    val postingComment: StateFlow<Set<String>> = _postingComment.asStateFlow()

    private val _lastError = MutableStateFlow<String?>(null)
    val lastError: StateFlow<String?> = _lastError.asStateFlow()

    // Guards against duplicate like writes for a title while one is in flight.
    private val likesInFlight = Collections.synchronizedSet(mutableSetOf<String>())

    private val currentUserId: String?
        get() = AuthViewModel.get().currentUserId

    companion object {
        @Volatile private var instance: SocialViewModel? = null
        fun init(context: Context): SocialViewModel =
            instance ?: synchronized(this) {
                instance ?: SocialViewModel(context.applicationContext).also { instance = it }
            }
        fun get(): SocialViewModel =
            instance ?: error("SocialViewModel not initialized")
    }

    /**
     * Reads the total like count, whether the current owner has liked the
     * title, and the total comment count, then writes all three into state.
     */
    suspend fun refreshCounts(titleId: String) {
        val trimmed = titleId.trim()
        if (trimmed.isEmpty()) return
        try {
            withContext(Dispatchers.IO) {
                val deviceId = DeviceIdentity.get().deviceId
                val uid = currentUserId
                val likeRows = SupabaseManager.client.postgrest
                    .from("title_likes")
                    .select { filter { eq("title_id", trimmed) } }
                    .decodeList<LikeRow>()
                val mineLiked = likeRows.any { row ->
                    if (uid != null) row.userId == uid || row.deviceId == deviceId
                    else row.deviceId == deviceId
                }
                val commentRows = SupabaseManager.client.postgrest
                    .from("title_comments")
                    .select { filter { eq("title_id", trimmed) } }
                    .decodeList<CountRow>()
                _likeCounts.value = _likeCounts.value + (trimmed to likeRows.size)
                _commentCounts.value = _commentCounts.value + (trimmed to commentRows.size)
                _likedByMe.value =
                    if (mineLiked) _likedByMe.value + trimmed else _likedByMe.value - trimmed
            }
        } catch (e: Throwable) {
            if (e is CancellationException) throw e
            _lastError.value = e.message
        }
    }

    /**
     * Optimistically flips the current owner's like, logs the event, then
     * writes through to `title_likes` (delete on remove, insert on add) and
     * re-reads the canonical count from the server. Network failures set
     * [lastError] and never revert the optimistic local state. Rapid repeated
     * taps for the same title are swallowed while a write is in flight.
     */
    fun toggleLike(titleId: String, mediaType: String? = null, tmdbId: Int? = null) {
        val trimmed = titleId.trim()
        if (trimmed.isEmpty()) return
        if (!likesInFlight.add(trimmed)) return

        val wasLiked = _likedByMe.value.contains(trimmed)
        _likedByMe.value =
            if (wasLiked) _likedByMe.value - trimmed else _likedByMe.value + trimmed
        val current = _likeCounts.value[trimmed] ?: 0
        val optimistic = (if (wasLiked) current - 1 else current + 1).coerceAtLeast(0)
        _likeCounts.value = _likeCounts.value + (trimmed to optimistic)

        WatchIntentLogger.get().log(
            WatchIntentLogger.IntentEventType.TRAILER_LIKED,
            titleId = trimmed,
        )

        scope.launch {
            val deviceId = DeviceIdentity.get().deviceId
            val uid = currentUserId
            try {
                if (wasLiked) {
                    SupabaseManager.client.postgrest
                        .from("title_likes")
                        .delete {
                            filter {
                                eq("title_id", trimmed)
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
                    insertLike(uid, deviceId, trimmed, mediaType, tmdbId)
                }
                val serverCount = serverLikeCount(trimmed)
                _likeCounts.value = _likeCounts.value + (trimmed to serverCount)
            } catch (e: Throwable) {
                if (e is CancellationException) throw e
                _lastError.value = e.message
            } finally {
                likesInFlight.remove(trimmed)
            }
        }
    }

    private suspend fun insertLike(
        userId: String?,
        deviceId: String,
        titleId: String,
        mediaType: String?,
        tmdbId: Int?,
    ): Boolean {
        val payload = buildJsonObject {
            put("device_id", deviceId)
            put("title_id", titleId)
            if (userId != null) put("user_id", userId)
            if (mediaType != null) put("media_type", mediaType)
            if (tmdbId != null) put("tmdb_id", tmdbId)
        }
        return try {
            SupabaseManager.client.postgrest
                .from("title_likes")
                .insert(payload)
            true
        } catch (e: Throwable) {
            if (e is CancellationException) throw e
            val msg = e.message?.lowercase() ?: ""
            // The partial unique index means the like already exists for this
            // owner — treat a duplicate insert as success, like insertWatched.
            if (msg.contains("duplicate") || msg.contains("23505")) true
            else {
                _lastError.value = e.message
                false
            }
        }
    }

    private suspend fun serverLikeCount(titleId: String): Int {
        val rows = SupabaseManager.client.postgrest
            .from("title_likes")
            .select { filter { eq("title_id", titleId) } }
            .decodeList<CountRow>()
        return rows.size
    }

    /**
     * Loads the comment thread for a title (newest first), storing both the
     * thread and its count. Failures set [lastError].
     */
    suspend fun loadComments(titleId: String, limit: Int = 200) {
        val trimmed = titleId.trim()
        if (trimmed.isEmpty()) return
        _loadingComments.value = _loadingComments.value + trimmed
        try {
            val rows = withContext(Dispatchers.IO) {
                SupabaseManager.client.postgrest
                    .from("title_comments")
                    .select {
                        filter { eq("title_id", trimmed) }
                        order("created_at", Order.DESCENDING)
                        limit(limit.toLong())
                    }
                    .decodeList<TitleComment>()
            }
            _commentsByTitle.value = _commentsByTitle.value + (trimmed to rows)
            _commentCounts.value = _commentCounts.value + (trimmed to rows.size)
        } catch (e: Throwable) {
            if (e is CancellationException) throw e
            _lastError.value = e.message
        } finally {
            _loadingComments.value = _loadingComments.value - trimmed
        }
    }

    /**
     * Trims and posts a comment, optimistically prepending it to the thread,
     * then re-loads so the optimistic row is replaced by the canonical server
     * record. Returns false on empty body or write failure.
     */
    suspend fun postComment(titleId: String, body: String): Boolean {
        val trimmedId = titleId.trim()
        val text = body.trim()
        if (trimmedId.isEmpty() || text.isEmpty()) return false

        val uid = currentUserId
        val deviceId = DeviceIdentity.get().deviceId
        val name = resolvedDisplayName()
        val initials = initialsOf(name)

        _postingComment.value = _postingComment.value + trimmedId

        val optimistic = TitleComment(
            id = "local-${UUID.randomUUID()}",
            titleId = trimmedId,
            userId = uid,
            deviceId = deviceId,
            body = text,
            displayName = name,
            initials = initials,
            createdAt = nowIso(),
        )
        val existing = _commentsByTitle.value[trimmedId] ?: emptyList()
        _commentsByTitle.value =
            _commentsByTitle.value + (trimmedId to (listOf(optimistic) + existing))
        val currentCount = _commentCounts.value[trimmedId] ?: existing.size
        _commentCounts.value = _commentCounts.value + (trimmedId to (currentCount + 1))

        return try {
            withContext(Dispatchers.IO) {
                val payload = buildJsonObject {
                    put("title_id", trimmedId)
                    put("device_id", deviceId)
                    put("body", text)
                    put("display_name", name)
                    put("initials", initials)
                    if (uid != null) put("user_id", uid)
                }
                SupabaseManager.client.postgrest
                    .from("title_comments")
                    .insert(payload)
            }
            loadComments(trimmedId)
            true
        } catch (e: Throwable) {
            if (e is CancellationException) throw e
            _lastError.value = e.message
            false
        } finally {
            _postingComment.value = _postingComment.value - trimmedId
        }
    }

    /**
     * Best display name for the current user: cached display name, then first
     * + last name, then the email handle, then the literal "You".
     */
    private fun resolvedDisplayName(): String {
        val auth = AuthViewModel.get()
        val display = auth.displayName.value?.trim()?.takeIf { it.isNotEmpty() }
        if (display != null) return display
        val composed = listOf(auth.firstName.value, auth.lastName.value)
            .mapNotNull { it?.trim() }
            .filter { it.isNotEmpty() }
            .joinToString(" ")
            .takeIf { it.isNotEmpty() }
        if (composed != null) return composed
        val handle = auth.email?.substringBefore("@")?.trim()?.takeIf { it.isNotEmpty() }
        if (handle != null) return handle
        return "You"
    }

    /** Up to two uppercase letters from the given name. */
    private fun initialsOf(name: String): String =
        name.split(Regex("\\s+"))
            .filter { it.isNotEmpty() }
            .take(2)
            .map { it.first().uppercaseChar() }
            .joinToString("")
            .ifEmpty { "?" }

    private fun nowIso(): String {
        val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
        fmt.timeZone = TimeZone.getTimeZone("UTC")
        return fmt.format(Date())
    }
}

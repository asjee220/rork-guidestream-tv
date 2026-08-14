package com.rork.guidestreamtvandroid.data.repository

import android.content.Context
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Rect
import com.rork.guidestreamtvandroid.data.remote.SupabaseManager
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Coach mark definitions — mirrors iOS CoachMark struct.
 * Eight marks split across two tours: home (1–5) and detail (6–8).
 */
@Immutable
data class CoachMark(
    val key: String,
    val title: String,
    val body: String,
    val targetKeys: List<String>,
) {
    val isCircular: Boolean get() = key == "ask" || key == "watchlist_add" || key == "sheet_watchlist"

    companion object {
        val homeTour = listOf(
            CoachMark("services", "Your services",
                "The services you subscribe to. Everything below is filtered to what you can actually watch.",
                listOf("services")),
            CoachMark("search", "Find anything, fast",
                "Search shows, movies, creators and podcasts across every service at once.",
                listOf("search")),
            CoachMark("reels", "Reels",
                "Swipe trailers for what is new. Tap once to start watching.",
                listOf("reels")),
            CoachMark("sports", "Sports",
                "Live games, scores and the channel carrying them. Star a team to follow it.",
                listOf("sports")),
            CoachMark("ask", "AI Enabled Ask Stream",
                "Describe what you feel like and get picks you can actually watch tonight.",
                listOf("ask")),
            CoachMark("genre", "Browse by genre",
                "Pick a genre and the rail underneath refills with titles in it.",
                listOf("genre", "because_you_watch")),
        )

        val sheetTour = listOf(
            CoachMark("sheet_play_on", "Send it to the TV",
                "Open this on your Roku without touching the remote.",
                listOf("sheet_play_on")),
            CoachMark("sheet_where_to_watch", "Pick your service",
                "Tap a service to switch where this plays. The Watch button follows your choice.",
                listOf("sheet_where_to_watch", "sheet_watch_button")),
            CoachMark("sheet_watchlist", "Add to watch list",
                "Save it and we will notify you the moment a new episode drops.",
                listOf("sheet_watchlist")),
        )
    }
}

/**
 * Manages first-run coach mark tour state, persistence to SharedPreferences
 * and Supabase (read-merge-write). Mirrors iOS CoachMarkManager.
 *
 * Stored value is a flat JSON object mapping each seen key to the ISO8601
 * timestamp it was dismissed, plus tour-level keys home_tour_done and
 * detail_tour_done.
 */
class CoachMarkManager private constructor(private val context: Context) {

    companion object {
        @Volatile private var instance: CoachMarkManager? = null

        fun init(context: Context): CoachMarkManager =
            instance ?: synchronized(this) {
                instance ?: CoachMarkManager(context.applicationContext).also { instance = it }
            }

        fun get(): CoachMarkManager =
            instance ?: error("CoachMarkManager not initialized")
    }

    private val prefs = context.getSharedPreferences("gs_prefs", Context.MODE_PRIVATE)
    private val storageKey = "gs.coachMarks"
    private val resetRevisionKey = "gs.coachMarks.resetRevision"

    /**
     * Bump to force a one-time clear of stored coach mark state on every
     * install. Matches the iOS reset version so both platforms replay once.
     */
    private val coachMarkResetVersion = 3
    private val resetVersionKey = "coach_mark_reset_version"
    private val pendingRemoteResetKey = "coach_mark_pending_remote_reset"

    /**
     * Accounts whose tour is force-reset once per [testerResetRevision].
     * Bump the revision to replay the tour again for these accounts.
     */
    private val testerEmails = setOf("ma@guidestream.tv")
    // Bump this to force the next one-time reset for tester accounts.
    private val testerResetRevision = 3

    /** Seen keys mapped to ISO8601 timestamps. */
    var seenKeys: Map<String, String> by mutableStateOf(emptyMap())
        private set

    /** Currently active tour marks. */
    var activeTour: List<CoachMark> by mutableStateOf(emptyList())
        private set

    var currentIndex: Int by mutableStateOf(0)
        private set

    var isShowing: Boolean by mutableStateOf(false)
        private set

    /** Measured bounds in root coordinates per key. */
    val measuredRects = mutableStateMapOf<String, Rect>()

    /** Scroll request id for the host to act on, or null when no scroll needed. */
    var scrollRequestId: String? by mutableStateOf(null)
        private set

    /** Set true by host after scroll + 350ms settle delay. */
    var scrollSettled: Boolean by mutableStateOf(false)
        private set

    var activeTourIsHome: Boolean by mutableStateOf(false)
        private set

    /** True while the genre mark is active so HomeScreen can bind highlight. */
    var genreHighlightActive: Boolean by mutableStateOf(false)
        private set

    /** True while the home-tour completion toast is visible. */
    var completionToastVisible: Boolean by mutableStateOf(false)
        private set

    private var completionToastJob: Job? = null

    private val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }

    init {
        applyOneTimeResetIfNeeded()
        loadFromPrefs()
    }

    /**
     * Runs at most once per install per [coachMarkResetVersion]. Clears the
     * stored seen-keys entry before [loadFromPrefs] can populate state, and
     * flags the remote copy for an authoritative clear on next hydrate.
     */
    private fun applyOneTimeResetIfNeeded() {
        if (prefs.getInt(resetVersionKey, 0) >= coachMarkResetVersion) return
        prefs.edit()
            .remove(storageKey)
            .putInt(resetVersionKey, coachMarkResetVersion)
            .putBoolean(pendingRemoteResetKey, true)
            .apply()
        seenKeys = emptyMap()
    }

    // ── Local persistence ────────────────────────────────────────────

    private fun loadFromPrefs() {
        val raw = prefs.getString(storageKey, null) ?: return
        try {
            val obj = Json.parseToJsonElement(raw) as JsonObject
            seenKeys = obj.mapValues { (_, v) -> (v as JsonPrimitive).content }
        } catch (_: Exception) { }
    }

    private fun saveToPrefs() {
        try {
            val json = buildJsonObject {
                seenKeys.forEach { (k, v) -> put(k, v) }
            }
            prefs.edit().putString(storageKey, json.toString()).apply()
        } catch (_: Exception) { }
    }

    // ── Tour gating ──────────────────────────────────────────────────

    val homeTourDone: Boolean get() = seenKeys.containsKey("home_tour_done")
    val sheetTourDone: Boolean get() = seenKeys.containsKey("sheet_tour_done")

    fun shouldStartHomeTour(
        isSignedIn: Boolean, hasCompletedOnboarding: Boolean,
        homeContentReady: Boolean, tabBarVisible: Boolean,
    ): Boolean {
        if (!isSignedIn || !hasCompletedOnboarding || !homeContentReady ||
            !tabBarVisible || homeTourDone || isShowing) return false
        return CoachMark.homeTour.any { !seenKeys.containsKey(it.key) }
    }

    fun shouldStartSheetTour(sourcesResolved: Boolean): Boolean {
        if (sheetTourDone || isShowing || !sourcesResolved) return false
        return CoachMark.sheetTour.any { !seenKeys.containsKey(it.key) }
    }

    // ── Tour control ─────────────────────────────────────────────────

    fun startHomeTour() {
        val unseen = CoachMark.homeTour.filter { !seenKeys.containsKey(it.key) }
        if (unseen.isEmpty()) return
        activeTour = unseen
        activeTourIsHome = true
        currentIndex = 0
        scrollSettled = false
        isShowing = true
        handleScrollForCurrentMark()
    }

    fun startSheetTour() {
        val unseen = CoachMark.sheetTour.filter { !seenKeys.containsKey(it.key) }
        if (unseen.isEmpty()) return
        activeTour = unseen
        activeTourIsHome = false
        currentIndex = 0
        scrollSettled = false
        isShowing = true
        handleScrollForCurrentMark()
    }

    val currentMark: CoachMark?
        get() = activeTour.getOrNull(currentIndex)

    fun advance() {
        val mark = currentMark ?: return
        markAsSeen(mark.key)
        if (currentIndex + 1 >= activeTour.size) {
            if (activeTourIsHome) {
                markAsSeen("home_tour_done")
                showCompletionToast()
            } else {
                markAsSeen("sheet_tour_done")
            }
            genreHighlightActive = false
            dismissTour()
        } else {
            currentIndex++
            scrollSettled = false
            genreHighlightActive = false
            handleScrollForCurrentMark()
        }
    }

    fun skipTour() {
        val remaining = activeTour.drop(currentIndex)
        for (mark in remaining) markAsSeen(mark.key)
        if (activeTourIsHome) {
            markAsSeen("home_tour_done")
            showCompletionToast()
        } else {
            markAsSeen("sheet_tour_done")
        }
        genreHighlightActive = false
        dismissTour()
    }

    fun handleBackground() {
        if (isShowing) {
            currentMark?.let { markAsSeen(it.key) }
            genreHighlightActive = false
            dismissTour()
        }
    }

    private fun dismissTour() {
        isShowing = false
        activeTourIsHome = false
        activeTour = emptyList()
        currentIndex = 0
        measuredRects.clear()
        scrollRequestId = null
        scrollSettled = false
    }

    private fun showCompletionToast() {
        completionToastJob?.cancel()
        completionToastVisible = true
        completionToastJob = scope.launch {
            delay(6000)
            completionToastVisible = false
        }
    }

    private fun hideCompletionToast() {
        completionToastJob?.cancel()
        completionToastJob = null
        completionToastVisible = false
    }

    fun currentMarkHasValidFrames(): Boolean {
        val mark = currentMark ?: return false
        return mark.targetKeys.all { key ->
            measuredRects[key]?.let { !it.isEmpty } ?: false
        }
    }

    fun setMeasuredRect(key: String, rect: Rect) {
        measuredRects[key] = rect
    }

    fun clearScrollRequest() {
        scrollRequestId = null
    }

    /**
     * Called by the host screen after it has scrolled the target into view
     * and allowed a 350 ms settle delay. Mirrors iOS markScrollSettled.
     */
    fun markScrollSettled() {
        scrollSettled = true
        scrollRequestId = null
    }

    // ── Scroll coordination ──────────────────────────────────────────

    private fun handleScrollForCurrentMark() {
        val mark = currentMark ?: return
        genreHighlightActive = (mark.key == "genre")
        when (mark.key) {
            "genre" -> scrollRequestId = "browseByGenre"
            "sheet_play_on" -> scrollRequestId = "cmSheetActions"
            "sheet_where_to_watch" -> scrollRequestId = "cmSheetWatch"
            "sheet_watchlist" -> scrollRequestId = "cmSheetWatchlist"
            else -> {
                scrollSettled = true
            }
        }
    }

    // ── Seen-key persistence ─────────────────────────────────────────

    fun markAsSeen(key: String) {
        seenKeys = seenKeys + (key to isoFormat.format(Date()))
        saveToPrefs()
        pushToSupabase()
    }

    // ── Supabase sync (read-merge-write) ─────────────────────────────

    private val scope get() = kotlinx.coroutines.CoroutineScope(Dispatchers.Main)

    fun pushToSupabase() {
        val userId = AuthViewModel.get().currentUserId ?: return
        val localCopy = seenKeys
        scope.launch {
            try {
                val rows = SupabaseManager.client.postgrest
                    .from("users")
                    .select { filter { eq("id", userId) }; limit(1) }
                    .decodeList<CoachMarksRow>()
                val remote = rows.firstOrNull()?.coachMarksSeen ?: emptyMap()
                val merged = remote.toMutableMap().apply {
                    localCopy.forEach { (k, v) -> if (!containsKey(k)) put(k, v) }
                }
                SupabaseManager.client.postgrest
                    .from("users")
                    .update(buildJsonObject {
                        put("coach_marks_seen", buildJsonObject {
                            merged.forEach { (k, v) -> put(k, v) }
                        })
                    }) { filter { eq("id", userId) } }
                seenKeys = merged
                saveToPrefs()
            } catch (_: Exception) {
                // Keep local value; do not block or retry
            }
        }
    }

    /**
     * Hydrate on sign-in / session restore, then apply any pending tester
     * reset so a cleared server copy is not immediately re-merged.
     */
    suspend fun hydrateFromSupabase(userId: String, email: String? = null) {
        // One-time reset: overwrite the remote copy authoritatively instead of
        // merging, otherwise the stale remote keys would be pulled straight
        // back down and the local clear undone. The flag only clears when the
        // write succeeds, so a failure retries on the next hydrate.
        if (prefs.getBoolean(pendingRemoteResetKey, false)) {
            try {
                SupabaseManager.client.postgrest
                    .from("users")
                    .update(buildJsonObject {
                        put("coach_marks_seen", buildJsonObject { })
                    }) { filter { eq("id", userId) } }
                prefs.edit().putBoolean(pendingRemoteResetKey, false).apply()
            } catch (_: Exception) {
                // Local reset already applied; retry the remote clear later
            }
            return
        }
        hydrateSeenKeys(userId)
        withContext(Dispatchers.Main) { maybeResetForTester(email) }
    }

    private suspend fun hydrateSeenKeys(userId: String) {
        try {
            val rows = SupabaseManager.client.postgrest
                .from("users")
                .select { filter { eq("id", userId) }; limit(1) }
                .decodeList<CoachMarksRow>()
            val remote = rows.firstOrNull()?.coachMarksSeen ?: emptyMap()
            val merged = seenKeys.toMutableMap().apply {
                remote.forEach { (k, v) -> put(k, v) }
            }
            seenKeys = merged
            saveToPrefs()
            SupabaseManager.client.postgrest
                .from("users")
                .update(buildJsonObject {
                    put("coach_marks_seen", buildJsonObject {
                        merged.forEach { (k, v) -> put(k, v) }
                    })
                }) { filter { eq("id", userId) } }
        } catch (_: Exception) { }
    }

    /**
     * Wipes all tour progress locally and remotely so both tours replay from
     * the first mark on the next eligible screen.
     */
    fun resetTours() {
        dismissTour()
        seenKeys = emptyMap()
        prefs.edit().remove(storageKey).apply()
        clearRemote()
    }

    /**
     * One-shot force reset for internal tester accounts. Runs at most once per
     * [testerResetRevision] so a tester who then completes the tour is not
     * shown it again on every launch.
     */
    fun maybeResetForTester(email: String?) {
        val normalized = email?.trim()?.lowercase(Locale.US) ?: return
        if (normalized !in testerEmails) return
        if (prefs.getInt(resetRevisionKey, 0) >= testerResetRevision) return
        prefs.edit().putInt(resetRevisionKey, testerResetRevision).apply()
        resetTours()
    }

    /** Clears the persisted server copy so the reset survives a reinstall. */
    private fun clearRemote() {
        val userId = AuthViewModel.get().currentUserId ?: return
        scope.launch {
            try {
                SupabaseManager.client.postgrest
                    .from("users")
                    .update(buildJsonObject {
                        put("coach_marks_seen", buildJsonObject { })
                    }) { filter { eq("id", userId) } }
            } catch (_: Exception) {
                // Local reset already applied; server copy stays as-is
            }
        }
    }

    fun clearForSignOut() {
        dismissTour()
    }

    @Serializable
    data class CoachMarksRow(
        @kotlinx.serialization.SerialName("coach_marks_seen")
        val coachMarksSeen: Map<String, String>? = null,
    )
}

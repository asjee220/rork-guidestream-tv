package com.rork.guidestreamtvandroid.data.repository

import android.content.Context
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import com.rork.guidestreamtvandroid.data.local.DeviceIdentity
import com.rork.guidestreamtvandroid.data.models.SportsGame
import com.rork.guidestreamtvandroid.data.remote.SupabaseManager
import com.rork.guidestreamtvandroid.sports.live.LiveScoreNotification
import com.rork.guidestreamtvandroid.sports.live.LiveScoreSnapshot
import com.rork.guidestreamtvandroid.widget.WidgetDataService
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.util.UUID

/**
 * Owns the tracked-game ongoing notification — Android's counterpart to iOS's
 * SportsLiveActivityController, and deliberately the same shape: start on the
 * watch sheet, stop on demand, reconcile on foreground, and mirror the row into
 * `live_activities` so the backend can push score updates while the app is
 * closed.
 *
 * Two differences from iOS, both forced by the platform:
 *
 *  * There is no per-activity push token. ActivityKit mints one per Live
 *    Activity; Android has only the app's FCM registration token, so that is
 *    what goes in `push_token` and `activity_id` is a locally minted UUID.
 *    `sports_poll_and_notify` branches on `platform` for exactly this reason.
 *
 *  * The notification is rebuilt whole on every update rather than patched, so
 *    the last known score is persisted locally. Without it a push arriving
 *    after process death would have a score and nothing to draw it on.
 *
 * The table client is WRITE-ONLY — upsert on conflict activity_id, never
 * SELECT. Guests write user_id null.
 */
class SportsLiveScoreController private constructor(context: Context) {

    private val appContext = context.applicationContext
    private val prefs = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    private val _trackedGameId = MutableStateFlow(loadSnapshot()?.gameId)
    val trackedGameId: StateFlow<String?> = _trackedGameId.asStateFlow()

    private val _lastStartError = MutableStateFlow<String?>(null)
    val lastStartError: StateFlow<String?> = _lastStartError.asStateFlow()

    companion object {
        private const val TAG = "GSLiveScore"
        private const val PREFS = "gs_live_score"
        private const val KEY_SNAPSHOT = "gs.liveScore.snapshot.v1"

        @Volatile private var instance: SportsLiveScoreController? = null

        fun init(context: Context): SportsLiveScoreController =
            instance ?: synchronized(this) {
                instance ?: SportsLiveScoreController(context).also { instance = it }
            }

        fun get(): SportsLiveScoreController =
            instance ?: error("SportsLiveScoreController not initialized")
    }

    /** Whether tracking can start at all — the user must allow notifications. */
    fun isAvailable(): Boolean =
        NotificationManagerCompat.from(appContext).areNotificationsEnabled()

    // MARK: - Start

    /**
     * Starts tracking [game]. Ends whatever was being tracked first (one at a
     * time, exactly as on iOS), posts the notification immediately so the user
     * sees it even if the network is slow, then registers the row.
     */
    suspend fun start(game: SportsGame, broadcast: String) {
        _lastStartError.value = null

        if (!isAvailable()) {
            _lastStartError.value = "Turn on notifications to track live scores."
            return
        }

        stop()

        val snapshot = LiveScoreSnapshot(
            gameId = game.id,
            sport = game.sport,
            leagueShort = game.leagueShort.ifBlank { game.sport },
            homeAbbr = game.home.abbreviation,
            awayAbbr = game.away.abbreviation,
            homeShortName = game.home.shortName.ifBlank { game.home.name },
            awayShortName = game.away.shortName.ifBlank { game.away.name },
            homeHex = game.home.primaryHex ?: "F5821F",
            awayHex = game.away.primaryHex ?: "F5821F",
            broadcast = broadcast,
            activityId = UUID.randomUUID().toString(),
            homeScore = game.homeScore ?: game.home.score.toIntOrNull() ?: 0,
            awayScore = game.awayScore ?: game.away.score.toIntOrNull() ?: 0,
            statusDetail = game.statusDetail,
            state = game.state,
        )

        saveSnapshot(snapshot)
        _trackedGameId.value = snapshot.gameId
        LiveScoreNotification.post(appContext, snapshot)
        refreshWidget()
        insertRow(snapshot)
    }

    // MARK: - Stop

    /** Cancels the notification and stamps ended_at on the row. */
    suspend fun stop() {
        val snapshot = loadSnapshot()
        LiveScoreNotification.cancel(appContext)
        clearSnapshot()
        _trackedGameId.value = null
        _lastStartError.value = null
        refreshWidget()
        if (snapshot != null) stampEnded(snapshot.activityId)
    }

    fun clearLastError() {
        _lastStartError.value = null
    }

    // MARK: - Reconcile

    /**
     * The client-side safety net, called on every return to the foreground —
     * the same job iOS's reconcile() does. A game that finished while the app
     * was dead leaves an ongoing notification pinned to the lock screen with a
     * stale score; this clears it.
     */
    suspend fun reconcile() {
        val snapshot = loadSnapshot() ?: run {
            _trackedGameId.value = null
            LiveScoreNotification.cancel(appContext)
            return
        }
        if (snapshot.isFinal) {
            stop()
            return
        }
        _trackedGameId.value = snapshot.gameId
        LiveScoreNotification.post(appContext, snapshot)
    }

    // MARK: - Push

    /**
     * Applies a `sports_live_update` data message. Called from the FCM service
     * on any process state, including a cold start where nothing else has run
     * yet, so it reads the persisted snapshot rather than in-memory state.
     *
     * A push for a game we are not tracking is dropped: the backend collapses
     * on game id, but a stale token or a switched game could still deliver one,
     * and rendering it would silently swap the card out from under the user.
     */
    fun applyPush(data: Map<String, String>) {
        val gameId = data["game_id"] ?: return
        val current = loadSnapshot() ?: return
        if (current.gameId != gameId) return

        val updated = current.copy(
            homeScore = data["home_score"]?.toIntOrNull() ?: current.homeScore,
            awayScore = data["away_score"]?.toIntOrNull() ?: current.awayScore,
            statusDetail = data["status_detail"] ?: current.statusDetail,
            state = data["state"] ?: current.state,
        )
        saveSnapshot(updated)
        refreshWidget()

        if (updated.isFinal) {
            // Post the final score once so the user sees it, then let the
            // notification go non-ongoing so it can be swiped away. The row is
            // closed by the server's own 410-equivalent path and by reconcile().
            LiveScoreNotification.post(appContext, updated)
            clearSnapshot()
            _trackedGameId.value = null
        } else {
            LiveScoreNotification.post(appContext, updated)
            _trackedGameId.value = updated.gameId
        }
    }

    /** The tracked game, for the widget and any UI that wants it. */
    fun currentSnapshot(): LiveScoreSnapshot? = loadSnapshot()

    // MARK: - Private

    private fun loadSnapshot(): LiveScoreSnapshot? {
        val raw = prefs.getString(KEY_SNAPSHOT, null) ?: return null
        return try {
            json.decodeFromString<LiveScoreSnapshot>(raw)
        } catch (_: Exception) {
            null
        }
    }

    private fun saveSnapshot(snapshot: LiveScoreSnapshot) {
        prefs.edit()
            .putString(KEY_SNAPSHOT, json.encodeToString(LiveScoreSnapshot.serializer(), snapshot))
            .apply()
    }

    private fun clearSnapshot() {
        prefs.edit().remove(KEY_SNAPSHOT).apply()
    }

    private fun refreshWidget() {
        try {
            WidgetDataService.get().refreshWidget(appContext)
        } catch (_: Throwable) {
            // Widget not initialized yet (receiver process); nothing to do.
        }
    }

    private suspend fun insertRow(snapshot: LiveScoreSnapshot) {
        val token = PushTokenManager.get().currentToken()
        if (token == null) {
            // No token means the backend has nowhere to push. The notification
            // still works — it just will not update until the app is opened.
            Log.w(TAG, "insertRow: no FCM token; live scores will not update in the background")
            return
        }
        try {
            val payload = buildJsonObject {
                put("activity_id", snapshot.activityId)
                put("game_id", snapshot.gameId)
                put("push_token", token)
                put("platform", "android")
                put("device_id", DeviceIdentity.get().deviceId)
                AuthViewModel.get().currentUserId?.let { put("user_id", it) }
                put("last_state", snapshot.state)
                put("last_home_score", snapshot.homeScore)
                put("last_away_score", snapshot.awayScore)
                put("last_status_detail", snapshot.statusDetail)
            }
            SupabaseManager.client.postgrest
                .from("live_activities")
                // NEVER add select() here, and never decode the result.
                // supabase-kt returns minimal by default, which is the only
                // reason this write survives: select() would make it an
                // INSERT ... RETURNING, and Postgres applies the SELECT policy
                // to a RETURNING clause. live_activities_read_own is
                // `auth.uid() = user_id`, authenticated only, so a GUEST has no
                // SELECT policy at all and the whole write would be rejected
                // with "new row violates row-level security policy" — which is
                // exactly the bug the iOS client had. The table is write-only.
                .upsert(payload) { onConflict = "activity_id" }
        } catch (e: Throwable) {
            if (e is CancellationException) throw e
            Log.e(TAG, "insertRow failed: ${e.message}")
        }
    }

    private suspend fun stampEnded(activityId: String) {
        if (activityId.isBlank()) return
        try {
            SupabaseManager.client.postgrest
                .from("live_activities")
                .update(buildJsonObject { put("ended_at", nowIso()) }) {
                    filter { eq("activity_id", activityId) }
                }
        } catch (e: Throwable) {
            if (e is CancellationException) throw e
            Log.e(TAG, "stampEnded failed: ${e.message}")
        }
    }

    private fun nowIso(): String =
        java.time.Instant.now().toString()
}

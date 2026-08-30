package com.rork.guidestreamtvandroid.widget

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import androidx.glance.appwidget.updateAll
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json

/**
 * Unified widget feed item — replaces the parallel leaving-soon and
 * new-episode arrays. Mirrors iOS WidgetFeedItem in WidgetData.swift.
 * The `kind` field is one of exactly four lowercase string values:
 * "live", "new", "soon", "out" and drives badge colour only.
 */
@Serializable
data class WidgetFeedItem(
    val id: String,
    val kind: String,
    val title: String,
    val subtitle: String = "",
    val badge: String,
    val platform: String,
    @SerialName("platform_color_hex") val platformColorHex: String,
    @SerialName("poster_url") val posterUrl: String? = null,
    @SerialName("deep_link") val deepLink: String? = null,
)

/**
 * The full widget payload written by the main app and read by the widget.
 * Mirrors iOS WidgetPayload. A stale v1 blob decodes to an empty payload
 * rather than throwing because `ignoreUnknownKeys = true` and all fields
 * default to empty/zero.
 */
@Serializable
data class WidgetPayload(
    val items: List<WidgetFeedItem> = emptyList(),
    @SerialName("watchlist_count") val watchlistCount: Int = 0,
    @SerialName("new_episode_count") val newEpisodeCount: Int = 0,
    @SerialName("live_count") val liveCount: Int = 0,
    @SerialName("last_updated") val lastUpdated: Long = 0L,
)

/**
 * Widget data service — mirrors iOS WidgetDataService.swift.
 * Writes the widget payload to SharedPreferences (shared via the app's
 * package) and triggers a Glance widget reload.
 */
class WidgetDataService private constructor(
    private val prefs: android.content.SharedPreferences,
) {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    companion object {
        private const val PREFS_NAME = "gs_widget_payload"
        private const val KEY = "gs.widgetPayload.v2"

        @Volatile private var instance: WidgetDataService? = null
        fun init(context: android.content.Context): WidgetDataService =
            instance ?: synchronized(this) {
                instance ?: WidgetDataService(
                    context.applicationContext.getSharedPreferences(PREFS_NAME, android.content.Context.MODE_PRIVATE)
                ).also { instance = it }
            }

        fun get(): WidgetDataService =
            instance ?: error("WidgetDataService not initialized")
    }

    /** Current cached payload, or a default empty one. */
    fun loadPayload(): WidgetPayload {
        val raw = prefs.getString(KEY, null) ?: return WidgetPayload()
        return try {
            json.decodeFromString<WidgetPayload>(raw)
        } catch (_: Exception) {
            WidgetPayload()
        }
    }

    /** Writes the payload to SharedPreferences. */
    fun writePayload(payload: WidgetPayload) {
        try {
            val raw = json.encodeToString(WidgetPayload.serializer(), payload)
            prefs.edit().putString(KEY, raw).apply()
        } catch (_: Exception) {}
    }

    /**
     * Push a full payload — mirrors iOS push(items:watchlistCount:newEpisodeCount:liveCount:).
     * Wipe protection: if the new items list is empty but we have a recent
     * (within 48h) non-empty payload, preserve the existing items.
     */
    fun push(
        items: List<WidgetFeedItem>,
        watchlistCount: Int,
        newEpisodeCount: Int,
        liveCount: Int,
    ) {
        val existing = loadPayload()
        val now = System.currentTimeMillis()
        val effectiveItems = if (items.isEmpty() &&
            existing.items.isNotEmpty() &&
            now - existing.lastUpdated < 48 * 60 * 60 * 1000L
        ) {
            existing.items
        } else {
            items
        }
        writePayload(
            WidgetPayload(
                items = effectiveItems,
                watchlistCount = watchlistCount,
                newEpisodeCount = newEpisodeCount,
                liveCount = liveCount,
                lastUpdated = now,
            )
        )
    }

    /**
     * Asks Glance to re-render every placed widget. Callers that change what
     * the widget should show — including SportsLiveScoreController, whose
     * tracked game is read straight out of its own prefs rather than the
     * payload — call this afterwards. Safe to call from any process; a failure
     * only means the widget redraws on its next scheduled update.
     */
    fun refreshWidget(context: android.content.Context) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                GuideStreamWidget().updateAll(context.applicationContext)
            } catch (_: Throwable) {}
        }
    }

    /** Write test data for the widget setup screen. */
    fun pushTestData() {
        push(
            items = listOf(
                WidgetFeedItem(
                    id = "sample-live", kind = "live",
                    title = "Live Channel Demo",
                    subtitle = "Just Chatting",
                    badge = "Live now",
                    platform = "TWITCH", platformColorHex = "#FF3B30",
                    posterUrl = null, deepLink = null,
                ),
                WidgetFeedItem(
                    id = "sample-new", kind = "new",
                    title = "New Show Example",
                    subtitle = "Season 3 just dropped",
                    badge = "S3 E1",
                    platform = "NETFLIX", platformColorHex = "#009E8A",
                    posterUrl = null, deepLink = null,
                ),
                WidgetFeedItem(
                    id = "sample-soon", kind = "soon",
                    title = "Coming Soon Demo",
                    subtitle = "Arrives this week",
                    badge = "in 3d",
                    platform = "PRIME", platformColorHex = "#1A6FE8",
                    posterUrl = null, deepLink = null,
                ),
            ),
            watchlistCount = 12,
            newEpisodeCount = 3,
            liveCount = 1,
        )
    }
}

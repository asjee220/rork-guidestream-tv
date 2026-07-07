package com.rork.guidestreamtvandroid.widget

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Widget payload model — mirrors iOS WidgetPayload/WidgetData.swift.
 * Shared between the app (writer) and the widget (reader) via SharedPreferences.
 */
@Serializable
data class WidgetLeavingSoonItem(
    val id: String,
    val title: String,
    @SerialName("days_left") val daysLeft: Int,
    val platform: String,
    @SerialName("platform_color_hex") val platformColorHex: String,
    @SerialName("poster_url") val posterUrl: String? = null,
)

@Serializable
data class WidgetNewEpisodeItem(
    val id: String,
    val title: String,
    @SerialName("episode_label") val episodeLabel: String,
    val platform: String,
    @SerialName("platform_color_hex") val platformColorHex: String,
)

@Serializable
data class WidgetPayload(
    @SerialName("leaving_soon") val leavingSoon: List<WidgetLeavingSoonItem> = emptyList(),
    @SerialName("new_episodes") val newEpisodes: List<WidgetNewEpisodeItem>? = null,
    @SerialName("watchlist_count") val watchlistCount: Int = 0,
    @SerialName("new_episode_count") val newEpisodeCount: Int = 0,
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
        private const val KEY = "gs.widgetPayload.v1"

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

    /** Push a full payload — mirrors iOS push(). */
    fun push(
        leavingSoon: List<WidgetLeavingSoonItem>,
        watchlistCount: Int,
        newEpisodeCount: Int,
        newEpisodes: List<WidgetNewEpisodeItem>? = null,
    ) {
        // Wipe protection: if the new leaving-soon list is empty but we have
        // a recent (within 48h) non-empty payload, preserve the existing data.
        val existing = loadPayload()
        val now = System.currentTimeMillis()
        val effectiveLeavingSoon = if (leavingSoon.isEmpty() &&
            existing.leavingSoon.isNotEmpty() &&
            now - existing.lastUpdated < 48 * 60 * 60 * 1000L
        ) {
            existing.leavingSoon
        } else {
            leavingSoon
        }
        val effectiveNewEpisodes = if (newEpisodes.isNullOrEmpty() && existing.newEpisodes != null) {
            existing.newEpisodes
        } else {
            newEpisodes
        }
        writePayload(
            WidgetPayload(
                leavingSoon = effectiveLeavingSoon,
                newEpisodes = effectiveNewEpisodes,
                watchlistCount = watchlistCount,
                newEpisodeCount = newEpisodeCount,
                lastUpdated = now,
            )
        )
    }

    /** Write test data for the widget setup screen. */
    fun pushTestData() {
        push(
            leavingSoon = listOf(
                WidgetLeavingSoonItem("test1", "Breaking Bad", 2, "NETFLIX", "#E50914"),
                WidgetLeavingSoonItem("test2", "The Office", 3, "PEACOCK", "#000000"),
                WidgetLeavingSoonItem("test3", "Succession", 5, "HBO", "#5A1FCB"),
            ),
            watchlistCount = 12,
            newEpisodeCount = 4,
        )
    }
}

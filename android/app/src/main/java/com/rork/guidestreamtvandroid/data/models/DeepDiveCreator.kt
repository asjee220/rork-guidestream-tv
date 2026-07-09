package com.rork.guidestreamtvandroid.data.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * A YouTube creator channel that publishes deep-dive / analysis content about a
 * show, returned by the `youtube_show_creators` edge function. Mirrors the iOS
 * `CreatorChannel` shape exactly.
 *
 * This is intentionally a NEW model, distinct from the existing [CreatorChannel]
 * in Models.kt (which has a different schema and must be left untouched).
 */
@Serializable
data class DeepDiveCreator(
    @SerialName("title_id") val titleId: String = "",
    @SerialName("channel_id") val channelId: String = "",
    val name: String = "",
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("subscriber_count") val subscriberCount: Long = 0,
    @SerialName("subscribers_hidden") val subscribersHidden: Boolean = false,
    @SerialName("relevant_videos") val relevantVideos: Int = 0,
    @SerialName("named_show") val namedShow: Boolean = false,
    @SerialName("channel_url") val channelUrl: String = "",
) {
    /**
     * Compact subscriber label (e.g. "1.2M", "34K"), or null when the count is
     * hidden or below 1,000 — mirrors iOS `subscriberLabel`.
     */
    val subscriberLabel: String?
        get() {
            if (subscribersHidden || subscriberCount < 1000) return null
            return when {
                subscriberCount >= 1_000_000 -> String.format("%.1fM", subscriberCount / 1_000_000.0)
                else -> String.format("%.0fK", subscriberCount / 1_000.0)
            }
        }
}

package com.rork.guidestreamtvandroid.data.models

/**
 * The kind of source a title_id represents, derived from its prefix.
 * Mirrors iOS SourceKind.swift — single-source classifier for routing.
 */
enum class SourceKind(val prefix: String, val sourceType: String, val displayLabel: String) {
    TMDB("", "tmdb", "Show"),
    YOUTUBE("yt:", "youtube", "YouTube"),
    PODCAST("pod:", "podcast", "Podcast"),
    TWITCH("tw:", "twitch", "Twitch"),
    KICK("kick:", "kick", "Kick");

    /** Map a raw title_id string to its SourceKind by inspecting the prefix. */
    companion object {
        fun from(titleId: String): SourceKind = when {
            titleId.startsWith("yt:") -> YOUTUBE
            titleId.startsWith("pod:") -> PODCAST
            titleId.startsWith("tw:") -> TWITCH
            titleId.startsWith("kick:") -> KICK
            else -> TMDB
        }
    }

    /** True when this kind represents a livestream platform (Twitch or Kick). */
    val isLivestream: Boolean get() = this == TWITCH || this == KICK

    /** True when this kind is not TMDB (any prefixed id). */
    val isNonTMDB: Boolean get() = this != TMDB
}

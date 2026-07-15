package com.rork.guidestreamtvandroid.data.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class UserStream(
    val id: String = "",
    @SerialName("user_id") val userId: String = "",
    @SerialName("title_id") val titleId: String = "",
    val title: String? = null,
    @SerialName("poster_url") val posterUrl: String? = null,
    val platform: String? = null,
    @SerialName("added_at") val addedAt: String? = null,
    @SerialName("title_name") val titleName: String? = null,
    @SerialName("device_id") val deviceId: String? = null,
    /** Media type — true = TV, false = movie, null = legacy row or non-TMDB entity. */
    @SerialName("is_tv") val isTv: Boolean? = null,
)

@Serializable
data class NewEpisodeRow(
    val id: String = "",
    @SerialName("title_id") val titleId: String = "",
    val title: String? = null,
    val season: Int? = null,
    val episode: Int? = null,
    @SerialName("duration_minutes") val durationMinutes: Int? = null,
    val platform: String? = null,
    @SerialName("poster_url") val posterUrl: String? = null,
    @SerialName("is_new") val isNew: Boolean? = null,
    @SerialName("released_at") val releasedAt: String? = null,
    @SerialName("episode_id") val episodeId: String? = null,
    @SerialName("deep_link_url") val deepLinkUrl: String? = null,
    @SerialName("thumbnail_url") val thumbnailUrl: String? = null,
    @SerialName("episode_title") val episodeTitle: String? = null,
)

@Serializable
data class UserProfileUpsert(
    val id: String,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("first_name") val firstName: String? = null,
    @SerialName("last_name") val lastName: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    val email: String? = null,
)

@Serializable
data class UserProfileNameRow(
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("first_name") val firstName: String? = null,
    @SerialName("last_name") val lastName: String? = null,
    val phone: String? = null,
)

@Serializable
data class OnboardingPrefsUpsert(
    val id: String,
    val services: List<String>,
    @SerialName("notify_push") val notifyPush: Boolean,
    @SerialName("notify_sms") val notifySms: Boolean,
)

@Serializable
data class TitleRecencyRow(
    @SerialName("title_id") val titleId: String,
    @SerialName("last_content_at") val lastContentAt: String? = null,
)

@Serializable
data class DeviceSessionRow(
    @SerialName("device_id") val deviceId: String,
    @SerialName("device_model") val deviceModel: String? = null,
    @SerialName("os_version") val osVersion: String? = null,
    @SerialName("app_version") val appVersion: String? = null,
    @SerialName("build_number") val buildNumber: String? = null,
    @SerialName("last_seen_at") val lastSeenAt: String? = null,
    @SerialName("first_seen_at") val firstSeenAt: String? = null,
    @SerialName("is_authenticated") val isAuthenticated: Boolean? = null,
    @SerialName("is_guest") val isGuest: Boolean? = null,
    @SerialName("session_count") val sessionCount: Int? = null,
)

@Serializable
data class ContentSource(
    @SerialName("title_id") val titleId: String,
    @SerialName("source_type") val sourceType: String,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("image_url") val imageUrl: String? = null,
    val category: String? = null,
    val description: String? = null,
    @SerialName("stream_url") val streamUrl: String? = null,
)

@Serializable
data class TMDBResult(
    val id: Int,
    @SerialName("media_type") val mediaType: String? = null,
    val name: String? = null,
    val title: String? = null,
    @SerialName("poster_path") val posterPath: String? = null,
    @SerialName("backdrop_path") val backdropPath: String? = null,
    val overview: String? = null,
    @SerialName("vote_average") val voteAverage: Double? = null,
    @SerialName("first_air_date") val firstAirDate: String? = null,
    @SerialName("release_date") val releaseDate: String? = null,
    @SerialName("genre_ids") val genreIds: List<Int>? = null,
) {
    val displayName: String get() = name ?: title ?: "Untitled"
    val isTV: Boolean get() = (mediaType ?: "tv") == "tv"
    val year: Int?
        get() {
            val date = firstAirDate ?: releaseDate
            return date?.takeIf { it.length >= 4 }?.substring(0, 4)?.toIntOrNull()
        }
    val posterUrl: String?
        get() = posterPath?.let { "${com.rork.guidestreamtvandroid.AppConfig.TMDB_IMAGE_BASE}w342${if (it.startsWith("/")) it else "/$it"}" }
    val backdropUrl: String?
        get() = backdropPath?.let { "${com.rork.guidestreamtvandroid.AppConfig.TMDB_IMAGE_BASE}w1280${if (it.startsWith("/")) it else "/$it"}" }
}

@Serializable
data class TMDBGenre(
    val id: Int,
    val name: String,
)

@Serializable
data class TMDBEpisodeSummary(
    val id: Int,
    val name: String? = null,
    val overview: String? = null,
    @SerialName("air_date") val airDate: String? = null,
    @SerialName("episode_number") val episodeNumber: Int? = null,
    @SerialName("season_number") val seasonNumber: Int? = null,
    val runtime: Int? = null,
    @SerialName("still_path") val stillPath: String? = null,
)

@Serializable
data class SportsGame(
    val id: String,
    val sport: String,
    /** Short league label (e.g. "NBA"). */
    val leagueShort: String = "",
    /** Normalized state: "live" | "pre" | "post". */
    val state: String = "pre",
    /** Human-readable status (e.g. "3rd Qtr · 8:42", "Final", "Fri 7:30 PM"). */
    val statusDetail: String = "",
    val home: TeamSummary,
    val away: TeamSummary,
    @SerialName("start_time") val startTime: String? = null,
    val broadcasts: List<String> = emptyList(),
    @SerialName("home_score") val homeScore: Int? = null,
    @SerialName("away_score") val awayScore: Int? = null,
) {
    @Serializable
    data class TeamSummary(
        val name: String,
        val abbreviation: String,
        val logoUrl: String? = null,
        val record: String? = null,
        /** Stable ESPN team uid used to key favorites. */
        val uid: String? = null,
        /** Full team display name (e.g. "New York Knicks"). */
        val displayName: String = "",
        /** Short team name (e.g. "Knicks"). */
        val shortName: String = "",
        /** Score as a string for direct display. */
        val score: String = "",
        /** Primary team color as a hex string without leading #. */
        val primaryHex: String? = null,
        val isWinner: Boolean = false,
    )
}

@Serializable
data class CreatorChannel(
    @SerialName("title_id") val titleId: String,
    @SerialName("display_name") val displayName: String,
    @SerialName("image_url") val imageUrl: String? = null,
    @SerialName("source_type") val sourceType: String,
    val category: String? = null,
    val subscribers: Long? = null,
    val description: String? = null,
)

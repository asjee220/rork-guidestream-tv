package com.rork.guidestreamtvandroid.ui.home

import androidx.compose.ui.graphics.Color
import com.rork.guidestreamtvandroid.data.models.NewEpisodeRow
import com.rork.guidestreamtvandroid.data.models.Platform
import com.rork.guidestreamtvandroid.data.models.SourceKind
import com.rork.guidestreamtvandroid.data.models.SportsGame
import com.rork.guidestreamtvandroid.data.models.TMDBResult
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.KickGreen
import com.rork.guidestreamtvandroid.ui.theme.PodcastPurple
import com.rork.guidestreamtvandroid.ui.theme.TwitchPurple
import com.rork.guidestreamtvandroid.ui.theme.YouTubeRed
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

/**
 * A followed creator who is live right now. Built from the viewer's own
 * user_streams rows joined with live_status, so only creators this customer
 * follows can reach the hero rail. Mirrors iOS HeroLiveCreator.
 */
data class HeroLiveCreator(
    val titleId: String,
    val displayName: String,
    val avatarUrl: String?,
    val streamTitle: String?,
    val category: String?,
    val viewerCount: Int?,
    val startedAtEpoch: Long?,
    val kind: SourceKind,
)

/**
 * The four things the home hero can hold. Mirrors iOS HeroItem so the two
 * rails stay the same feature rather than drifting into two different ideas
 * of what belongs at the top of Home.
 */
sealed interface HeroItem {
    val id: String

    /** Newest-first sort key, in epoch millis. */
    val sortEpoch: Long

    data class Media(val result: TMDBResult, val platform: Platform?) : HeroItem {
        override val id: String get() = "media-${result.id}"
        override val sortEpoch: Long
            get() = parseHeroDate(result.firstAirDate ?: result.releaseDate) ?: Long.MIN_VALUE
    }

    data class Game(val game: SportsGame) : HeroItem {
        override val id: String get() = "game-${game.id}"
        override val sortEpoch: Long get() = game.startDate ?: Long.MIN_VALUE
    }

    data class LiveCreator(val creator: HeroLiveCreator) : HeroItem {
        override val id: String get() = "live-${creator.titleId}"

        // A live stream with no start time is happening now, so it sorts as
        // now rather than falling to the bottom of the rail.
        override val sortEpoch: Long
            get() = creator.startedAtEpoch ?: System.currentTimeMillis()
    }

    data class CreatorUpload(val upload: NewEpisodeRow) : HeroItem {
        override val id: String get() = "upload-${upload.id}"
        override val sortEpoch: Long get() = parseHeroDate(upload.releasedAt) ?: Long.MIN_VALUE
    }
}

/**
 * Parses the date shapes these rows actually arrive in: a bare `yyyy-MM-dd`
 * from TMDB, and a full timestamp from Supabase with or without a trailing Z.
 * Returns null rather than throwing so one unparseable row cannot empty the
 * rail.
 */
internal fun parseHeroDate(raw: String?): Long? {
    if (raw.isNullOrEmpty()) return null
    if (raw.length == 10) {
        return runCatching {
            LocalDate.parse(raw).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
        }.getOrNull()
    }
    runCatching { Instant.parse(raw).toEpochMilli() }.getOrNull()?.let { return it }
    runCatching { Instant.parse(raw + "Z").toEpochMilli() }.getOrNull()?.let { return it }
    return runCatching {
        LocalDate.parse(raw.substring(0, 10)).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
    }.getOrNull()
}

/** Brand colour per source kind, matching the search screen's mapping. */
internal fun heroSourceColor(kind: SourceKind): Color = when (kind) {
    SourceKind.YOUTUBE -> YouTubeRed
    SourceKind.TWITCH -> TwitchPurple
    SourceKind.KICK -> KickGreen
    SourceKind.PODCAST -> PodcastPurple
    SourceKind.TMDB -> BrandOrange
}

/**
 * Assembles the hero rail. Caps and ordering are iOS's, deliberately: live
 * sports first, then live creators, then the newest upload per followed
 * channel, then provider-gated trending media — all re-sorted newest-first
 * and capped at 24.
 *
 * The per-category caps are applied before the sort, so a busy Saturday of
 * sport cannot push every show off the rail and a quiet day still fills it.
 */
internal fun buildHeroRail(
    trending: List<TMDBResult>,
    onAir: List<TMDBResult>,
    bingeReady: List<TMDBResult>,
    providerByTmdb: Map<Int, Platform>,
    games: List<SportsGame>,
    liveCreators: List<HeroLiveCreator>,
    creatorUploads: List<NewEpisodeRow>,
): List<HeroItem> {
    val items = mutableListOf<HeroItem>()

    // Live sports only, up to 4, newest first.
    games.filter { it.state == "live" }
        .sortedByDescending { it.startDate ?: Long.MIN_VALUE }
        .take(4)
        .forEach { items += HeroItem.Game(it) }

    // Live creators, up to 2 — follow-scoped only.
    liveCreators.take(2).forEach { items += HeroItem.LiveCreator(it) }

    // One newest upload per followed channel, 4 total. The rows arrive
    // released_at-descending, so the first per titleId is that channel's
    // newest.
    val seenChannels = mutableSetOf<String>()
    for (upload in creatorUploads) {
        if (!seenChannels.add(upload.titleId)) continue
        items += HeroItem.CreatorUpload(upload)
        if (seenChannels.size >= 4) break
    }

    // Trending media, up to 15, from the same deduped pool iOS uses, gated on
    // having a resolved provider so the badge can name a real service.
    val seenIds = mutableSetOf<Int>()
    var mediaCount = 0
    for (result in trending + onAir + bingeReady) {
        if (!seenIds.add(result.id)) continue
        val platform = providerByTmdb[result.id] ?: continue
        items += HeroItem.Media(result, platform)
        mediaCount++
        if (mediaCount >= 15) break
    }

    // Deterministic id tie-break so equal timestamps never reshuffle between
    // rebuilds and the rail does not visibly churn while Home is on screen.
    return items
        .sortedWith(compareByDescending<HeroItem> { it.sortEpoch }.thenBy { it.id })
        .take(24)
}

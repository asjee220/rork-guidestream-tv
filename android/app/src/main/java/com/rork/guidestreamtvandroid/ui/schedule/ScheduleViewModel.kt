package com.rork.guidestreamtvandroid.ui.schedule

import com.rork.guidestreamtvandroid.data.models.SportsGame
import com.rork.guidestreamtvandroid.data.remote.SportsService
import com.rork.guidestreamtvandroid.data.remote.TMDBService
import com.rork.guidestreamtvandroid.data.repository.StreamsViewModel
import com.rork.guidestreamtvandroid.data.repository.TeamFavoritesService
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Android half of GUI-95 — the Schedule week view, on both of its surfaces:
 * Sports -> Schedule (games for followed teams) and Watch List -> Schedule
 * (episodes for saved shows).
 *
 * Mirrors iOS `ScheduleService`. The week math lives here rather than in the
 * screen so the two platforms cannot disagree about where a week starts or
 * which local day something belongs to.
 */
class ScheduleViewModel private constructor() {

    enum class Surface { SPORTS, WATCHLIST }

    /**
     * One dated episode of a saved show.
     *
     * TMDB publishes `air_date` as a calendar date with no time of day, so
     * this carries a DAY, not an instant, and the UI shows the service rather
     * than inventing a drop time.
     */
    data class ScheduledEpisode(
        val titleId: String,
        val showTitle: String,
        val posterUrl: String?,
        val platform: String?,
        val season: Int?,
        val number: Int?,
        val name: String?,
        /** Start of the local day this episode airs, epoch millis. */
        val airDay: Long,
        val isSeasonFinale: Boolean,
    ) {
        val episodeLabel: String
            get() = if (season != null && number != null) "S$season E$number" else name ?: "New episode"
    }

    private val _games = MutableStateFlow<List<SportsGame>>(emptyList())
    val games: StateFlow<List<SportsGame>> = _games.asStateFlow()

    private val _episodes = MutableStateFlow<List<ScheduledEpisode>>(emptyList())
    val episodes: StateFlow<List<ScheduledEpisode>> = _episodes.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    /** weekStart -> that week's favourite-team games. Paging back is free. */
    private val gameCache = mutableMapOf<Long, List<SportsGame>>()

    /** tmdbId -> every dated episode of the season(s) in play, once per session. */
    private val episodeCache = mutableMapOf<Int, List<ScheduledEpisode>>()

    // ---- Sports ----------------------------------------------------------

    suspend fun loadGames(weekStart: Long) {
        gameCache[weekStart]?.let {
            _games.value = it
            return
        }
        val favorites = TeamFavoritesService.get().rows.value
        if (favorites.isEmpty()) {
            _games.value = emptyList()
            return
        }

        _isLoading.value = true
        try {
            val uids = favorites.keys
            val abbrs = favorites.values.mapNotNull { it.teamAbbr?.uppercase() }.filter { it.isNotBlank() }.toSet()
            val sports = favorites.values.mapNotNull { it.sport }.filter { it.isNotBlank() }.toSet()

            val end = endOfWeek(weekStart)
            val all = SportsService.get().fetchRange(weekStart, end, sports.ifEmpty { null })

            // The fetch window is padded a day either side for UTC, so the
            // local week bounds are re-applied here — this is the only place
            // that decides which week a game belongs to.
            val mine = all
                .filter { it.startDate != null && it.startDate!! >= weekStart && it.startDate!! < end }
                .filter { involvesFavorite(it, uids, abbrs) }
                .sortedBy { it.startDate }

            gameCache[weekStart] = mine
            _games.value = mine
        } finally {
            _isLoading.value = false
        }
    }

    /**
     * Matches on ESPN's uid — the join key `team_favorites` is built on — and
     * falls back to the abbreviation for rows saved before uids were stored.
     */
    private fun involvesFavorite(game: SportsGame, uids: Set<String>, abbrs: Set<String>): Boolean {
        game.home.uid?.let { if (it in uids) return true }
        game.away.uid?.let { if (it in uids) return true }
        if (game.home.abbreviation.uppercase() in abbrs) return true
        if (game.away.abbreviation.uppercase() in abbrs) return true
        return false
    }

    // ---- Shows -----------------------------------------------------------

    suspend fun loadEpisodes() {
        val shows = StreamsViewModel.get().userStreams.value.filter { stream ->
            (stream.isTv ?: true) && stream.titleId.trim().toIntOrNull() != null
        }
        if (shows.isEmpty()) {
            _episodes.value = emptyList()
            return
        }

        _isLoading.value = true
        try {
            val resolved = mutableListOf<ScheduledEpisode>()
            val pending = mutableListOf<Pair<Int, com.rork.guidestreamtvandroid.data.models.UserStream>>()
            for (stream in shows.take(MAX_SHOWS)) {
                val tmdbId = stream.titleId.trim().toIntOrNull() ?: continue
                val cached = episodeCache[tmdbId]
                if (cached != null) resolved += cached else pending += tmdbId to stream
            }

            if (pending.isNotEmpty()) {
                val fetched = coroutineScope {
                    pending.map { (tmdbId, stream) ->
                        async { tmdbId to fetchEpisodes(tmdbId, stream) }
                    }.awaitAll()
                }
                for ((tmdbId, eps) in fetched) {
                    episodeCache[tmdbId] = eps
                    resolved += eps
                }
            }

            _episodes.value = resolved.sortedWith(
                compareBy<ScheduledEpisode> { it.airDay }.thenBy { it.showTitle.lowercase() }
            )
        } finally {
            _isLoading.value = false
        }
    }

    /**
     * The saved show's currently-airing season(s), dated.
     *
     * Both `next_episode_to_air` and `last_episode_to_air` are consulted
     * because a week can straddle a season boundary — a finale and the
     * following premiere land days apart, and taking only one of them silently
     * drops half the week.
     */
    private suspend fun fetchEpisodes(
        tmdbId: Int,
        stream: com.rork.guidestreamtvandroid.data.models.UserStream,
    ): List<ScheduledEpisode> {
        val detail = TMDBService.get().getTVDetail(tmdbId) ?: return emptyList()

        val seasons = sortedSetOf<Int>()
        detail.nextEpisodeToAir?.seasonNumber?.let { seasons += it }
        detail.lastEpisodeToAir?.seasonNumber?.let { seasons += it }
        if (seasons.isEmpty()) detail.numberOfSeasons?.takeIf { it > 0 }?.let { seasons += it }
        if (seasons.isEmpty()) return emptyList()

        val out = mutableListOf<ScheduledEpisode>()
        for (seasonNumber in seasons) {
            val season = TMDBService.get().getSeason(tmdbId, seasonNumber) ?: continue
            val finaleNumber = season.episodes.maxOfOrNull { it.episodeNumber }
            for (episode in season.episodes) {
                val day = parseAirDay(episode.airDate) ?: continue
                out += ScheduledEpisode(
                    titleId = tmdbId.toString(),
                    showTitle = stream.title ?: detail.name,
                    posterUrl = stream.posterUrl,
                    platform = stream.platform,
                    season = episode.seasonNumber ?: seasonNumber,
                    number = episode.episodeNumber,
                    name = episode.name,
                    airDay = day,
                    isSeasonFinale = episode.episodeNumber == finaleNumber,
                )
            }
        }
        return out
    }

    companion object {
        /** How far the arrows travel in each direction. Bounds the fan-out. */
        const val MAX_OFFSET = 4

        /**
         * Ceiling on saved shows resolved against TMDB. Each costs a detail
         * call plus a season call, so an unbounded watch list would open the
         * screen with a hundred requests in flight.
         */
        private const val MAX_SHOWS = 30

        @Volatile private var instance: ScheduleViewModel? = null
        fun get(): ScheduleViewModel = instance ?: synchronized(this) {
            instance ?: ScheduleViewModel().also { instance = it }
        }

        /**
         * Start of the week containing [millis], honouring the locale's first
         * weekday rather than hard-coding Sunday.
         */
        fun startOfWeek(millis: Long): Long {
            val cal = Calendar.getInstance()
            cal.timeInMillis = millis
            cal.set(Calendar.HOUR_OF_DAY, 0)
            cal.set(Calendar.MINUTE, 0)
            cal.set(Calendar.SECOND, 0)
            cal.set(Calendar.MILLISECOND, 0)
            val delta = cal.get(Calendar.DAY_OF_WEEK) - cal.firstDayOfWeek
            cal.add(Calendar.DAY_OF_YEAR, -(if (delta < 0) delta + 7 else delta))
            return cal.timeInMillis
        }

        fun endOfWeek(weekStart: Long): Long = addDays(weekStart, 7)

        fun addDays(millis: Long, days: Int): Long {
            val cal = Calendar.getInstance()
            cal.timeInMillis = millis
            cal.add(Calendar.DAY_OF_YEAR, days)
            return cal.timeInMillis
        }

        fun daysOfWeek(weekStart: Long): List<Long> = (0 until 7).map { addDays(weekStart, it) }

        fun isSameDay(a: Long, b: Long): Boolean {
            val ca = Calendar.getInstance().apply { timeInMillis = a }
            val cb = Calendar.getInstance().apply { timeInMillis = b }
            return ca.get(Calendar.YEAR) == cb.get(Calendar.YEAR) &&
                ca.get(Calendar.DAY_OF_YEAR) == cb.get(Calendar.DAY_OF_YEAR)
        }

        /** "Aug 30 – Sep 5"; the month repeats only across a boundary. */
        fun rangeLabel(weekStart: Long): String {
            val last = addDays(weekStart, 6)
            val md = SimpleDateFormat("MMM d", Locale.getDefault())
            val d = SimpleDateFormat("d", Locale.getDefault())
            val sameMonth = SimpleDateFormat("yyyyMM", Locale.getDefault()).let {
                it.format(Date(weekStart)) == it.format(Date(last))
            }
            return "${md.format(Date(weekStart))} – ${if (sameMonth) d.format(Date(last)) else md.format(Date(last))}"
        }

        /**
         * TMDB air dates are bare `yyyy-MM-dd` calendar dates. Parsed in the
         * device's own zone — as UTC, every West Coast Sunday drop lands on
         * Saturday.
         */
        private fun parseAirDay(raw: String?): Long? {
            if (raw.isNullOrBlank()) return null
            return try {
                val parsed = SimpleDateFormat("yyyy-MM-dd", Locale.US).parse(raw) ?: return null
                val cal = Calendar.getInstance()
                cal.time = parsed
                cal.set(Calendar.HOUR_OF_DAY, 0)
                cal.set(Calendar.MINUTE, 0)
                cal.set(Calendar.SECOND, 0)
                cal.set(Calendar.MILLISECOND, 0)
                cal.timeInMillis
            } catch (_: Exception) {
                null
            }
        }
    }
}

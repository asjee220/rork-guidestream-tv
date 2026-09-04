package com.rork.guidestreamtvandroid.ui.schedule

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rork.guidestreamtvandroid.data.models.SportsGame
import com.rork.guidestreamtvandroid.data.repository.TeamFavoritesService
import com.rork.guidestreamtvandroid.ui.components.RemoteImage
import com.rork.guidestreamtvandroid.ui.sports.TeamLogo
import com.rork.guidestreamtvandroid.ui.theme.BrandBlue
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.Navy
import com.rork.guidestreamtvandroid.ui.theme.NetflixRed
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * GUI-95 — the Schedule week view on Android.
 *
 * Layout is the day list, matching the phone: a week strip pinned above a
 * scroll of per-day sections. The seven-column grid was mocked alongside it and
 * lost on the merits — a phone-width day cell fits two crests before it
 * truncates and has no room for a kickoff time or a network, so every cell
 * needs a tap before it says anything. tvOS ships the grid, where the width
 * exists.
 *
 * Presented as a state overlay from MainScreen, following the pattern the app
 * actually uses — `Routes` below MAIN is dead (see
 * claude/new-episodes-surfaces-aug31-2026.md).
 */
@Composable
fun ScheduleScreen(
    surface: ScheduleViewModel.Surface,
    onBack: () -> Unit,
    onOpenGame: (SportsGame) -> Unit,
    onOpenTitle: (ScheduleViewModel.ScheduledEpisode) -> Unit,
    modifier: Modifier = Modifier,
) {
    BackHandler { onBack() }

    val vm = remember { ScheduleViewModel.get() }
    val games by vm.games.collectAsStateWithLifecycle()
    val episodes by vm.episodes.collectAsStateWithLifecycle()
    val isLoading by vm.isLoading.collectAsStateWithLifecycle()

    var weekOffset by rememberSaveable { mutableIntStateOf(0) }

    val thisWeek = remember { ScheduleViewModel.startOfWeek(System.currentTimeMillis()) }
    val weekStart = remember(weekOffset, thisWeek) { ScheduleViewModel.addDays(thisWeek, weekOffset * 7) }
    val days = remember(weekStart) { ScheduleViewModel.daysOfWeek(weekStart) }
    val today = remember { System.currentTimeMillis() }

    val accent = if (surface == ScheduleViewModel.Surface.SPORTS) BrandOrange else BrandBlue

    LaunchedEffect(weekStart, surface) {
        when (surface) {
            ScheduleViewModel.Surface.SPORTS -> vm.loadGames(weekStart)
            // Episodes are resolved once for the whole season and sliced per
            // week locally, so paging costs nothing after the first load.
            ScheduleViewModel.Surface.WATCHLIST -> if (episodes.isEmpty()) vm.loadEpisodes()
        }
    }

    fun gamesOn(day: Long) = games.filter { it.startDate != null && ScheduleViewModel.isSameDay(it.startDate!!, day) }
    fun episodesOn(day: Long) = episodes.filter { ScheduleViewModel.isSameDay(it.airDay, day) }
    fun isEmptyDay(day: Long) =
        if (surface == ScheduleViewModel.Surface.SPORTS) gamesOn(day).isEmpty() else episodesOn(day).isEmpty()

    val populatedDays = days.filterNot { isEmptyDay(it) }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(Navy),
    ) {
        Spacer(Modifier.statusBarsPadding().height(12.dp))

        // Back row
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onBack() },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = "Back",
                    tint = TextPrimary,
                    modifier = Modifier.size(24.dp),
                )
            }
            Spacer(Modifier.width(4.dp))
            Column {
                Text(
                    text = if (surface == ScheduleViewModel.Surface.SPORTS) "MY TEAMS" else "WATCH LIST",
                    fontSize = 10.sp,
                    lineHeight = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = TextTertiary,
                )
                Text(
                    text = "Schedule",
                    fontSize = 24.sp,
                    lineHeight = 29.sp,
                    fontWeight = FontWeight.Bold,
                    color = TextPrimary,
                )
            }
            Spacer(Modifier.weight(1f))
            if (isLoading) {
                CircularProgressIndicator(
                    color = accent,
                    strokeWidth = 2.dp,
                    modifier = Modifier.size(18.dp),
                )
                Spacer(Modifier.width(12.dp))
            }
        }

        // Week navigation
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            WeekArrow(
                icon = true,
                enabled = weekOffset > -ScheduleViewModel.MAX_OFFSET,
                onClick = { weekOffset -= 1 },
            )
            Text(
                text = ScheduleViewModel.rangeLabel(weekStart),
                fontSize = 15.sp,
                lineHeight = 19.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
                modifier = Modifier.weight(1f),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
            WeekArrow(
                icon = false,
                enabled = weekOffset < ScheduleViewModel.MAX_OFFSET,
                onClick = { weekOffset += 1 },
            )
        }

        // Week strip
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp)
                .padding(bottom = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            days.forEach { day ->
                DayChip(
                    day = day,
                    isToday = ScheduleViewModel.isSameDay(day, today),
                    hasItems = !isEmptyDay(day),
                    accent = accent,
                    modifier = Modifier.weight(1f),
                )
            }
        }

        Box(Modifier.fillMaxWidth().height(1.dp).background(Color.White.copy(alpha = 0.06f)))

        if (populatedDays.isEmpty()) {
            EmptyWeek(surface = surface, weekOffset = weekOffset, isLoading = isLoading)
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(bottom = 120.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                populatedDays.forEach { day ->
                    item(key = "header-$day") {
                        DayHeader(day = day, isToday = ScheduleViewModel.isSameDay(day, today), accent = accent)
                    }
                    if (surface == ScheduleViewModel.Surface.SPORTS) {
                        items(gamesOn(day).size) { index ->
                            val game = gamesOn(day)[index]
                            GameRow(game = game, onClick = { onOpenGame(game) })
                        }
                    } else {
                        items(episodesOn(day).size) { index ->
                            val episode = episodesOn(day)[index]
                            EpisodeRow(
                                episode = episode,
                                accent = accent,
                                onClick = { onOpenTitle(episode) },
                            )
                        }
                    }
                }
            }
        }
    }
}

// ---- Pieces --------------------------------------------------------------

@Composable
private fun WeekArrow(icon: Boolean, enabled: Boolean, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(36.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(Color.White.copy(alpha = if (enabled) 0.07f else 0.03f))
            .clickable(enabled = enabled) { onClick() },
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = if (icon) Icons.Filled.KeyboardArrowLeft else Icons.Filled.KeyboardArrowRight,
            contentDescription = if (icon) "Previous week" else "Next week",
            tint = if (enabled) TextPrimary else Color.White.copy(alpha = 0.2f),
            modifier = Modifier.size(20.dp),
        )
    }
}

@Composable
private fun DayChip(
    day: Long,
    isToday: Boolean,
    hasItems: Boolean,
    accent: Color,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(Color.White.copy(alpha = if (isToday) 0.09f else 0.04f))
            .then(
                if (isToday) Modifier.border(1.dp, accent.copy(alpha = 0.5f), RoundedCornerShape(12.dp))
                else Modifier
            )
            .padding(vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(
            text = SimpleDateFormat("EEEEE", Locale.getDefault()).format(Date(day)),
            fontSize = 10.sp,
            lineHeight = 13.sp,
            fontWeight = FontWeight.SemiBold,
            color = if (isToday) Color.White.copy(alpha = 0.75f) else TextTertiary,
        )
        Text(
            text = SimpleDateFormat("d", Locale.getDefault()).format(Date(day)),
            fontSize = 15.sp,
            lineHeight = 19.sp,
            fontWeight = FontWeight.Bold,
            color = if (isToday) accent else TextPrimary,
        )
        Box(
            modifier = Modifier
                .size(4.dp)
                .clip(CircleShape)
                .background(if (hasItems) accent else Color.Transparent),
        )
    }
}

@Composable
private fun DayHeader(day: Long, isToday: Boolean, accent: Color) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 16.dp, end = 16.dp, top = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (isToday) {
            Text(
                text = "TODAY",
                fontSize = 11.sp,
                lineHeight = 14.sp,
                fontWeight = FontWeight.Black,
                color = accent,
            )
        }
        Text(
            text = SimpleDateFormat("EEEE, MMM d", Locale.getDefault()).format(Date(day)).uppercase(),
            fontSize = 11.sp,
            lineHeight = 14.sp,
            fontWeight = FontWeight.Bold,
            color = TextSecondary,
        )
    }
}

@Composable
private fun GameRow(game: SportsGame, onClick: () -> Unit) {
    RowShell(onClick = onClick) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            modifier = Modifier.width(64.dp),
        ) {
            TeamLogo(team = game.away, size = 28.dp, cornerRadius = 8.dp, inset = 4.dp, abbreviationFontSize = 7.sp)
            TeamLogo(team = game.home, size = 28.dp, cornerRadius = 8.dp, inset = 4.dp, abbreviationFontSize = 7.sp)
        }
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(
                text = "${game.away.abbreviation} at ${game.home.abbreviation}",
                fontSize = 13.sp,
                lineHeight = 17.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.height(3.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                Text(
                    text = game.sport,
                    fontSize = 9.sp,
                    lineHeight = 12.sp,
                    fontWeight = FontWeight.Black,
                    color = TextTertiary,
                )
                game.broadcasts.take(2).forEach { network ->
                    Text(
                        text = network,
                        fontSize = 9.sp,
                        lineHeight = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White.copy(alpha = 0.7f),
                        modifier = Modifier
                            .clip(RoundedCornerShape(4.dp))
                            .background(Color.White.copy(alpha = 0.09f))
                            .padding(horizontal = 5.dp, vertical = 2.dp),
                    )
                }
            }
        }
        Spacer(Modifier.width(6.dp))
        // The right edge is the whole difference between a played game and a
        // scheduled one: a final carries the score, a live game the clock, and
        // everything ahead its start time.
        Column(horizontalAlignment = Alignment.End) {
            when (game.state) {
                "post" -> {
                    Text("FINAL", fontSize = 9.sp, lineHeight = 12.sp, fontWeight = FontWeight.Black, color = TextTertiary)
                    Text(
                        text = "${game.away.score}–${game.home.score}",
                        fontSize = 14.sp,
                        lineHeight = 18.sp,
                        fontWeight = FontWeight.Black,
                        color = TextPrimary,
                    )
                }
                "live" -> {
                    Text("LIVE", fontSize = 9.sp, lineHeight = 12.sp, fontWeight = FontWeight.Black, color = NetflixRed)
                    Text(
                        text = "${game.away.score}–${game.home.score}",
                        fontSize = 14.sp,
                        lineHeight = 18.sp,
                        fontWeight = FontWeight.Black,
                        color = TextPrimary,
                    )
                }
                else -> Text(
                    text = game.startDate?.let {
                        SimpleDateFormat("h:mm a", Locale.getDefault()).format(Date(it))
                    } ?: game.statusDetail,
                    fontSize = 12.sp,
                    lineHeight = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = Color.White.copy(alpha = 0.65f),
                )
            }
        }
    }
}

@Composable
private fun EpisodeRow(
    episode: ScheduleViewModel.ScheduledEpisode,
    accent: Color,
    onClick: () -> Unit,
) {
    RowShell(onClick = onClick) {
        RemoteImage(
            url = episode.posterUrl,
            contentDescription = episode.showTitle,
            cornerRadius = 6,
            modifier = Modifier.size(width = 30.dp, height = 44.dp),
        )
        Spacer(Modifier.width(11.dp))
        Column(Modifier.weight(1f)) {
            Text(
                text = episode.showTitle,
                fontSize = 13.sp,
                lineHeight = 17.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.height(3.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                Text(
                    text = episode.episodeLabel,
                    fontSize = 9.sp,
                    lineHeight = 12.sp,
                    fontWeight = FontWeight.Black,
                    color = TextTertiary,
                )
                episode.platform?.takeIf { it.isNotBlank() }?.let { platform ->
                    Text(
                        text = platform,
                        fontSize = 9.sp,
                        lineHeight = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White.copy(alpha = 0.7f),
                        modifier = Modifier
                            .clip(RoundedCornerShape(4.dp))
                            .background(Color.White.copy(alpha = 0.09f))
                            .padding(horizontal = 5.dp, vertical = 2.dp),
                    )
                }
                if (episode.isSeasonFinale) {
                    Text(
                        text = "Season finale",
                        fontSize = 9.sp,
                        lineHeight = 12.sp,
                        fontWeight = FontWeight.Bold,
                        color = accent,
                        modifier = Modifier
                            .border(1.dp, accent.copy(alpha = 0.45f), RoundedCornerShape(4.dp))
                            .padding(horizontal = 5.dp, vertical = 2.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun RowShell(onClick: () -> Unit, content: @Composable RowScope.() -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(Color(red = 0x12, green = 0x16, blue = 0x1F))
            .border(1.dp, Color.White.copy(alpha = 0.06f), RoundedCornerShape(14.dp))
            .clickable { onClick() }
            .padding(11.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        content()
    }
}

/**
 * An empty week is normal here — especially forward, where TMDB simply has no
 * announced dates yet — so the state says which kind of empty it is rather
 * than reading as a failure.
 */
@Composable
private fun EmptyWeek(
    surface: ScheduleViewModel.Surface,
    weekOffset: Int,
    isLoading: Boolean,
) {
    val hasFavorites = runCatching { TeamFavoritesService.get().rows.value.isNotEmpty() }.getOrDefault(false)
    val title = when {
        isLoading -> "Loading…"
        surface == ScheduleViewModel.Surface.SPORTS && !hasFavorites -> "No teams followed"
        else -> "Nothing this week"
    }
    val message = when {
        isLoading -> ""
        surface == ScheduleViewModel.Surface.SPORTS && !hasFavorites ->
            "Add teams in My Teams and their games will show up here."
        surface == ScheduleViewModel.Surface.SPORTS -> "None of your teams play between these dates."
        weekOffset > 0 -> "Air dates this far ahead haven't been announced yet."
        else -> "No episodes from your saved shows this week."
    }

    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(
                text = title,
                fontSize = 15.sp,
                lineHeight = 19.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
            )
            if (message.isNotEmpty()) {
                Text(
                    text = message,
                    fontSize = 12.sp,
                    lineHeight = 17.sp,
                    color = Color.White.copy(alpha = 0.45f),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                    modifier = Modifier.padding(horizontal = 44.dp),
                )
            }
        }
    }
}

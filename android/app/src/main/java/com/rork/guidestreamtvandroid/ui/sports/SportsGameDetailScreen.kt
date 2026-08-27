package com.rork.guidestreamtvandroid.ui.sports

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import com.rork.guidestreamtvandroid.data.models.SportsGame
import com.rork.guidestreamtvandroid.data.remote.SportsService
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.data.repository.TeamFavoritesService
import com.rork.guidestreamtvandroid.ui.theme.BottomSafeSpacer
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.GlassFill
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Seconds between live-score polls while the game is live and in foreground. */
private const val REFRESH_INTERVAL_MS = 20_000L

/**
 * Sports game detail screen — mirrors iOS SportsGameDetailView.swift.
 * Matchup, scoreline, live-refreshing status, tappable broadcast chips and an
 * inline Watch CTA that presents the existing [SportsWatchSheet]. All deep
 * linking, watch-intent logging, cast and watchlist behavior stays in the sheet.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SportsGameDetailScreen(
    game: SportsGame,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    /** Optional "Full schedule" handler for the watch sheet; falls back to [onBack]. */
    onOpenSchedule: (() -> Unit)? = null,
) {
    val favorites = TeamFavoritesService.get()
    val favRows by favorites.rows.collectAsStateWithLifecycle()
    val auth = AuthViewModel.get()
    val lifecycleOwner = LocalLifecycleOwner.current

    // Live copy of the game, seeded from the passed-in game and replaced by
    // each successful ESPN refresh. Everything below reads `current`.
    var liveGame by remember(game.id) { mutableStateOf(game) }
    var lastRefresh by remember(game.id) { mutableStateOf<Long?>(null) }
    var nowMs by remember(game.id) { mutableLongStateOf(System.currentTimeMillis()) }
    var selectedBroadcast by remember(game.id) { mutableStateOf<String?>(null) }
    var showWatchSheet by remember { mutableStateOf(false) }

    val current = liveGame
    val isLive = current.state == "live"
    val isFinal = current.state == "post"
    val statusText = when (current.state) {
        "live" -> "LIVE"
        "post" -> "FINAL"
        else -> "UPCOMING"
    }
    val statusColor = if (isLive) BrandOrange else TextTertiary

    val awayFav = current.away.uid != null && favRows.containsKey(current.away.uid)
    val homeFav = current.home.uid != null && favRows.containsKey(current.home.uid)

    // Broadcasts enriched with streaming simulcast companions, de-duped
    // preserving first-seen order, then stable-sorted so services the user
    // subscribes to come first — the same ordering the watch sheet uses.
    val sortedBroadcasts = enrichBroadcasts(current.broadcasts)
        .distinct()
        .withIndex()
        .sortedWith(
            compareByDescending<IndexedValue<String>> { auth.subscribesToService(it.value) }
                .thenBy { it.index }
        )
        .map { it.value }

    val activeBroadcast = selectedBroadcast?.takeIf { sortedBroadcasts.contains(it) }
        ?: sortedBroadcasts.firstOrNull()
        ?: current.broadcasts.firstOrNull()

    // Live-score polling. Runs only while the game is live and the screen is
    // resumed; repeatOnLifecycle stops it on background and restarts it with an
    // immediate refresh on foreground. A failed refresh keeps the last good
    // values and the previous stamp — no blanked score, no error banner.
    LaunchedEffect(current.state, game.id) {
        if (current.state != "live") return@LaunchedEffect
        lifecycleOwner.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            while (isActive) {
                SportsService.get().refresh(liveGame)?.let {
                    liveGame = it
                    lastRefresh = System.currentTimeMillis()
                    nowMs = System.currentTimeMillis()
                }
                delay(REFRESH_INTERVAL_MS)
            }
        }
    }

    // 1s tick so "updated Ns ago" counts up between refreshes.
    LaunchedEffect(current.state, game.id) {
        if (current.state != "live") return@LaunchedEffect
        lifecycleOwner.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            while (isActive) {
                nowMs = System.currentTimeMillis()
                delay(1_000L)
            }
        }
    }

    val updatedStamp: String? = lastRefresh
        ?.takeIf { isLive }
        ?.let { last ->
            val seconds = ((nowMs - last) / 1000L).coerceAtLeast(0L)
            if (seconds < 60) "updated ${seconds}s ago" else "updated ${seconds / 60}m ago"
        }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(Color(red = 0x04, green = 0x09, blue = 0x0F))
            .verticalScroll(rememberScrollState()),
    ) {
        // Top bar
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(GlassFill)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onBack() },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Filled.ArrowBack,
                    contentDescription = "Back",
                    tint = TextPrimary,
                    modifier = Modifier.size(22.dp),
                )
            }
            Spacer(Modifier.width(12.dp))
            Text(
                text = current.sport.replaceFirstChar { it.uppercase() },
                fontSize = 20.sp,
                fontWeight = FontWeight.Black,
                color = TextPrimary,
            )
        }

        Column(
            modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            // League label
            Text(
                text = current.sport.uppercase(),
                fontSize = 12.sp,
                fontWeight = FontWeight.Black,
                color = TextTertiary,
                letterSpacing = 1.4.sp,
            )

            // Scoreline
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // Away team
                Column(modifier = Modifier.weight(1f)) {
                    TeamLogo(
                        team = current.away,
                        size = 56.dp,
                        cornerRadius = 14.dp,
                        inset = 8.dp,
                        abbreviationFontSize = 13.sp,
                    )
                    Spacer(Modifier.height(8.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            text = current.away.abbreviation.take(3),
                            fontSize = 22.sp,
                            fontWeight = FontWeight.Bold,
                            color = TextPrimary,
                        )
                        Spacer(Modifier.width(8.dp))
                        FavoriteStar(
                            isFavorite = awayFav,
                            onClick = { favorites.toggle(current.away, current.leagueShort, current.sport) },
                        )
                    }
                    Text(
                        text = (current.awayScore ?: 0).toString(),
                        fontSize = 36.sp,
                        fontWeight = FontWeight.Black,
                        color = TextPrimary,
                    )
                }

                // Status
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(12.dp))
                        .background(GlassFill)
                        .padding(horizontal = 12.dp, vertical = 6.dp),
                ) {
                    Text(
                        text = statusText,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Black,
                        color = statusColor,
                    )
                }

                // Home team
                Column(
                    modifier = Modifier.weight(1f),
                    horizontalAlignment = Alignment.End,
                ) {
                    TeamLogo(
                        team = current.home,
                        size = 56.dp,
                        cornerRadius = 14.dp,
                        inset = 8.dp,
                        abbreviationFontSize = 13.sp,
                    )
                    Spacer(Modifier.height(8.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        FavoriteStar(
                            isFavorite = homeFav,
                            onClick = { favorites.toggle(current.home, current.leagueShort, current.sport) },
                        )
                        Spacer(Modifier.width(8.dp))
                        Text(
                            text = current.home.abbreviation.take(3),
                            fontSize = 22.sp,
                            fontWeight = FontWeight.Bold,
                            color = TextPrimary,
                        )
                    }
                    Text(
                        text = (current.homeScore ?: 0).toString(),
                        fontSize = 36.sp,
                        fontWeight = FontWeight.Black,
                        color = TextPrimary,
                        textAlign = TextAlign.End,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }

            // Status + date (+ refresh stamp for live games)
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = if (isLive) "In Progress" else if (isFinal) "Game Finished" else "Scheduled",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = TextPrimary,
                    )
                    updatedStamp?.let {
                        Spacer(Modifier.width(6.dp))
                        Text(
                            text = "· $it",
                            fontSize = 12.sp,
                            color = TextTertiary,
                        )
                    }
                }
                current.startTime?.let { ts ->
                    Text(
                        text = formatGameTime(ts),
                        fontSize = 13.sp,
                        color = TextSecondary,
                    )
                }
            }

            // Watch on — tappable chips, subscribed-first, wrapping
            if (sortedBroadcasts.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        text = "WATCH ON",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Black,
                        color = TextTertiary,
                        letterSpacing = 1.4.sp,
                    )
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        sortedBroadcasts.forEachIndexed { index, name ->
                            BroadcastChip(
                                name = name,
                                accented = index == 0 && auth.subscribesToService(name),
                                selected = activeBroadcast == name,
                                onClick = { selectedBroadcast = name },
                            )
                        }
                    }
                }
            }

            // Inline watch CTA — presents the existing watch sheet.
            val canWatch = !activeBroadcast.isNullOrEmpty()
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(54.dp)
                    .clip(CircleShape)
                    .background(if (canWatch) BrandOrange else Color.White.copy(alpha = 0.15f))
                    .clickable(
                        enabled = canWatch,
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { showWatchSheet = true },
                contentAlignment = Alignment.Center,
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(
                        imageVector = Icons.Filled.PlayArrow,
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier.size(20.dp),
                    )
                    Text(
                        text = if (canWatch) "Watch on $activeBroadcast" else "Broadcast TBA",
                        fontSize = 16.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White,
                    )
                }
            }

            BottomSafeSpacer(withTabBar = false)
        }
    }

    if (showWatchSheet) {
        SportsWatchSheet(
            game = current,
            onDismiss = { showWatchSheet = false },
            onOpenGameDetail = { /* already on the detail screen */ },
            onOpenSchedule = { onOpenSchedule?.invoke() ?: onBack() },
            showGameDetailsPill = false,
        )
    }
}

@Composable
private fun BroadcastChip(
    name: String,
    accented: Boolean,
    selected: Boolean,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .clip(CircleShape)
            .background(if (accented) BrandOrange.copy(alpha = 0.14f) else Color.White.copy(alpha = 0.07f))
            .border(
                width = if (selected) 1.5.dp else 1.dp,
                color = when {
                    accented -> BrandOrange
                    selected -> Color.White.copy(alpha = 0.45f)
                    else -> Color.White.copy(alpha = 0.12f)
                },
                shape = CircleShape,
            )
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() }
            .padding(horizontal = 14.dp, vertical = 9.dp),
    ) {
        Text(
            text = name,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            color = if (accented) BrandOrange else Color.White,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun FavoriteStar(isFavorite: Boolean, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(32.dp)
            .clip(CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = if (isFavorite) Icons.Filled.Star else Icons.Outlined.Star,
            contentDescription = "Favorite team",
            tint = if (isFavorite) BrandOrange else TextTertiary,
            modifier = Modifier
                .size(16.dp)
                .clip(CircleShape)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) { onClick() },
        )
    }
}

private fun formatGameTime(timestamp: String): String {
    return try {
        // ISO 8601 format
        val inputFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)
        inputFormat.timeZone = java.util.TimeZone.getTimeZone("UTC")
        val date: Date = inputFormat.parse(timestamp) ?: return timestamp
        val outputFormat = SimpleDateFormat("EEE, MMM d · h:mm a", Locale.getDefault())
        outputFormat.format(date)
    } catch (_: Exception) {
        timestamp
    }
}

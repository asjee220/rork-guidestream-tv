package com.rork.guidestreamtvandroid.ui.sports

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rork.guidestreamtvandroid.data.models.Platform
import com.rork.guidestreamtvandroid.data.models.SportsGame
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.data.repository.StreamsViewModel
import com.rork.guidestreamtvandroid.data.repository.TeamFavoritesService
import com.rork.guidestreamtvandroid.data.repository.WatchIntentLogger
import com.rork.guidestreamtvandroid.ui.cast.CastToTVSheet
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.Hairline
import com.rork.guidestreamtvandroid.ui.theme.Navy
import com.rork.guidestreamtvandroid.ui.theme.OutlineVariant
import com.rork.guidestreamtvandroid.ui.theme.SurfaceContainer
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Bottom sheet presented when a user taps a game card in the Sports tab.
 * Mirrors iOS SportsWatchSheet.swift — header, actions row, watch context,
 * Where to Watch chips, watch CTA + watch list, secondary pills, About, close.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SportsWatchSheet(
    game: SportsGame,
    onDismiss: () -> Unit,
    onOpenGameDetail: (SportsGame) -> Unit,
    onOpenSchedule: () -> Unit,
) {
    val context = LocalContext.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val favorites = TeamFavoritesService.get()
    val favRows by favorites.rows.collectAsStateWithLifecycle()
    val streams = StreamsViewModel.get()
    val userStreams by streams.userStreams.collectAsStateWithLifecycle()

    val auth = AuthViewModel.get()
    var showCast by remember { mutableStateOf(false) }
    var selectedBroadcast by remember { mutableStateOf<String?>(null) }

    val primaryBroadcast = game.broadcasts.firstOrNull()

    // De-duped broadcasts preserving first-seen order, then stable-sorted so
    // services the user subscribes to come first — mirrors the iOS chip order.
    val sortedBroadcasts = game.broadcasts
        .distinct()
        .withIndex()
        .sortedWith(
            compareByDescending<IndexedValue<String>> { auth.subscribesToService(it.value) }
                .thenBy { it.index }
        )
        .map { it.value }

    // The broadcast the Watch CTA currently targets.
    val activeBroadcast = selectedBroadcast?.takeIf { sortedBroadcasts.contains(it) }
        ?: sortedBroadcasts.firstOrNull()
        ?: game.broadcasts.firstOrNull()
    val gameTitle = "${game.away.shortName.ifEmpty { game.away.abbreviation }} vs ${game.home.shortName.ifEmpty { game.home.abbreviation }}"
    val saveId = WatchIntentLogger.get().titleSlug("${game.away.abbreviation}-${game.home.abbreviation}-${game.sport}")
    val isSaved = userStreams.any { it.titleId == saveId }

    LaunchedEffect(saveId) {
        WatchIntentLogger.get().log(
            WatchIntentLogger.IntentEventType.EPISODE_DETAIL_VIEWED,
            titleId = saveId,
            platformId = primaryBroadcast?.lowercase(),
            metadata = mapOf("sport" to game.sport, "state" to game.state),
        )
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Color(red = 0x13, green = 0x18, blue = 0x1D),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(bottom = 28.dp),
        ) {
            // Header
            HeaderRow(game, gameTitle, primaryBroadcast)

            Divider()

            // Actions row: favorite away, favorite home, share, send to TV
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 20.dp),
                horizontalArrangement = Arrangement.SpaceEvenly,
            ) {
                val awayFav = game.away.uid != null && favRows.containsKey(game.away.uid)
                val homeFav = game.home.uid != null && favRows.containsKey(game.home.uid)
                CircleAction(
                    icon = if (awayFav) Icons.Filled.Star else Icons.Outlined.Star,
                    label = game.away.abbreviation,
                    tint = if (awayFav) BrandOrange else Color.White,
                ) { favorites.toggle(game.away, game.leagueShort, game.sport) }
                CircleAction(
                    icon = if (homeFav) Icons.Filled.Star else Icons.Outlined.Star,
                    label = game.home.abbreviation,
                    tint = if (homeFav) BrandOrange else Color.White,
                ) { favorites.toggle(game.home, game.leagueShort, game.sport) }
                CircleAction(
                    icon = Icons.Filled.Share,
                    label = "Share",
                    tint = Color.White,
                ) {
                    val share = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, "Watch $gameTitle on GuideStream TV\nhttps://guidestream.tv")
                    }
                    context.startActivity(Intent.createChooser(share, "Share"))
                }
                CircleAction(
                    icon = Icons.Filled.Tv,
                    label = "Send to TV",
                    tint = Color.White,
                ) { showCast = true }
            }

            Divider()

            // Watch context card
            Column(
                modifier = Modifier
                    .padding(horizontal = 20.dp)
                    .padding(top = 20.dp)
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(SurfaceContainer)
                    .border(0.5.dp, OutlineVariant, RoundedCornerShape(14.dp))
                    .padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                StatusChip(game.state)
                if (game.state != "pre") {
                    LiveScoreRow(game)
                }
            }

            // Where to Watch chips
            SportsWhereToWatchRow(
                broadcasts = sortedBroadcasts,
                activeBroadcast = activeBroadcast,
                isSubscribed = { auth.subscribesToService(it) },
                onSelect = { selectedBroadcast = it },
            )

            // Watch CTA + watch list
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp)
                    .padding(top = 22.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.Top,
            ) {
                val canWatch = activeBroadcast != null
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(56.dp)
                        .clip(CircleShape)
                        .background(if (canWatch) BrandOrange else Color.White.copy(alpha = 0.15f))
                        .clickable(
                            enabled = canWatch,
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) {
                            WatchIntentLogger.get().log(
                                WatchIntentLogger.IntentEventType.DEEPLINK_FIRED,
                                titleId = saveId,
                                platformId = activeBroadcast?.lowercase(),
                                metadata = mapOf("sport" to game.sport, "platform_name" to (activeBroadcast ?: "")),
                            )
                            val q = Uri.encode("watch ${activeBroadcast ?: ""} $gameTitle live")
                            runCatching {
                                context.startActivity(
                                    Intent(Intent.ACTION_VIEW, Uri.parse("https://www.google.com/search?q=$q")),
                                )
                            }
                            onDismiss()
                        },
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
                            modifier = Modifier.size(18.dp),
                        )
                        Text(
                            text = if (canWatch) "Watch on $activeBroadcast" else "Broadcast TBA",
                            fontSize = 16.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = Color.White,
                        )
                    }
                }

                // Watch list circle
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(
                        modifier = Modifier
                            .size(56.dp)
                            .clip(CircleShape)
                            .then(
                                if (isSaved) Modifier.border(1.8.dp, Color.White, CircleShape)
                                else Modifier.background(BrandOrange)
                            )
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                            ) {
                                if (isSaved) {
                                    streams.removeFromMyStreams(saveId)
                                } else {
                                    streams.addToMyStreams(saveId, gameTitle, null, activeBroadcast)
                                }
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            imageVector = if (isSaved) Icons.Filled.Check else Icons.Filled.Add,
                            contentDescription = null,
                            tint = Color.White,
                            modifier = Modifier.size(24.dp),
                        )
                    }
                    Spacer(Modifier.height(6.dp))
                    Text(
                        text = if (isSaved) "Saved" else "Watch List",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White,
                    )
                }
            }

            // Secondary pills: full schedule, game details
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp)
                    .padding(top = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                SecondaryPill(
                    icon = Icons.Filled.CalendarMonth,
                    label = "Full schedule",
                    modifier = Modifier.weight(1f),
                ) {
                    onDismiss()
                    onOpenSchedule()
                }
                SecondaryPill(
                    icon = Icons.Filled.Info,
                    label = "Game details",
                    modifier = Modifier.weight(1f),
                ) {
                    onDismiss()
                    onOpenGameDetail(game)
                }
            }

            // About
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp)
                    .padding(top = 28.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Text(
                    text = "ABOUT",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Black,
                    color = TextTertiary,
                    letterSpacing = 1.4.sp,
                )
                Text(
                    text = aboutText(game, primaryBroadcast),
                    fontSize = 15.sp,
                    color = Color.White.copy(alpha = 0.85f),
                    lineHeight = 21.sp,
                )
            }
        }
    }

    if (showCast) {
        CastToTVSheet(onClose = { showCast = false })
    }
}

/**
 * Selectable "Where to Watch" chip row for the sports sheet. Faithfully mirrors
 * the show-detail `WhereToWatchRow` styling: one chip per broadcast, subscribed
 * chips get a green "Subscribed" badge and the active chip an orange checkmark.
 * Hidden entirely when there are no broadcasts.
 */
@Composable
private fun SportsWhereToWatchRow(
    broadcasts: List<String>,
    activeBroadcast: String?,
    isSubscribed: (String) -> Boolean,
    onSelect: (String) -> Unit,
) {
    if (broadcasts.isEmpty()) return
    Text(
        text = "Where to Watch",
        fontSize = 17.sp,
        fontWeight = FontWeight.Bold,
        color = TextPrimary,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
    )
    LazyRow(
        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        items(broadcasts) { broadcast ->
            val subscribed = isSubscribed(broadcast)
            val selected = activeBroadcast == broadcast
            val dotColor = Platform.from(broadcast)?.color ?: BrandOrange
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(12.dp))
                    .background(dotColor.copy(alpha = if (subscribed) 0.28f else 0.18f))
                    .border(
                        width = if (selected) 2.dp else 1.dp,
                        color = if (selected) dotColor else dotColor.copy(alpha = if (subscribed) 0.70f else 0.45f),
                        shape = RoundedCornerShape(12.dp),
                    )
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) {
                        onSelect(broadcast)
                    }
                    .padding(horizontal = 14.dp, vertical = 10.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = Modifier
                            .size(8.dp)
                            .clip(CircleShape)
                            .background(dotColor),
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        text = broadcast,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = TextPrimary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    if (subscribed) {
                        Spacer(Modifier.width(8.dp))
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(4.dp))
                                .background(Color(0xFF34C759).copy(alpha = 0.85f))
                                .padding(horizontal = 6.dp, vertical = 2.dp),
                        ) {
                            Text(
                                text = "Subscribed",
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Black,
                                color = Color.White,
                            )
                        }
                    }
                    if (selected) {
                        Spacer(Modifier.width(6.dp))
                        Box(
                            modifier = Modifier
                                .size(16.dp)
                                .clip(CircleShape)
                                .background(BrandOrange),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(
                                imageVector = Icons.Filled.Check,
                                contentDescription = "Selected",
                                tint = Color.White,
                                modifier = Modifier.size(10.dp),
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun HeaderRow(game: SportsGame, gameTitle: String, primaryBroadcast: String?) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp)
            .padding(top = 6.dp, bottom = 18.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // Team-color thumbnail
        val awayColor = game.away.primaryHex?.let { parseHex(it) } ?: Color.White.copy(alpha = 0.18f)
        val homeColor = game.home.primaryHex?.let { parseHex(it) } ?: Color.White.copy(alpha = 0.18f)
        Box(
            modifier = Modifier
                .size(width = 110.dp, height = 150.dp)
                .clip(RoundedCornerShape(12.dp)),
        ) {
            Column(Modifier.fillMaxWidth()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(75.dp)
                        .background(awayColor)
                        .padding(10.dp),
                ) {
                    Column {
                        Text("AWAY", fontSize = 8.sp, fontWeight = FontWeight.Black, color = Color.White.copy(alpha = 0.65f))
                        Text(game.away.abbreviation, fontSize = 22.sp, fontWeight = FontWeight.Black, color = Color.White)
                    }
                }
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(75.dp)
                        .background(homeColor)
                        .padding(10.dp),
                    contentAlignment = Alignment.BottomEnd,
                ) {
                    Column(horizontalAlignment = Alignment.End) {
                        Text("HOME", fontSize = 8.sp, fontWeight = FontWeight.Black, color = Color.White.copy(alpha = 0.65f))
                        Text(game.home.abbreviation, fontSize = 22.sp, fontWeight = FontWeight.Black, color = Color.White)
                    }
                }
            }
            Box(
                modifier = Modifier
                    .align(Alignment.Center)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.5f))
                    .border(1.dp, Color.White.copy(alpha = 0.18f), CircleShape)
                    .padding(horizontal = 8.dp, vertical = 4.dp),
            ) {
                Text("VS", fontSize = 11.sp, fontWeight = FontWeight.Black, color = Color.White)
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                text = gameTitle,
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
                maxLines = 2,
            )
            val meta = listOf(game.sport, game.statusDetail).filter { it.isNotEmpty() }.joinToString(" · ")
            Text(text = meta, fontSize = 13.sp, color = TextSecondary)
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                StatusChip(game.state)
                Box(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(SurfaceContainer)
                        .padding(horizontal = 10.dp, vertical = 6.dp),
                ) {
                    Text(game.sport.uppercase(), fontSize = 11.sp, fontWeight = FontWeight.Black, color = Color.White)
                }
            }
        }
    }
}

@Composable
private fun StatusChip(state: String) {
    val (label, bg) = when (state) {
        "live" -> "LIVE" to Color(0xFFE50914)
        "post" -> "FINAL" to Color.White.copy(alpha = 0.18f)
        else -> "UPCOMING" to BrandOrange
    }
    Box(
        modifier = Modifier
            .clip(CircleShape)
            .background(bg)
            .padding(horizontal = 10.dp, vertical = 6.dp),
    ) {
        Text(label, fontSize = 11.sp, fontWeight = FontWeight.Black, color = Color.White)
    }
}

@Composable
private fun LiveScoreRow(game: SportsGame) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column {
            Text(game.away.abbreviation, fontSize = 10.sp, fontWeight = FontWeight.Black, color = Color.White.copy(alpha = 0.6f))
            Text(game.away.score.ifEmpty { "0" }, fontSize = 22.sp, fontWeight = FontWeight.Black, color = if (game.away.isWinner) Color.White else Color.White.copy(alpha = 0.7f))
        }
        Text("–", fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Color.White.copy(alpha = 0.3f))
        Column {
            Text(game.home.abbreviation, fontSize = 10.sp, fontWeight = FontWeight.Black, color = Color.White.copy(alpha = 0.6f))
            Text(game.home.score.ifEmpty { "0" }, fontSize = 22.sp, fontWeight = FontWeight.Black, color = if (game.home.isWinner) Color.White else Color.White.copy(alpha = 0.7f))
        }
    }
}

@Composable
private fun CircleAction(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    tint: Color,
    onClick: () -> Unit,
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() }
            .padding(horizontal = 4.dp),
    ) {
        Box(
            modifier = Modifier
                .size(54.dp)
                .clip(CircleShape)
                .background(SurfaceContainer),
            contentAlignment = Alignment.Center,
        ) {
            Icon(imageVector = icon, contentDescription = label, tint = tint, modifier = Modifier.size(22.dp))
        }
        Text(label, fontSize = 12.sp, color = Color.White.copy(alpha = 0.7f), maxLines = 1)
    }
}

@Composable
private fun SecondaryPill(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Row(
        modifier = modifier
            .height(44.dp)
            .clip(CircleShape)
            .border(0.5.dp, Color.White.copy(alpha = 0.12f), CircleShape)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() },
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(imageVector = icon, contentDescription = null, tint = Color.White, modifier = Modifier.size(16.dp))
        Spacer(Modifier.width(6.dp))
        Text(label, fontSize = 13.sp, fontWeight = FontWeight.Medium, color = Color.White)
    }
}

@Composable
private fun Divider() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp)
            .height(1.dp)
            .background(Hairline),
    )
}

private fun aboutText(game: SportsGame, broadcast: String?): String = when (game.state) {
    "live" -> if (broadcast != null) "Live now on $broadcast. Tap watch to open the broadcast and jump into the action." else "Live now. Tap watch to find the broadcast and start streaming."
    "post" -> {
        val summary = when {
            game.away.isWinner -> "${game.away.shortName} won ${game.away.score}–${game.home.score} over ${game.home.shortName}."
            game.home.isWinner -> "${game.home.shortName} won ${game.home.score}–${game.away.score} over ${game.away.shortName}."
            else -> "Final: ${game.away.shortName} ${game.away.score}, ${game.home.shortName} ${game.home.score}."
        }
        if (broadcast != null) "$summary Watch the recap and highlights on $broadcast." else "$summary Highlights will be available shortly after the final whistle."
    }
    else -> {
        val whenStr = formatStart(game.startTime)
        if (broadcast != null) "$whenStr on $broadcast. Set a reminder so you don't miss tip-off — or tap watch when the broadcast goes live." else "$whenStr. Broadcast info will appear closer to game time."
    }
}

private fun formatStart(timestamp: String?): String {
    if (timestamp == null) return "Upcoming"
    return try {
        val input = SimpleDateFormat("yyyy-MM-dd'T'HH:mm'Z'", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }
        val date: Date = input.parse(timestamp) ?: return "Upcoming"
        SimpleDateFormat("EEE, MMM d · h:mm a", Locale.getDefault()).format(date)
    } catch (_: Exception) {
        try {
            val input = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }
            val date: Date = input.parse(timestamp) ?: return "Upcoming"
            SimpleDateFormat("EEE, MMM d · h:mm a", Locale.getDefault()).format(date)
        } catch (_: Exception) {
            "Upcoming"
        }
    }
}

internal fun parseHex(hex: String): Color {
    val clean = hex.removePrefix("#")
    return try {
        val v = clean.toLong(16)
        when (clean.length) {
            6 -> Color(
                red = ((v shr 16) and 0xFF) / 255f,
                green = ((v shr 8) and 0xFF) / 255f,
                blue = (v and 0xFF) / 255f,
            )
            8 -> Color(
                red = ((v shr 24) and 0xFF) / 255f,
                green = ((v shr 16) and 0xFF) / 255f,
                blue = ((v shr 8) and 0xFF) / 255f,
                alpha = (v and 0xFF) / 255f,
            )
            else -> Navy
        }
    } catch (_: Exception) {
        Navy
    }
}

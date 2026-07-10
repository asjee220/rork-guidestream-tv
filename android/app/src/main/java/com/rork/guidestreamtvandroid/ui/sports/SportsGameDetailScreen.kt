package com.rork.guidestreamtvandroid.ui.sports

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.guidestreamtvandroid.data.models.SportsGame
import com.rork.guidestreamtvandroid.data.repository.TeamFavoritesService
import com.rork.guidestreamtvandroid.ui.components.RemoteImage
import com.rork.guidestreamtvandroid.ui.components.glassCard
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.GlassFill
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Sports game detail screen — mirrors iOS SportsGameDetailView.swift.
 * Matchup, scoreline, status, broadcasts, deep link to streaming app.
 */
@Composable
fun SportsGameDetailScreen(
    game: SportsGame,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val favorites = TeamFavoritesService.get()
    val favRows by favorites.rows.collectAsStateWithLifecycle()
    val awayFav = game.away.uid != null && favRows.containsKey(game.away.uid)
    val homeFav = game.home.uid != null && favRows.containsKey(game.home.uid)

    val isLive = game.state == "live"
    val isFinal = game.state == "final"
    val statusText = when (game.state) {
        "live" -> "LIVE"
        "final" -> "FINAL"
        else -> "UPCOMING"
    }
    val statusColor = if (isLive) BrandOrange else TextTertiary

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
                text = game.sport.replaceFirstChar { it.uppercase() },
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
                text = game.sport.uppercase(),
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
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            text = game.away.abbreviation.take(3),
                            fontSize = 22.sp,
                            fontWeight = FontWeight.Bold,
                            color = TextPrimary,
                        )
                        Spacer(Modifier.width(8.dp))
                        FavoriteStar(
                            isFavorite = awayFav,
                            onClick = { favorites.toggle(game.away, game.leagueShort, game.sport) },
                        )
                    }
                    Text(
                        text = (game.awayScore ?: 0).toString(),
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
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        FavoriteStar(
                            isFavorite = homeFav,
                            onClick = { favorites.toggle(game.home, game.leagueShort, game.sport) },
                        )
                        Spacer(Modifier.width(8.dp))
                        Text(
                            text = game.home.abbreviation.take(3),
                            fontSize = 22.sp,
                            fontWeight = FontWeight.Bold,
                            color = TextPrimary,
                        )
                    }
                    Text(
                        text = (game.homeScore ?: 0).toString(),
                        fontSize = 36.sp,
                        fontWeight = FontWeight.Black,
                        color = TextPrimary,
                        textAlign = TextAlign.End,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }

            // Status + date
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    text = if (isLive) "In Progress" else if (isFinal) "Game Finished" else "Scheduled",
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = TextPrimary,
                )
                game.startTime?.let { ts ->
                    val formatted = formatGameTime(ts)
                    Text(
                        text = formatted,
                        fontSize = 13.sp,
                        color = TextSecondary,
                    )
                }
            }

            // Watch on
            if (game.broadcasts.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        text = "WATCH ON",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Black,
                        color = TextTertiary,
                        letterSpacing = 1.4.sp,
                    )
                    Text(
                        text = game.broadcasts.joinToString(" · "),
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = TextPrimary,
                    )
                }
            }

            Spacer(Modifier.height(8.dp))

            // Watch CTA — opens a search for the broadcast
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(BrandOrange)
                    .padding(vertical = 16.dp),
                contentAlignment = Alignment.Center,
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = Icons.Filled.PlayArrow,
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier.size(20.dp),
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        text = "Watch Game",
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                    )
                }
            }
        }
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

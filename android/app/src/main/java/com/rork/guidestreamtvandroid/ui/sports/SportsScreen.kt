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
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
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
import com.rork.guidestreamtvandroid.data.repository.WatchIntentLogger
import com.rork.guidestreamtvandroid.ui.components.RemoteImage
import com.rork.guidestreamtvandroid.ui.components.glassCard
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.GlassFill
import com.rork.guidestreamtvandroid.ui.theme.GlassStroke
import com.rork.guidestreamtvandroid.ui.theme.NewsGreen
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary

/**
 * Sports screen — mirrors iOS SportsView.swift.
 * Live/upcoming games list with scores, broadcast info, sport filters.
 */
@Composable
fun SportsScreen(
    modifier: Modifier = Modifier,
) {
    val vm = SportsViewModel.get()
    val games by vm.games.collectAsStateWithLifecycle()
    val isLoading by vm.isLoading.collectAsStateWithLifecycle()
    val selectedSport by vm.selectedSport.collectAsStateWithLifecycle()

    LaunchedEffect(Unit) {
        vm.fetchGames()
    }

    Column(
        modifier = modifier.fillMaxSize(),
    ) {
        // Header
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "Sports",
                fontSize = 24.sp,
                fontWeight = FontWeight.Black,
                color = TextPrimary,
            )
            Spacer(Modifier.weight(1f))
            if (isLoading) {
                CircularProgressIndicator(
                    color = BrandOrange,
                    modifier = Modifier.size(20.dp),
                    strokeWidth = 2.dp,
                )
            }
        }

        // Sport filter chips
        val sports = remember(games) { games.map { it.sport }.distinct().sorted() }
        LazyRow(
            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            item {
                val selected = selectedSport == null
                SportChip("All", selected) { vm.setSport(null) }
            }
            items(sports) { sport ->
                val selected = selectedSport == sport
                SportChip(sport, selected) { vm.setSport(sport) }
            }
        }

        // Games list
        val filtered = remember(games, selectedSport) {
            if (selectedSport != null) games.filter { it.sport == selectedSport } else games
        }

        if (filtered.isEmpty() && !isLoading) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = "No games right now. Check back later.",
                    fontSize = 14.sp,
                    color = TextTertiary,
                )
            }
        } else {
            LazyColumn(
                contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                items(filtered) { game ->
                    GameCard(game = game, onClick = {
                        WatchIntentLogger.get().log(
                            WatchIntentLogger.IntentEventType.CARD_TAPPED,
                            titleId = "${game.away.abbreviation}-${game.home.abbreviation}-${game.sport}",
                            metadata = mapOf("section" to "sports", "sport" to game.sport),
                        )
                    })
                }
            }
        }
    }
}

@Composable
private fun SportChip(label: String, selected: Boolean, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(16.dp))
            .background(if (selected) BrandOrange else GlassFill)
            .border(1.dp, if (selected) BrandOrange else GlassStroke, RoundedCornerShape(16.dp))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() }
            .padding(horizontal = 14.dp, vertical = 7.dp),
    ) {
        Text(
            text = label,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            color = if (selected) Color.White else TextSecondary,
        )
    }
}

@Composable
private fun GameCard(game: SportsGame, onClick: () -> Unit) {
    val isLive = game.state == "live"
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .glassCard(12)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() }
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Away team
        Column(
            modifier = Modifier.weight(1f),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            if (game.away.logoUrl != null) {
                RemoteImage(
                    url = game.away.logoUrl,
                    contentDescription = game.away.name,
                    modifier = Modifier.size(40.dp),
                    cornerRadius = 20,
                )
            } else {
                Box(
                    modifier = Modifier
                        .size(40.dp)
                        .clip(CircleShape)
                        .background(GlassFill),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = game.away.abbreviation.take(3),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        color = TextPrimary,
                    )
                }
            }
            Spacer(Modifier.height(4.dp))
            Text(
                text = game.away.abbreviation,
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
            )
            if (game.awayScore != null) {
                Text(
                    text = game.awayScore.toString(),
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Black,
                    color = if (isLive) NewsGreen else TextPrimary,
                )
            }
        }

        // Center: status
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.padding(horizontal = 8.dp),
        ) {
            if (isLive) {
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(4.dp))
                        .background(NewsGreen)
                        .padding(horizontal = 6.dp, vertical = 2.dp),
                ) {
                    Text(
                        text = "LIVE",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Black,
                        color = Color.Black,
                    )
                }
            } else {
                Text(
                    text = game.sport,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    color = BrandOrange,
                )
            }
            Spacer(Modifier.height(4.dp))
            Text(
                text = if (isLive) game.state else (game.startTime?.take(10) ?: ""),
                fontSize = 11.sp,
                color = TextTertiary,
            )
            Text(
                text = "VS",
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                color = TextTertiary,
            )
        }

        // Home team
        Column(
            modifier = Modifier.weight(1f),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            if (game.home.logoUrl != null) {
                RemoteImage(
                    url = game.home.logoUrl,
                    contentDescription = game.home.name,
                    modifier = Modifier.size(40.dp),
                    cornerRadius = 20,
                )
            } else {
                Box(
                    modifier = Modifier
                        .size(40.dp)
                        .clip(CircleShape)
                        .background(GlassFill),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = game.home.abbreviation.take(3),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        color = TextPrimary,
                    )
                }
            }
            Spacer(Modifier.height(4.dp))
            Text(
                text = game.home.abbreviation,
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
            )
            if (game.homeScore != null) {
                Text(
                    text = game.homeScore.toString(),
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Black,
                    color = if (isLive) NewsGreen else TextPrimary,
                )
            }
        }
    }

    // Broadcasts
    if (game.broadcasts.isNotEmpty()) {
        Text(
            text = game.broadcasts.joinToString(" · "),
            fontSize = 11.sp,
            color = TextTertiary,
            modifier = Modifier.padding(start = 16.dp, top = 2.dp),
        )
    }
}

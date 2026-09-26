package com.rork.guidestreamtvandroid.ui.sports

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.SubcomposeAsyncImage
import com.rork.guidestreamtvandroid.data.models.SportsGame
import com.rork.guidestreamtvandroid.data.remote.SportsTeamCatalogService

/**
 * Sports restyle (2026-09-25): a team crest on a filled circle with a white
 * ring. The fill is `sports_teams.fill_color` — the team colour, or its
 * secondary colour when the crest is mostly the primary one (computed
 * server-side by sports_team_fill) — falling back to the game's ESPN primary
 * colour. Mirrors iOS TeamCrestCircle.swift.
 */
internal object SportsCrestStyle {
    /** White ring around every crest circle on the phone (approved mockup: 3). */
    val ringWidth: Dp = 3.dp

    fun ring(size: Dp): Dp = when {
        size >= 44.dp -> ringWidth
        size >= 28.dp -> ringWidth * 0.67f
        else -> maxOf(1.dp, ringWidth * 0.5f)
    }

    /** Background of a crest circle for a team that is not followed. */
    val emptyFill = Color(0xFF141B26)
}

@Composable
internal fun TeamCrestCircle(
    team: SportsGame.TeamSummary,
    size: Dp,
    modifier: Modifier = Modifier,
    filled: Boolean = true,
) {
    // Read the catalogue as state so circles recolour once it loads — the
    // callers' own parameters don't change when it does, so without this a
    // circle drawn before the catalogue arrived keeps the ESPN primary.
    val catalog = SportsTeamCatalogService.get()
    val catalogTeams by catalog.teams.collectAsState()
    val fillHex = remember(catalogTeams, team.uid, team.primaryHex) {
        catalog.fillHex(team.uid) ?: team.primaryHex
    }
    val fill = if (filled) hexToColor(fillHex, Color.White.copy(alpha = 0.15f)) else SportsCrestStyle.emptyFill
    val ring = if (filled) SportsCrestStyle.ring(size) else 1.5.dp
    val ringColor = if (filled) Color.White else Color.White.copy(alpha = 0.14f)
    val textColor = if (filled && fill.luminance() > 0.6f) Color(0xFF0B0F16) else Color.White
    val logoUrl = team.logoUrl?.takeIf { it.isNotBlank() }

    Box(
        modifier = modifier
            .size(size)
            .clip(CircleShape)
            .background(fill)
            .border(ring, ringColor, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        val abbreviation: @Composable () -> Unit = {
            Text(
                team.abbreviation,
                fontSize = (size.value * 0.26f).sp,
                fontWeight = FontWeight.ExtraBold,
                color = textColor,
                maxLines = 1,
            )
        }
        if (logoUrl != null) {
            SubcomposeAsyncImage(
                model = logoUrl,
                contentDescription = team.abbreviation,
                modifier = Modifier.fillMaxSize().padding(size * 0.18f),
                contentScale = ContentScale.Fit,
                error = { Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { abbreviation() } },
                success = { state ->
                    Image(
                        painter = state.painter,
                        contentDescription = team.abbreviation,
                        modifier = Modifier.fillMaxSize(),
                        contentScale = ContentScale.Fit,
                    )
                },
            )
        } else {
            abbreviation()
        }
    }
}

// MARK: - Shared Sports card parts (2026-09-25)

/** The one Watch button on every Sports card — hero, Live now and See all. */
@Composable
internal fun SportsWatchPill() {
    Box(
        modifier = Modifier
            .clip(CircleShape)
            .background(com.rork.guidestreamtvandroid.ui.theme.BrandOrange)
            .padding(horizontal = 14.dp, vertical = 7.dp),
    ) {
        Text("Watch ▶", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Color.White)
    }
}

/**
 * Photo layer for a Sports card: `sports_games.image_url` (the ESPN game
 * photo, or the stadium photo the server falls back to) under a dark scrim so
 * the scores stay readable. Draws nothing without a URL or on a failed load,
 * leaving the card's own fill. Place first inside a Box, sized to the card.
 */
@Composable
internal fun SportsPhotoBackdrop(url: String?, modifier: Modifier = Modifier) {
    val u = url?.takeIf { it.isNotBlank() } ?: return
    SubcomposeAsyncImage(
        model = u,
        contentDescription = null,
        modifier = modifier,
        contentScale = ContentScale.Crop,
        success = { state ->
            Box(Modifier.fillMaxSize()) {
                Image(
                    painter = state.painter,
                    contentDescription = null,
                    modifier = Modifier.fillMaxSize(),
                    contentScale = ContentScale.Crop,
                )
                Box(
                    Modifier
                        .fillMaxSize()
                        .background(
                            androidx.compose.ui.graphics.Brush.verticalGradient(
                                0f to Color(0xFF04090F).copy(alpha = 0.65f),
                                1f to Color(0xFF04090F).copy(alpha = 0.88f),
                            ),
                        ),
                )
            }
        },
    )
}

package com.rork.guidestreamtvandroid.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.guidestreamtvandroid.data.models.NewEpisodeRow
import com.rork.guidestreamtvandroid.data.models.Platform
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary

// Shared presentation for a `new_episodes` row, used by the Home rail and the
// full New Episodes screen so the two can never drift.
//
// Note on lineHeight: every Text here pins its own. AppTypography.bodyLarge
// carries lineHeight = 24.sp, and overriding only fontSize leaves the 24sp line
// box behind — that is what collapsed the attribution line to height zero in
// the inline ad chip (see claude/ad-chip-v2-aug2026.md).

/**
 * The episode line: "S3 E5" for a numbered TMDB episode, the episode's own
 * title for sourced content (YouTube, podcasts, streams) which has no
 * numbering. Same precedence the home widget's tier-2 feed uses, so the widget
 * and the app never label the same row differently.
 */
fun newEpisodeBadge(row: NewEpisodeRow): String {
    val season = row.season
    val episode = row.episode
    if (season != null && episode != null) return "S$season E$episode"
    val epTitle = row.episodeTitle
    if (!epTitle.isNullOrBlank()) return epTitle
    return "New episode"
}

/** The show line, falling back the same way the widget feed does. */
fun newEpisodeShowName(row: NewEpisodeRow): String =
    row.title?.takeIf { it.isNotBlank() }
        ?: row.episodeTitle?.takeIf { it.isNotBlank() }
        ?: row.titleId

/**
 * `thumbnail_url` is the 16:9 still that sourced content carries; `poster_url`
 * is TMDB's portrait art. Both are drawn in a 16:9 frame — a cropped poster
 * reads as an episode still, a letterboxed one does not.
 */
fun newEpisodeImageUrl(row: NewEpisodeRow): String? =
    row.thumbnailUrl?.takeIf { it.isNotBlank() } ?: row.posterUrl

/**
 * Solid brand chip. Uses the platform's own colour and its paired text colour
 * rather than tinting — several brands (Hulu, Paramount, Disney+, Max) collide
 * their background and accent, which is what made the service tile render as a
 * solid block in GUI-65.
 */
@Composable
private fun PlatformChip(raw: String?) {
    val platform = Platform.from(raw)
    val label = platform?.name ?: raw?.trim()?.uppercase().orEmpty()
    if (label.isEmpty()) return
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(4.dp))
            .background(platform?.color ?: BrandOrange)
            .padding(horizontal = 6.dp, vertical = 2.dp),
    ) {
        Text(
            text = label,
            fontSize = 10.sp,
            lineHeight = 12.sp,
            fontWeight = FontWeight.Bold,
            color = platform?.textColor ?: Color.White,
            maxLines = 1,
        )
    }
}

/** Horizontal-rail card. Fixed width so a LazyRow measures uniformly. */
@Composable
fun NewEpisodeCard(
    row: NewEpisodeRow,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val showName = newEpisodeShowName(row)
    Column(
        modifier = modifier
            .width(176.dp)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() },
    ) {
        RemoteImage(
            url = newEpisodeImageUrl(row),
            contentDescription = showName,
            cornerRadius = 10,
            placeholderText = showName,
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(16f / 9f),
        )
        Spacer(Modifier.height(6.dp))
        Text(
            text = showName,
            fontSize = 13.sp,
            lineHeight = 16.sp,
            fontWeight = FontWeight.SemiBold,
            color = TextPrimary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Spacer(Modifier.height(3.dp))
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(
                text = newEpisodeBadge(row),
                fontSize = 11.sp,
                lineHeight = 14.sp,
                color = TextSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false),
            )
            PlatformChip(row.platform)
        }
    }
}

/** Full-width row for the New Episodes screen. */
@Composable
fun NewEpisodeListRow(
    row: NewEpisodeRow,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val showName = newEpisodeShowName(row)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RemoteImage(
            url = newEpisodeImageUrl(row),
            contentDescription = showName,
            cornerRadius = 10,
            placeholderText = showName,
            modifier = Modifier
                .width(140.dp)
                .aspectRatio(16f / 9f),
        )
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = showName,
                fontSize = 15.sp,
                lineHeight = 19.sp,
                fontWeight = FontWeight.SemiBold,
                color = TextPrimary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.height(4.dp))
            Text(
                text = newEpisodeBadge(row),
                fontSize = 12.sp,
                lineHeight = 15.sp,
                color = TextSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.height(6.dp))
            PlatformChip(row.platform)
        }
    }
}

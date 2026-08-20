package com.rork.guidestreamtvandroid.ui.sports

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp

/** Neutral light fill shared by every crest plate render site. */
internal val TeamCrestPlateColor = Color.White.copy(alpha = 0.92f)

/**
 * Shared neutral light plate behind a team crest. ESPN serves crests on
 * transparent backgrounds, so a team-tinted plate makes dark-primary crests
 * (navy, black) disappear against the dark card; a near-white plate keeps
 * every crest legible regardless of the team's primary colour. The
 * abbreviation fallback badge is intentionally separate — it fills with the
 * full team colour and white text.
 */
@Composable
internal fun TeamCrestPlate(
    size: Dp,
    cornerRadius: Dp,
    modifier: Modifier = Modifier,
    content: @Composable BoxScope.() -> Unit,
) {
    Box(
        modifier = modifier
            .size(size)
            .clip(RoundedCornerShape(cornerRadius))
            .background(TeamCrestPlateColor),
        content = content,
    )
}

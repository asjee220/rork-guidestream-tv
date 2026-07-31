package com.rork.guidestreamtvandroid.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.rork.guidestreamtvandroid.ui.theme.BrandWordmark
import com.rork.guidestreamtvandroid.ui.theme.OutlineVariant
import com.rork.guidestreamtvandroid.ui.theme.SurfaceDark
import com.rork.guidestreamtvandroid.ui.theme.WordmarkSize

/** Crossfade duration for the container + hairline, in milliseconds. */
private const val TOP_BAR_FADE_MS = 200

/**
 * The single shared top bar used by Home and Sports.
 *
 * Pinned and non-collapsing: the wordmark holds identical position, size, weight
 * and colour at every scroll offset. Only two things animate — the container
 * colour (transparent at rest, opaque [SurfaceDark] once scrolled) and the
 * bottom hairline's alpha, both on the same 200ms tween so they crossfade
 * together.
 *
 * @param elevated true once the host list/column has scrolled past its threshold.
 * @param trailing trailing content rendered in the bar's [RowScope], right-aligned.
 */
@Composable
fun GsTopBar(
    elevated: Boolean,
    modifier: Modifier = Modifier,
    trailing: @Composable RowScope.() -> Unit = {},
) {
    val containerColor by animateColorAsState(
        targetValue = if (elevated) SurfaceDark else Color.Transparent,
        animationSpec = tween(durationMillis = TOP_BAR_FADE_MS),
        label = "gsTopBarContainer",
    )
    val hairlineAlpha by animateFloatAsState(
        targetValue = if (elevated) 1f else 0f,
        animationSpec = tween(durationMillis = TOP_BAR_FADE_MS),
        label = "gsTopBarHairline",
    )

    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(containerColor),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .height(56.dp)
                .padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            BrandWordmark(size = WordmarkSize.NAV)
            Spacer(Modifier.weight(1f))
            trailing()
        }
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(1.dp)
                .background(OutlineVariant.copy(alpha = OutlineVariant.alpha * hairlineAlpha)),
        )
    }
}

package com.rork.guidestreamtvandroid.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.rork.guidestreamtvandroid.ui.theme.OutlineVariant
import com.rork.guidestreamtvandroid.ui.theme.SurfaceContainer

/**
 * Material 3 tonal card modifier: opaque tonal fill (#142033) + white 13% hairline
 * outline, 10dp corners, with a soft elevation shadow. On the near-black Navy
 * background the shadow is subtle by design — the opaque tonal fill is the primary
 * depth cue, which is how Material 3 expresses elevation in dark themes.
 */
fun Modifier.glassCard(
    cornerRadius: Int = 10,
    elevation: Dp = 6.dp,
): Modifier {
    val shape = RoundedCornerShape(cornerRadius.dp)
    return this
        .shadow(elevation, shape, clip = false)
        .clip(shape)
        .background(SurfaceContainer)
        .border(1.dp, OutlineVariant, shape)
}

@Composable
fun GlassCard(
    modifier: Modifier = Modifier,
    cornerRadius: Int = 10,
    elevation: Dp = 6.dp,
    content: @Composable () -> Unit,
) {
    Box(
        modifier = modifier.glassCard(cornerRadius, elevation),
    ) {
        content()
    }
}

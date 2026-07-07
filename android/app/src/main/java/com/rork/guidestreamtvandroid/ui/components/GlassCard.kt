package com.rork.guidestreamtvandroid.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.rork.guidestreamtvandroid.ui.theme.GlassFill
import com.rork.guidestreamtvandroid.ui.theme.GlassStroke

/**
 * Glass card modifier: white 7% fill + white 10% hairline stroke, 14dp corners.
 * Mirrors iOS `.glassCard()` modifier.
 */
fun Modifier.glassCard(
    cornerRadius: Int = 14,
): Modifier = this
    .clip(RoundedCornerShape(cornerRadius.dp))
    .background(GlassFill)
    .border(1.dp, GlassStroke, RoundedCornerShape(cornerRadius.dp))

@Composable
fun GlassCard(
    modifier: Modifier = Modifier,
    cornerRadius: Int = 14,
    content: @Composable () -> Unit,
) {
    Box(
        modifier = modifier.glassCard(cornerRadius),
    ) {
        content()
    }
}

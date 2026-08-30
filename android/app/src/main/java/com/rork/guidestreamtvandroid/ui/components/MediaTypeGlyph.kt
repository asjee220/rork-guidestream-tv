package com.rork.guidestreamtvandroid.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.size
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * The movie / series glyph beside a title in the home rails (GUI-70).
 *
 * Hand-drawn rather than a Material icon on purpose: Material's `Tv` is a flat
 * panel and `LiveTv` draws signal waves, while SF Symbols has no antenna
 * television at all — three platforms could not have matched any other way.
 *
 * The twin lives in ios/Shared/MediaTypeGlyph.swift and traces the same
 * 24-unit grid, coordinate for coordinate. Change one, change the other.
 */
@Composable
fun MediaTypeGlyph(
    isTV: Boolean,
    modifier: Modifier = Modifier,
    size: Dp = 12.dp,
    color: Color = Color.White.copy(alpha = 0.62f),
) {
    Canvas(modifier = modifier.size(size)) {
        val s = kotlin.math.min(this.size.width, this.size.height) / 24f
        val stroke = Stroke(
            // 1.7 at 24 units, scaled so the shape keeps its proportions
            // instead of going spindly at 12dp.
            width = 1.7f * s,
            cap = StrokeCap.Round,
            join = StrokeJoin.Round,
        )
        val path = Path()

        if (isTV) {
            // Television with rabbit-ear antennae.
            path.addRoundRect(
                RoundRect(
                    left = 2.5f * s, top = 9f * s, right = 21.5f * s, bottom = 21f * s,
                    cornerRadius = CornerRadius(2.5f * s, 2.5f * s),
                )
            )
            path.moveTo(8f * s, 9f * s); path.lineTo(5f * s, 3.5f * s)
            path.moveTo(16f * s, 9f * s); path.lineTo(19f * s, 3.5f * s)
        } else {
            // Film strip: a body with a sprocket column down each side.
            path.addRoundRect(
                RoundRect(
                    left = 2.5f * s, top = 4.5f * s, right = 21.5f * s, bottom = 19.5f * s,
                    cornerRadius = CornerRadius(2.5f * s, 2.5f * s),
                )
            )
            for (x in listOf(7f, 17f)) {
                path.moveTo(x * s, 4.5f * s); path.lineTo(x * s, 19.5f * s)
            }
            for (y in listOf(9.5f, 14.5f)) {
                path.moveTo(2.5f * s, y * s); path.lineTo(7f * s, y * s)
                path.moveTo(17f * s, y * s); path.lineTo(21.5f * s, y * s)
            }
        }

        drawPath(path = path, color = color, style = stroke)
    }
}

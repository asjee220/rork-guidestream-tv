package com.rork.guidestreamtvandroid.ui.theme

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

/**
 * Full-screen brand background: navy base + three soft radial glows
 * (blue, orange, light-blue) for a consistent "themed depth" effect.
 * Mirrors iOS BrandBackground.swift.
 */
@Composable
fun BrandBackground(
    modifier: Modifier = Modifier
) {
    Box(modifier = modifier.fillMaxSize()) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val w = size.width
            val h = size.height

            // Blue glow — top-left
            drawCircle(
                brush = Brush.radial(
                    colors = listOf(BrandBlue.copy(alpha = 0.24f), Color.Transparent),
                    center = Offset(w * 0.12f, h * 0.28f),
                    radius = w * 0.6f
                ),
                center = Offset(w * 0.12f, h * 0.28f),
                radius = w * 0.6f
            )

            // Orange glow — bottom-right
            drawCircle(
                brush = Brush.radial(
                    colors = listOf(BrandOrange.copy(alpha = 0.15f), Color.Transparent),
                    center = Offset(w * 0.72f, h * 0.78f),
                    radius = w * 0.5f
                ),
                center = Offset(w * 0.72f, h * 0.78f),
                radius = w * 0.5f
            )

            // Light-blue glow — center
            drawCircle(
                brush = Brush.radial(
                    colors = listOf(LightBlue.copy(alpha = 0.08f), Color.Transparent),
                    center = Offset(w * 0.45f, h * 0.4f),
                    radius = w * 0.4f
                ),
                center = Offset(w * 0.45f, h * 0.4f),
                radius = w * 0.4f
            )
        }
    }
}

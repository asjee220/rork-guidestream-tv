package com.rork.guidestreamtvandroid.ui.theme

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Adaptive width classes shared by every surface that needs to reflow for
 * tablets and large windows. Breakpoints match the iOS port exactly:
 * below 600dp is phone-like, 600..<840 is a small tablet or split view,
 * and 840+ is a full tablet window.
 */
enum class GSWidthClass {
    Compact,
    Medium,
    Expanded;

    companion object {
        /** Maps a dp width to its width class. */
        fun from(widthDp: Int): GSWidthClass = when {
            widthDp < 600 -> Compact
            widthDp < 840 -> Medium
            else -> Expanded
        }

        /** Horizontal content clamp; null means span the full width (compact). */
        fun contentMaxWidth(widthClass: GSWidthClass): Dp? = when (widthClass) {
            Compact -> null
            Medium -> 720.dp
            Expanded -> 1040.dp
        }

        /** Poster grid column count for grids that opt into adaptive columns. */
        fun posterColumns(widthClass: GSWidthClass): Int = when (widthClass) {
            Compact -> 3
            Medium -> 5
            Expanded -> 7
        }
    }
}

/** Reads the current window width and maps it to a [GSWidthClass]. */
@Composable
fun rememberWidthClass(): GSWidthClass {
    val configuration = LocalConfiguration.current
    return remember(configuration.screenWidthDp) {
        GSWidthClass.from(configuration.screenWidthDp)
    }
}

/** Vertical drawing bleed kept outside the clip (shadows, glows). */
private val ClipBleed = 48.dp

/**
 * Clamps the modified content to [GSWidthClass.contentMaxWidth] and centres
 * it horizontally, so wide-window content forms even gutters instead of
 * stretching edge to edge. The clamped content is clipped to that frame
 * horizontally so full-bleed rails can no longer draw past the clamp's
 * trailing edge — with vertical bleed so shadows and glows keep drawing
 * past the frame. A no-op in compact so phone layouts are untouched.
 */
fun Modifier.gsContentWidth(widthClass: GSWidthClass): Modifier {
    val maxWidth = GSWidthClass.contentMaxWidth(widthClass) ?: return this
    return this
        .fillMaxWidth()
        .wrapContentWidth(align = Alignment.CenterHorizontally)
        .widthIn(max = maxWidth)
        .drawWithContent {
            val bleedPx = ClipBleed.toPx()
            clipRect(
                left = 0f,
                top = -bleedPx,
                right = size.width,
                bottom = size.height + bleedPx,
            ) {
                // clipRect's block is a plain DrawScope, so drawContent needs
                // the outer ContentDrawScope receiver explicitly.
                this@drawWithContent.drawContent()
            }
        }
}

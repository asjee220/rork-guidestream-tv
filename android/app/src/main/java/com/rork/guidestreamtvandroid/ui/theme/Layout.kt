package com.rork.guidestreamtvandroid.ui.theme

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
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

/** Horizontal padding for home section containers. Full-width on tablets
 * (expanded) so the content stretches edge-to-edge like Sports; phones and
 * split-view windows keep their existing 12dp gutters. */
val GSWidthClass.homeHorizontalPadding: Dp
    get() = when (this) {
        GSWidthClass.Expanded -> 0.dp
        else -> 12.dp
    }

/** Horizontal padding for the home search bar. Full-width on tablets, 16dp on phones. */
val GSWidthClass.homeSearchHorizontalPadding: Dp
    get() = when (this) {
        GSWidthClass.Expanded -> 0.dp
        else -> 16.dp
    }



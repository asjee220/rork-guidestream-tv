package com.rork.guidestreamtvandroid.ui.theme

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.union
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp

/**
 * Single source of truth for bottom safe-area clearance. Every screen routes its
 * bottom spacing through here so content clears both the floating tab bar (where
 * visible) and the real system navigation bar inset — which differs between
 * gesture navigation (~16–24dp) and three-button navigation (~48dp).
 */

/** Height of the floating pill in [com.rork.guidestreamtvandroid.ui.components.FloatingTabBar]. */
val FloatingTabBarHeight: Dp = 64.dp

/** Bottom gap the floating tab bar reserves below the pill. */
val TabBarBottomGap: Dp = 4.dp

/** The real bottom system navigation bar inset as a [Dp]. */
@Composable
fun systemBottomInset(): Dp =
    WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()

/**
 * Total bottom clearance for screens that show the floating tab bar: pill height +
 * gap + [extra] breathing room + the real system inset.
 */
@Composable
fun tabBarBottomInset(extra: Dp = 12.dp): Dp =
    FloatingTabBarHeight + TabBarBottomGap + extra + systemBottomInset()

/**
 * Spacer that reserves the correct bottom clearance. Pass [withTabBar] = true on
 * screens where the floating tab bar is visible (Home, Sports, Profile), false on
 * screens/overlays where it is hidden (Reels, detail screens).
 */
@Composable
fun BottomSafeSpacer(withTabBar: Boolean) {
    val height = if (withTabBar) tabBarBottomInset() else systemBottomInset()
    Spacer(Modifier.height(height))
}

/**
 * Top-side counterpart to [BottomSafeSpacer], for modal bottom sheets. Union
 * of the status bar and the display cutout restricted to the top side only,
 * passed to every ModalBottomSheet via `contentWindowInsets` so no sheet
 * surface or content can draw beneath the status bar or a punch-hole camera
 * at full expansion — in portrait or landscape. Bottom clearance stays the
 * responsibility of each sheet's own navigationBarsPadding.
 */
@Composable
fun sheetTopInset(): WindowInsets =
    WindowInsets.statusBars.union(WindowInsets.displayCutout).only(WindowInsetsSides.Top)

/**
 * Horizontal-only safe-area padding for edge-anchored content over full-bleed
 * surfaces (hero backdrops, immersive players). Unions the display cutout with
 * the navigation bars — the same idiom Reels uses for its landscape overlay —
 * then keeps ONLY the horizontal axis, so call sites never pick up a vertical
 * inset that would double against statusBarsPadding or BottomSafeSpacer.
 * Resolves to zero on both axes on cutout-free devices and in portrait.
 */
@Composable
fun horizontalCutoutInsets(): PaddingValues {
    val sides = WindowInsets.displayCutout.union(WindowInsets.navigationBars).asPaddingValues()
    return PaddingValues(
        start = sides.calculateLeftPadding(LayoutDirection.Ltr),
        end = sides.calculateRightPadding(LayoutDirection.Ltr),
    )
}

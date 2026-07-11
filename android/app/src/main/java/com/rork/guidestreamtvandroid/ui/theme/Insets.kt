package com.rork.guidestreamtvandroid.ui.theme

import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
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

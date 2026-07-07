package com.rork.guidestreamtvandroid.ui.navigation

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.rork.guidestreamtvandroid.ui.components.FloatingTabBar
import com.rork.guidestreamtvandroid.ui.theme.BrandBackground
import com.rork.guidestreamtvandroid.ui.screens.HomeScreen
import com.rork.guidestreamtvandroid.ui.sports.SportsScreen
import com.rork.guidestreamtvandroid.ui.profile.ProfileScreen
import com.rork.guidestreamtvandroid.ui.reels.ReelsScreen

/**
 * Root main screen — floating tab bar + tab content.
 * Mirrors iOS ContentView.mainApp.
 */
@Composable
fun MainScreen(
    router: AppRouter,
    onOpenAsk: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var selectedTab by remember { mutableStateOf(AppTab.HOME) }
    var tabBarVisible by remember { mutableStateOf(true) }
    var tabBeforeReels by remember { mutableStateOf(AppTab.HOME) }

    Box(modifier = modifier.fillMaxSize()) {
        BrandBackground()

        // Tab content
        Box(
            modifier = Modifier
                .fillMaxSize()

            contentAlignment = Alignment.TopStart,
        ) {
            when (selectedTab) {
                AppTab.HOME -> HomeScreen(
                    onOpenTitle = { route -> router.showTitle(route) },
                )
                AppTab.SPORTS -> SportsScreen()
                AppTab.ASK -> { /* Intercepted — opens sheet */ }
                AppTab.REELS -> ReelsScreen(
                    onDismiss = {
                        val target = if (tabBeforeReels == AppTab.REELS) AppTab.HOME else tabBeforeReels
                        selectedTab = target
                    },
                )
                AppTab.PROFILE -> ProfileScreen()
            }
        }

        // Floating tab bar
        AnimatedVisibility(
            visible = tabBarVisible,
            enter = slideInVertically { it } + fadeIn(),
            exit = slideOutVertically { it } + fadeOut(),
            modifier = Modifier.align(Alignment.BottomCenter),
        ) {
            FloatingTabBar(
                selected = selectedTab,
                onTabSelected = { tab ->
                    if (tab == AppTab.ASK) {
                        onOpenAsk()
                    } else {
                        if (selectedTab != AppTab.REELS && tab == AppTab.REELS) {
                            tabBeforeReels = selectedTab
                        }
                        selectedTab = tab
                        tabBarVisible = tab != AppTab.REELS
                    }
                },
            )
        }
    }
}

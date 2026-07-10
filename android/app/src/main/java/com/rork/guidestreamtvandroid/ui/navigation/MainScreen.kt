package com.rork.guidestreamtvandroid.ui.navigation

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.rork.guidestreamtvandroid.data.models.SourceKind
import com.rork.guidestreamtvandroid.ui.ask.AskStreamSheet
import com.rork.guidestreamtvandroid.ui.components.FloatingTabBar
import com.rork.guidestreamtvandroid.ui.detail.CreatorDetailScreen
import com.rork.guidestreamtvandroid.ui.detail.ShowDetailScreen
import com.rork.guidestreamtvandroid.ui.reels.ReelsScreen
import com.rork.guidestreamtvandroid.ui.screens.HomeScreen
import com.rork.guidestreamtvandroid.ui.screens.PopularOnServiceCategoriesScreen
import com.rork.guidestreamtvandroid.ui.search.SearchScreen
import com.rork.guidestreamtvandroid.ui.sports.SportsGameDetailScreen
import com.rork.guidestreamtvandroid.ui.sports.SportsScreen
import com.rork.guidestreamtvandroid.ui.profile.ProfileScreen
import com.rork.guidestreamtvandroid.ui.theme.BrandBackground
import com.rork.guidestreamtvandroid.ui.theme.Navy

/** Target for the "Popular on {service}" full-screen category browser overlay. */
data class PopularCategoriesTarget(
    val serviceId: String,
    val providerId: Int,
)

/**
 * Root main screen — floating tab bar + tab content + detail overlays.
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

    // Overlay state — mirrors iOS sheet/fullScreenCover state in ContentView + HomeView
    var showSearch by remember { mutableStateOf(false) }
    var showAskSheet by remember { mutableStateOf(false) }
    var showDetail by remember { mutableStateOf<PendingTitleRoute?>(null) }
    var showCreatorDetail by remember { mutableStateOf<String?>(null) }
    var selectedGame by remember { mutableStateOf<com.rork.guidestreamtvandroid.data.models.SportsGame?>(null) }
    var showPopularCategories by remember { mutableStateOf<PopularCategoriesTarget?>(null) }

    // Consume pending title route from AppRouter (deep-link / push buffer)
    val pendingRoute = router.pendingTitleRoute
    LaunchedEffect(pendingRoute) {
        val route = pendingRoute ?: return@LaunchedEffect
        router.consumePendingTitleRoute()
        // Route to correct detail screen — mirrors iOS openPendingTitleRoute
        val kind = SourceKind.from(route.titleId)
        if (kind.isNonTMDB) {
            showCreatorDetail = route.titleId
        } else {
            showDetail = route
        }
    }

    Box(modifier = modifier.fillMaxSize()) {
        BrandBackground()

        // Tab content
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.TopStart,
        ) {
            when (selectedTab) {
                AppTab.HOME -> HomeScreen(
                    onOpenTitle = { route ->
                        val kind = SourceKind.from(route.titleId)
                        if (kind.isNonTMDB) {
                            showCreatorDetail = route.titleId
                        } else {
                            showDetail = route
                        }
                    },
                    onOpenSearch = { showSearch = true },
                    onSeeAllPopular = { serviceId, providerId ->
                        showPopularCategories = PopularCategoriesTarget(serviceId, providerId)
                    },
                )
                AppTab.SPORTS -> SportsScreen(
                    onOpenGame = { game -> selectedGame = game },
                )
                AppTab.ASK -> { /* Intercepted — opens sheet via onOpenAsk */ }
                AppTab.REELS -> ReelsScreen(
                    onDismiss = {
                        val target = if (tabBeforeReels == AppTab.REELS) AppTab.HOME else tabBeforeReels
                        selectedTab = target
                        tabBarVisible = true
                    },
                )
                AppTab.PROFILE -> ProfileScreen()
            }
        }

        // Full-screen overlay open flag — hides the floating tab bar behind opaque covers
        val overlayOpen = showDetail != null || showCreatorDetail != null || showSearch || selectedGame != null || showPopularCategories != null

        // Show detail (full-screen cover equivalent)
        showDetail?.let { route ->
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Navy)
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { },
            ) {
                ShowDetailScreen(
                    titleId = route.titleId,
                    titleName = route.titleName ?: "Show",
                    isTV = route.isTv,
                    onBack = { showDetail = null },
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }

        // Creator detail (sheet equivalent)
        showCreatorDetail?.let { titleId ->
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Navy)
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { },
            ) {
                CreatorDetailScreen(
                    titleId = titleId,
                    onBack = { showCreatorDetail = null },
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }

        // Search (full-screen cover equivalent)
        if (showSearch) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Navy)
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { },
            ) {
                SearchScreen(
                    onClose = { showSearch = false },
                    onOpenTitle = { route ->
                        showSearch = false
                        val kind = SourceKind.from(route.titleId)
                        if (kind.isNonTMDB) {
                            showCreatorDetail = route.titleId
                        } else {
                            showDetail = route
                        }
                    },
                    onOpenCreator = { titleId ->
                        showSearch = false
                        showCreatorDetail = titleId
                    },
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }

        // Sports game detail
        selectedGame?.let { game ->
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Navy)
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { },
            ) {
                SportsGameDetailScreen(
                    game = game,
                    onBack = { selectedGame = null },
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }

        // Popular on {service} category browser (full-screen cover equivalent)
        showPopularCategories?.let { target ->
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Navy)
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { },
            ) {
                PopularOnServiceCategoriesScreen(
                    target = target,
                    onBack = { showPopularCategories = null },
                    onOpenTitle = { route ->
                        showPopularCategories = null
                        showDetail = route
                    },
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }

        // Ask Stream sheet
        AskStreamSheet(
            isOpen = showAskSheet,
            onClose = { showAskSheet = false },
        )

        // Floating tab bar
        AnimatedVisibility(
            visible = tabBarVisible && !overlayOpen,
            enter = slideInVertically { it } + fadeIn(),
            exit = slideOutVertically { it } + fadeOut(),
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .navigationBarsPadding(),
        ) {
            FloatingTabBar(
                selected = selectedTab,
                onTabSelected = { tab ->
                    if (tab == AppTab.ASK) {
                        // Intercept ask tab — open sheet instead of switching
                        showAskSheet = true
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

package com.rork.guidestreamtvandroid.ui.navigation

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow

/**
 * Pending deep-link route for a title (show, movie, or creator).
 * Mirrors iOS PendingTitleRoute.
 */
data class PendingTitleRoute(
    val titleId: String,
    val titleName: String? = null,
    val posterUrl: String? = null,
    val isTv: Boolean = true,
)

/**
 * Global router that buffers deep-link and push-notification routes.
 * Mirrors iOS AppRouter — switches tabs and buffers title routes
 * so they're consumed by HomeScreen when it appears.
 */
class AppRouter {
    var selectedTab: AppTab by mutableStateOf(AppTab.HOME)
        private set

    var pendingTitleRoute: PendingTitleRoute? by mutableStateOf(null)
        private set

    /** One-shot event flow for title navigation requests. */
    private val _titleNavigation = MutableSharedFlow<PendingTitleRoute>(extraBufferCapacity = 4)
    val titleNavigation: SharedFlow<PendingTitleRoute> = _titleNavigation

    fun selectTab(tab: AppTab) {
        selectedTab = tab
    }

    fun showTitle(route: PendingTitleRoute) {
        selectedTab = AppTab.HOME
        pendingTitleRoute = route
    }

    fun consumePendingTitleRoute() {
        pendingTitleRoute = null
    }

    companion object {
        @Volatile private var instance: AppRouter? = null
        fun get(): AppRouter =
            instance ?: synchronized(this) {
                instance ?: AppRouter().also { instance = it }
            }
    }
}

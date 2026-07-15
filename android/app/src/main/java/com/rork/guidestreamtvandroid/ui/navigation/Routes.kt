package com.rork.guidestreamtvandroid.ui.navigation

/**
 * All navigation routes in the app.
 * Mirrors iOS HomeRoute + AppRouter destinations.
 */
object Routes {
    const val MAIN = "main"

    // Onboarding
    const val ONBOARDING = "onboarding"

    // Home sub-routes (pushed onto home stack)
    const val SEARCH = "search"
    const val SHOW_DETAIL = "show_detail/{titleId}/{title}/{isTv}"
    const val CREATOR_DETAIL = "creator_detail/{titleId}"
    const val WATCH_LIST_SHEET = "watch_list_sheet"
    const val NEW_EPISODES = "new_episodes"
    const val WHATS_NEW_TODAY = "whats_new_today"
    const val TOP_PICKS = "top_picks"
    const val TRENDING = "trending"
    const val LEAVING_SOON = "leaving_soon"
    const val CONTINUE_WATCHING = "continue_watching"
    const val WIDGET_SETUP = "widget_setup"

    // Profile sub-routes
    const val ACCOUNT = "account"
    const val CONNECTED_SERVICES = "connected_services"
    const val NOTIFICATIONS_SETTINGS = "notifications_settings"
    const val DEVICES = "devices"
    const val HELP = "help"
    const val PROFILES = "profiles"

    // Sports
    const val SPORTS_DETAIL = "sports_detail/{gameId}"

    // Reels
    const val REELS = "reels"

    fun showDetail(titleId: String, title: String, isTv: Boolean): String =
        "show_detail/$titleId/${java.net.URLEncoder.encode(title, "UTF-8")}/$isTv"

    fun creatorDetail(titleId: String): String = "creator_detail/$titleId"
    fun sportsDetail(gameId: String): String = "sports_detail/$gameId"
}

/**
 * App tab enum — mirrors iOS AppTab.
 */
enum class AppTab(val title: String, val icon: String) {
    HOME("Home", "home"),
    SPORTS("Sports", "sports"),
    ASK("Ask", "sparkles"),
    REELS("Reels", "reels"),
    PROFILE("Profile", "profile"),
}

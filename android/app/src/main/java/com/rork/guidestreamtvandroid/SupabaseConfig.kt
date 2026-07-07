package com.rork.guidestreamtvandroid

/**
 * App-wide configuration constants.
 * Supabase URL + anon key match the iOS app's SupabaseConfig.
 */
object SupabaseConfig {
    const val URL = "https://qwxxkubkbanridcqsqjo.supabase.co"
    const val ANON_KEY = "sb_publishable_b4OuwPfvEivzdiLNXgxv1g_3iGLhSE5"
}

object AppConfig {
    // TMDB
    const val TMDB_BASE_URL = "https://api.themoviedb.org/3"
    const val TMDB_IMAGE_BASE = "https://image.tmdb.org/t/p/"

    // Deep link scheme
    const val DEEP_LINK_SCHEME = "guidestream"

    // AdMob test ad unit IDs
    const val ADMOB_APP_ID = "ca-app-pub-3940256099942544~1458002511"
    const val ADMOB_NATIVE_AD_UNIT_ID = "ca-app-pub-3940256099942544/2247696110"
    const val ADMOB_INTERSTITIAL_AD_UNIT_ID = "ca-app-pub-3940256099942544/1033173712"
}

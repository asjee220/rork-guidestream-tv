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

    // Google Sign-In — Web (server) OAuth client ID configured as the Google
    // provider client ID in the Supabase dashboard. Credential Manager passes
    // this as `serverClientId` so the returned ID token is minted for the same
    // audience Supabase validates against. This is NOT the Android client ID.
    const val GOOGLE_WEB_CLIENT_ID =
        "740276432473-bk96lbtrbujhihq5dhhf2infrvbdddlt.apps.googleusercontent.com"

    // Bundled AdMob ad units — injected from env vars at release build time
    // (see build.gradle.kts buildConfigFields), falling back to Google's test
    // units so debug builds keep serving ads. The Supabase `ads_android`
    // remote-config row can override these without a new build; AdUnitResolver
    // validates any remote unit's publisher against the manifest app id.
    val ADMOB_NATIVE_AD_UNIT_ID: String = BuildConfig.ADMOB_NATIVE_AD_UNIT_ID
    val ADMOB_BANNER_AD_UNIT_ID: String = BuildConfig.ADMOB_BANNER_AD_UNIT_ID
    val ADMOB_INTERSTITIAL_AD_UNIT_ID: String = BuildConfig.ADMOB_INTERSTITIAL_AD_UNIT_ID
}

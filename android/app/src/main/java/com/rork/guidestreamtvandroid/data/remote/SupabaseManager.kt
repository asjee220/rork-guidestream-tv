package com.rork.guidestreamtvandroid.data.remote

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest

/**
 * Singleton Supabase client — mirrors iOS SupabaseManager.swift.
 * Uses the same URL + anon key as the iOS app.
 */
object SupabaseManager {
    private const val SUPABASE_URL = "https://qwxxkubkbanridcqsqjo.supabase.co"
    private const val SUPABASE_ANON_KEY = "sb_publishable_b4OuwPfvEivzdiLNXgxv1g_3iGLhSE5"

    val client: SupabaseClient = createSupabaseClient(
        supabaseUrl = SUPABASE_URL,
        supabaseKey = SUPABASE_ANON_KEY,
    ) {
        install(Auth) {
            // Deep-link redirect target for OAuth (Google) sign-in. Produces the
            // redirect URL "guidestream://auth-callback", matching the scheme
            // registered in AndroidManifest.xml and the password-reset redirect.
            scheme = "guidestream"
            host = "auth-callback"
        }
        install(Postgrest)
    }
}

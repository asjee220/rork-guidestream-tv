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
        install(Auth)
        install(Postgrest)
    }
}

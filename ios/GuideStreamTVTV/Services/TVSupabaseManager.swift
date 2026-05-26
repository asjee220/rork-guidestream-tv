//
//  TVSupabaseManager.swift
//  GuideStreamTVTV
//
//  Thin wrapper around the Supabase client so the tvOS target talks to
//  the **same** project as the iOS app. The schema (user_streams,
//  title_likes, etc.) is identical — the tvOS app just reuses it.
//

import Foundation
import Supabase

nonisolated enum TVSupabaseConfig {
    static let url: String = "https://qwxxkubkbanridcqsqjo.supabase.co"
    static let anonKey: String = "sb_publishable_b4OuwPfvEivzdiLNXgxv1g_3iGLhSE5"
}

final class TVSupabaseManager: @unchecked Sendable {
    static let shared = TVSupabaseManager()

    let client: SupabaseClient

    private init() {
        guard let url = URL(string: TVSupabaseConfig.url) else {
            fatalError("Invalid Supabase URL")
        }
        self.client = SupabaseClient(supabaseURL: url, supabaseKey: TVSupabaseConfig.anonKey)
    }
}

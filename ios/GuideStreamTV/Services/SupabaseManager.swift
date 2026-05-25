//
//  SupabaseManager.swift
//  GuideStreamTV
//

import Foundation
import Supabase

enum SupabaseConfig {
    static let url: String = "https://qwxxkubkbanridcqsqjo.supabase.co"
    static let anonKey: String = "sb_publishable_b4OuwPfvEivzdiLNXgxv1g_3iGLhSE5"
}

final class SupabaseManager {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    private init() {
        guard let url = URL(string: SupabaseConfig.url) else {
            fatalError("Invalid Supabase URL")
        }
        self.client = SupabaseClient(supabaseURL: url, supabaseKey: SupabaseConfig.anonKey)
    }
}

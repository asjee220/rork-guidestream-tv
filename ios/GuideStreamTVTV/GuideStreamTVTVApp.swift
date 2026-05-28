//
//  GuideStreamTVTVApp.swift
//  GuideStreamTVTV
//
//  Apple TV companion to GuideStream. Shares the same Supabase project
//  as the phone app — sign in with the same Apple ID and your watch
//  list syncs both ways.
//

import SwiftUI
import Supabase

@main
struct GuideStreamTVTVApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    guard url.scheme == "guidestream" else { return }
                    Task {
                        do {
                            try await SupabaseManager.shared.client.auth.session(from: url)
                            print("[Auth] tvOS onOpenURL handled: \(url)")
                        } catch {
                            print("[Auth] tvOS onOpenURL failed: \(error.localizedDescription)")
                        }
                    }
                }
        }
    }
}

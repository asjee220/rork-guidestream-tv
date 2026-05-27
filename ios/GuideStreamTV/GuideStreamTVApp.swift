//
//  GuideStreamTVApp.swift
//  GuideStreamTV
//

import SwiftUI
import Supabase

@main
struct GuideStreamTVApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    guard url.scheme == "guidestream" else { return }
                    Task {
                        do {
                            try await SupabaseManager.shared.client.auth.session(from: url)
                            print("[Auth] SwiftUI onOpenURL handled: \(url)")
                        } catch {
                            print("[Auth] SwiftUI onOpenURL failed: \(error.localizedDescription)")
                        }
                    }
                }
        }
    }
}

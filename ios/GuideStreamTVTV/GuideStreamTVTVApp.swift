//
//  GuideStreamTVTVApp.swift
//  GuideStreamTVTV
//
//  Apple TV companion to GuideStream. Shares the same Supabase project
//  as the phone app — sign in with the same Apple ID and your watch
//  list syncs both ways.
//

import SwiftUI

@main
struct GuideStreamTVTVApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

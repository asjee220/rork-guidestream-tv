//
//  GuideStreamTVApp.swift
//  GuideStreamTV
//

import SwiftUI

@main
struct GuideStreamTVApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

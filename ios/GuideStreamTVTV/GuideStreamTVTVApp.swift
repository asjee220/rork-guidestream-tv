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
import UIKit

@main
struct GuideStreamTVTVApp: App {
    @UIApplicationDelegateAdaptor(TVAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                // provider_brand_map carries every service's display name,
                // aliases and TMDB logo. The only refresh call in the repo
                // sits in HomeView.swift — the stale iOS mirror this target
                // never renders — so on Apple TV the map has always been
                // empty: Platform.from fell through to its twelve-entry
                // local catalogue and every logo lookup returned nil.
                .task {
                    await TVProviderBrandMapService.shared.refresh()
                    // Also on every launch, not just at sign-in: a session
                    // restored from the keychain never runs the sign-in path.
                    await TVAuthViewModel.shared.loadSelectedServices()
                    TVTrackingAuthorization.requestIfNeeded()
                }
                // Guideline 5.1.2(i): App Privacy in App Store Connect is one
                // record shared by both platforms, and the phone app declares
                // Device ID used for tracking, so the tvOS binary has to
                // present the ATT alert as well. TVTrackingAuthorization has
                // the full reasoning — and the conditions for deleting it.
                // Both call sites are needed: `.task` can run before the
                // scene is active, and `onChange` does not fire if the scene
                // was already active when this view appeared.
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    TVTrackingAuthorization.requestIfNeeded()
                }
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

//
//  ContentView.swift
//  GuideStreamTVTV
//
//  Root router. Restores the persisted Supabase session on launch and
//  routes between the sign-in landing and the main tab shell. The launch
//  splash sits over the gradient backdrop so the cold-launch flash
//  matches the rest of the app instead of going system white.
//

import SwiftUI

struct ContentView: View {
    @State private var auth = TVAuthViewModel.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasRestored: Bool = false

    var body: some View {
        Group {
            if !hasRestored {
                splash
            } else if auth.isSignedIn {
                TVMainView(onSignOut: { /* state flips via auth */ })
                    .transition(.opacity)
            } else {
                TVSignInView(onContinue: { /* state flips via auth */ })
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: auth.isSignedIn)
        .animation(.easeInOut(duration: 0.35), value: hasRestored)
        .task {
            await auth.restoreSession()
            hasRestored = true
            TVSelfName.shared.refresh()
            TVPlayCommandListener.shared.start()
        }
        .onChange(of: auth.isSignedIn) { _, _ in
            // Restart the listener with the updated Supabase user id
            // when the user signs in or out.
            TVPlayCommandListener.shared.stop()
            TVPlayCommandListener.shared.start()
        }
        .onChange(of: scenePhase) { _, phase in
            // The only trigger used to be cold launch. tvOS suspends the app
            // whenever the viewer goes to the home screen or opens Netflix,
            // and the realtime socket dies with it — so the TV came back
            // looking open and listening while it was subscribed to nothing.
            guard phase == .active else { return }
            TVPlayCommandListener.shared.wake()
            // The user can rename the TV in Settings at any time, so re-ask
            // rather than trusting the cache forever.
            TVSelfName.shared.refresh()
        }
    }

    private var splash: some View {
        ZStack {
            TVTheme.backgroundGradient
            VStack(spacing: 40) {
                TVBrandWordmark(wordmarkSize: .hero)
                    .shadow(color: TVTheme.orange.opacity(0.5), radius: 40)
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.6)
            }
        }
    }
}

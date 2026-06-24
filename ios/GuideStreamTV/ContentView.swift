//
//  ContentView.swift
//  GuideStreamTV
//

import SwiftUI

struct ContentView: View {
    @State private var selection: AppTab = .home
    @State private var router = AppRouter()
    @State private var askSheetOpen: Bool = false
    @State private var searchSelectedResult: TMDBResult? = nil
    @State private var previousTab: AppTab = .home
    /// Tab the user was on right before opening Reels. Used to dismiss the
    /// reels feed (chevron tap or swipe-down) back to where they came from.
    @State private var tabBeforeReels: AppTab = .home
    @State private var didRestoreSession: Bool = false
    @State private var auth = AuthViewModel.shared
    @State private var tabBarVisibility = TabBarVisibility()

    var body: some View {
        ZStack {
            if auth.isSignedIn && auth.hasCompletedOnboarding {
                mainApp
                    .transition(.opacity)
            } else if didRestoreSession {
                OnboardingFlow(
                    startStep: auth.isSignedIn ? 1 : 0,
                    onFinish: {
                        auth.completeOnboarding()
                    }
                )
                .transition(.opacity)
            } else {
                BrandBackground()
            }
        }
        .animation(.easeOut(duration: 0.3), value: auth.hasCompletedOnboarding)
        .animation(.easeOut(duration: 0.3), value: auth.isSignedIn)
        .environment(\.tabBarVisibility, tabBarVisibility)
        .environment(router)
        .preferredColorScheme(.dark)
        // Clamp Dynamic Type so extreme accessibility sizes don't break dense layouts.
        // Users still get meaningful scaling from .xSmall through .accessibility2.
        .dynamicTypeSize(.xSmall ... .accessibility2)
        .task {
            await auth.restoreSession()
            didRestoreSession = true

            // Push whatever watchlist / new-episode counts we have right now
            // so the widget has data immediately — before the home screen
            // finishes its network round-trips.
            WidgetDataService.shared.pushCounts(
                watchlistCount: StreamsViewModel.shared.userStreams.count,
                newEpisodeCount: StreamsViewModel.shared.newEpisodes.count
            )

            // Capture a session_started event for every install — signed-in
            // or guest. This is the first row that should appear in Supabase
            // for any new device.
            WatchIntentLogger.shared.log(
                eventType: .sessionStarted,
                metadata: [
                    "first_launch": DeviceIdentity.shared.isFirstLaunch,
                    "is_authenticated": auth.isAuthenticated,
                    "is_guest": auth.isGuest,
                    "onboarding_complete": auth.hasCompletedOnboarding
                ]
            )

            // Upsert the single device_sessions row for this install so we
            // always have a guest "profile" in Supabase — even users who
            // never sign in get one row that updates with last_seen_at and
            // their current selections.
            DeviceSessionService.shared.incrementSessionAndUpsert()

            // Warm up the reels feed in the background so the tab opens instantly
            // when the user first taps it. Network calls and trailer-key lookups
            // would otherwise add a 2–3s spinner on first reveal.
            Task.detached(priority: .userInitiated) {
                await ReelsViewModel.shared.loadIfNeeded()
            }
        }
    }

    private var mainApp: some View {
        ZStack(alignment: .bottom) {
            BrandBackground()

            Group {
                switch selection {
                case .home: HomeView(onOpenAgent: openAskSheet)
                case .sports: SportsView()
                case .ask: AskStreamView()
                case .reels: ReelsScreen(onDismiss: dismissReels)
                case .profile: ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)

            FloatingTabBar(selection: $selection)
                .offset(y: tabBarVisibility.isVisible ? 0 : 140)
                .opacity(tabBarVisibility.isVisible ? 1 : 0)
                .allowsHitTesting(tabBarVisibility.isVisible)
                .onChange(of: selection) { oldValue, newValue in
                    if newValue == .ask {
                        // Intercept ask tab — open sheet instead
                        selection = oldValue == .ask ? previousTab : oldValue
                        openAskSheet()
                    } else {
                        // Remember the tab the user came from before entering Reels so the
                        // dismiss chevron/swipe can return them there.
                        if newValue == .reels && oldValue != .reels {
                            tabBeforeReels = oldValue
                        }
                        previousTab = newValue
                        if newValue == .reels {
                            // Reels is a full-screen consumption surface — hide the floating tab bar.
                            tabBarVisibility.hide()
                        } else {
                            tabBarVisibility.reset()
                        }
                    }
                }
                .onChange(of: router.selectedTab) { _, newTab in
                    selection = newTab
                }

            AskStreamSheet(isOpen: askSheetOpen, onClose: { askSheetOpen = false }, onSelectResult: { searchSelectedResult = $0 })
                .ignoresSafeArea()
        }
        .fullScreenCover(item: $searchSelectedResult) { result in
            ShowDetailScreen(
                titleId: String(result.id),
                title: result.displayName,
                posterUrl: result.posterUrl,
                backdropUrl: result.backdropUrl,
                isTV: result.isTV,
                onBack: { searchSelectedResult = nil }
            )
        }
    }

    private func openAskSheet() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            askSheetOpen = true
        }
    }

    /// Returns the user to whichever tab they were on before opening Reels.
    /// Triggered by the chevron button or the swipe-down dismiss gesture
    /// inside `ReelsScreen`.
    private func dismissReels() {
        let target = tabBeforeReels == .reels ? .home : tabBeforeReels
        withAnimation(.easeOut(duration: 0.28)) {
            selection = target
        }
    }
}

#Preview {
    ContentView()
}

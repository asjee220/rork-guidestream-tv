//
//  TVMainView.swift
//  GuideStreamTVTV
//
//  Side-menu shell. The selected screen fills the frame while a leading
//  overlay menu (TVSideMenu) handles navigation — content never shifts or
//  resizes when the menu expands. The menu is collapsed at rest and opens
//  only on a left move issued from the content's leading edge. Search and
//  Reels are wired to placeholder screens so the menu structure matches the
//  mockups; their full screens can be filled in later.
//

import SwiftUI

struct TVMainView: View {
    let onSignOut: () -> Void

    @State private var selection: TVSideMenuItem = .home
    @State private var menuIsOpen: Bool = false

    var body: some View {
        ZStack(alignment: .leading) {
            screen(for: selection)
                .focusSection()
                .onMoveCommand { direction in
                    // The only thing that opens the menu: a deliberate left
                    // move command issued from the content's leading edge —
                    // the focus engine found nothing further left, so the
                    // command falls through to here.
                    if direction == .left, !menuIsOpen {
                        menuIsOpen = true
                    }
                }

            // Leading-to-trailing scrim between the open menu and content.
            if menuIsOpen {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.60),
                        Color.black.opacity(0.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            TVSideMenu(selection: $selection, isOpen: $menuIsOpen)
        }
        .animation(.easeOut(duration: 0.25), value: menuIsOpen)
        .background(TVTheme.backgroundGradient.ignoresSafeArea())
        .onChange(of: selection) { _, _ in
            // The menu is closed on every screen entry, including returns
            // from sheets and full-screen covers.
            menuIsOpen = false
        }
        .onPreferenceChange(TVHeroSideMenuRequestKey.self) { count in
            // A left move at the hero's first item falls through to the
            // side menu rather than being swallowed by the hero.
            if count > 0, !menuIsOpen {
                menuIsOpen = true
            }
        }
    }

    @ViewBuilder
    private func screen(for item: TVSideMenuItem) -> some View {
        switch item {
        case .home: TVHomeView()
        case .watchList: TVWatchListView()
        case .sports: SportsView()
        case .profile: ProfileView()
        case .search: TVSearchView()
        case .reels: TVReelsView()
        }
    }
}

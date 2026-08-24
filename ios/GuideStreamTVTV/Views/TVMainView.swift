//
//  TVMainView.swift
//  GuideStreamTVTV
//
//  Side-menu shell. The selected screen fills the frame while a leading
//  overlay menu (TVSideMenu) handles navigation — content never shifts or
//  resizes when the menu expands. Reels remains withheld for launch.
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
        .background(TVTheme.bg.ignoresSafeArea())
        .onChange(of: selection) { _, _ in
            // The menu is closed on every screen entry, including returns
            // from sheets and full-screen covers.
            menuIsOpen = false
        }
    }

    @ViewBuilder
    private func screen(for item: TVSideMenuItem) -> some View {
        switch item {
        case .home: TVHomeView()
        case .watchList: TVWatchListView()
        case .sports: SportsView()
        case .profile: ProfileView()
        }
    }
}

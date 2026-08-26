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

    /// Constant leading inset for the content screen. The collapsed rail
    /// occupies 32pt + 72pt = 104pt; the rail headers use 80pt of internal
    /// horizontal gutter. Insetting the whole content container by 72pt
    /// puts every rail title and first poster at 152pt from the screen edge,
    /// giving a 48pt margin beyond the rail so a focused first card —
    /// including its focus ring and scale expansion — never slides behind
    /// the panel. The menu still overlays the same content when it opens,
    /// and the content never shifts or resizes.
    private let contentLeadingInset: CGFloat = 72

    @State private var selection: TVSideMenuItem = .home
    @State private var menuIsOpen: Bool = false

    /// Root focus scope. The content declares itself the default focus in
    /// this scope, which is what keeps tvOS's initial focus assignment out
    /// of the side rail now that the rail is focusable in both states.
    /// Without it tvOS picks the leading-most focusable view — the rail —
    /// and the menu would be expanded before the user touches the remote.
    @Namespace private var rootNamespace
    @Environment(\.resetFocus) private var resetFocus

    var body: some View {
        ZStack(alignment: .leading) {
            screen(for: selection)
                .padding(.leading, contentLeadingInset)
                .focusSection()
                .prefersDefaultFocus(true, in: rootNamespace)

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
        .focusScope(rootNamespace)
        .animation(.easeOut(duration: 0.25), value: menuIsOpen)
        .background(TVTheme.backgroundGradient.ignoresSafeArea())
        .onChange(of: selection) { _, _ in
            // The menu is closed on every screen entry, including returns
            // from sheets and full-screen covers. Resetting the root scope
            // hands focus back to the content, which is what collapses the
            // rail now that expansion follows focus.
            menuIsOpen = false
            resetFocus(in: rootNamespace)
        }
        .onPreferenceChange(TVHeroSideMenuRequestKey.self) { count in
            // The hero consumes its own move commands to step the carousel,
            // so the focus engine never sees a left move there. This is the
            // one place that still has to ask for the menu explicitly.
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

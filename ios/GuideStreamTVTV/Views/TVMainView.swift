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

    var body: some View {
        ZStack(alignment: .leading) {
            screen(for: selection)
                .padding(.leading, contentLeadingInset)
                .focusSection()
                // Only the leading-most item in a row opens the menu, via
                // .tvSideMenuLeadingEdge. A handler here would fire on every
                // left press anywhere in the content, which made the menu
                // open mid-rail and stopped the user scrolling a row back.
                .environment(\.tvOpenSideMenu, TVOpenSideMenuAction { openMenu() })

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

    private func openMenu() {
        guard !menuIsOpen else { return }
        menuIsOpen = true
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

// MARK: - Opening the side menu from a row's leading edge

/// Injected by TVMainView so the leading-most item in any row can open the
/// side menu without holding a reference to it.
struct TVOpenSideMenuAction {
    let handler: () -> Void
    func callAsFunction() { handler() }
}

private struct TVOpenSideMenuKey: EnvironmentKey {
    static let defaultValue = TVOpenSideMenuAction(handler: {})
}

extension EnvironmentValues {
    var tvOpenSideMenu: TVOpenSideMenuAction {
        get { self[TVOpenSideMenuKey.self] }
        set { self[TVOpenSideMenuKey.self] = newValue }
    }
}

private struct TVSideMenuLeadingEdge: ViewModifier {
    let isLeading: Bool
    @Environment(\.tvOpenSideMenu) private var openSideMenu

    func body(content: Content) -> some View {
        content.onMoveCommand { direction in
            guard isLeading, direction == .left else { return }
            openSideMenu()
        }
    }
}

extension View {
    /// Marks the leading-most focusable item in a row. A left move command
    /// reaching it has nowhere further left to go, so it opens the side menu.
    ///
    /// Apply this to the FIRST item of a row and to nothing else. Attaching
    /// it to every item — or to the whole content container, which is what
    /// TVMainView did before — opens the menu on every left press, so a rail
    /// can never be stepped back through.
    func tvSideMenuLeadingEdge(_ isLeading: Bool) -> some View {
        modifier(TVSideMenuLeadingEdge(isLeading: isLeading))
    }
}

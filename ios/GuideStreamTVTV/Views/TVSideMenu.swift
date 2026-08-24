//
//  TVSideMenu.swift
//  GuideStreamTVTV
//
//  Leading-edge navigation rail that replaces the tvOS tab bar. Collapsed
//  it is a 72pt icon rail on the surface color with a trailing hairline;
//  when focus enters it expands to 300pt revealing the wordmark and labels.
//  The menu overlays the content — screens never shift or resize while it
//  expands. Selecting an item collapses the menu immediately and hands
//  focus to the selected screen.
//

import SwiftUI

/// The four destinations the side menu routes to, in display order.
/// Reels and Search are intentionally withheld for launch.
enum TVSideMenuItem: String, CaseIterable, Identifiable {
    case home
    case watchList
    case sports
    case profile

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: return "Home"
        case .watchList: return "Watch List"
        case .sports: return "Sports"
        case .profile: return "Profile"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .watchList: return "popcorn.fill"
        case .sports: return "sportscourt.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }
}

struct TVSideMenu: View {
    @Binding var selection: TVSideMenuItem
    @Binding var isOpen: Bool

    @FocusState private var focusedItem: TVSideMenuItem?

    private let closedWidth: CGFloat = 72
    private let openWidth: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandMark
                .padding(.top, 64)
                .padding(.bottom, 48)
                .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(TVSideMenuItem.allCases) { item in
                    menuButton(for: item)
                }
            }

            Spacer()
        }
        .frame(width: isOpen ? openWidth : closedWidth)
        .frame(maxHeight: .infinity)
        .background(TVTheme.surface.opacity(0.92))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(TVTheme.hairline)
                .frame(width: 1)
        }
        .focusSection()
        .animation(.easeOut(duration: 0.25), value: isOpen)
        .onChange(of: focusedItem) { _, focused in
            // Opens the moment focus enters the rail (including a left
            // move from the content area) and closes as soon as focus
            // leaves without a selection. Selections close explicitly.
            isOpen = focused != nil
        }
    }

    // MARK: - Brand mark

    /// The GuideStream mark — icon-only when collapsed, the full nav-size
    /// wordmark when expanded.
    @ViewBuilder
    private var brandMark: some View {
        if isOpen {
            TVBrandWordmark(wordmarkSize: .nav)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Image("GuideStreamLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Items

    private func menuButton(for item: TVSideMenuItem) -> some View {
        let isSelected = selection == item
        return Button {
            select(item)
        } label: {
            HStack(spacing: 16) {
                Image(systemName: item.icon)
                    .font(.system(size: 28, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(isSelected ? TVTheme.orange : TVTheme.textSecondary)
                if isOpen {
                    Text(item.label)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(isSelected ? TVTheme.textPrimary : TVTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                if focusedItem == item {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(TVTheme.surfaceElevated)
                }
            }
        }
        .buttonStyle(.plain)
        .focused($focusedItem, equals: item)
    }

    // MARK: - Selection

    private func select(_ item: TVSideMenuItem) {
        if selection != item {
            selection = item
        }
        // Collapse immediately and hand focus to the selected screen. The
        // already-selected screen stays mounted and untouched.
        isOpen = false
        focusedItem = nil
    }
}

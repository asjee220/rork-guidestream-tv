//
//  TVSideMenu.swift
//  GuideStreamTVTV
//
//  Leading-edge navigation rail that replaces the tvOS tab bar. At rest
//  it is collapsed to a floating, icon-only rounded panel with no
//  focusable views, so launch focus always lands in the content. The ONLY
//  thing that opens it is a left move command issued from the content's
//  leading edge (handled in TVMainView); it then expands to 300pt over
//  0.25s revealing the wordmark and labels. The menu overlays the
//  content — screens never shift or resize. It closes on selection or
//  when a right move hands focus back to the content.
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

    /// Floating collapsed panel width (icon-only).
    private let closedWidth: CGFloat = 140
    /// Expanded width over 0.25s easeOut.
    private let openWidth: CGFloat = 300
    /// Insets that make the panel read as a floating card rather than a
    /// full-height flush rail — kept identical in both states so the
    /// expansion is a pure width change.
    private let leadingInset: CGFloat = 32
    private let verticalInset: CGFloat = 48

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandMark
                .padding(.top, 36)
                .padding(.bottom, 56)
                .padding(.leading, 26)
                .padding(.trailing, 16)

            VStack(alignment: .leading, spacing: 24) {
                ForEach(TVSideMenuItem.allCases) { item in
                    menuRow(for: item)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(width: isOpen ? openWidth : closedWidth)
        .frame(maxHeight: .infinity)
        .background(TVTheme.surface.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .padding(.leading, leadingInset)
        .padding(.vertical, verticalInset)
        .focusSection()
        .animation(.easeOut(duration: 0.25), value: isOpen)
        .onMoveCommand { direction in
            // A right move from inside the menu closes it and hands focus
            // back to the content. (Natural focus moves into the content
            // also close it via the focusedItem change below.)
            if direction == .right, isOpen {
                close()
            }
        }
        .onChange(of: isOpen) { _, open in
            guard open else { return }
            // Opening hands focus to the item matching the current
            // selection. The buttons only become focusable in this same
            // update, so re-assert after a beat if the first attempt
            // didn't land.
            focusedItem = selection
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                if isOpen && focusedItem == nil {
                    focusedItem = selection
                }
            }
        }
        .onChange(of: focusedItem) { _, focused in
            // Closes when a move hands focus back to the content without
            // a selection. This never OPENS the menu — focus arriving in
            // the rail is never what expands it.
            if focused == nil && isOpen {
                close()
            }
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
                .frame(width: 44, height: 44)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Items

    /// While collapsed the rows are plain views — the menu contains no
    /// focusable views, so tvOS can neither assign it initial focus nor
    /// land focus in it by accident. Only the open state mounts buttons.
    @ViewBuilder
    private func menuRow(for item: TVSideMenuItem) -> some View {
        if isOpen {
            menuButton(for: item)
        } else {
            rowContent(for: item)
                .padding(.vertical, 6)
        }
    }

    private func menuButton(for item: TVSideMenuItem) -> some View {
        Button {
            select(item)
        } label: {
            rowContent(for: item)
                .padding(.vertical, 6)
                .background {
                    if focusedItem == item {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(TVTheme.surfaceElevated)
                    }
                }
        }
        .buttonStyle(.plain)
        .focused($focusedItem, equals: item)
    }

    /// Shared row layout: the orange selection bar sits at the panel's
    /// leading edge beside the icon (at the same x in both states), and
    /// the label is revealed to the right when open.
    private func rowContent(for item: TVSideMenuItem) -> some View {
        let isSelected = selection == item
        return HStack(spacing: 0) {
            Capsule()
                .fill(isSelected ? TVTheme.orange : Color.clear)
                .frame(width: 6, height: 44)
            Image(systemName: item.icon)
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(isSelected ? TVTheme.orange : TVTheme.textSecondary)
                .frame(width: 44, height: 44)
                .padding(.leading, 24)
            if isOpen {
                Text(item.label)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(isSelected ? TVTheme.textPrimary : TVTheme.textSecondary)
                    .lineLimit(1)
                    .padding(.leading, 18)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - State

    private func close() {
        isOpen = false
        focusedItem = nil
    }

    private func select(_ item: TVSideMenuItem) {
        if selection != item {
            selection = item
        }
        // Collapse immediately and hand focus to the selected screen. The
        // already-selected screen stays mounted and untouched.
        close()
    }
}

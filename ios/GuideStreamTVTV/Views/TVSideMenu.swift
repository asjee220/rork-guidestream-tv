//
//  TVSideMenu.swift
//  GuideStreamTVTV
//
//  Leading-edge navigation rail that replaces the tvOS tab bar. Closed, it
//  is a narrow 72pt icon-only floating panel with the brand icon at the
//  top. Opened, it expands to 300pt and reveals the "GuideStream TV"
//  wordmark with the brand icon plus labels. The menu only opens from a
//  deliberate left move command in the content area; focus landing in the
//  rail never opens it. It closes on selection, a right move, or focus
//  returning to the content.
//

import SwiftUI

/// The destinations the side menu routes to, in the top-to-bottom order
/// shown in the design mockups: Search, Home, Watchlist, Sports, Reels,
/// Profile. Reels and Search are wired to placeholder screens for now so
/// the menu structure matches the mockups; the screens can be filled in later.
enum TVSideMenuItem: String, CaseIterable, Identifiable {
    case search
    case home
    case watchList
    case sports
    case reels
    case profile

    var id: String { rawValue }

    var label: String {
        switch self {
        case .profile: return "Profile"
        case .reels: return "Reels"
        case .sports: return "Sports"
        case .watchList: return "Watchlist"
        case .home: return "Home"
        case .search: return "Search"
        }
    }

    var icon: String {
        switch self {
        case .profile: return "person.fill"
        case .reels: return "play.fill"
        case .sports: return "american.football.fill"
        case .watchList: return "play.rectangle.fill"
        case .home: return "house"
        case .search: return "magnifyingglass"
        }
    }
}

struct TVSideMenu: View {
    @Binding var selection: TVSideMenuItem
    @Binding var isOpen: Bool

    @FocusState private var focusedItem: TVSideMenuItem?

    /// Focus scope for the rail. The selected row declares itself the
    /// scope's default focus, so focus arriving from the content lands on
    /// the row the user is currently on rather than the topmost one.
    @Namespace private var menuNamespace
    @Environment(\.resetFocus) private var resetFocus

    /// Collapsed rail width — icon-only, narrow, with the brand icon at
    /// the top. Mirrors the closed-state mockup.
    private let closedWidth: CGFloat = 72
    /// Expanded width — reveals the "GuideStream TV" wordmark with an
    /// icon and labels. Mirrors the opened-state mockup.
    private let openWidth: CGFloat = 300
    /// Insets that make the panel read as a floating card rather than a
    /// full-height flush rail — kept identical in both states so the
    /// expansion is a pure width change.
    private let leadingInset: CGFloat = 32
    private let verticalInset: CGFloat = 48
    /// Width of the orange selection indicator.
    private let barWidth: CGFloat = 6
    /// Height of the orange selection indicator.
    private let barHeight: CGFloat = 44
    /// Icon frame size.
    private let iconFrame: CGFloat = 44
    /// Icon image size.
    private let iconSize: CGFloat = 28
    /// Horizontal padding that centers the icon frame in the collapsed
    /// 72pt rail while the 6pt selection bar sits flush at the left edge.
    private let closedIconLeading: CGFloat = 14
    /// Horizontal spacing from the selection bar to the icon when the menu
    /// is open.
    private let openIconLeading: CGFloat = 16
    /// Spacing from the icon to the label in the open menu.
    private let labelLeading: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandMark
                .padding(.top, 24)
                .padding(.bottom, 28)
                .padding(.leading, isOpen ? 22 : 16)
                .padding(.trailing, 16)

            VStack(alignment: .leading, spacing: 16) {
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
        .focusScope(menuNamespace)
        .animation(.easeOut(duration: 0.25), value: isOpen)
        .onChange(of: isOpen) { _, open in
            // The hero raises isOpen without focus moving, because it
            // consumes its own left/right move commands to step the carousel
            // and the focus engine never sees them there. Pull focus in for
            // that case only. Unlike before, the rows are mounted in both
            // states, so this assignment is not racing their creation.
            guard open, focusedItem == nil else { return }
            resetFocus(in: menuNamespace)
            focusedItem = selection
        }
        .onChange(of: focusedItem) { _, focused in
            // The rail is a real focus section, so the focus engine moves
            // into it from the leading-most item of any row and back out to
            // the right — exactly the Paramount+ behaviour. Expansion simply
            // follows focus; nothing intercepts move commands.
            //
            // Launch focus cannot land here: TVMainView marks the content as
            // prefersDefaultFocus in the root scope, so tvOS picks the
            // content, not the rail, on first appearance.
            isOpen = (focused != nil)
        }
    }

    // MARK: - Brand mark

    /// The GuideStream mark — the square monogram icon when collapsed, the
    /// full "GuideStream TV" wordmark with the brand icon when opened.
    /// The open state and onboarding still use the horizontal wordmark
    /// lockup asset (GuideStreamLogo); the collapsed rail uses the square
    /// mark (GuideStreamMark) so it stays crisp at the small size.
    @ViewBuilder
    private var brandMark: some View {
        if isOpen {
            Image("GuideStreamMenuHeader")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Image("GuideStreamMark")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Items

    /// While collapsed the rows are plain views — the menu contains no
    /// focusable views, so tvOS can neither assign it initial focus nor
    /// land focus in it by accident. Only the open state mounts buttons.
    private func menuRow(for item: TVSideMenuItem) -> some View {
        menuButton(for: item)
    }

    private func menuButton(for item: TVSideMenuItem) -> some View {
        Button {
            select(item)
        } label: {
            rowContent(for: item, isFocused: focusedItem == item)
                .padding(.vertical, 6)
        }
        .buttonStyle(TVMenuButtonStyle())
        .focused($focusedItem, equals: item)
        .prefersDefaultFocus(item == selection, in: menuNamespace)
        .focusEffectDisabled()
    }

    /// Shared row layout: the orange selection bar sits flush at the
    /// panel's leading edge, and the icon is centered in the collapsed
    /// rail. When opened, the label appears to the right.
    ///
    /// Four treatments, and the two cues are independent so they never
    /// read as the same state:
    ///   selected + focused  — orange bar, white icon/label, focus plate
    ///   selected, unfocused — orange bar, white icon/label, no plate
    ///   focused, unselected — no bar, white icon/label, focus plate
    ///   resting             — no bar, muted icon/label, no plate
    /// The bar tracks `selection` only. The plate tracks focus only. White
    /// vs. 65%-white alone is not readable at a 10-foot viewing distance,
    /// which is why focus also gets the plate.
    private func rowContent(for item: TVSideMenuItem, isFocused: Bool = false) -> some View {
        let isSelected = selection == item
        let isActive = isSelected || isFocused
        return HStack(spacing: 0) {
            Capsule()
                .fill(isSelected ? TVTheme.orange : Color.clear)
                .frame(width: barWidth, height: barHeight)
            HStack(spacing: 0) {
                Image(systemName: item.icon)
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(isActive ? TVTheme.textPrimary : TVTheme.textSecondary)
                    .frame(width: iconFrame, height: iconFrame)
                if isOpen {
                    Text(item.label)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(isActive ? TVTheme.textPrimary : TVTheme.textSecondary)
                        .lineLimit(1)
                        .padding(.leading, labelLeading)
                }
            }
            .padding(.leading, isOpen ? openIconLeading : closedIconLeading)
            .padding(.trailing, isOpen ? 24 : 0)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isFocused ? Color.white.opacity(0.16) : Color.clear)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .scaleEffect(isFocused ? 1.06 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }

    // MARK: - State

    private func select(_ item: TVSideMenuItem) {
        if selection != item {
            selection = item
        }
        // TVMainView resets focus to the content on any selection change,
        // which collapses the rail via the focus change above. Selecting the
        // already-selected item still needs an explicit collapse, since
        // `selection` does not change and no reset fires.
        isOpen = false
        focusedItem = nil
    }
}

// MARK: - Button style

/// A completely inert button style that returns the label untouched. This
/// suppresses the default white focus plate that tvOS draws behind
/// PlainButtonStyle on this SDK, leaving focus state entirely to the
/// rowContent scale and text-color lift.
private struct TVMenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

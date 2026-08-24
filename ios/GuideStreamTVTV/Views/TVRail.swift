//
//  TVRail.swift
//  GuideStreamTVTV
//
//  Reusable horizontal rail container — title pill on the left, content
//  scrolls horizontally to the right. The Siri Remote naturally scrolls
//  the rail as the user moves focus.
//

import SwiftUI

struct TVRail<Content: View>: View {
    let title: String
    let accent: Color
    let count: Int?
    /// Section key used in the See-all button's `card_tapped` metadata
    /// ("<key>_see_all"). Only read when `onSeeAll` is non-nil.
    let seeAllKey: String?
    /// When non-nil, renders a trailing "See all" capsule in the header.
    let onSeeAll: (() -> Void)?
    @ViewBuilder var content: () -> Content

    @FocusState private var seeAllFocused: Bool

    init(
        title: String,
        accent: Color = TVTheme.orange,
        count: Int? = nil,
        seeAllKey: String? = nil,
        onSeeAll: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.accent = accent
        self.count = count
        self.seeAllKey = seeAllKey
        self.onSeeAll = onSeeAll
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                Capsule()
                    .fill(accent)
                    .frame(width: 6, height: 30)
                    .shadow(color: accent.opacity(0.65), radius: 10)
                Text(title)
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(.white)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.08), in: Capsule())
                }
                Spacer()
                if onSeeAll != nil {
                    seeAllButton
                }
            }
            .padding(.horizontal, 80)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 32) {
                    content()
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 30)
            }
        }
    }

    // MARK: - See all

    /// Trailing "See all" capsule — transparent fill with a 1pt white-25%
    /// stroke that thickens to 2pt orange with a white label on focus.
    /// Selecting it logs `.cardTapped` with the rail's section key, then
    /// invokes the caller's closure.
    private var seeAllButton: some View {
        Button {
            WatchIntentLogger.shared.log(
                eventType: .cardTapped,
                metadata: ["section": "\(seeAllKey ?? "rail")_see_all"]
            )
            onSeeAll?()
        } label: {
            Text("See all")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(seeAllFocused ? Color.white : TVTheme.textSecondary)
                .padding(.horizontal, 28)
                .padding(.vertical, 10)
                .background(
                    Capsule().stroke(
                        seeAllFocused ? TVTheme.orange : Color.white.opacity(0.25),
                        lineWidth: seeAllFocused ? 2 : 1
                    )
                )
        }
        .buttonStyle(.plain)
        .focused($seeAllFocused)
    }
}

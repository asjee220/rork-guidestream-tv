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
            // The See all capsule sits at the trailing end of this row while
            // the cards below start at the leading edge, so a plain vertical
            // move from a card never overlaps it and can never reach it. On
            // the first rail the hero makes it worse: its focusable frame
            // still covers this row, because the rail is pulled up over the
            // hero art with a negative bottom padding. Making the header its
            // own focus section lets a move up enter the section and pick
            // See all regardless of horizontal alignment.
            .focusSection()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 32) {
                    content()
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 30)
            }
            // Cards are their own section too. With both halves sectioned,
            // an up move out of the cards resolves section-to-section and
            // lands in the header above, instead of being decided purely on
            // frame overlap — which handed it to whatever the hero happened
            // to have sitting directly above the focused card.
            .focusSection()
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
                // Same selected treatment as the side menu rows: a white 16%
                // plate and a 1.06 lift, with the resting outline kept so the
                // control still reads as a button when nothing is focused.
                .background(
                    Capsule().fill(Color.white.opacity(seeAllFocused ? 0.16 : 0))
                )
                .background(
                    Capsule().stroke(Color.white.opacity(seeAllFocused ? 0 : 0.25),
                                     lineWidth: 1)
                )
                .scaleEffect(seeAllFocused ? 1.06 : 1.0)
                .animation(.easeOut(duration: 0.15), value: seeAllFocused)
        }
        // An empty style, not .plain: .plain still lets tvOS lay its own
        // white focus slab over the control even with the effect disabled.
        .buttonStyle(TVRailFlatButtonStyle())
        .focusEffectDisabled()
        .focused($seeAllFocused)
    }
}

/// Draws nothing, so the See all button's own plate is the only focus cue.
private struct TVRailFlatButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

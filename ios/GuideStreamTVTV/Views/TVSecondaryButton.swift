//
//  TVSecondaryButton.swift
//  GuideStreamTVTV
//
//  The one secondary affordance: "See all", "Edit", and anything else that
//  sits at the trailing end of a section header.
//
//  There used to be two. TVRail carried a capsule that matched the side
//  menu's selected treatment — a white plate and a small lift — while Sports
//  carried GhostButton, an orange outline that inverted to a filled orange
//  pill. Two focus languages on two screens meant the same word, "See all",
//  told the viewer different things about what focus looks like depending on
//  where they were standing. This is the capsule, and it is the only one.
//
//  Also here: the empty ButtonStyle every focus-drawn control in the target
//  needs. `.plain` still lays tvOS's white slab over a control even with
//  .focusEffectDisabled(), so a control that draws its own focus state has
//  to be given a style that draws nothing at all.
//

import SwiftUI

/// Draws nothing, so a control's own plate, capsule or outline is the only
/// focus cue.
struct TVFlatButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// Trailing secondary control for a section header.
///
/// `sectionKey` is logged with the tap as `<key>_see_all`, the same metadata
/// shape the Home rails have always written, so Sports' headers start
/// reporting alongside them instead of silently.
struct TVSecondaryButton: View {
    let title: String
    var sectionKey: String?
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button {
            if let sectionKey {
                WatchIntentLogger.shared.log(
                    eventType: .cardTapped,
                    metadata: ["section": "\(sectionKey)_see_all"]
                )
            }
            action()
        } label: {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isFocused ? TVButtonFocus.content : TVTheme.textSecondary)
                .padding(.horizontal, 28)
                .padding(.vertical, 10)
                // The shared white fill and a 1.06 lift on focus, with the
                // resting outline kept so the control still reads as a
                // button when nothing is focused.
                .background(Capsule().fill(isFocused ? TVButtonFocus.fill : Color.clear))
                .background(
                    Capsule().stroke(Color.white.opacity(isFocused ? 0 : 0.25), lineWidth: 1)
                )
                .scaleEffect(isFocused ? TVButtonFocus.scale : 1.0)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
        .buttonStyle(TVFlatButtonStyle())
        .focusEffectDisabled()
        .focused($isFocused)
    }
}

/// The focused state every control that reads as a button shares on tvOS:
/// a solid white fill with black text and black icons. Content cards —
/// posters, hero and game cards, crests, logo tiles — keep their own
/// artwork-led focus and do not use this.
enum TVButtonFocus {
    static let fill = Color.white
    static let content = Color.black
    static let scale: CGFloat = 1.06
}

extension View {
    /// A soft shadow under a focused button. The white fill is the focus
    /// cue; for a selected pill that is already white at rest, this and the
    /// scale lift are what tell focus apart from selection.
    func tvButtonFocusShadow(_ isFocused: Bool) -> some View {
        shadow(
            color: Color.black.opacity(isFocused ? 0.45 : 0),
            radius: isFocused ? 14 : 0,
            y: isFocused ? 6 : 0
        )
    }
}

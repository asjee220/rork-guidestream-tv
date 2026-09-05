//
//  TVPosterCard.swift
//  GuideStreamTVTV
//
//  Focus-aware poster tile. On Apple TV the Siri Remote drives the focus
//  engine — the system handles the "lift" automatically when a button
//  becomes focused, but we lean into it with a gradient ring, a
//  shadow burst, and a saved checkmark so each tile feels alive.
//

import SwiftUI

struct TVPosterCard: View {
    let title: String
    let subtitle: String?
    let posterUrl: String?
    let accent: Color
    /// True when this title is already saved in the watch list — shows
    /// the saved checkmark and dims the call-to-action.
    let isSaved: Bool
    let action: () -> Void

    @FocusState private var isFocused: Bool

    init(
        title: String,
        subtitle: String? = nil,
        posterUrl: String?,
        accent: Color = TVTheme.orange,
        isSaved: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.posterUrl = posterUrl
        self.accent = accent
        self.isSaved = isSaved
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Color(white: 0.05)
                    .overlay {
                        TVRemoteImage(urlString: posterUrl)
                            .allowsHitTesting(false)
                    }
                    .overlay(alignment: .bottomLeading) {
                        // Title gradient
                        LinearGradient(
                            colors: [
                                .black.opacity(0.85),
                                .black.opacity(0.0)
                            ],
                            startPoint: .bottom,
                            endPoint: .center
                        )
                        .overlay(alignment: .bottomLeading) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(title)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                if let subtitle, !subtitle.isEmpty {
                                    Text(subtitle.uppercased())
                                        .font(.system(size: 14, weight: .heavy))
                                        .foregroundStyle(accent)
                                        .tracking(0.8)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.bottom, 14)
                        }
                    }
                if isSaved {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white, accent)
                        .padding(14)
                        .shadow(color: .black.opacity(0.6), radius: 8)
                }
            }
            .clipShape(.rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isFocused ? accent.opacity(0.95) : Color.white.opacity(0.06),
                        lineWidth: isFocused ? 4 : 1
                    )
            }
        }
        .buttonStyle(.card)
        .focused($isFocused)
        .frame(width: 260, height: 380)
        .shadow(
            color: isFocused ? accent.opacity(0.55) : Color.black.opacity(0.45),
            radius: isFocused ? 36 : 14,
            y: isFocused ? 24 : 8
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isFocused)
    }
}

/// Wide tile variant used for news (16:9 backdrop instead of 2:3 poster).
/// Picks the button style for a wide card. Two styles cannot be applied
/// conditionally inline — the branches have different types — so the choice
/// lives in a modifier.
private struct TVWideCardButtonStyle: ViewModifier {
    let flat: Bool

    func body(content: Content) -> some View {
        if flat {
            content
                .buttonStyle(TVFlatButtonStyle())
                .focusEffectDisabled()
        } else {
            content.buttonStyle(.card)
        }
    }
}

struct TVWideCard: View {
    let title: String
    let subtitle: String?
    let backdropUrl: String?
    let accent: Color
    let isSaved: Bool
    /// Optional card width override — defaults to 480 so existing call
    /// sites render exactly as before. Used by full-width layouts such as
    /// the Home "Today's Pick" banner.
    let width: CGFloat?
    /// Optional height override — defaults to 270 so existing call sites are
    /// unchanged. The Home "Today's Pick" banner asks for more.
    let height: CGFloat?
    /// How the artwork fills the card. `.fill` is right for a 16:9 backdrop.
    /// `.fit` is for a portrait poster, which `.fill` would crop to a sliver
    /// of its middle — the Today's Pick banner was showing faces cut in half
    /// because a 2:3 poster was being filled into a wide box.
    let imageContentMode: ContentMode
    /// Opt out of `.buttonStyle(.card)`.
    ///
    /// `.card` brings tvOS's own focus appearance with it, and on a banner the
    /// size of Today's Pick that system treatment reads louder than the accent
    /// stroke drawn underneath it — the card looked unselectable because the
    /// orange never showed. With this set the card uses the house treatment
    /// instead: no system effect, a thicker accent stroke and a stronger accent
    /// glow, driven by the card's own focus state. Existing call sites keep
    /// `.card` and are untouched.
    let usesFlatFocus: Bool
    let action: () -> Void

    @FocusState private var isFocused: Bool

    init(
        title: String,
        subtitle: String? = nil,
        backdropUrl: String?,
        accent: Color = TVTheme.newsGreen,
        isSaved: Bool = false,
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        imageContentMode: ContentMode = .fill,
        usesFlatFocus: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.backdropUrl = backdropUrl
        self.accent = accent
        self.isSaved = isSaved
        self.width = width
        self.height = height
        self.imageContentMode = imageContentMode
        self.usesFlatFocus = usesFlatFocus
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                Color(white: 0.05)
                    .overlay {
                        // A blurred, over-scaled copy fills the corners so a
                        // `.fit` image sits on a soft bed of its own colours
                        // instead of black bars. Invisible under a `.fill`
                        // image, so `.fill` call sites are unaffected.
                        if imageContentMode == .fit {
                            TVRemoteImage(urlString: backdropUrl, contentMode: .fill)
                                .blur(radius: 40)
                                .opacity(0.55)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay {
                        TVRemoteImage(urlString: backdropUrl, contentMode: imageContentMode)
                            .allowsHitTesting(false)
                    }
                    .overlay(alignment: .bottomLeading) {
                        LinearGradient(
                            colors: [
                                .black.opacity(0.95),
                                .black.opacity(0.1)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                        .overlay(alignment: .bottomLeading) {
                            VStack(alignment: .leading, spacing: 6) {
                                if let subtitle, !subtitle.isEmpty {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(accent)
                                            .frame(width: 8, height: 8)
                                            .shadow(color: accent.opacity(0.8), radius: 6)
                                        Text(subtitle.uppercased())
                                            .font(.system(size: 14, weight: .heavy))
                                            .foregroundStyle(accent)
                                            .tracking(0.9)
                                    }
                                }
                                Text(title)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 14)
                        }
                    }
                if isSaved {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white, accent)
                        .padding(14)
                }
            }
            .clipShape(.rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isFocused ? accent.opacity(0.95) : Color.white.opacity(0.06),
                        lineWidth: isFocused ? (usesFlatFocus ? 6 : 4) : 1
                    )
            }
        }
        .modifier(TVWideCardButtonStyle(flat: usesFlatFocus))
        .focused($isFocused)
        .frame(width: width ?? 480, height: height ?? 270)
        .scaleEffect(usesFlatFocus && isFocused ? 1.015 : 1.0)
        .animation(.easeOut(duration: 0.18), value: isFocused)
        .shadow(
            color: isFocused ? accent.opacity(usesFlatFocus ? 0.75 : 0.55) : Color.black.opacity(0.45),
            radius: isFocused ? (usesFlatFocus ? 48 : 36) : 14,
            y: isFocused ? 24 : 8
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isFocused)
    }
}

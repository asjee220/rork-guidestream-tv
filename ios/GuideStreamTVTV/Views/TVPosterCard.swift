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
struct TVWideCard: View {
    let title: String
    let subtitle: String?
    let backdropUrl: String?
    let accent: Color
    let isSaved: Bool
    let action: () -> Void

    @FocusState private var isFocused: Bool

    init(
        title: String,
        subtitle: String? = nil,
        backdropUrl: String?,
        accent: Color = TVTheme.newsGreen,
        isSaved: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.backdropUrl = backdropUrl
        self.accent = accent
        self.isSaved = isSaved
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                Color(white: 0.05)
                    .overlay {
                        TVRemoteImage(urlString: backdropUrl)
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
                        lineWidth: isFocused ? 4 : 1
                    )
            }
        }
        .buttonStyle(.card)
        .focused($isFocused)
        .frame(width: 480, height: 270)
        .shadow(
            color: isFocused ? accent.opacity(0.55) : Color.black.opacity(0.45),
            radius: isFocused ? 36 : 14,
            y: isFocused ? 24 : 8
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isFocused)
    }
}

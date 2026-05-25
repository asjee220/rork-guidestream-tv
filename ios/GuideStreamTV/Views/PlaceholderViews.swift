//
//  PlaceholderViews.swift
//  GuideStreamTV
//

import SwiftUI
import Auth

struct LiveTVView: View {
    var body: some View {
        PlaceholderShell(
            symbol: "dot.radiowaves.left.and.right",
            title: "Live TV",
            subtitle: "Live channels from every provider, one guide.",
            accent: Theme.blue
        )
    }
}

struct AskStreamView: View {
    var body: some View {
        PlaceholderShell(
            symbol: "sparkles",
            title: "Ask Stream",
            subtitle: "Your AI co-pilot for what to watch tonight.",
            accent: Theme.orange
        )
    }
}

struct PlaceholderShell: View {
    let symbol: String
    let title: String
    let subtitle: String
    let accent: Color

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.18))
                    .frame(width: 130, height: 130)
                    .blur(radius: 22)
                Circle()
                    .stroke(accent.opacity(0.4), lineWidth: 1)
                    .frame(width: 100, height: 100)
                Image(systemName: symbol)
                    .scaledFont(size: 40, weight: .light)
                    .foregroundStyle(accent)
            }
            Text(title)
                .scaledFont(size: 28, weight: .heavy)
                .foregroundStyle(.white)
            Text(subtitle)
                .scaledFont(size: 14)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

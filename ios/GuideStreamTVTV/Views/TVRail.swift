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
    @ViewBuilder var content: () -> Content

    init(
        title: String,
        accent: Color = TVTheme.orange,
        count: Int? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.accent = accent
        self.count = count
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
}

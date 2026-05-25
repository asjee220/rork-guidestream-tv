//
//  PosterView.swift
//  GuideStreamTV
//

import SwiftUI

struct PosterView: View {
    let show: Show
    var compact: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: show.posterColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Subtle noise / texture rings
            GeometryReader { geo in
                Circle()
                    .fill(show.accent.opacity(0.25))
                    .frame(width: geo.size.width * 1.1)
                    .blur(radius: 60)
                    .offset(x: -geo.size.width * 0.3, y: -geo.size.height * 0.3)
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    .frame(width: geo.size.width * 0.7)
                    .offset(x: geo.size.width * 0.35, y: geo.size.height * 0.35)
                Circle()
                    .stroke(Color.white.opacity(0.04), lineWidth: 1)
                    .frame(width: geo.size.width * 1.1)
                    .offset(x: geo.size.width * 0.45, y: geo.size.height * 0.45)
            }

            Image(systemName: show.symbol)
                .font(.system(size: compact ? 44 : 78, weight: .light))
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: show.accent.opacity(0.6), radius: 18)
        }
    }
}

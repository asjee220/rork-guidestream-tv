//
//  HeroCardView.swift
//  GuideStreamTV
//

import SwiftUI

struct HeroCardView: View {
    let show: Show
    var onPlay: () -> Void = {}

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black
                .frame(height: 460)
                .overlay {
                    PosterView(show: show)
                        .allowsHitTesting(false)
                }
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: Theme.bg.opacity(0.4), location: 0.55),
                            .init(color: Theme.bg, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }
                .clipShape(.rect(cornerRadius: 28))
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 14) {
                if let badge = show.badge {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Theme.orange)
                            .frame(width: 6, height: 6)
                            .shadow(color: Theme.orange, radius: 4)
                        Text(badge)
                            .scaledFont(size: 11, weight: .heavy)
                            .tracking(1.4)
                            .foregroundStyle(Theme.orange)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(Theme.orange.opacity(0.14))
                    )
                    .overlay(
                        Capsule().stroke(Theme.orange.opacity(0.5), lineWidth: 0.7)
                    )
                }

                Text(show.network)
                    .scaledFont(size: 11, weight: .semibold)
                    .tracking(2)
                    .foregroundStyle(Theme.blue)

                Text(show.title)
                    .scaledFont(size: 38, weight: .heavy, design: .default)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 2)

                Text(show.subtitle)
                    .scaledFont(size: 14, weight: .regular)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .padding(.trailing, 40)

                HStack(spacing: 12) {
                    Button(action: onPlay) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .scaledFont(size: 14, weight: .bold)
                            Text("Play")
                                .scaledFont(size: 15, weight: .bold)
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(.white))
                    }

                    Button(action: {}) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .scaledFont(size: 13, weight: .bold)
                            Text("My List")
                                .scaledFont(size: 14, weight: .semibold)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().fill(.ultraThinMaterial)
                        )
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                    }
                }
                .padding(.top, 6)
            }
            .padding(22)
        }
        .padding(.horizontal, 16)
    }
}

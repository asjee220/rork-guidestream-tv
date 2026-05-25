//
//  EpisodeCardView.swift
//  GuideStreamTV
//

import SwiftUI

struct EpisodeCardView: View {
    let show: Show

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.black
                .frame(width: 180, height: 240)
                .overlay {
                    PosterView(show: show, compact: true)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .topLeading) {
                    if let badge = show.badge {
                        Text(badge)
                            .scaledFont(size: 9, weight: .heavy)
                            .tracking(1)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(badge == "LIVE" ? Color.red : Theme.orange)
                            )
                            .padding(10)
                    }
                }
                .clipShape(.rect(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(show.network)
                    .scaledFont(size: 9, weight: .bold)
                    .tracking(1.4)
                    .foregroundStyle(Theme.blue)
                Text(show.title)
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(show.episode) · \(show.duration)")
                    .scaledFont(size: 12)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .frame(width: 180)
    }
}

struct ContinueCardView: View {
    let show: Show

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.black
                .frame(width: 260, height: 150)
                .overlay {
                    PosterView(show: show, compact: true)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .center) {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 52, height: 52)
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            .frame(width: 52, height: 52)
                        Image(systemName: "play.fill")
                            .scaledFont(size: 18, weight: .bold)
                            .foregroundStyle(.white)
                            .offset(x: 2)
                    }
                }
                .overlay(alignment: .bottom) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.white.opacity(0.18))
                                .frame(height: 3)
                            Rectangle()
                                .fill(Theme.orange)
                                .frame(width: geo.size.width * show.progress, height: 3)
                                .shadow(color: Theme.orange.opacity(0.7), radius: 4)
                        }
                    }
                    .frame(height: 3)
                }
                .clipShape(.rect(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(show.title)
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(show.episode) · \(show.duration)")
                    .scaledFont(size: 12)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .frame(width: 260)
    }
}

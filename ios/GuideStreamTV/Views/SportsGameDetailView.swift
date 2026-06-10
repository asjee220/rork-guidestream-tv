//
//  SportsGameDetailView.swift
//  GuideStreamTV
//

import SwiftUI

struct SportsGameDetailView: View {
    let game: SportsGame

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // League
                Text(game.leagueShort.uppercased())
                    .scaledFont(size: 12, weight: .heavy)
                    .tracking(1.4)
                    .foregroundStyle(Color.white.opacity(0.45))

                // Scoreline
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(game.away.shortName)
                            .scaledFont(size: 22, weight: .bold)
                            .foregroundStyle(game.away.isWinner ? .white : Color.white.opacity(0.55))
                        Text(game.away.score)
                            .scaledFont(size: 36, weight: .black)
                            .foregroundStyle(game.away.isWinner ? .white : Color.white.opacity(0.55))
                    }
                    Spacer()
                    Text(game.state == .pre ? "vs" : game.state == .live ? "LIVE" : "FINAL")
                        .scaledFont(size: 13, weight: .heavy)
                        .foregroundStyle(Color.white.opacity(0.35))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(game.home.shortName)
                            .scaledFont(size: 22, weight: .bold)
                            .foregroundStyle(game.home.isWinner ? .white : Color.white.opacity(0.55))
                        Text(game.home.score)
                            .scaledFont(size: 36, weight: .black)
                            .foregroundStyle(game.home.isWinner ? .white : Color.white.opacity(0.55))
                    }
                }

                // Status + date
                VStack(alignment: .leading, spacing: 6) {
                    Text(game.statusDetail)
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(.white)
                    Text(formattedStartDate)
                        .scaledFont(size: 13)
                        .foregroundStyle(Color.white.opacity(0.55))
                }

                // Watch on
                if !game.broadcasts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Watch on")
                            .scaledFont(size: 12, weight: .heavy)
                            .tracking(1.4)
                            .foregroundStyle(Color.white.opacity(0.45))
                        Text(game.broadcasts.joined(separator: " · "))
                            .scaledFont(size: 14, weight: .semibold)
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(Color(hex: "04090F").ignoresSafeArea())
        .navigationTitle("Game Details")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color(hex: "04090F"), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var formattedStartDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: game.startDate)
    }
}

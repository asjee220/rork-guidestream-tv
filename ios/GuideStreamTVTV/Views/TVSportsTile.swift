//
//  TVSportsTile.swift
//  GuideStreamTVTV
//
//  Sports rail tile: live/upcoming game with team abbreviations, score,
//  and broadcaster chips. Mirrors the phone app's sports card aesthetic
//  but scaled for the focus engine and 10-foot viewing distance.
//

import SwiftUI

struct TVSportsTile: View {
    let game: TVSportsGame
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Text(game.sport)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(TVTheme.blue.opacity(0.95), in: Capsule())
                    if game.state.isLive {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.red)
                                .frame(width: 8, height: 8)
                            Text("LIVE")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(.red)
                                .tracking(0.8)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(game.statusDetail)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(TVTheme.textSecondary)
                        .lineLimit(1)
                }

                VStack(spacing: 10) {
                    teamRow(team: game.away)
                    teamRow(team: game.home)
                }

                if !game.broadcasts.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(game.broadcasts.prefix(3), id: \.self) { b in
                            Text(b)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.white.opacity(0.08), in: Capsule())
                        }
                    }
                }
            }
            .padding(20)
            .frame(width: 360, height: 280, alignment: .topLeading)
            .background {
                ZStack {
                    TVTheme.surface
                    LinearGradient(
                        colors: [
                            TVTheme.blue.opacity(0.18),
                            Color.clear
                        ],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                }
            }
            .clipShape(.rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isFocused ? TVTheme.blue.opacity(0.95) : Color.white.opacity(0.06),
                        lineWidth: isFocused ? 4 : 1
                    )
            }
        }
        .buttonStyle(.card)
        .focused($isFocused)
        .shadow(
            color: isFocused ? TVTheme.blue.opacity(0.55) : Color.black.opacity(0.45),
            radius: isFocused ? 36 : 14,
            y: isFocused ? 24 : 8
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isFocused)
    }

    private func teamRow(team: TVGameTeam) -> some View {
        HStack(spacing: 14) {
            Text(team.abbreviation)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 80, alignment: .leading)
            Text(team.shortName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(TVTheme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(team.score)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(team.isWinner ? .white : TVTheme.textSecondary)
        }
    }
}

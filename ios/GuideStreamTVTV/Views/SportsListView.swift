//
//  SportsListView.swift
//  GuideStreamTV
//
//  Full-screen "See all" destination for each Sports section (Live / Upcoming /
//  Final). Reuses the same compact game-row visual as the main Sports tab and
//  opens the shared SportsWatchSheet on tap so the watch flow stays consistent.
//

import SwiftUI
import UIKit

/// Where the see-all list came from. Drives the navigation title.
enum SportsSection {
    case live, upcoming, finalGames

    var title: String {
        switch self {
        case .live: return "Live Now"
        case .upcoming: return "Upcoming"
        case .finalGames: return "Final"
        }
    }
}

struct SportsListView: View {
    let games: [SportsGame]
    let section: SportsSection
    let sportFilter: String

    @State private var selectedGame: SportsGame?

    var body: some View {
        ZStack {
            Color(hex: "04090F").ignoresSafeArea()

            if games.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(games) { game in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                selectedGame = game
                            } label: {
                                row(for: game)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 120)
                }
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color(hex: "04090F"), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        #if os(tvOS)
        .fullScreenCover(item: $selectedGame) { game in
            SportsWatchSheet(game: game)
        }
        #else
        .sheet(item: $selectedGame) { game in
            SportsWatchSheet(game: game)
        }
        #endif
    }

    private var navigationTitle: String {
        if sportFilter == "All" { return section.title }
        return "\(section.title) · \(sportFilter)"
    }

    // MARK: - Row

    @ViewBuilder
    private func row(for game: SportsGame) -> some View {
        switch section {
        case .live: liveRow(game)
        case .upcoming: upcomingRow(game)
        case .finalGames: finalRow(game)
        }
    }

    private func liveRow(_ game: SportsGame) -> some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(hex: "E50914"))
                        .frame(width: 6, height: 6)
                    Text("LIVE")
                        .scaledFont(size: 9, weight: .black)
                        .foregroundStyle(Color(hex: "E50914"))
                    Text("\(game.sport) · \(game.statusDetail)")
                        .scaledFont(size: 9, weight: .semibold)
                        .foregroundStyle(Color.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer()
                Text("Watch ▶")
                    .scaledFont(size: 11, weight: .bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 20).fill(Color(hex: "F5821F"))
                    )
            }

            HStack {
                liveTeam(team: game.away, leading: true)
                Spacer()
                Text("VS")
                    .scaledFont(size: 11, weight: .bold)
                    .foregroundStyle(Color.white.opacity(0.2))
                Spacer()
                liveTeam(team: game.home, leading: false)
            }

            broadcastsRow(game.broadcasts)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "161B27")))
        .overlay(
            RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func liveTeam(team: GameTeam, leading: Bool) -> some View {
        let color = team.primaryHex.map { Color(hex: $0) } ?? Color.white.opacity(0.2)
        let scoreColor: Color = team.isWinner ? .white : Color.white.opacity(0.55)
        return VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 10)
                .fill(color)
                .frame(width: 38, height: 38)
                .overlay(
                    Text(team.abbreviation)
                        .scaledFont(size: 9, weight: .black)
                        .foregroundStyle(.white)
                )
            Text(team.shortName)
                .scaledFont(size: 10, weight: .semibold)
                .foregroundStyle(Color.white.opacity(0.6))
                .lineLimit(1)
            Text(team.score)
                .scaledFont(size: 24, weight: .black)
                .foregroundStyle(scoreColor)
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
    }

    private func upcomingRow(_ game: SportsGame) -> some View {
        let awayColor = game.away.primaryHex.map { Color(hex: $0) } ?? Color.white.opacity(0.2)
        let homeColor = game.home.primaryHex.map { Color(hex: $0) } ?? Color.white.opacity(0.2)
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(awayColor)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Text(game.away.abbreviation)
                            .scaledFont(size: 7, weight: .black)
                            .foregroundStyle(.white)
                    )
                Text("vs")
                    .scaledFont(size: 11, weight: .bold)
                    .foregroundStyle(Color.white.opacity(0.3))
                RoundedRectangle(cornerRadius: 8)
                    .fill(homeColor)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Text(game.home.abbreviation)
                            .scaledFont(size: 7, weight: .black)
                            .foregroundStyle(.white)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(game.away.shortName) vs \(game.home.shortName)")
                        .scaledFont(size: 13, weight: .bold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(game.sport) · \(game.statusDetail)")
                        .scaledFont(size: 10)
                        .foregroundStyle(Color.white.opacity(0.4))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .scaledFont(size: 12, weight: .bold)
                    .foregroundStyle(Color.white.opacity(0.3))
            }

            broadcastsRow(game.broadcasts)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "161B27")))
        .overlay(
            RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func finalRow(_ game: SportsGame) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(game.away.abbreviation)
                        .scaledFont(size: 11, weight: .bold)
                        .foregroundStyle(game.away.isWinner ? .white : Color.white.opacity(0.5))
                    Spacer()
                    Text(game.away.score)
                        .scaledFont(size: 14, weight: .black)
                        .foregroundStyle(game.away.isWinner ? .white : Color.white.opacity(0.5))
                }
                HStack(spacing: 6) {
                    Text(game.home.abbreviation)
                        .scaledFont(size: 11, weight: .bold)
                        .foregroundStyle(game.home.isWinner ? .white : Color.white.opacity(0.5))
                    Spacer()
                    Text(game.home.score)
                        .scaledFont(size: 14, weight: .black)
                        .foregroundStyle(game.home.isWinner ? .white : Color.white.opacity(0.5))
                }
            }
            .frame(width: 110)

            Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(game.statusDetail)
                    .scaledFont(size: 10, weight: .bold)
                    .foregroundStyle(Color.white.opacity(0.55))
                Text(game.sport)
                    .scaledFont(size: 9, weight: .semibold)
                    .foregroundStyle(Color.white.opacity(0.35))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .scaledFont(size: 12, weight: .bold)
                .foregroundStyle(Color.white.opacity(0.3))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: "12161F")))
        .overlay(
            RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func broadcastsRow(_ broadcasts: [String]) -> some View {
        if !broadcasts.isEmpty {
            HStack(spacing: 6) {
                Text("ON:")
                    .scaledFont(size: 9, weight: .bold)
                    .foregroundStyle(Color.white.opacity(0.35))
                ForEach(broadcasts.prefix(4), id: \.self) { name in
                    Text(name)
                        .scaledFont(size: 9, weight: .black)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5).fill(broadcastColor(name))
                        )
                }
                Spacer()
            }
        }
    }

    private func broadcastColor(_ name: String) -> Color {
        let lower = name.lowercased()
        if lower.contains("espn") { return Color(hex: "CC0000") }
        if lower.contains("peacock") { return Color.black }
        if lower.contains("prime") || lower.contains("amazon") { return Color(hex: "00A8E0") }
        if lower.contains("apple") { return Color.black }
        if lower.contains("paramount") { return Color(hex: "0064FF") }
        if lower.contains("max") || lower.contains("hbo") { return Color(hex: "002BE7") }
        if lower.contains("nbc") { return Color(hex: "FCB900") }
        if lower.contains("fox") { return Color(hex: "003366") }
        if lower.contains("cbs") { return Color(hex: "003366") }
        if lower.contains("abc") { return Color(hex: "000000") }
        if lower.contains("tnt") || lower.contains("tbs") { return Color(hex: "E2231A") }
        return Color.white.opacity(0.15)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sportscourt")
                .scaledFont(size: 28)
                .foregroundStyle(Color.white.opacity(0.3))
            Text("No \(section.title.lowercased()) games\(sportFilter == "All" ? "" : " for \(sportFilter)").")
                .scaledFont(size: 13, weight: .medium)
                .foregroundStyle(Color.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

#Preview {
    NavigationStack {
        SportsListView(
            games: [],
            section: .live,
            sportFilter: "All"
        )
    }
    .preferredColorScheme(.dark)
}

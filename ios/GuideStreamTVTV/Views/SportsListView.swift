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

// MARK: - Team Logo Badge

/// Reusable team logo badge. With a non-blank logo URL it draws a rounded
/// rectangle at 7% team colour with the logo scaled to fit and inset. With
/// a missing or failed logo it falls back to the full-colour abbreviation
/// badge. The badge is always `size × size`.
struct TeamLogoBadge: View {
    let team: GameTeam
    let size: CGFloat
    let cornerRadius: CGFloat
    let inset: CGFloat
    let abbreviationFontSize: CGFloat

    private var fillColor: Color {
        team.primaryHex.map { Color(hex: $0) } ?? Color.white.opacity(0.2)
    }

    private var logoFillColor: Color {
        team.primaryHex.map { Color(hex: $0).opacity(0.07) } ?? Color.white.opacity(0.07)
    }

    var body: some View {
        if let logoURL = team.logoURL,
           !logoURL.isEmpty,
           let url = URL(string: logoURL) {
            AsyncImage(url: url) { phase in
                Group {
                    switch phase {
                    case .success(let image):
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(logoFillColor)
                            .frame(width: size, height: size)
                            .overlay {
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .padding(inset)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    case .empty:
                        // Loading — quiet placeholder at the same size, radius
                        // and 7% tint as the loaded state so the crest fades in
                        // instead of the solid abbreviation square flashing
                        // first.
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(logoFillColor)
                            .frame(width: size, height: size)
                    case .failure:
                        fallbackBadge
                    @unknown default:
                        fallbackBadge
                    }
                }
                .animation(.easeOut(duration: 0.2), value: phaseKey(phase))
            }
        } else {
            fallbackBadge
        }
    }

    /// Stable Equatable key for the load phase so the badge can cross-fade
    /// between states — AsyncImagePhase itself does not conform to Equatable.
    private func phaseKey(_ phase: AsyncImagePhase) -> Int {
        switch phase {
        case .empty: return 0
        case .success: return 1
        case .failure: return 2
        @unknown default: return 3
        }
    }

    private var fallbackBadge: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(fillColor)
            .frame(width: size, height: size)
            .overlay {
                Text(team.abbreviation)
                    .scaledFont(size: abbreviationFontSize, weight: .black)
                    .foregroundStyle(.white)
            }
    }
}

/// Where the see-all list came from. Drives the navigation title.
enum SportsSection {
    case live, upcoming, finalGames

    var title: String {
        switch self {
        case .live: return "Live now"
        case .upcoming: return "Upcoming"
        case .finalGames: return "Final"
        }
    }
}

struct SportsListView: View {
    let games: [SportsGame]
    let section: SportsSection
    let sportFilter: String
    /// Game photos keyed by game id (sports_games.image_url) — the live rows
    /// draw them behind the scores. Empty for sections that do not use them.
    var images: [String: String] = [:]

    @State private var selectedGame: SportsGame?
    /// Focus is a thin white outline here too — `.plain` lays tvOS's white
    /// slab over the whole row.
    @FocusState private var focusedGameId: String?

    var body: some View {
        ZStack {
            Color(hex: "04090F").ignoresSafeArea()

            if games.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 28) {
                        ForEach(games) { game in
                            let isFocused = focusedGameId == game.id
                            Button {
                                selectedGame = game
                            } label: {
                                row(for: game)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.white.opacity(isFocused ? 1 : 0), lineWidth: 2)
                                    )
                                    .animation(.easeOut(duration: 0.15), value: isFocused)
                            }
                            .buttonStyle(TVFlatButtonStyle())
                            .focusEffectDisabled()
                            .focused($focusedGameId, equals: game.id)
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }
            }
        }
        .navigationTitle(navigationTitle)
        #if !os(tvOS)
        .toolbarBackground(Color(hex: "04090F"), for: .navigationBar)
        #endif
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
        VStack(spacing: 24) {
            HStack {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(hex: "E50914"))
                        .frame(width: 12, height: 12)
                    Text("LIVE")
                        .scaledFont(size: 24, weight: .black)
                        .foregroundStyle(Color(hex: "E50914"))
                    Text("\(game.sport) · \(game.scheduleLabel)")
                        .scaledFont(size: 24, weight: .semibold)
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineLimit(1)
                }
                Spacer()
                TVSportsWatchPill()
            }

            HStack {
                liveTeam(team: game.away, leading: true)
                Spacer()
                Text("VS")
                    .scaledFont(size: 28, weight: .bold)
                    .foregroundStyle(Color.white.opacity(0.3))
                Spacer()
                liveTeam(team: game.home, leading: false)
            }

            broadcastsRow(TVSportsSimulcast.ranked(game.broadcasts))
        }
        .padding(40)
        .background(TVSportsPhotoBackdrop(url: images[game.id]))
        .overlay(
            RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func liveTeam(team: GameTeam, leading: Bool) -> some View {
        let scoreColor: Color = team.isWinner ? .white : Color.white.opacity(0.55)
        return VStack(spacing: 8) {
            TVTeamCrestCircle(team: team, size: 130)
            Text(team.shortName)
                .scaledFont(size: 26, weight: .semibold)
                .foregroundStyle(Color.white.opacity(0.7))
                .lineLimit(1)
            Text(team.score)
                .scaledFont(size: 60, weight: .black)
                .foregroundStyle(scoreColor)
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
    }

    private func upcomingRow(_ game: SportsGame) -> some View {
        return VStack(spacing: 20) {
            HStack(spacing: 20) {
                TeamLogoBadge(team: game.away, size: 120, cornerRadius: 24, inset: 14, abbreviationFontSize: 26)
                Text("vs")
                    .scaledFont(size: 26, weight: .bold)
                    .foregroundStyle(Color.white.opacity(0.4))
                TeamLogoBadge(team: game.home, size: 120, cornerRadius: 24, inset: 14, abbreviationFontSize: 26)
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(game.away.shortName) vs \(game.home.shortName)")
                        .scaledFont(size: 32, weight: .bold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(game.sport) · \(game.scheduleLabel)")
                        .scaledFont(size: 24)
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                }
                .padding(.leading, 8)
                Spacer()
                Image(systemName: "chevron.right")
                    .scaledFont(size: 26, weight: .bold)
                    .foregroundStyle(Color.white.opacity(0.4))
            }

            broadcastsRow(TVSportsSimulcast.ranked(game.broadcasts))
        }
        .padding(40)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "161B27")))
        .overlay(
            RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func finalRow(_ game: SportsGame) -> some View {
        HStack(spacing: 32) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    TeamLogoBadge(team: game.away, size: 72, cornerRadius: 16, inset: 9, abbreviationFontSize: 18)
                    Text(game.away.abbreviation)
                        .scaledFont(size: 28, weight: .bold)
                        .foregroundStyle(game.away.isWinner ? .white : Color.white.opacity(0.55))
                    Spacer()
                    Text(game.away.score)
                        .scaledFont(size: 40, weight: .black)
                        .foregroundStyle(game.away.isWinner ? .white : Color.white.opacity(0.55))
                }
                HStack(spacing: 16) {
                    TeamLogoBadge(team: game.home, size: 72, cornerRadius: 16, inset: 9, abbreviationFontSize: 18)
                    Text(game.home.abbreviation)
                        .scaledFont(size: 28, weight: .bold)
                        .foregroundStyle(game.home.isWinner ? .white : Color.white.opacity(0.55))
                    Spacer()
                    Text(game.home.score)
                        .scaledFont(size: 40, weight: .black)
                        .foregroundStyle(game.home.isWinner ? .white : Color.white.opacity(0.55))
                }
            }
            .frame(width: 320)

            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 2, height: 120)

            VStack(alignment: .leading, spacing: 8) {
                Text(game.scheduleLabel)
                    .scaledFont(size: 26, weight: .bold)
                    .foregroundStyle(Color.white.opacity(0.7))
                Text(game.sport)
                    .scaledFont(size: 22, weight: .semibold)
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .scaledFont(size: 26, weight: .bold)
                .foregroundStyle(Color.white.opacity(0.4))
        }
        .padding(40)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: "12161F")))
        .overlay(
            RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func broadcastsRow(_ broadcasts: [String]) -> some View {
        if !broadcasts.isEmpty {
            HStack(spacing: 12) {
                Text("ON:")
                    .scaledFont(size: 22, weight: .bold)
                    .foregroundStyle(Color.white.opacity(0.45))
                ForEach(broadcasts.prefix(4), id: \.self) { name in
                    Text(name)
                        .scaledFont(size: 22, weight: .black)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10).fill(broadcastColor(name))
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
                .scaledFont(size: 56)
                .foregroundStyle(Color.white.opacity(0.3))
            Text("No \(section.title.lowercased()) games\(sportFilter == "All" ? "" : " for \(sportFilter)").")
                .scaledFont(size: 28, weight: .medium)
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

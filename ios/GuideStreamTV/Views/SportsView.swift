//
//  SportsView.swift
//  GuideStreamTV
//

import SwiftUI

// MARK: - Color(hex:) helper

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b, a: Double
        switch s.count {
        case 6:
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255
            a = 1
        case 8:
            r = Double((v >> 24) & 0xFF) / 255
            g = Double((v >> 16) & 0xFF) / 255
            b = Double((v >> 8) & 0xFF) / 255
            a = Double(v & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0; a = 1
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - SportsView

struct SportsView: View {
    @State private var selectedSport: String = "All"
    @State private var games: [SportsGame] = []
    @State private var isLoading: Bool = true
    @State private var loadError: String?

    private let sports: [String] = ["All", "NBA", "NFL", "Soccer", "MLB", "UFC"]

    private struct TeamChip {
        let abbrev: String
        let name: String
        let color: Color
        let next: String
    }

    private let myTeams: [TeamChip] = [
        TeamChip(abbrev: "NYK", name: "Knicks", color: Color(hex: "006BB6"), next: "Tonight"),
        TeamChip(abbrev: "MAN", name: "Man Utd", color: Color(hex: "C8102E"), next: "Sat"),
        TeamChip(abbrev: "DAL", name: "Cowboys", color: Color(hex: "003594"), next: "Sun")
    ]

    private var filteredGames: [SportsGame] {
        selectedSport == "All" ? games : games.filter { $0.sport == selectedSport }
    }

    private var liveGames: [SportsGame] { filteredGames.filter { $0.state == .live } }
    private var upcomingGames: [SportsGame] { filteredGames.filter { $0.state == .pre } }
    private var finalGames: [SportsGame] { filteredGames.filter { $0.state == .post } }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "04090F").ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        header
                        sportPills
                        myTeamsSection
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 1)

                        if isLoading && games.isEmpty {
                            loadingPlaceholder
                        } else if filteredGames.isEmpty {
                            emptyState
                        } else {
                            if !liveGames.isEmpty {
                                liveNowSection
                            }
                            if !upcomingGames.isEmpty {
                                upcomingSection
                            }
                            if !finalGames.isEmpty {
                                finalSection
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100)
                    .padding(.top, 12)
                }
                .refreshable { await load() }
                .tracksTabBarVisibility()
            }
            .navigationBarHidden(true)
        }
        .task { await load() }
    }

    private func load() async {
        if games.isEmpty { isLoading = true }
        let fetched = await SportsService.shared.fetchAll()
        await MainActor.run {
            self.games = fetched
            self.isLoading = false
            self.loadError = fetched.isEmpty ? "No games available right now." : nil
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("Guide")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
            Text("Stream")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color(hex: "F5821F"))
            Text(" TV")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.45))
            Spacer()
            if isLoading && !games.isEmpty {
                ProgressView()
                    .tint(Color(hex: "F5821F"))
                    .scaleEffect(0.8)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Sport pills

    private var sportPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sports, id: \.self) { sport in
                    let isActive = sport == selectedSport
                    Button {
                        selectedSport = sport
                    } label: {
                        Text(sport)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.5))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Group {
                                    if isActive {
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(Color(hex: "F5821F"))
                                    } else {
                                        Color.clear
                                    }
                                }
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(isActive ? Color.clear : Color.white.opacity(0.15), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - My Teams

    private var myTeamsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("My Teams")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("Edit")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "1A6FE8"))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(myTeams.enumerated()), id: \.offset) { _, team in
                        teamChip(team)
                    }
                    addTeamChip
                }
            }
        }
    }

    private func teamChip(_ team: TeamChip) -> some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 7)
                .fill(team.color)
                .frame(width: 26, height: 26)
                .overlay(
                    Text(team.abbrev)
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(.white)
                )
            Text(team.name)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.6))
            Text(team.next)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color(hex: "F5821F"))
        }
        .padding(8)
        .frame(minWidth: 58)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private var addTeamChip: some View {
        Button {
            // no-op
        } label: {
            VStack(spacing: 3) {
                Text("+")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.2))
                    .frame(width: 26, height: 26)
                Text("Add")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.4))
                Text(" ")
                    .font(.system(size: 8, weight: .bold))
            }
            .padding(8)
            .frame(minWidth: 58)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundStyle(Color.white.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Live Now

    private var liveNowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Live Now", count: liveGames.count)
            ForEach(liveGames) { game in
                liveScoreCard(game)
            }
        }
    }

    private func liveScoreCard(_ game: SportsGame) -> some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(hex: "E50914"))
                        .frame(width: 6, height: 6)
                    Text("LIVE")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(Color(hex: "E50914"))
                    Text("\(game.sport) · \(game.statusDetail)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer()
                NavigationLink(destination: GameDetailView()) {
                    Text("Watch ▶")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 20).fill(Color(hex: "F5821F"))
                        )
                }
                .buttonStyle(.plain)
            }

            HStack {
                liveTeamBlock(team: game.away, leading: true)
                Spacer()
                Text("VS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.2))
                Spacer()
                liveTeamBlock(team: game.home, leading: false)
            }

            broadcastsRow(game.broadcasts)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16).fill(Color(hex: "161B27"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func liveTeamBlock(team: GameTeam, leading: Bool) -> some View {
        let color = team.primaryHex.map { Color(hex: $0) } ?? Color.white.opacity(0.2)
        let scoreColor: Color = team.isWinner ? .white : Color.white.opacity(0.55)
        return VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 10)
                .fill(color)
                .frame(width: 38, height: 38)
                .overlay(
                    Text(team.abbreviation)
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white)
                )
            Text(team.shortName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.6))
                .lineLimit(1)
            Text(team.score)
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(scoreColor)
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
    }

    // MARK: - Upcoming

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: upcomingTitle, count: upcomingGames.count)
            ForEach(upcomingGames.prefix(8)) { game in
                upcomingGameCard(game)
            }
        }
    }

    private var upcomingTitle: String {
        let cal = Calendar.current
        if let first = upcomingGames.first, cal.isDateInToday(first.startDate) {
            return "Tonight"
        }
        return "Upcoming"
    }

    private func upcomingGameCard(_ game: SportsGame) -> some View {
        let awayColor = game.away.primaryHex.map { Color(hex: $0) } ?? Color.white.opacity(0.2)
        let homeColor = game.home.primaryHex.map { Color(hex: $0) } ?? Color.white.opacity(0.2)

        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(awayColor)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Text(game.away.abbreviation)
                            .font(.system(size: 7, weight: .black))
                            .foregroundStyle(.white)
                    )
                Text("vs")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.3))
                RoundedRectangle(cornerRadius: 8)
                    .fill(homeColor)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Text(game.home.abbreviation)
                            .font(.system(size: 7, weight: .black))
                            .foregroundStyle(.white)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(game.away.shortName) vs \(game.home.shortName)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(game.sport) · \(game.statusDetail)")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.4))
                        .lineLimit(1)
                }
                Spacer()
                Button { } label: {
                    Text("+ Alert")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            broadcastsRow(game.broadcasts)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16).fill(Color(hex: "161B27"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    // MARK: - Final

    private var finalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Final", count: finalGames.count)
            ForEach(finalGames.prefix(6)) { game in
                finalGameCard(game)
            }
        }
    }

    private func finalGameCard(_ game: SportsGame) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(game.away.abbreviation)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(game.away.isWinner ? .white : Color.white.opacity(0.5))
                    Spacer()
                    Text(game.away.score)
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(game.away.isWinner ? .white : Color.white.opacity(0.5))
                }
                HStack(spacing: 6) {
                    Text(game.home.abbreviation)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(game.home.isWinner ? .white : Color.white.opacity(0.5))
                    Spacer()
                    Text(game.home.score)
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(game.home.isWinner ? .white : Color.white.opacity(0.5))
                }
            }
            .frame(width: 110)

            Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(game.statusDetail)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.55))
                Text(game.sport)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(Color(hex: "12161F"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    // MARK: - Broadcasts row

    @ViewBuilder
    private func broadcastsRow(_ broadcasts: [String]) -> some View {
        if !broadcasts.isEmpty {
            HStack(spacing: 6) {
                Text("ON:")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.35))
                ForEach(broadcasts.prefix(4), id: \.self) { name in
                    Text(name)
                        .font(.system(size: 9, weight: .black))
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
        if lower.contains("tnt") { return Color(hex: "E2231A") }
        if lower.contains("tbs") { return Color(hex: "E2231A") }
        return Color.white.opacity(0.15)
    }

    // MARK: - States

    private var loadingPlaceholder: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.04))
                    .frame(height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
            }
        }
        .redacted(reason: .placeholder)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sportscourt")
                .font(.system(size: 28))
                .foregroundStyle(Color.white.opacity(0.3))
            Text(loadError ?? "No \(selectedSport) games today.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Helpers

    private func sectionHeader(title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
            Text("\(count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(Color.white.opacity(0.08))
                )
            Spacer()
            Text("See all")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: "1A6FE8"))
        }
    }
}

#Preview {
    SportsView()
        .preferredColorScheme(.dark)
}

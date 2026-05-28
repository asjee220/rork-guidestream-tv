//
//  SportsView.swift
//  GuideStreamTV
//

import SwiftUI
import UIKit

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

// MARK: - Routes

enum SportsRoute: Hashable {
    case allLive
    case allUpcoming
    case allFinal
}

// MARK: - SportsView

struct SportsView: View {
    @State private var selectedSport: String = "All"
    @State private var games: [SportsGame] = []
    @State private var isLoading: Bool = true
    @State private var loadError: String?
    @State private var path: [SportsRoute] = []
    @State private var selectedGame: SportsGame?
    @State private var showServicesSheet: Bool = false
    @State private var auth = AuthViewModel.shared

    private let sports: [String] = ["All", "NBA", "NFL", "Soccer", "MLB", "UFC"]

    private struct TeamChip: Hashable {
        let abbrev: String
        let name: String
        let color: Color
        let next: String
        let isLive: Bool
    }

    private var filteredGames: [SportsGame] {
        selectedSport == "All" ? games : games.filter { $0.sport == selectedSport }
    }

    private var liveGames: [SportsGame] { filteredGames.filter { $0.state == .live } }
    private var upcomingGames: [SportsGame] { filteredGames.filter { $0.state == .pre } }
    private var finalGames: [SportsGame] { filteredGames.filter { $0.state == .post } }

    /// Real "My Teams" derived from the day's live + upcoming games. Unique
    /// teams ordered by live > today > later; capped at 5 chips so the rail
    /// stays compact. The "Edit" affordance is a stub — a real favorites
    /// store would replace this derivation.
    private var derivedTeams: [TeamChip] {
        let cal = Calendar.current
        let pool = (liveGames + upcomingGames).filter {
            $0.state == .live || cal.isDateInToday($0.startDate) || $0.startDate.timeIntervalSinceNow < 60 * 60 * 24 * 7
        }
        var seen = Set<String>()
        var chips: [TeamChip] = []
        for game in pool {
            for team in [game.away, game.home] {
                guard !team.abbreviation.isEmpty, team.abbreviation != "—" else { continue }
                if seen.contains(team.abbreviation) { continue }
                seen.insert(team.abbreviation)
                let color = team.primaryHex.map { Color(hex: $0) } ?? Color.white.opacity(0.15)
                let label = nextLabel(for: game, cal: cal)
                chips.append(TeamChip(
                    abbrev: team.abbreviation,
                    name: team.shortName,
                    color: color,
                    next: label,
                    isLive: game.state == .live
                ))
                if chips.count >= 5 { break }
            }
            if chips.count >= 5 { break }
        }
        return chips
    }

    private func nextLabel(for game: SportsGame, cal: Calendar) -> String {
        if game.state == .live { return "LIVE" }
        let f = DateFormatter()
        if cal.isDateInToday(game.startDate) {
            f.dateFormat = "h:mm a"
            return f.string(from: game.startDate)
        }
        f.dateFormat = "EEE"
        return f.string(from: game.startDate)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color(hex: "04090F").ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        header
                        sportPills
                        if !derivedTeams.isEmpty {
                            myTeamsSection
                            Rectangle()
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 1)
                        }

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
            .navigationDestination(for: SportsRoute.self) { route in
                switch route {
                case .allLive:
                    SportsListView(games: liveGames, section: .live, sportFilter: selectedSport)
                case .allUpcoming:
                    SportsListView(games: upcomingGames, section: .upcoming, sportFilter: selectedSport)
                case .allFinal:
                    SportsListView(games: finalGames, section: .finalGames, sportFilter: selectedSport)
                }
            }
            #if os(tvOS)
            .fullScreenCover(item: $selectedGame) { game in
                SportsWatchSheet(game: game)
            }
            .fullScreenCover(isPresented: $showServicesSheet) {
                ServicesBottomSheet()
            }
            #else
            .sheet(item: $selectedGame) { game in
                SportsWatchSheet(game: game)
            }
            .sheet(isPresented: $showServicesSheet) {
                ServicesBottomSheet()
            }
            #endif
        }
        .task { await load() }
    }

    /// Selected service ids in catalogue order — keeps the pill's stacked icons
    /// in the same priority as the onboarding grid.
    private var orderedSelectedServiceIds: [String] {
        StreamingCatalog.ordered(from: auth.selectedServices).map { $0.id }
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
        HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Guide")
                    .scaledFont(size: 22, weight: .semibold)
                    .foregroundStyle(.white)
                Text("Stream")
                    .scaledFont(size: 22, weight: .semibold)
                    .foregroundStyle(Color(hex: "F5821F"))
                Text(" TV")
                    .scaledFont(size: 16, weight: .regular)
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            if !orderedSelectedServiceIds.isEmpty {
                ServicesPill(
                    serviceIds: orderedSelectedServiceIds,
                    onTap: { showServicesSheet = true }
                )
                .padding(.leading, 4)
            }
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
                            .scaledFont(size: 12, weight: .bold)
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

    // MARK: - My Teams (derived from real games)

    private var myTeamsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("My Teams")
                    .scaledFont(size: 16, weight: .bold)
                    .foregroundStyle(.white)
                Spacer()
                Text("Edit")
                    .scaledFont(size: 13, weight: .medium)
                    .foregroundStyle(Color(hex: "1A6FE8"))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(derivedTeams, id: \.abbrev) { team in
                        Button {
                            if let game = teamGame(for: team) {
                                selectedGame = game
                            }
                        } label: {
                            teamChip(team)
                        }
                        .buttonStyle(.plain)
                    }
                    addTeamChip
                }
            }
        }
    }

    /// Finds the next game involving `team` so tapping a chip opens that
    /// game's sheet rather than a dead-end.
    private func teamGame(for team: TeamChip) -> SportsGame? {
        let abbr = team.abbrev
        return (liveGames + upcomingGames).first { game in
            game.away.abbreviation == abbr || game.home.abbreviation == abbr
        }
    }

    private func teamChip(_ team: TeamChip) -> some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 7)
                .fill(team.color)
                .frame(width: 26, height: 26)
                .overlay(
                    Text(team.abbrev)
                        .scaledFont(size: 7, weight: .black)
                        .foregroundStyle(.white)
                )
            Text(team.name)
                .scaledFont(size: 9, weight: .semibold)
                .foregroundStyle(Color.white.opacity(0.6))
                .lineLimit(1)
            Text(team.next)
                .scaledFont(size: 8, weight: .bold)
                .foregroundStyle(team.isLive ? Color(hex: "E50914") : Color(hex: "F5821F"))
        }
        .padding(8)
        .frame(minWidth: 64)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(team.isLive ? Color(hex: "E50914").opacity(0.35) : Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private var addTeamChip: some View {
        Button {
            // Placeholder — real favorites flow lives in Profile.
        } label: {
            VStack(spacing: 3) {
                Text("+")
                    .scaledFont(size: 18, weight: .bold)
                    .foregroundStyle(Color.white.opacity(0.2))
                    .frame(width: 26, height: 26)
                Text("Add")
                    .scaledFont(size: 9, weight: .semibold)
                    .foregroundStyle(Color.white.opacity(0.4))
                Text(" ")
                    .scaledFont(size: 8, weight: .bold)
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

    // MARK: - Helper for tappable card wrapper

    /// Wraps a card view in a Button that opens the SportsWatchSheet. Uses
    /// `.plain` style so the visual layout is preserved exactly.
    @ViewBuilder
    private func tappableCard<Content: View>(_ game: SportsGame, @ViewBuilder content: () -> Content) -> some View {
        Button {
            selectedGame = game
        } label: {
            content()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Live Now

    private var liveNowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Live Now", count: liveGames.count) {
                path.append(.allLive)
            }
            ForEach(liveGames.prefix(4)) { game in
                tappableCard(game) {
                    liveScoreCard(game)
                }
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
                        .scaledFont(size: 9, weight: .black)
                        .foregroundStyle(Color(hex: "E50914"))
                    Text("\(game.sport) · \(game.statusDetail)")
                        .scaledFont(size: 9, weight: .semibold)
                        .foregroundStyle(Color.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer()
                // The "Watch ▶" affordance now shares the same handler as the
                // whole card — opens the SportsWatchSheet for this game.
                Text("Watch ▶")
                    .scaledFont(size: 11, weight: .bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 20).fill(Color(hex: "F5821F"))
                    )
            }

            HStack {
                liveTeamBlock(team: game.away, leading: true)
                Spacer()
                Text("VS")
                    .scaledFont(size: 11, weight: .bold)
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

    // MARK: - Upcoming

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: upcomingTitle, count: upcomingGames.count) {
                path.append(.allUpcoming)
            }
            ForEach(upcomingGames.prefix(8)) { game in
                tappableCard(game) {
                    upcomingGameCard(game)
                }
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
                    .foregroundStyle(Color.white.opacity(0.35))
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
            sectionHeader(title: "Final", count: finalGames.count) {
                path.append(.allFinal)
            }
            ForEach(finalGames.prefix(6)) { game in
                tappableCard(game) {
                    finalGameCard(game)
                }
            }
        }
    }

    private func finalGameCard(_ game: SportsGame) -> some View {
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
                .foregroundStyle(Color.white.opacity(0.35))
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
                .scaledFont(size: 28)
                .foregroundStyle(Color.white.opacity(0.3))
            Text(loadError ?? "No \(selectedSport) games today.")
                .scaledFont(size: 13, weight: .medium)
                .foregroundStyle(Color.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Helpers

    private func sectionHeader(title: String, count: Int, onSeeAll: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .scaledFont(size: 16, weight: .bold)
                .foregroundStyle(.white)
            Text("\(count)")
                .scaledFont(size: 11, weight: .bold)
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(Color.white.opacity(0.08))
                )
            Spacer()
            Button(action: onSeeAll) {
                HStack(spacing: 4) {
                    Text("See all")
                        .scaledFont(size: 13, weight: .medium)
                    Image(systemName: "arrow.right")
                        .scaledFont(size: 11, weight: .bold)
                }
                .foregroundStyle(Color(hex: "1A6FE8"))
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    SportsView()
        .preferredColorScheme(.dark)
}

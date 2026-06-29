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
    case gameDetail(SportsGame)
}

// MARK: - SportsView

struct SportsView: View {
    @Environment(AppRouter.self) private var router
    @State private var selectedSport: String = "All"
    @State private var games: [SportsGame] = []
    @State private var isLoading: Bool = true
    @State private var loadError: String?
    @State private var path: [SportsRoute] = []
    @State private var selectedGame: SportsGame?
    @State private var showServicesSheet: Bool = false
    @State private var auth = AuthViewModel.shared
    @State private var favorites = TeamFavoritesService.shared
    @State private var isEditingTeams: Bool = false

    private let sports: [String] = ["All", "NBA", "NFL", "Soccer", "MLB", "UFC"]

    private struct TeamChip: Hashable {
        let abbrev: String
        let name: String
        let color: Color
        let next: String
        let isLive: Bool
        let teamUid: String
    }

    private var filteredGames: [SportsGame] {
        selectedSport == "All" ? games : games.filter { $0.sport == selectedSport }
    }

    private var liveGames: [SportsGame] { filteredGames.filter { $0.state == .live } }
    private var upcomingGames: [SportsGame] { filteredGames.filter { $0.state == .pre } }
    private var finalGames: [SportsGame] { filteredGames.filter { $0.state == .post } }

    /// Real "My Teams" built from the user's persisted favorites via
    /// TeamFavoritesService. Each chip shows the stored team_abbr/team_name,
    /// finds its most relevant game in the already-loaded sports data, and
    /// displays a live/upcoming/final status label.
    private var favoriteTeams: [TeamChip] {
        return favorites.favoriteUids().compactMap { uid -> TeamChip? in
            guard let row = favorites.rows[uid] else { return nil }
            let game = findGameForFavorite(teamUid: uid, teamAbbr: row.team_abbr)
            let color: Color = {
                if let game {
                    if game.away.uid == uid, let hex = game.away.primaryHex { return Color(hex: hex) }
                    if game.home.uid == uid, let hex = game.home.primaryHex { return Color(hex: hex) }
                }
                return Color.white.opacity(0.15)
            }()
            let label = statusLabel(for: game)
            return TeamChip(
                abbrev: row.team_abbr ?? String((row.team_name ?? uid).prefix(3)).uppercased(),
                name: row.team_name ?? row.team_abbr ?? "",
                color: color,
                next: label,
                isLive: game?.state == .live,
                teamUid: uid
            )
        }
    }

    /// Finds the most relevant game for a favorited team: prefers a live game,
    /// then the soonest upcoming, then the most recent final. Matches by
    /// team_uid first, falling back to abbreviation if uid is nil.
    private func findGameForFavorite(teamUid: String, teamAbbr: String?) -> SportsGame? {
        func matches(_ game: SportsGame) -> Bool {
            if game.away.uid == teamUid || game.home.uid == teamUid { return true }
            if let abbr = teamAbbr {
                return game.away.abbreviation == abbr || game.home.abbreviation == abbr
            }
            return false
        }
        if let live = games.first(where: { $0.state == .live && matches($0) }) { return live }
        let upcoming = games.filter { $0.state == .pre && matches($0) }.sorted { a, b in a.startDate < b.startDate }
        if let next = upcoming.first { return next }
        let finals = games.filter { $0.state == .post && matches($0) }.sorted { a, b in a.startDate > b.startDate }
        if let recent = finals.first { return recent }
        return nil
    }

    private func statusLabel(for game: SportsGame?) -> String {
        guard let game else { return "No game scheduled" }
        if game.state == .live { return "LIVE" }
        let cal = Calendar.current
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
                        if !favoriteTeams.isEmpty {
                            myTeamsSection
                            Rectangle()
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 1)
                        } else {
                            noFavoritesPrompt
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
                case .gameDetail(let game):
                    SportsGameDetailView(game: game)
                }
            }
            .sheet(item: $selectedGame) { game in
                SportsWatchSheet(game: game)
            }
            .sheet(isPresented: $showServicesSheet) {
                ServicesBottomSheet()
            }
        }
        .task {
            await favorites.load()
            await load()
        }
        .onChange(of: router.pendingSportsRoute) { _, route in
            if let route {
                path.append(route)
                router.pendingSportsRoute = nil
            }
        }
        .onAppear {
            if let route = router.pendingSportsRoute {
                path.append(route)
                router.pendingSportsRoute = nil
            }
            Task { await favorites.load() }
        }
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

    /// Mirrors the home screen's PageBar — same BrandWordmark, same
    /// ServicesPill with the same tap-to-edit-services behaviour, and
    /// a trailing ProgressView when a background refresh is in flight.
    private var header: some View {
        HStack(spacing: 10) {
            BrandWordmark(wordmarkSize: .nav)
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
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    // MARK: - Sport pills

    private var sportPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sports, id: \.self) { sport in
                    let isActive = sport == selectedSport
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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

    // MARK: - My Teams (from real favorites)

    private var myTeamsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("My Teams")
                    .scaledFont(size: 16, weight: .bold)
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeOut(duration: 0.2)) {
                        isEditingTeams.toggle()
                    }
                } label: {
                    Text(isEditingTeams ? "Done" : "Edit")
                        .scaledFont(size: 13, weight: .medium)
                        .foregroundStyle(Color(hex: "1A6FE8"))
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(favoriteTeams, id: \.teamUid) { team in
                        teamChipView(team)
                    }
                }
            }
        }
    }

    /// Renders a single team chip. In edit mode, shows an unfavorite (x)
    /// affordance; tapping the chip body opens the matched game.
    private func teamChipView(_ team: TeamChip) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if let game = findGameForFavorite(teamUid: team.teamUid, teamAbbr: team.abbrev) {
                    selectedGame = game
                }
            } label: {
                teamChipContent(team)
            }
            .buttonStyle(.plain)

            if isEditingTeams {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task {
                        let row = favorites.rows[team.teamUid]
                        let dummyTeam = GameTeam(
                            id: nil,
                            uid: team.teamUid,
                            abbreviation: team.abbrev,
                            displayName: team.name,
                            shortName: team.name,
                            score: "0",
                            primaryHex: nil,
                            isWinner: false
                        )
                        await favorites.toggle(
                            team: dummyTeam,
                            league: row?.league,
                            sport: row?.sport
                        )
                    }
                } label: {
                    Image(systemName: "xmark")
                        .scaledFont(size: 10, weight: .bold)
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color(hex: "E50914")))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
            }
        }
    }

    /// Prompt shown when the user has no favorited teams yet.
    private var noFavoritesPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("My Teams")
                .scaledFont(size: 16, weight: .bold)
                .foregroundStyle(.white)
            HStack(spacing: 8) {
                Image(systemName: "star")
                    .scaledFont(size: 14)
                    .foregroundStyle(Color.orange.opacity(0.7))
                Text("Tap the star on any game to favorite a team and see it here.")
                    .scaledFont(size: 13, weight: .medium)
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineLimit(2)
            }
            .padding(.vertical, 8)
        }
    }

    private func teamChipContent(_ team: TeamChip) -> some View {
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

    // MARK: - Helper for tappable card wrapper

    /// Wraps a card view in a Button that opens the SportsWatchSheet. Uses
    /// `.plain` style so the visual layout is preserved exactly.
    @ViewBuilder
    private func tappableCard<Content: View>(_ game: SportsGame, @ViewBuilder content: () -> Content) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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

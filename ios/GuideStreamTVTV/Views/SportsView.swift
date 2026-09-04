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
    @State private var favorites = TVTeamFavoritesService.shared
    /// Non-nil while the picker is up; carries which mode it opened in.
    @State private var picker: TVTeamPickerView.Mode?
    /// GUI-95 — the week grid of games for followed teams.
    @State private var showSchedule: Bool = false

    // Focus is drawn by the controls themselves on this screen — a thin
    // white outline on the item's own shape. tvOS's `.plain` button style
    // lays a white slab over whatever it wraps even with
    // .focusEffectDisabled(), which is why every control here uses
    // TVFlatButtonStyle and reads its own focus state instead.
    @FocusState private var focusedSport: String?
    @FocusState private var focusedTeam: String?
    @FocusState private var focusedGameId: String?
    /// One-shot: a viewer with no teams is offered the picker the first time
    /// they open Sports, and never again whatever they choose. Same key the
    /// phone uses, but UserDefaults is per-device, so the Apple TV asks once
    /// of its own accord.
    @AppStorage("gs.sportsTeamPickerSeen.v1") private var hasSeenPicker = false

    private let sports: [String] = ["All", "NFL", "CFB", "NBA", "NBA Summer", "WNBA", "NCAA Men", "NCAA Women", "MLB", "Soccer", "UFC"]

    private struct TeamChip: Hashable {
        let abbrev: String
        let name: String
        let color: Color
        let next: String
        let isLive: Bool
        let logoURL: String?
        let team: TVGameTeam
    }

    private var filteredGames: [SportsGame] {
        selectedSport == "All" ? games : games.filter { $0.sport == selectedSport }
    }

    private var liveGames: [SportsGame] { filteredGames.filter { $0.state == .live } }
    private var upcomingGames: [SportsGame] { filteredGames.filter { $0.state == .pre } }
    private var finalGames: [SportsGame] { filteredGames.filter { $0.state == .post } }

    /// My Teams, from the teams the viewer actually follows.
    ///
    /// This used to be derived from whichever teams happened to be playing
    /// today, capped at five — which meant the rail changed every day, showed
    /// teams nobody had asked for, and had an Edit button that did nothing.
    /// It now reads `team_favorites`, the same rows the phone writes, and
    /// each chip carries that team's own next game.
    private var favoriteTeams: [TeamChip] {
        let cal = Calendar.current
        return favorites.favoriteUids().compactMap { uid -> TeamChip? in
            let row = favorites.rows[uid]
            // Prefer the live game object: it carries the logo, the colour
            // and the score. Fall back to the stored row so a followed team
            // still shows a chip on a day it is not playing.
            let game = nextGame(forUid: uid)
            let team = game.flatMap { g in
                [g.away, g.home].first { $0.uid == uid }
            }
            let abbrev = team?.abbreviation ?? row?.team_abbr ?? ""
            let name = team?.shortName ?? row?.team_name ?? ""
            guard !abbrev.isEmpty || !name.isEmpty else { return nil }
            let color = team?.primaryHex.map { Color(hex: $0) } ?? Color.white.opacity(0.15)
            return TeamChip(
                abbrev: abbrev.isEmpty ? String(name.prefix(3)).uppercased() : abbrev,
                name: name.isEmpty ? abbrev : name,
                color: color,
                next: game.map { nextLabel(for: $0, cal: cal) } ?? "",
                isLive: game?.state == .live,
                logoURL: team?.logoURL,
                team: team ?? TVGameTeam(
                    id: row?.team_id,
                    uid: uid,
                    abbreviation: abbrev,
                    displayName: name,
                    shortName: name,
                    score: "",
                    primaryHex: nil,
                    isWinner: false
                )
            )
        }
        // Live first, then whoever plays soonest, then the rest by name, so
        // the chip worth pressing is the one nearest the left edge.
        .sorted { a, b in
            if a.isLive != b.isLive { return a.isLive }
            return a.name < b.name
        }
    }

    /// The followed team's next game: live if one is on, else the soonest
    /// upcoming, else the most recent final.
    private func nextGame(forUid uid: String) -> SportsGame? {
        func involves(_ game: SportsGame) -> Bool {
            game.away.uid == uid || game.home.uid == uid
        }
        if let live = liveGames.first(where: involves) { return live }
        if let next = upcomingGames
            .filter(involves)
            .sorted(by: { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) })
            .first { return next }
        return finalGames
            .filter(involves)
            .sorted(by: { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) })
            .first
    }

    private func nextLabel(for game: SportsGame, cal: Calendar) -> String {
        if game.state == .live { return "LIVE" }
        guard let date = game.startDate else { return "" }
        let f = DateFormatter()
        if cal.isDateInToday(date) {
            f.dateFormat = "h:mm a"
            return f.string(from: date)
        }
        f.dateFormat = "EEE"
        return f.string(from: date)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color(hex: "04090F").ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 34) {
                        header
                        sportPills
                        // Always shown now: with nothing followed the
                        // section is the invitation to follow something,
                        // which is the whole point of the screen having
                        // favourites at all.
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
                    .padding(.leading, 80)
                    .padding(.trailing, 40)
                    .padding(.bottom, 100)
                    .padding(.top, 12)
                }
                .refreshable { await load() }
                .tracksTabBarVisibility()
            }
            // A NavigationStack applies its own safe-area insets to its
            // content, which TVMainView's .ignoresSafeArea() cannot reach —
            // this and ProfileView were the only two screens still boxed in
            // after that change, and they are the only two with a stack.
            .ignoresSafeArea()
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
            .fullScreenCover(item: $picker) { mode in
                TVTeamPickerView(mode: mode) { picker = nil }
            }
            .fullScreenCover(isPresented: $showSchedule) {
                TVScheduleView(surface: .sports) { showSchedule = false }
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
        .task {
            await load()
            await favorites.load()
            // A viewer with nothing followed is offered the picker once, on
            // their first Sports visit. Whatever they do with it, the flag is
            // set, so the screen never asks again on its own.
            if !hasSeenPicker, favorites.favoriteUids().isEmpty {
                hasSeenPicker = true
                picker = .onboarding
            }
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

    private var header: some View {
        HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Guide")
                    .scaledFont(size: 33, weight: .semibold)
                    .foregroundStyle(.white)
                Text("Stream")
                    .scaledFont(size: 33, weight: .semibold)
                    .foregroundStyle(Color(hex: "F5821F"))
                Text(" TV")
                    .scaledFont(size: 24, weight: .regular)
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
            HStack(spacing: 14) {
                ForEach(sports, id: \.self) { sport in
                    let isActive = sport == selectedSport
                    let isFocused = focusedSport == sport
                    Button {
                        selectedSport = sport
                    } label: {
                        Text(sport)
                            .scaledFont(size: 28, weight: .bold)
                            .foregroundStyle(isActive || isFocused ? Color.white : Color.white.opacity(0.5))
                            .padding(.horizontal, 30)
                            .padding(.vertical, 16)
                            .background(
                                Group {
                                    if isActive {
                                        RoundedRectangle(cornerRadius: 32)
                                            .fill(Color(hex: "F5821F"))
                                    } else {
                                        Color.clear
                                    }
                                }
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 32)
                                    .stroke(
                                        isFocused ? Color.white : (isActive ? Color.clear : Color.white.opacity(0.15)),
                                        lineWidth: isFocused ? 2 : 1
                                    )
                            )
                            .animation(.easeOut(duration: 0.15), value: isFocused)
                    }
                    .buttonStyle(TVFlatButtonStyle())
                    .focusEffectDisabled()
                    .focused($focusedSport, equals: sport)
                }
            }
            .padding(.vertical, 4)
        }
        // Without this the row is not a focus destination of its own and an
        // up move from My Teams had nothing to land on — the league pills
        // could not be reached with the remote at all. Every other section
        // on this screen is already a focus section.
        .focusSection()
    }

    // MARK: - My Teams (derived from real games)

    private var myTeamsSection: some View {
        VStack(alignment: .leading, spacing: 34) {
            HStack {
                Text("My Teams")
                    .scaledFont(size: 24, weight: .bold)
                    .foregroundStyle(.white)
                Spacer()
                TVSecondaryButton(title: "Schedule", sectionKey: "my_teams_schedule") {
                    showSchedule = true
                }
                TVSecondaryButton(title: "Edit", sectionKey: "my_teams") {
                    picker = .edit
                }
            }
            .focusSection()

            if favoriteTeams.isEmpty {
                noFavoritesPrompt
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(favoriteTeams, id: \.abbrev) { team in
                            Button {
                                if let game = teamGame(for: team) {
                                    selectedGame = game
                                }
                            } label: {
                                teamChip(team, isFocused: focusedTeam == team.abbrev)
                            }
                            .buttonStyle(TVFlatButtonStyle())
                            .focusEffectDisabled()
                            .focused($focusedTeam, equals: team.abbrev)
                        }
                        addTeamChip
                    }
                }
                .focusSection()
            }
        }
    }

    /// Shown in place of the rail when nothing is followed yet — the same
    /// invitation the phone shows, rather than an empty row.
    private var noFavoritesPrompt: some View {
        HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Follow your teams")
                    .scaledFont(size: 26, weight: .bold)
                    .foregroundStyle(.white)
                Text("Their games lead this screen, and you get alerts when they start.")
                    .scaledFont(size: 20)
                    .foregroundStyle(TVTheme.textSecondary)
            }
            Spacer()
            TVSecondaryButton(title: "Pick teams", sectionKey: "my_teams_empty") {
                picker = .onboarding
            }
        }
        .padding(32)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07), lineWidth: 1))
        .focusSection()
    }

    /// Finds the next game involving `team` so tapping a chip opens that
    /// game's sheet rather than a dead-end.
    private func teamGame(for team: TeamChip) -> SportsGame? {
        if let uid = team.team.uid, let game = nextGame(forUid: uid) { return game }
        // A followed team with no uid on the card (an older stored row) still
        // matches on abbreviation.
        let abbr = team.abbrev
        return (liveGames + upcomingGames).first { game in
            game.away.abbreviation == abbr || game.home.abbreviation == abbr
        }
    }

    private func teamChip(_ team: TeamChip, isFocused: Bool = false) -> some View {
        VStack(spacing: 3) {
            TeamLogoBadge(team: team.team, size: 72, cornerRadius: 7, inset: 9, abbreviationFontSize: 11)
            Text(team.name)
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(Color.white.opacity(0.6))
                .lineLimit(1)
            if !team.next.isEmpty {
                Text(team.next)
                    .scaledFont(size: 12, weight: .bold)
                    .foregroundStyle(team.isLive ? Color(hex: "E50914") : Color(hex: "F5821F"))
            }
        }
        .padding(32)
        .frame(minWidth: 270, minHeight: 180)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isFocused
                        ? Color.white
                        : (team.isLive ? Color(hex: "E50914").opacity(0.35) : Color.white.opacity(0.07)),
                    lineWidth: isFocused ? 2 : 1
                )
        )
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }

    private var addTeamChip: some View {
        let isFocused = focusedTeam == "__add__"
        return Button {
            picker = .edit
        } label: {
            VStack(spacing: 3) {
                Text("+")
                    .scaledFont(size: 27, weight: .bold)
                    .foregroundStyle(Color.white.opacity(0.2))
                    .frame(width: 72, height: 72)
                Text("Add")
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(Color.white.opacity(0.4))
                Text(" ")
                    .scaledFont(size: 12, weight: .bold)
            }
            .padding(32)
            .frame(minWidth: 270, minHeight: 180)
            .overlay(
                Group {
                    if isFocused {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white, lineWidth: 2)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4]))
                            .foregroundStyle(Color.white.opacity(0.15))
                    }
                }
            )
            .animation(.easeOut(duration: 0.15), value: isFocused)
        }
        .buttonStyle(TVFlatButtonStyle())
        .focusEffectDisabled()
        .focused($focusedTeam, equals: "__add__")
    }

    // MARK: - Helper for tappable card wrapper

    /// Wraps a card view in a Button that opens the SportsWatchSheet.
    ///
    /// `.plain` used to be the style here "so the visual layout is preserved
    /// exactly" — but on tvOS it also lays a white slab over the whole card
    /// on focus, which is the overlay this screen was asked to stop using.
    /// TVFlatButtonStyle draws nothing, so the card keeps its own layout and
    /// focus is a thin white outline on its own shape.
    @ViewBuilder
    private func tappableCard<Content: View>(_ game: SportsGame, @ViewBuilder content: () -> Content) -> some View {
        let isFocused = focusedGameId == game.id
        Button {
            selectedGame = game
        } label: {
            content()
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

    // MARK: - Live Now

    private var liveNowSection: some View {
        VStack(alignment: .leading, spacing: 34) {
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
                        .scaledFont(size: 14, weight: .black)
                        .foregroundStyle(Color(hex: "E50914"))
                    Text("\(game.sport) · \(game.statusDetail)")
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(Color.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer()
                // The "Watch ▶" affordance now shares the same handler as the
                // whole card — opens the SportsWatchSheet for this game.
                Text("Watch ▶")
                    .scaledFont(size: 17, weight: .bold)
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
                    .scaledFont(size: 17, weight: .bold)
                    .foregroundStyle(Color.white.opacity(0.2))
                Spacer()
                liveTeamBlock(team: game.home, leading: false)
            }

            broadcastsRow(game.broadcasts)
        }
        .padding(46)
        .frame(minHeight: 210)
        .background(
            RoundedRectangle(cornerRadius: 16).fill(Color(hex: "161B27"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func liveTeamBlock(team: GameTeam, leading: Bool) -> some View {
        let scoreColor: Color = team.isWinner ? .white : Color.white.opacity(0.55)
        return VStack(spacing: 4) {
            TeamLogoBadge(team: team, size: 110, cornerRadius: 22, inset: 13, abbreviationFontSize: 14)
            Text(team.shortName)
                .scaledFont(size: 15, weight: .semibold)
                .foregroundStyle(Color.white.opacity(0.6))
                .lineLimit(1)
            Text(team.score)
                .scaledFont(size: 36, weight: .black)
                .foregroundStyle(scoreColor)
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
    }

    // MARK: - Upcoming

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 34) {
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
        if let first = upcomingGames.first, let date = first.startDate, cal.isDateInToday(date) {
            return "Tonight"
        }
        return "Upcoming"
    }

    private func upcomingGameCard(_ game: SportsGame) -> some View {
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                TeamLogoBadge(team: game.away, size: 110, cornerRadius: 22, inset: 13, abbreviationFontSize: 11)
                Text("vs")
                    .scaledFont(size: 17, weight: .bold)
                    .foregroundStyle(Color.white.opacity(0.3))
                TeamLogoBadge(team: game.home, size: 110, cornerRadius: 22, inset: 13, abbreviationFontSize: 11)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(game.away.shortName) vs \(game.home.shortName)")
                        .scaledFont(size: 20, weight: .bold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(game.sport) · \(game.statusDetail)")
                        .scaledFont(size: 15)
                        .foregroundStyle(Color.white.opacity(0.4))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .scaledFont(size: 18, weight: .bold)
                    .foregroundStyle(Color.white.opacity(0.35))
            }

            broadcastsRow(game.broadcasts)
        }
        .padding(46)
        .frame(minHeight: 210)
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
        VStack(alignment: .leading, spacing: 34) {
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
                    TeamLogoBadge(team: game.away, size: 110, cornerRadius: 22, inset: 13, abbreviationFontSize: 9)
                    Text(game.away.abbreviation)
                        .scaledFont(size: 17, weight: .bold)
                        .foregroundStyle(game.away.isWinner ? .white : Color.white.opacity(0.5))
                    Spacer()
                    Text(game.away.score)
                        .scaledFont(size: 21, weight: .black)
                        .foregroundStyle(game.away.isWinner ? .white : Color.white.opacity(0.5))
                }
                HStack(spacing: 6) {
                    TeamLogoBadge(team: game.home, size: 110, cornerRadius: 22, inset: 13, abbreviationFontSize: 9)
                    Text(game.home.abbreviation)
                        .scaledFont(size: 17, weight: .bold)
                        .foregroundStyle(game.home.isWinner ? .white : Color.white.opacity(0.5))
                    Spacer()
                    Text(game.home.score)
                        .scaledFont(size: 21, weight: .black)
                        .foregroundStyle(game.home.isWinner ? .white : Color.white.opacity(0.5))
                }
            }
            .frame(minWidth: 165)

            Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1, height: 54)

            VStack(alignment: .leading, spacing: 3) {
                Text(game.statusDetail)
                    .scaledFont(size: 15, weight: .bold)
                    .foregroundStyle(Color.white.opacity(0.55))
                Text(game.sport)
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(Color.white.opacity(0.35))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .scaledFont(size: 18, weight: .bold)
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .padding(46)
        .frame(minHeight: 210)
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
                    .scaledFont(size: 17, weight: .bold)
                    .foregroundStyle(Color.white.opacity(0.35))
                ForEach(broadcasts.prefix(4), id: \.self) { name in
                    Text(name)
                        .scaledFont(size: 17, weight: .black)
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
                    .frame(height: 180)
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
                .scaledFont(size: 42)
                .foregroundStyle(Color.white.opacity(0.3))
            Text(loadError ?? "No \(selectedSport) games today.")
                .scaledFont(size: 20, weight: .medium)
                .foregroundStyle(Color.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Helpers

    private func sectionHeader(title: String, count: Int, onSeeAll: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .scaledFont(size: 24, weight: .bold)
                .foregroundStyle(.white)
            Text("\(count)")
                .scaledFont(size: 17, weight: .bold)
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(Color.white.opacity(0.08))
                )
            Spacer()
            TVSecondaryButton(title: "See all",
                              sectionKey: title.lowercased().replacingOccurrences(of: " ", with: "_"),
                              action: onSeeAll)
        }
    }
}


#Preview {
    SportsView()
        .preferredColorScheme(.dark)
}

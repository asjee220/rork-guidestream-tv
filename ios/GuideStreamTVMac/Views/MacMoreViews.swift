//
//  MacMoreViews.swift
//  GuideStreamTVMac
//
//  Schedule (TVScheduleService), creator pages (TVCreatorService) and the
//  sports game sheet — the Apple TV data layer under Mac layouts.
//

import SwiftUI

// MARK: - Schedule

struct MacScheduleView: View {
    @State private var schedule = TVScheduleService.shared
    @State private var weekOffset = 0
    @Environment(\.openTitle) private var openTitle
    @Environment(\.openGame) private var openGame

    private var weekStart: Date {
        let base = TVScheduleWeek.start(of: Date())
        return Calendar.current.date(byAdding: .day, value: 7 * weekOffset, to: base) ?? base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left") }
                    .disabled(weekOffset <= 0)
                Text(TVScheduleWeek.rangeLabel(for: weekStart)).font(.system(size: 15, weight: .semibold))
                    .frame(minWidth: 140)
                Button { weekOffset += 1 } label: { Image(systemName: "chevron.right") }
                    .disabled(weekOffset >= TVScheduleWeek.maxOffset)
                if weekOffset != 0 { Button("This week") { weekOffset = 0 } }
                Spacer()
                if schedule.isLoadingEpisodes || schedule.isLoadingGames { ProgressView().controlSize(.small) }
            }
            .buttonStyle(.bordered)

            if !AuthViewModel.shared.isAuthenticated {
                MacEmptyState(icon: "calendar", title: "Sign in to see your schedule",
                              message: "Episodes of shows you save and games for teams you follow land here.")
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 7),
                              alignment: .leading, spacing: 10) {
                        ForEach(TVScheduleWeek.days(from: weekStart), id: \.self) { day in dayColumn(day) }
                    }
                }
            }
        }
        .padding(MacLayout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await TVStreamsViewModel.shared.fetchUserStreams(); await schedule.loadEpisodes() }
        .task(id: weekOffset) {
            await TVTeamFavoritesService.shared.load()
            await schedule.loadGames(weekStart: weekStart)
        }
    }

    private func dayColumn(_ day: Date) -> some View {
        let cal = Calendar.current
        let episodes = schedule.episodes.filter { cal.isDate($0.airDay, inSameDayAs: day) }
        let games = schedule.games.filter { $0.startDate.map { cal.isDate($0, inSameDayAs: day) } ?? false }
        let today = cal.isDateInToday(day)
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.system(size: 11, weight: .bold)).tracking(0.8)
                    .foregroundStyle(today ? MacColor.orange : MacColor.text3)
                Text(day.formatted(.dateTime.day())).font(.system(size: 20, weight: .bold))
                    .foregroundStyle(today ? MacColor.orange : .white)
            }
            if episodes.isEmpty && games.isEmpty {
                Text("—").font(.system(size: 12)).foregroundStyle(MacColor.text3)
            }
            ForEach(episodes) { ep in
                Button {
                    if let id = TVTitleID.tmdbId(from: ep.titleId) {
                        openTitle(MacTitleRef(titleId: "tmdb:tv:\(id)", tmdbId: id, isTV: true, title: ep.showTitle, posterUrl: ep.posterUrl))
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        TVRemoteImage(urlString: ep.posterUrl, contentMode: .fill)
                            .aspectRatio(2 / 3, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text(ep.showTitle).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                        Text(ep.isSeasonFinale ? "\(ep.episodeLabel) · Finale" : ep.episodeLabel)
                            .font(.system(size: 11)).foregroundStyle(ep.isSeasonFinale ? MacColor.orange : MacColor.text3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            ForEach(games) { g in
                Button { openGame(g) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(g.away.abbreviation) @ \(g.home.abbreviation)").font(.system(size: 12, weight: .bold))
                        Text(g.startDate?.formatted(date: .omitted, time: .shortened) ?? g.statusDetail)
                            .font(.system(size: 11)).foregroundStyle(MacColor.text3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(MacColor.elevated, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(today ? MacColor.orange.opacity(0.06) : MacColor.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(today ? MacColor.orange.opacity(0.4) : MacColor.hairline, lineWidth: 1))
    }
}

// MARK: - Creator page

struct MacCreatorRef: Identifiable, Hashable {
    let titleId: String
    var id: String { titleId }
}

// MARK: - Game sheet

struct MacGameSheet: View {
    let game: TVSportsGame
    @Environment(\.dismiss) private var dismiss
    @State private var favorites = TVTeamFavoritesService.shared
    /// D — "Wrong channel or time?"
    @State private var reportContext: ReportContext?

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Text(game.leagueShort.isEmpty ? game.sport : game.leagueShort.uppercased())
                    .font(.system(size: 12, weight: .bold)).tracking(1).foregroundStyle(MacColor.text2)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)) }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction)
            }
            HStack(alignment: .center, spacing: 24) {
                teamColumn(game.away)
                VStack(spacing: 6) {
                    if game.state == .pre {
                        Text(game.startDate?.formatted(date: .abbreviated, time: .shortened) ?? game.statusDetail)
                            .font(.system(size: 15, weight: .semibold))
                    } else {
                        Text("\(game.away.score) – \(game.home.score)").font(.system(size: 38, weight: .heavy)).monospacedDigit()
                        Text(game.statusDetail).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(game.state.isLive ? MacColor.live : MacColor.text2)
                    }
                }
                .frame(minWidth: 160)
                teamColumn(game.home)
            }
            if !game.broadcasts.isEmpty {
                VStack(spacing: 8) {
                    Text("WATCH ON").font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(MacColor.text3)
                    HStack(spacing: 8) {
                        ForEach(sortedBroadcasts, id: \.self) { b in
                            let mine = AuthViewModel.shared.subscribesToService(named: b)
                            Text(b).font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(mine ? MacColor.orange : MacColor.elevated, in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(mine ? Color(red: 0.03, green: 0.02, blue: 0.02) : .white)
                        }
                    }
                }
            }
            // D — report a wrong channel or start time for this game.
            MacReportProblemLink(prompt: "Wrong channel or time?") {
                reportContext = ReportContext(
                    kind: .sports,
                    entryPoint: "sports_link",
                    titleName: "\(game.away.displayName) vs \(game.home.displayName)",
                    providerName: sortedBroadcasts.first,
                    titleId: WatchIntentLogger.titleSlug("\(game.away.abbreviation)-\(game.home.abbreviation)-\(game.sport)"),
                    gameId: game.id
                )
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(MacColor.navy)
        .sheet(item: $reportContext) { ctx in
            MacReportProblemSheet(context: ctx, onClose: { reportContext = nil })
        }
        .onAppear {
            WatchIntentLogger.shared.log(eventType: .cardTapped,
                                         titleId: WatchIntentLogger.titleSlug("\(game.away.abbreviation)-\(game.home.abbreviation)-\(game.sport)"),
                                         platformId: (game.broadcasts.first ?? "").lowercased(),
                                         metadata: ["surface": "mac_game", "kind": "sport"])
        }
    }

    /// Services the viewer subscribes to first, as on the phone.
    private var sortedBroadcasts: [String] {
        game.broadcasts.enumerated().sorted { a, b in
            let sa = AuthViewModel.shared.subscribesToService(named: a.element)
            let sb = AuthViewModel.shared.subscribesToService(named: b.element)
            return sa != sb ? sa : a.offset < b.offset
        }.map(\.element)
    }

    private func teamColumn(_ t: TVGameTeam) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(Color.fromHex(t.primaryHex) ?? MacColor.elevated)
                if let logo = t.logoURL { TVRemoteImage(urlString: logo, contentMode: .fit).padding(12) }
                else { Text(t.abbreviation).font(.system(size: 16, weight: .bold)) }
            }
            .frame(width: 72, height: 72)
            Text(t.displayName).font(.system(size: 14, weight: .semibold)).multilineTextAlignment(.center).lineLimit(2)
            if t.uid != nil {
                Button {
                    Task { await favorites.toggle(team: t, league: game.leagueShort, sport: game.sport) }
                } label: {
                    Image(systemName: favorites.isFavorite(t.uid) ? "star.fill" : "star")
                        .foregroundStyle(favorites.isFavorite(t.uid) ? MacColor.orange : MacColor.text2)
                }
                .buttonStyle(.plain)
                .disabled(!AuthViewModel.shared.isAuthenticated)
                .help(favorites.isFavorite(t.uid) ? "Remove from My Teams" : "Add to My Teams")
            }
        }
        .frame(width: 150)
    }
}

// MARK: - Environment routes

private struct OpenGameKey: EnvironmentKey { static let defaultValue: (TVSportsGame) -> Void = { _ in } }
private struct OpenCreatorKey: EnvironmentKey { static let defaultValue: (String) -> Void = { _ in } }

extension EnvironmentValues {
    var openGame: (TVSportsGame) -> Void {
        get { self[OpenGameKey.self] }
        set { self[OpenGameKey.self] = newValue }
    }
    /// Opens the creator sheet for a "yt:", "tw:", "kick:" or "pod:" title id.
    var openCreator: (String) -> Void {
        get { self[OpenCreatorKey.self] }
        set { self[OpenCreatorKey.self] = newValue }
    }
}

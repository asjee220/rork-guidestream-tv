//
//  ScheduleView.swift
//  GuideStreamTV
//
//  GUI-95 — the Schedule week view on the phone.
//
//  Layout is the day list, not a seven-column calendar grid: a week strip
//  pinned above a scroll of per-day sections. The grid was mocked alongside it
//  and lost on the merits — a phone-width day cell fits two crests before it
//  truncates and has no room at all for a kickoff time or a network, so every
//  cell needs a tap before it says anything. The list truncates nothing.
//
//  One view serves both entry points; `surface` is the only thing that differs.
//

import SwiftUI
import UIKit

// MARK: - Surface

enum ScheduleSurface: Hashable {
    /// Reached from Sports → My Teams. Shows games for favorited teams.
    case sports
    /// Reached from Watchlist → Shows. Shows episodes for saved series.
    case watchlist

    var kicker: String {
        switch self {
        case .sports: return "My Teams"
        case .watchlist: return "Watchlist"
        }
    }

    var accent: Color {
        switch self {
        case .sports: return Color(hex: "F5821F")
        case .watchlist: return Color(hex: "1A6FE8")
        }
    }
}

// MARK: - Schedule

struct ScheduleView: View {
    let surface: ScheduleSurface

    @State private var schedule = ScheduleService.shared
    @State private var weekOffset: Int = 0
    @State private var selectedGame: SportsGame?
    @State private var detailSubject: DetailSubject?

    private let calendar = Calendar.current
    private var today: Date { Date() }
    private var weekStart: Date {
        calendar.date(
            byAdding: .day,
            value: weekOffset * 7,
            to: ScheduleWeek.start(of: today, calendar: calendar)
        ) ?? ScheduleWeek.start(of: today, calendar: calendar)
    }
    private var days: [Date] { ScheduleWeek.days(from: weekStart, calendar: calendar) }

    private var isLoading: Bool {
        surface == .sports ? schedule.isLoadingGames : schedule.isLoadingEpisodes
    }

    /// Days that have something on them, in week order. Drives both the strip
    /// dots and the "is this week empty" decision, so the two can never
    /// disagree.
    private var populatedDays: [Date] {
        days.filter { !isEmptyDay($0) }
    }

    var body: some View {
        ZStack {
            Color(hex: "04090F").ignoresSafeArea()

            VStack(spacing: 0) {
                weekNav
                weekStrip
                Divider().overlay(Color.white.opacity(0.06))
                dayScroll
            }
        }
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(hex: "04090F"), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .task(id: weekStart) { await load() }
        .sheet(item: $selectedGame) { game in
            SportsWatchSheet(game: game)
        }
        .sheet(item: $detailSubject) { subject in
            EpisodeDetailSheet(subject: subject, level: .raised)
        }
    }

    // MARK: - Loading

    private func load() async {
        switch surface {
        case .sports:
            await schedule.loadGames(weekStart: weekStart)
        case .watchlist:
            // Episodes are resolved once for the whole season and sliced per
            // week locally, so paging costs nothing after the first load.
            if schedule.episodes.isEmpty {
                await schedule.loadEpisodes()
            }
        }
    }

    // MARK: - Week navigation

    private var weekNav: some View {
        HStack(spacing: 8) {
            arrow(systemName: "chevron.left", delta: -1, enabled: weekOffset > -ScheduleWeek.maxOffset)

            VStack(spacing: 1) {
                Text(ScheduleWeek.rangeLabel(for: weekStart, calendar: calendar))
                    .scaledFont(size: 15, weight: .bold)
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text(surface.kicker)
                    .scaledFont(size: 10, weight: .semibold)
                    .foregroundStyle(Color.white.opacity(0.35))
                    .textCase(.uppercase)
            }
            .frame(maxWidth: .infinity)

            arrow(systemName: "chevron.right", delta: 1, enabled: weekOffset < ScheduleWeek.maxOffset)
        }
        .overlay(alignment: .trailing) {
            if isLoading {
                ProgressView()
                    .tint(surface.accent)
                    .scaleEffect(0.7)
                    .offset(x: 0, y: -22)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private func arrow(systemName: String, delta: Int, enabled: Bool) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            weekOffset += delta
        } label: {
            Image(systemName: systemName)
                .scaledFont(size: 13, weight: .bold)
                .foregroundStyle(enabled ? Color.white : Color.white.opacity(0.2))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(enabled ? 0.07 : 0.03))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(delta < 0 ? "Previous week" : "Next week")
    }

    // MARK: - Week strip

    private var weekStrip: some View {
        HStack(spacing: 6) {
            ForEach(days, id: \.self) { day in
                dayChip(day)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private func dayChip(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        let hasItems = !isEmptyDay(day)
        return VStack(spacing: 4) {
            Text(Self.weekdayInitial(day))
                .scaledFont(size: 10, weight: .semibold)
                .foregroundStyle(Color.white.opacity(isToday ? 0.75 : 0.35))
            Text(Self.dayNumber(day))
                .scaledFont(size: 15, weight: .bold)
                .foregroundStyle(isToday ? surface.accent : .white)
                .monospacedDigit()
            Circle()
                .fill(hasItems ? surface.accent : Color.clear)
                .frame(width: 4, height: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(isToday ? 0.09 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isToday ? surface.accent.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.accessibleDay(day))
        .accessibilityValue(hasItems ? "Has entries" : "Nothing scheduled")
    }

    // MARK: - Day sections

    @ViewBuilder
    private var dayScroll: some View {
        if isLoading && populatedDays.isEmpty {
            loadingPlaceholder
        } else if populatedDays.isEmpty {
            emptyWeek
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(populatedDays, id: \.self) { day in
                        Section {
                            daySection(day)
                        } header: {
                            dayHeader(day)
                        }
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }

    private func dayHeader(_ day: Date) -> some View {
        HStack(spacing: 6) {
            if calendar.isDateInToday(day) {
                Text("Today")
                    .scaledFont(size: 11, weight: .black)
                    .foregroundStyle(surface.accent)
            }
            Text(Self.sectionTitle(day))
                .scaledFont(size: 11, weight: .bold)
                .foregroundStyle(Color.white.opacity(0.4))
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(Color(hex: "04090F"))
    }

    @ViewBuilder
    private func daySection(_ day: Date) -> some View {
        VStack(spacing: 10) {
            switch surface {
            case .sports:
                ForEach(schedule.games(on: day, calendar: calendar)) { game in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selectedGame = game
                    } label: {
                        gameRow(game)
                    }
                    .buttonStyle(.plain)
                }
            case .watchlist:
                ForEach(schedule.episodes(on: day, calendar: calendar)) { episode in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        detailSubject = .show(Self.posterShow(from: episode))
                    } label: {
                        episodeRow(episode)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Rows

    private func gameRow(_ game: SportsGame) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: -8) {
                TeamLogoBadge(team: game.away, size: 30, cornerRadius: 8, inset: 4, abbreviationFontSize: 7)
                TeamLogoBadge(team: game.home, size: 30, cornerRadius: 8, inset: 4, abbreviationFontSize: 7)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(hex: "04090F"), lineWidth: 2)
                    )
            }
            .frame(width: 56, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(game.away.shortName) at \(game.home.shortName)")
                    .scaledFont(size: 13, weight: .bold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(game.sport)
                        .scaledFont(size: 9, weight: .black)
                        .foregroundStyle(Color.white.opacity(0.35))
                    ForEach(SportsSimulcast.enrich(game.broadcasts).prefix(2), id: \.self) { name in
                        Text(name)
                            .scaledFont(size: 9, weight: .semibold)
                            .foregroundStyle(Color.white.opacity(0.7))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.09))
                            )
                    }
                }
            }

            Spacer(minLength: 6)
            gameTrailing(game)
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: "12161F")))
        .overlay(
            RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    /// The right edge is the whole difference between a played game and a
    /// scheduled one: a final carries the score, a live game carries the clock,
    /// and everything ahead carries its start time.
    @ViewBuilder
    private func gameTrailing(_ game: SportsGame) -> some View {
        switch game.state {
        case .post:
            VStack(alignment: .trailing, spacing: 2) {
                Text("FINAL")
                    .scaledFont(size: 9, weight: .black)
                    .foregroundStyle(Color.white.opacity(0.35))
                Text("\(game.away.score)–\(game.home.score)")
                    .scaledFont(size: 14, weight: .black)
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
        case .live:
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Circle().fill(Color(hex: "E50914")).frame(width: 5, height: 5)
                    Text("LIVE")
                        .scaledFont(size: 9, weight: .black)
                        .foregroundStyle(Color(hex: "E50914"))
                }
                Text("\(game.away.score)–\(game.home.score)")
                    .scaledFont(size: 14, weight: .black)
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
        case .pre:
            Text(Self.timeLabel(game.startDate))
                .scaledFont(size: 12, weight: .semibold)
                .foregroundStyle(Color.white.opacity(0.65))
                .monospacedDigit()
        }
    }

    private func episodeRow(_ episode: ScheduledEpisode) -> some View {
        HStack(spacing: 11) {
            RemoteImage(url: episode.posterUrl.flatMap(URL.init(string:)))
                .frame(width: 30, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(episode.showTitle)
                    .scaledFont(size: 13, weight: .bold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(episode.episodeLabel)
                        .scaledFont(size: 9, weight: .black)
                        .foregroundStyle(Color.white.opacity(0.35))
                    if let platform = episode.platform, !platform.isEmpty {
                        Text(platform)
                            .scaledFont(size: 9, weight: .semibold)
                            .foregroundStyle(Color.white.opacity(0.7))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.09))
                            )
                    }
                    if episode.isSeasonFinale {
                        Text("Season finale")
                            .scaledFont(size: 9, weight: .bold)
                            .foregroundStyle(surface.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(surface.accent.opacity(0.45), lineWidth: 1)
                            )
                    }
                }
            }

            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .scaledFont(size: 12, weight: .bold)
                .foregroundStyle(Color.white.opacity(0.25))
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: "12161F")))
        .overlay(
            RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - States

    private var loadingPlaceholder: some View {
        VStack(spacing: 10) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 66)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    /// An empty week is normal here — especially forward, where TMDB simply has
    /// no announced dates yet — so the state says which kind of empty it is
    /// rather than reading as a failure.
    private var emptyWeek: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: surface == .sports ? "sportscourt" : "tv")
                .scaledFont(size: 28, weight: .light)
                .foregroundStyle(Color.white.opacity(0.2))
            Text(emptyTitle)
                .scaledFont(size: 15, weight: .bold)
                .foregroundStyle(.white)
            Text(emptyMessage)
                .scaledFont(size: 12)
                .foregroundStyle(Color.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
            Spacer()
        }
    }

    private var emptyTitle: String {
        switch surface {
        case .sports:
            return TeamFavoritesService.shared.favoriteUids().isEmpty ? "No teams followed" : "Nothing this week"
        case .watchlist:
            return "Nothing this week"
        }
    }

    private var emptyMessage: String {
        switch surface {
        case .sports:
            if TeamFavoritesService.shared.favoriteUids().isEmpty {
                return "Add teams in My Teams and their games will show up here."
            }
            return "None of your teams play between these dates."
        case .watchlist:
            return weekOffset > 0
                ? "Air dates this far ahead haven't been announced yet."
                : "No episodes from your saved shows this week."
        }
    }

    // MARK: - Helpers

    private func isEmptyDay(_ day: Date) -> Bool {
        switch surface {
        case .sports: return schedule.games(on: day, calendar: calendar).isEmpty
        case .watchlist: return schedule.episodes(on: day, calendar: calendar).isEmpty
        }
    }

    private static func posterShow(from episode: ScheduledEpisode) -> PosterShow {
        PosterShow(
            title: episode.showTitle,
            meta: episode.episodeLabel,
            posterColors: HomeFallback.posterColors,
            symbol: "tv",
            posterUrl: episode.posterUrl,
            tmdbId: Int(episode.titleId),
            isTV: true
        )
    }

    private static func timeLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f.string(from: date)
    }

    private static func weekdayInitial(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        return String(f.veryShortStandaloneWeekdaySymbols[Calendar.current.component(.weekday, from: date) - 1])
    }

    private static func dayNumber(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("d")
        return f.string(from: date)
    }

    private static func sectionTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("EEEEMMMd")
        return f.string(from: date)
    }

    private static func accessibleDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("EEEEMMMd")
        return f.string(from: date)
    }
}

// MARK: - Sheet wrapper

/// Watchlist reaches Schedule from inside a sheet, so it gets its own sheet
/// chrome rather than a navigation push.
struct ScheduleSheet: View {
    let surface: ScheduleSurface
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            GsSheetHeader(title: "Schedule", subtitle: surface.kicker) {
                Button("Close") { dismiss() }
                    .foregroundStyle(Color.textSecondary)
            }
            ScheduleView(surface: surface)
        }
        .preferredColorScheme(.dark)
        .sheetSurface(.raised)
    }
}

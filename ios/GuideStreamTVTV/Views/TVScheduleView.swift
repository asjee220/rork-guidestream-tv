//
//  TVScheduleView.swift
//  GuideStreamTVTV
//
//  GUI-95 — the Schedule week view on tvOS.
//
//  Layout here is the seven-column grid, the opposite of the phone's choice.
//  A TV row is 1700pt wide, so a day column has room for a crest pair, the
//  matchup and a time without truncating anything, and the whole week reads at
//  a glance from across a room. The phone ships the day list for the same
//  reason inverted: at 393pt a grid cell has room for neither.
//
//  Selection is a 2pt white stroke on the item's own shape. `.buttonStyle(.plain)`
//  is not used anywhere in this file — on tvOS it lays a white slab over
//  whatever it wraps on focus, and does so even under `.focusEffectDisabled()`.
//

import SwiftUI

// MARK: - Surface

enum TVScheduleSurface: Hashable {
    case sports
    case watchlist

    var kicker: String {
        switch self {
        case .sports: return "My Teams"
        case .watchlist: return "Watch List"
        }
    }

    var accent: Color {
        switch self {
        case .sports: return TVTheme.orange
        case .watchlist: return TVTheme.blue
        }
    }
}

// MARK: - Focus targets

private enum TVScheduleFocus: Hashable {
    case previous
    case next
    case close
    case item(String)
}

// MARK: - Schedule

struct TVScheduleView: View {
    let surface: TVScheduleSurface
    var onClose: () -> Void

    @State private var schedule = TVScheduleService.shared
    @State private var weekOffset: Int = 0
    @FocusState private var focus: TVScheduleFocus?

    /// A game card opens the same watch sheet the Sports tab opens.
    @State private var selectedGame: TVSportsGame?
    /// A show card hands off to the shell's title route, so Back from the
    /// title screen lands on the week again rather than on the tab.
    @Environment(\.showTitleDetail) private var showTitleDetail

    private let calendar = Calendar.current

    private var weekStart: Date {
        calendar.date(
            byAdding: .day,
            value: weekOffset * 7,
            to: TVScheduleWeek.start(of: Date(), calendar: calendar)
        ) ?? TVScheduleWeek.start(of: Date(), calendar: calendar)
    }
    private var days: [Date] { TVScheduleWeek.days(from: weekStart, calendar: calendar) }

    private var isLoading: Bool {
        surface == .sports ? schedule.isLoadingGames : schedule.isLoadingEpisodes
    }

    private var isWeekEmpty: Bool {
        days.allSatisfy { isEmptyDay($0) }
    }

    var body: some View {
        ZStack {
            // No ignoresSafeArea: as a shell route this sits beside the side
            // rail rather than over it, the same as every tab screen.
            TVTheme.backgroundGradient

            VStack(alignment: .leading, spacing: 24) {
                header
                    .padding(.leading, 80)
                    .padding(.trailing, 60)
                    .padding(.top, 40)
                    .focusSection()

                if isWeekEmpty {
                    emptyWeek
                } else {
                    weekGrid
                        .padding(.leading, 80)
                        .padding(.trailing, 60)
                        .focusSection()
                }

                Spacer(minLength: 0)
            }
        }
        .task(id: weekStart) { await load() }
        .onExitCommand { onClose() }
        .fullScreenCover(item: $selectedGame) { game in
            SportsWatchSheet(game: game)
        }
    }

    // MARK: - Loading

    private func load() async {
        switch surface {
        case .sports:
            await schedule.loadGames(weekStart: weekStart)
        case .watchlist:
            if schedule.episodes.isEmpty {
                await schedule.loadEpisodes()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(surface.kicker)
                    .font(.system(size: 20, weight: .heavy))
                    .textCase(.uppercase)
                    .foregroundStyle(TVTheme.textTertiary)
                Text("Schedule")
                    .font(.system(size: 48, weight: .black))
                    .foregroundStyle(.white)
            }

            Spacer()

            if isLoading {
                ProgressView().tint(.white)
            }

            navButton(systemName: "chevron.left", target: .previous, enabled: weekOffset > -TVScheduleWeek.maxOffset) {
                weekOffset -= 1
            }

            Text(TVScheduleWeek.rangeLabel(for: weekStart, calendar: calendar))
                .font(.system(size: 28, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(minWidth: 260)

            navButton(systemName: "chevron.right", target: .next, enabled: weekOffset < TVScheduleWeek.maxOffset) {
                weekOffset += 1
            }
        }
    }

    private func navButton(
        systemName: String,
        target: TVScheduleFocus,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(enabled ? Color.white : Color.white.opacity(0.25))
                .frame(width: 62, height: 62)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(focus == target ? Color.white : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(TVFlatButtonStyle())
        .focusEffectDisabled()
        .focused($focus, equals: target)
        .disabled(!enabled)
        .accessibilityLabel(target == .previous ? "Previous week" : "Next week")
    }

    // MARK: - Week grid

    private var weekGrid: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(days, id: \.self) { day in
                dayColumn(day)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private func dayColumn(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.weekdayShort(day))
                    .font(.system(size: 18, weight: .heavy))
                    .textCase(.uppercase)
                    .foregroundStyle(TVTheme.textTertiary)
                Spacer()
                Text(Self.dayNumber(day))
                    .font(.system(size: 24, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? surface.accent : TVTheme.textSecondary)
            }
            .padding(.bottom, 2)

            switch surface {
            case .sports:
                ForEach(schedule.games(on: day, calendar: calendar)) { game in
                    gameCard(game)
                }
            case .watchlist:
                ForEach(schedule.episodes(on: day, calendar: calendar)) { episode in
                    episodeCard(episode)
                }
            }

            if isEmptyDay(day) {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.07), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .frame(height: 96)
            }
        }
        .focusSection()
    }

    // MARK: - Cards

    private func gameCard(_ game: TVSportsGame) -> some View {
        let key = TVScheduleFocus.item(game.id)
        return Button {
            selectedGame = game
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    TVTeamCrest(team: game.away, size: 40)
                    TVTeamCrest(team: game.home, size: 40)
                }
                Text("\(game.away.abbreviation) at \(game.home.abbreviation)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(Self.gameStatus(game))
                    .font(.system(size: 17, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(game.state == .live ? Color(red: 0xE5 / 255, green: 0x09 / 255, blue: 0x14 / 255) : TVTheme.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(focus == key ? Color.white : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(TVFlatButtonStyle())
        .focusEffectDisabled()
        .focused($focus, equals: key)
    }

    private func episodeCard(_ episode: TVScheduledEpisode) -> some View {
        let key = TVScheduleFocus.item(episode.id)
        return Button {
            showTitleDetail(
                TVTitleDetail(
                    titleId: episode.titleId,
                    title: episode.showTitle,
                    overview: nil,
                    posterUrl: episode.posterUrl,
                    backdropUrl: episode.posterUrl,
                    tag: episode.episodeLabel,
                    accent: surface.accent,
                    year: nil,
                    platform: episode.platform,
                    // Every row on this surface came from a saved TV title, so
                    // the sheet can skip its media-type probe.
                    isTVHint: true
                )
            )
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                TVRemoteImage(url: episode.posterUrl.flatMap(URL.init(string:)))
                    .frame(width: 48, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(episode.showTitle)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(episode.isSeasonFinale ? "\(episode.episodeLabel) · Finale" : episode.episodeLabel)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(episode.isSeasonFinale ? surface.accent : TVTheme.textSecondary)
                    .lineLimit(1)
                if let platform = episode.platform, !platform.isEmpty {
                    Text(platform)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(TVTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(focus == key ? Color.white : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(TVFlatButtonStyle())
        .focusEffectDisabled()
        .focused($focus, equals: key)
    }

    // MARK: - Empty

    private var emptyWeek: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(isLoading ? "Loading…" : "Nothing this week")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
            if !isLoading {
                Text(emptyMessage)
                    .font(.system(size: 22))
                    .foregroundStyle(TVTheme.textTertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyMessage: String {
        switch surface {
        case .sports:
            return TVTeamFavoritesService.shared.favoriteUids().isEmpty
                ? "Follow teams and their games will show up here."
                : "None of your teams play between these dates."
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

    private static func gameStatus(_ game: TVSportsGame) -> String {
        switch game.state {
        case .post: return "Final \(game.away.score)–\(game.home.score)"
        case .live: return "Live \(game.away.score)–\(game.home.score)"
        case .pre:
            guard let start = game.startDate else { return game.statusDetail }
            let f = DateFormatter()
            f.locale = .current
            f.setLocalizedDateFormatFromTemplate("jmm")
            return f.string(from: start)
        }
    }

    private static func weekdayShort(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        return f.shortStandaloneWeekdaySymbols[Calendar.current.component(.weekday, from: date) - 1]
    }

    private static func dayNumber(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("d")
        return f.string(from: date)
    }
}

// MARK: - Entry chip

/// The control that opens the Schedule, shared by Sports and the Watch List so
/// the two entry points are visibly the same thing.
///
/// Orange outline, orange text, calendar glyph — an action, not a category.
/// Selection follows the house tvOS rule: flat style, a 2pt stroke on focus,
/// no white slab. It owns its own `@FocusState` so it drops into any chip row
/// without the host view having to carry one.
struct TVScheduleChip: View {
    var action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 22, weight: .semibold))
                Text("Schedule")
                    .font(.system(size: 24, weight: .semibold))
            }
            .foregroundStyle(TVTheme.orange)
            .padding(.horizontal, 26)
            .padding(.vertical, 12)
            .background(Capsule().fill(TVTheme.orange.opacity(isFocused ? 0.16 : 0)))
            .overlay(Capsule().stroke(TVTheme.orange, lineWidth: 2))
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isFocused)
        }
        .buttonStyle(TVFlatButtonStyle())
        .focusEffectDisabled()
        .focused($isFocused)
        .accessibilityLabel("Open schedule")
    }
}

// MARK: - Crest

/// Crest on the shared neutral light plate, falling back to the team-colour
/// abbreviation badge. Mirrors the phone's `TeamLogoBadge` at TV scale.
private struct TVTeamCrest: View {
    let team: TVGameTeam
    let size: CGFloat

    var body: some View {
        Group {
            if let raw = team.logoURL, !raw.isEmpty, let url = URL(string: raw) {
                TVRemoteImage(url: url, contentMode: .fit)
                    .padding(4)
                    .frame(width: size, height: size)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.92))
                    )
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(team.primaryHex.map { Color(hex: $0) } ?? Color.white.opacity(0.2))
                    .frame(width: size, height: size)
                    .overlay {
                        Text(team.abbreviation)
                            .font(.system(size: size * 0.32, weight: .black))
                            .foregroundStyle(.white)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

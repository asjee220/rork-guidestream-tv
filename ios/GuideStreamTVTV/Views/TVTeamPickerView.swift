//
//  TVTeamPickerView.swift
//  GuideStreamTVTV
//
//  Follow teams. This is what the Sports screen's "Edit" opens, and what a
//  viewer with no teams yet is offered on their first visit — the same two
//  modes the phone's TeamPickerSheet has.
//
//  The phone leads with a search field. A tvOS keyboard costs a viewer far
//  more than scrolling does, so the search field is not ported: the sport
//  pills narrow the roster to one league and the grid takes it from there,
//  which is a handful of moves on a remote against a dozen for typing.
//
//  Selection is session-local and committed on Done, so a viewer can change
//  their mind inside the picker without a write per press. Commit diffs the
//  session against what is already stored: additions go in one insert,
//  removals one delete each.
//

import SwiftUI

struct TVTeamPickerView: View {
    /// Identifiable so the Sports screen can present the picker with
    /// `.fullScreenCover(item:)` — the mode *is* the presentation's identity,
    /// so there is no separate flag to keep in step with it.
    enum Mode: String, Identifiable {
        /// First visit: the viewer has no teams yet, so the copy invites
        /// rather than instructs, and there is a way out that saves nothing.
        case onboarding
        case edit

        var id: String { rawValue }
    }

    let mode: Mode
    let onClose: () -> Void

    @State private var catalog = TVSportsTeamCatalogService.shared
    @State private var favorites = TVTeamFavoritesService.shared

    @State private var selectedSport: String?
    /// Session selection, seeded from what is already followed.
    @State private var selection: Set<String> = []
    @State private var isSaving = false

    @FocusState private var focusedSport: String?
    @FocusState private var focusedTeam: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 28), count: 5)

    private var sports: [String] { catalog.sports }

    private var visibleTeams: [TVSportsTeamRow] {
        guard let selectedSport else { return catalog.teams }
        return catalog.teams(forSport: selectedSport)
    }

    var body: some View {
        ZStack {
            TVTheme.backgroundGradient.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 32) {
                header
                sportPills
                if catalog.teams.isEmpty {
                    loadingState
                } else {
                    teamGrid
                }
            }
            .padding(.horizontal, 80)
            .padding(.top, 60)
        }
        .task {
            await catalog.load()
            await favorites.load()
            selection = favorites.favoriteUids()
            if selectedSport == nil { selectedSport = sports.first }
        }
        // Menu backs out without saving, which is what Menu means everywhere
        // else in the app. Done is the commit.
        .onExitCommand { onClose() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text(mode == .onboarding ? "Follow your teams" : "My Teams")
                    .font(.system(size: 48, weight: .black))
                    .foregroundStyle(.white)
                Text(mode == .onboarding
                     ? "Pick the teams you care about and their games lead your Sports screen."
                     : "Selected teams lead your Sports screen and drive game alerts.")
                    .font(.system(size: 24))
                    .foregroundStyle(TVTheme.textSecondary)
            }
            Spacer()
            if isSaving {
                ProgressView().tint(.white)
            }
            TVSecondaryButton(title: doneTitle) {
                Task { await commit() }
            }
        }
    }

    private var doneTitle: String {
        let added = selection.subtracting(favorites.favoriteUids()).count
        if mode == .onboarding, added > 0 { return "Follow \(added) team\(added == 1 ? "" : "s")" }
        return "Done"
    }

    // MARK: - Sport pills

    private var sportPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(sports, id: \.self) { sport in
                    let isOn = selectedSport == sport
                    let focused = focusedSport == sport
                    Button {
                        selectedSport = sport
                    } label: {
                        Text(sport)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(isOn ? Color.black : TVTheme.textSecondary)
                            .padding(.horizontal, 26)
                            .padding(.vertical, 12)
                            // Selection and focus stay separate cues, as on
                            // the title screen's season pills.
                            .background(isOn ? Color.white.opacity(0.92) : Color.white.opacity(0.10), in: Capsule())
                            .overlay(Capsule().fill(Color.white.opacity(focused && !isOn ? 0.16 : 0)))
                            .overlay(Capsule().stroke(Color.white.opacity(focused ? 0.9 : 0), lineWidth: 2))
                            .scaleEffect(focused ? 1.06 : 1.0)
                            .animation(.easeOut(duration: 0.15), value: focused)
                    }
                    .buttonStyle(TVFlatButtonStyle())
                    .focusEffectDisabled()
                    .focused($focusedSport, equals: sport)
                }
            }
            .padding(.vertical, 8)
        }
        .focusSection()
    }

    // MARK: - Grid

    private var teamGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 32) {
                ForEach(visibleTeams) { team in
                    teamTile(team)
                }
            }
            .padding(.vertical, 24)
            .padding(.bottom, 60)
        }
        .focusSection()
    }

    private func teamTile(_ team: TVSportsTeamRow) -> some View {
        let isOn = selection.contains(team.team_uid)
        let focused = focusedTeam == team.team_uid
        return Button {
            if isOn { selection.remove(team.team_uid) } else { selection.insert(team.team_uid) }
        } label: {
            VStack(spacing: 14) {
                ZStack(alignment: .topTrailing) {
                    TeamLogoBadge(team: team.asGameTeam, size: 96, cornerRadius: 12, inset: 12,
                                  abbreviationFontSize: 20)
                    if isOn {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white, TVTheme.orange)
                            .offset(x: 10, y: -10)
                    }
                }
                Text(team.displayLabel)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(team.league)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TVTheme.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(isOn ? 0.12 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(focused ? TVTheme.orange.opacity(0.95) : Color.white.opacity(isOn ? 0.25 : 0.06),
                            lineWidth: focused ? 4 : 1)
            )
            .scaleEffect(focused ? 1.05 : 1.0)
            .shadow(color: focused ? TVTheme.orange.opacity(0.55) : .clear,
                    radius: focused ? 30 : 0, y: focused ? 18 : 0)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: focused)
        }
        .buttonStyle(TVFlatButtonStyle())
        .focusEffectDisabled()
        .focused($focusedTeam, equals: team.team_uid)
    }

    private var loadingState: some View {
        VStack(spacing: 20) {
            ProgressView().tint(.white).scaleEffect(2)
            Text("Loading teams…")
                .font(.system(size: 24))
                .foregroundStyle(TVTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Commit

    /// Diffs the session's selection against what is stored: one insert for
    /// everything added, one delete per team dropped. Nothing is written
    /// while the viewer is still choosing.
    private func commit() async {
        isSaving = true
        defer { isSaving = false }

        let stored = favorites.favoriteUids()
        let added = selection.subtracting(stored)
        let removed = stored.subtracting(selection)

        if !added.isEmpty {
            let entries = catalog.teams
                .filter { added.contains($0.team_uid) }
                .map { (team: $0.asGameTeam, league: Optional($0.league), sport: Optional($0.sport)) }
            await favorites.addMany(entries)
        }
        for uid in removed {
            guard let row = catalog.teams.first(where: { $0.team_uid == uid }) else { continue }
            await favorites.toggle(team: row.asGameTeam, league: row.league, sport: row.sport)
        }
        onClose()
    }
}

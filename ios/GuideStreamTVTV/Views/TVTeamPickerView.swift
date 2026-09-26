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

    /// Sports restyle: eight crest circles per row, as in the approved mockup.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 24), count: 8)

    private var sports: [String] { catalog.sports }

    private var visibleTeams: [TVSportsTeamRow] {
        guard let selectedSport else { return catalog.teams }
        return catalog.teams(forSport: selectedSport)
    }

    var body: some View {
        ZStack {
            TVTheme.backgroundGradient.ignoresSafeArea()

            // One vertical scroll for the whole screen, as TVWatchListView
            // does. The grid used to own a nested vertical ScrollView, and
            // focus could not leave it upward: from the teams there was no way
            // to reach the league pills or Done. Every row above the grid is
            // its own focus section so a move up lands on it from any column.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 32) {
                    header
                    followingRow
                    sportPills
                    if catalog.teams.isEmpty {
                        loadingState
                    } else {
                        teamGrid
                    }
                }
                .padding(.horizontal, 80)
                .padding(.top, 60)
                .padding(.bottom, 60)
            }
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
                Text(mode == .onboarding ? "Follow your teams" : "My teams")
                    .font(.system(size: 48, weight: .bold))
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
        .focusSection()
    }

    private var doneTitle: String {
        let added = selection.subtracting(favorites.favoriteUids()).count
        if mode == .onboarding, added > 0 { return "Follow \(added) team\(added == 1 ? "" : "s")" }
        return "Done"
    }

    // MARK: - Sport pills

    private var sportPills: some View {
        // Plain row, not a horizontal ScrollView: eight leagues fit, and a
        // nested scroll view is one more container the focus engine has to
        // find its way into.
        HStack(spacing: 0) {
            HStack(spacing: 18) {
                ForEach(sports, id: \.self) { sport in
                    let isOn = selectedSport == sport
                    let focused = focusedSport == sport
                    Button {
                        selectedSport = sport
                    } label: {
                        Text(sport)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(focused ? TVButtonFocus.content : (isOn ? Color.black : TVTheme.textSecondary))
                            .padding(.horizontal, 26)
                            .padding(.vertical, 12)
                            // Selection and focus stay separate cues, as on
                            // the title screen's season pills: focus is the
                            // shared solid white fill, and on the selected
                            // (already white) pill the lift and shadow carry it.
                            .background(focused ? TVButtonFocus.fill : (isOn ? Color.white.opacity(0.92) : Color.white.opacity(0.10)), in: Capsule())
                            .scaleEffect(focused ? TVButtonFocus.scale : 1.0)
                            .tvButtonFocusShadow(focused)
                            .animation(.easeOut(duration: 0.15), value: focused)
                    }
                    .buttonStyle(TVFlatButtonStyle())
                    .focusEffectDisabled()
                    .focused($focusedSport, equals: sport)
                }
            }
            .padding(.vertical, 8)
            Spacer(minLength: 0)
        }
        .focusSection()
    }

    // MARK: - Grid

    private var teamGrid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 32) {
            ForEach(visibleTeams) { team in
                teamTile(team)
            }
        }
        .padding(.vertical, 24)
        .focusSection()
    }

    /// Followed: the crest on its team-colour circle with the white ring.
    /// Not followed: the crest on a dark circle with a faint ring. Focus
    /// thickens the ring and lifts the circle — no tvOS focus slab.
    private func teamTile(_ team: TVSportsTeamRow) -> some View {
        let isOn = selection.contains(team.team_uid)
        let focused = focusedTeam == team.team_uid
        return Button {
            if isOn { selection.remove(team.team_uid) } else { selection.insert(team.team_uid) }
        } label: {
            VStack(spacing: 14) {
                TVTeamCrestCircle(team: team.asGameTeam, size: 140, filled: isOn, focused: focused)
                Text(team.displayLabel)
                    .font(.system(size: 22, weight: isOn || focused ? .semibold : .medium))
                    .foregroundStyle(isOn || focused ? .white : Color.white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(TVFlatButtonStyle())
        .focusEffectDisabled()
        .focused($focusedTeam, equals: team.team_uid)
    }

    // MARK: - Following

    /// Teams picked so far. Selecting one here unfollows it.
    @ViewBuilder
    private var followingRow: some View {
        let followed = catalog.teams.filter { selection.contains($0.team_uid) }
        if !followed.isEmpty {
            HStack(spacing: 24) {
                Text("Following")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(TVTheme.orange)
                    .frame(width: 170, alignment: .leading)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 22) {
                        ForEach(followed) { team in
                            let key = "following-" + team.team_uid
                            Button {
                                selection.remove(team.team_uid)
                            } label: {
                                TVTeamCrestCircle(team: team.asGameTeam, size: 84, focused: focusedTeam == key)
                            }
                            .buttonStyle(TVFlatButtonStyle())
                            .focusEffectDisabled()
                            .focused($focusedTeam, equals: key)
                            .accessibilityLabel("Unfollow \(team.displayLabel)")
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 10)
                }
            }
            .focusSection()
        }
    }

    private var loadingState: some View {
        VStack(spacing: 20) {
            ProgressView().tint(.white).scaleEffect(2)
            Text("Loading teams…")
                .font(.system(size: 24))
                .foregroundStyle(TVTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
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

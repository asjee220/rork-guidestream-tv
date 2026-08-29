//
//  TeamPickerSheet.swift
//  GuideStreamTV
//
//  Favorite-team picker. Shown automatically the first time a user opens the
//  Sports tab, and on demand from "My Teams → Edit".
//
//  Reads the full league rosters from SportsTeamCatalogService and writes
//  through TeamFavoritesService, so a team favorited here is identical to one
//  starred on a game card and is picked up by sports_poll_and_notify for
//  starting-soon / going-live / final-score pushes.
//

import SwiftUI
import UIKit

struct TeamPickerSheet: View {
    /// Presentation source. First-run gets onboarding copy and a "Not right
    /// now" escape; the edit entry point gets neutral copy and Done.
    /// Identifiable so callers can drive it with `.sheet(item:)`.
    enum Mode: String, Identifiable {
        case onboarding
        case edit

        var id: String { rawValue }
    }

    let mode: Mode
    let onDismiss: () -> Void

    @State private var catalog = SportsTeamCatalogService.shared
    @State private var favorites = TeamFavoritesService.shared
    @State private var selectedSport: String = ""
    @State private var query: String = ""
    /// Teams picked in this session, keyed by uid. Seeded from existing
    /// favorites so the edit entry point opens pre-ticked.
    @State private var selected: [String: SportsTeamRow] = [:]
    @State private var isSaving: Bool = false

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    private var activeSport: String {
        selectedSport.isEmpty ? (catalog.sports.first ?? "") : selectedSport
    }

    private var visibleTeams: [SportsTeamRow] {
        let pool = catalog.teams(forSport: activeSport)
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return pool }
        return pool.filter { $0.searchHaystack.contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            sportPills
            searchField
            content
            footer
        }
        .background(Color(hex: "0B131D").ignoresSafeArea())
        .task {
            await catalog.load()
            await favorites.load()
            seedSelection()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sports")
                .scaledFont(size: 11, weight: .bold)
                .kerning(1.4)
                .foregroundStyle(Color(hex: "F5821F"))
            Text(mode == .onboarding ? "Pick your teams" : "Your teams")
                .scaledFont(size: 21, weight: .bold)
                .foregroundStyle(.white)
            Text(mode == .onboarding
                 ? "We'll ping you before kickoff, when they go live, and with the final score — and pin them to the top of Sports."
                 : "Add or remove teams. Changes save when you tap Done.")
                .scaledFont(size: 12.5, weight: .regular)
                .foregroundStyle(Color.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    // MARK: - Sport pills

    private var sportPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(catalog.sports, id: \.self) { sport in
                    let isActive = sport == activeSport
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selectedSport = sport
                    } label: {
                        Text(sport)
                            .scaledFont(size: 12, weight: .bold)
                            .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.5))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background {
                                if isActive {
                                    Capsule().fill(Color(hex: "F5821F"))
                                }
                            }
                            .overlay {
                                Capsule()
                                    .stroke(isActive ? Color.clear : Color.white.opacity(0.15), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 11)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .scaledFont(size: 13, weight: .semibold)
                .foregroundStyle(Color.white.opacity(0.45))
            TextField("", text: $query, prompt:
                Text("Search teams").foregroundStyle(Color.white.opacity(0.35))
            )
            .scaledFont(size: 13)
            .foregroundStyle(.white)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .scaledFont(size: 14)
                        .foregroundStyle(Color.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Grid

    @ViewBuilder
    private var content: some View {
        if catalog.teams.isEmpty && catalog.isLoading {
            loadingGrid
        } else if catalog.teams.isEmpty {
            catalogUnavailable
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(visibleTeams) { team in
                        teamTile(team)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                if visibleTeams.isEmpty {
                    Text("No teams match that search.")
                        .scaledFont(size: 12.5, weight: .medium)
                        .foregroundStyle(Color.white.opacity(0.35))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 34)
                }
            }
        }
    }

    private func teamTile(_ team: SportsTeamRow) -> some View {
        let isOn = selected[team.team_uid] != nil
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if isOn {
                selected.removeValue(forKey: team.team_uid)
            } else {
                selected[team.team_uid] = team
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    TeamLogoBadge(
                        team: team.asGameTeam,
                        size: 46,
                        cornerRadius: 11,
                        inset: 5,
                        abbreviationFontSize: 11
                    )
                    Text(team.displayLabel)
                        .scaledFont(size: 10, weight: .semibold)
                        .foregroundStyle(isOn ? .white : Color.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 2)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 92)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isOn ? Color(hex: "F5821F").opacity(0.10) : Color.white.opacity(0.045))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isOn ? Color(hex: "F5821F") : Color.white.opacity(0.07), lineWidth: 1)
                )

                if isOn {
                    Image(systemName: "checkmark")
                        .scaledFont(size: 9, weight: .black)
                        .foregroundStyle(.white)
                        .frame(width: 17, height: 17)
                        .background(Circle().fill(Color(hex: "F5821F")))
                        .padding(5)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var loadingGrid: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<12, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.045))
                    .frame(height: 92)
            }
        }
        .padding(.horizontal, 20)
        .redacted(reason: .placeholder)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var catalogUnavailable: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .scaledFont(size: 26)
                .foregroundStyle(Color.white.opacity(0.3))
            Text("Couldn't load teams right now.")
                .scaledFont(size: 13, weight: .medium)
                .foregroundStyle(Color.white.opacity(0.5))
            Button {
                Task { await catalog.load(force: true) }
            } label: {
                Text("Try again")
                    .scaledFont(size: 13, weight: .bold)
                    .foregroundStyle(Color(hex: "1A6FE8"))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            if !selected.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(orderedSelection) { team in
                            selectedChip(team)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .frame(height: 34)
                .padding(.bottom, 10)
            }

            Button {
                Task { await commit() }
            } label: {
                Group {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text(ctaLabel)
                            .scaledFont(size: 15, weight: .bold)
                    }
                }
                .foregroundStyle(ctaEnabled ? .white : Color.white.opacity(0.35))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(ctaEnabled ? Color(hex: "F5821F") : Color.white.opacity(0.10))
                )
            }
            .buttonStyle(.plain)
            .disabled(!ctaEnabled || isSaving)
            .padding(.horizontal, 20)

            if mode == .onboarding {
                Button {
                    onDismiss()
                } label: {
                    Text("Not right now")
                        .scaledFont(size: 13, weight: .medium)
                        .foregroundStyle(Color.white.opacity(0.42))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background {
            Rectangle()
                .fill(Color(hex: "04090F").opacity(0.5))
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// Selection in catalogue order so the strip doesn't reshuffle on each tap.
    private var orderedSelection: [SportsTeamRow] {
        catalog.teams.filter { selected[$0.team_uid] != nil }
    }

    private func selectedChip(_ team: SportsTeamRow) -> some View {
        HStack(spacing: 5) {
            TeamLogoBadge(
                team: team.asGameTeam,
                size: 16,
                cornerRadius: 4,
                inset: 1,
                abbreviationFontSize: 5
            )
            Text(team.team_abbr ?? team.displayLabel)
                .scaledFont(size: 10.5, weight: .semibold)
                .foregroundStyle(.white)
            Button {
                selected.removeValue(forKey: team.team_uid)
            } label: {
                Image(systemName: "xmark")
                    .scaledFont(size: 8, weight: .bold)
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 5)
        .padding(.trailing, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
    }

    private var ctaEnabled: Bool {
        mode == .edit ? true : !selected.isEmpty
    }

    private var ctaLabel: String {
        if mode == .edit { return "Done" }
        let n = selected.count
        if n == 0 { return "Continue" }
        return "Follow \(n) team\(n > 1 ? "s" : "")"
    }

    // MARK: - Selection / commit

    /// Pre-ticks whatever is already favorited so the edit entry point is a
    /// true editor rather than an additive-only picker.
    private func seedSelection() {
        guard selected.isEmpty else { return }
        let favUids = favorites.favoriteUids()
        guard !favUids.isEmpty else { return }
        for team in catalog.teams where favUids.contains(team.team_uid) {
            selected[team.team_uid] = team
        }
    }

    /// Diffs the session selection against persisted favorites and applies
    /// only what actually changed, so re-opening the sheet and tapping Done
    /// writes nothing.
    private func commit() async {
        isSaving = true
        defer { isSaving = false }

        let before = favorites.favoriteUids()
        let after = Set(selected.keys)

        let additions = after.subtracting(before).compactMap { selected[$0] }
        let removals = before.subtracting(after)

        if !additions.isEmpty {
            await favorites.addMany(additions.map {
                ($0.asGameTeam, $0.league, $0.sport)
            })
        }

        for uid in removals {
            let row = favorites.rows[uid]
            let stub = GameTeam(
                id: row?.team_id,
                uid: uid,
                abbreviation: row?.team_abbr ?? "",
                displayName: row?.team_name ?? "",
                shortName: row?.team_name ?? "",
                score: "",
                primaryHex: nil,
                isWinner: false
            )
            await favorites.toggle(team: stub, league: row?.league, sport: row?.sport)
        }

        onDismiss()
    }
}

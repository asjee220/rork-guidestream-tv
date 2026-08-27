//
//  SportsGameDetailView.swift
//  GuideStreamTV
//

import SwiftUI
import UIKit

struct SportsGameDetailView: View {
    let game: SportsGame

    @Environment(\.scenePhase) private var scenePhase
    @State private var favorites = TeamFavoritesService.shared

    /// Live copy of the game, seeded from `game` on first appearance and
    /// replaced by each successful ESPN refresh. Every score / status / state
    /// read below goes through `current` so a live game keeps ticking while
    /// the screen is open.
    @State private var liveGame: SportsGame?
    /// Timestamp of the last *successful* refresh. A failed refresh keeps the
    /// previous values and the previous stamp.
    @State private var lastRefresh: Date?
    /// Drives the "· updated Ns ago" stamp so it ticks instead of freezing.
    @State private var now: Date = Date()
    @State private var selectedBroadcast: String?
    @State private var showWatchSheet: Bool = false

    /// Seconds between live-score polls.
    private let refreshInterval: TimeInterval = 20

    private var current: SportsGame { liveGame ?? game }

    /// Polling runs only while the game is live and the app is foregrounded.
    /// Changing this token cancels the running loops; returning to `.live` +
    /// `.active` restarts them with an immediate refresh.
    private var pollToken: String {
        "\(current.state.rawValue)|\(scenePhase == .active)"
    }

    private var isPolling: Bool {
        current.state == .live && scenePhase == .active
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // League
                Text(current.leagueShort.uppercased())
                    .scaledFont(size: 12, weight: .heavy)
                    .tracking(1.4)
                    .foregroundStyle(Color.white.opacity(0.45))

                // Scoreline
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        TeamLogoBadge(team: current.away, size: 56, cornerRadius: 14, inset: 8, abbreviationFontSize: 13)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(current.away.shortName)
                                    .scaledFont(size: 22, weight: .bold)
                                    .foregroundStyle(current.away.isWinner ? .white : Color.white.opacity(0.55))
                                favoriteStar(team: current.away)
                            }
                            Text(current.away.score)
                            .scaledFont(size: 36, weight: .black)
                            .foregroundStyle(current.away.isWinner ? .white : Color.white.opacity(0.55))
                        }
                    }
                    Spacer()
                    Text(current.state == .pre ? "vs" : current.state == .live ? "LIVE" : "FINAL")
                        .scaledFont(size: 13, weight: .heavy)
                        .foregroundStyle(Color.white.opacity(0.35))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        TeamLogoBadge(team: current.home, size: 56, cornerRadius: 14, inset: 8, abbreviationFontSize: 13)
                        VStack(alignment: .trailing, spacing: 4) {
                            HStack(spacing: 8) {
                                favoriteStar(team: current.home)
                                Text(current.home.shortName)
                                    .scaledFont(size: 22, weight: .bold)
                                    .foregroundStyle(current.home.isWinner ? .white : Color.white.opacity(0.55))
                            }
                            Text(current.home.score)
                            .scaledFont(size: 36, weight: .black)
                            .foregroundStyle(current.home.isWinner ? .white : Color.white.opacity(0.55))
                        }
                    }
                }

                // Status + date (+ refresh stamp for live games)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(current.statusDetail)
                            .scaledFont(size: 15, weight: .semibold)
                            .foregroundStyle(.white)
                        if let stamp = updatedStamp {
                            Text("· \(stamp)")
                                .scaledFont(size: 12)
                                .foregroundStyle(Color.white.opacity(0.45))
                        }
                    }
                    Text(formattedStartDate)
                        .scaledFont(size: 13)
                        .foregroundStyle(Color.white.opacity(0.55))
                }

                // Watch on — tappable chips, subscribed-first, wrapping
                if !sortedBroadcasts.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Watch on")
                            .scaledFont(size: 12, weight: .heavy)
                            .tracking(1.4)
                            .foregroundStyle(Color.white.opacity(0.45))
                        ChipFlowLayout(spacing: 8) {
                            ForEach(Array(sortedBroadcasts.enumerated()), id: \.element) { index, name in
                                broadcastChip(name, isFirst: index == 0)
                            }
                        }
                    }
                }

                // Track live score (Live Activity) — same capsule as the sheet
                if SportsTrackCapsule.isAvailable(for: current) {
                    SportsTrackCapsule(game: current, broadcast: activeBroadcast ?? "")
                        .padding(.top, 4)
                }

                // Inline watch CTA — presents the existing watch sheet, which
                // owns every deep link, cast and watchlist behavior.
                watchCTA
                    .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(Color(hex: "04090F").ignoresSafeArea())
        .navigationTitle("Game Details")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color(hex: "04090F"), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await favorites.load()
        }
        // Live-score polling. Stops when the game leaves `.live`, when the
        // screen disappears, and when the app is backgrounded; resumes with an
        // immediate refresh on foreground so the stamp is never ten minutes old.
        .task(id: pollToken) {
            guard isPolling else { return }
            await refreshNow()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(refreshInterval))
                if Task.isCancelled { break }
                guard current.state == .live else { break }
                await refreshNow()
            }
        }
        // 1s tick so "updated Ns ago" counts up between refreshes.
        .task(id: pollToken) {
            guard isPolling else { return }
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .sheet(isPresented: $showWatchSheet) {
            SportsWatchSheet(game: current, showsGameDetailsPill: false)
        }
    }

    // MARK: - Live refresh

    /// Pulls the game's own sport from ESPN and swaps in the fresh copy. A
    /// failure (network, ESPN hiccup, game no longer listed) silently keeps the
    /// last good values — never blanks the score, never shows an error banner.
    private func refreshNow() async {
        guard let updated = await SportsService.shared.refresh(game: current) else { return }
        liveGame = updated
        lastRefresh = Date()
        now = Date()
    }

    /// "updated 12s ago" — live games only, and only once a refresh has landed.
    private var updatedStamp: String? {
        guard current.state == .live, let last = lastRefresh else { return nil }
        let seconds = max(0, Int(now.timeIntervalSince(last)))
        if seconds < 60 { return "updated \(seconds)s ago" }
        return "updated \(seconds / 60)m ago"
    }

    // MARK: - Broadcasts

    /// `broadcasts` enriched with streaming simulcast companions, de-duplicated
    /// preserving first-seen order, then stable-sorted so broadcasts the user
    /// subscribes to come first — the same ordering the watch sheet uses.
    private var sortedBroadcasts: [String] {
        var seen = Set<String>()
        let unique = SportsSimulcast.enrich(current.broadcasts).filter { seen.insert($0).inserted }
        return unique.enumerated().sorted { a, b in
            let aSub = AuthViewModel.shared.subscribesToService(named: a.element)
            let bSub = AuthViewModel.shared.subscribesToService(named: b.element)
            if aSub != bSub { return aSub }
            return a.offset < b.offset
        }.map { $0.element }
    }

    /// The broadcast the Watch CTA currently targets.
    private var activeBroadcast: String? {
        if let sel = selectedBroadcast, sortedBroadcasts.contains(sel) {
            return sel
        }
        return sortedBroadcasts.first ?? current.broadcasts.first
    }

    private func broadcastChip(_ name: String, isFirst: Bool) -> some View {
        let subscribed = AuthViewModel.shared.subscribesToService(named: name)
        let accented = isFirst && subscribed
        let isActive = activeBroadcast == name
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedBroadcast = name
        } label: {
            Text(name)
                .scaledFont(size: 13, weight: .semibold)
                .foregroundStyle(accented ? Color.orange : .white)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(accented ? Color.orange.opacity(0.14) : Color.white.opacity(0.07))
                )
                .overlay(
                    Capsule().stroke(
                        accented ? Color.orange : Color.white.opacity(isActive ? 0.45 : 0.12),
                        lineWidth: isActive ? 1.5 : 1
                    )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? "\(name), selected" : name)
    }

    // MARK: - Watch CTA

    private var watchCTA: some View {
        let platform = activeBroadcast ?? ""
        let canWatch = !platform.isEmpty
        return Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showWatchSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: current.state == .live ? "play.fill" : "play.tv.fill")
                    .scaledFont(size: 15, weight: .bold)
                Text(canWatch ? "Watch on \(platform)" : "Broadcast TBA")
                    .scaledFont(size: 17, weight: .semibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Capsule().fill(canWatch ? Color.orange : Color.white.opacity(0.15)))
            .shadow(color: canWatch ? Color.orange.opacity(0.45) : .clear, radius: 20, y: 0)
        }
        .buttonStyle(.plain)
        .disabled(!canWatch)
    }

    // MARK: - Favorite star

    private func favoriteStar(team: GameTeam) -> some View {
        let isFav = favorites.isFavorite(team.uid)
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task {
                await favorites.toggle(
                    team: team,
                    league: current.leagueShort,
                    sport: current.sport
                )
            }
        } label: {
            Image(systemName: isFav ? "star.fill" : "star")
                .scaledFont(size: 16, weight: .regular)
                .foregroundStyle(isFav ? Color.orange : Color.white.opacity(0.35))
        }
        .buttonStyle(.plain)
    }

    private var formattedStartDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: current.startDate)
    }
}

// MARK: - Wrapping chip layout

/// Minimal flow layout: lays subviews left-to-right and wraps to a new line
/// when the next one would overflow the proposed width.
private struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        let width = maxWidth.isFinite ? maxWidth : max(0, x - spacing)
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

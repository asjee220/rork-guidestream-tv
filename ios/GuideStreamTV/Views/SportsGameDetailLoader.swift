//
//  SportsGameDetailLoader.swift
//  GuideStreamTV
//
//  Destination for a sports push tap. Takes only the `game_id` from the
//  payload, so the screen can be pushed the instant the tap is handled and the
//  game resolved afterwards, on screen.
//
//  GUI-46. The previous flow resolved the game *first* and navigated only if
//  it succeeded, which had two failure modes that both look identical to the
//  user — nothing happens:
//
//    * `SportsService.fetchAll()` fans out to nine ESPN scoreboard endpoints
//      and waits for all of them. There is no timeout. On a slow or flaky
//      connection the tap sat there for many seconds; if a request hung, for
//      ever. ESPN also blocks callers by IP (it has been 403ing Supabase's
//      egress since 2026-08-19), so "ESPN answers" is not something to build a
//      navigation on.
//    * A resolve that finished *before* SportsView had mounted set the pending
//      route into a gap where nothing was observing it, and it was dropped.
//
//  Resolution order is now the reverse of what it was. `sports_games` is
//  queried first: it is a single indexed row, and by construction it always
//  holds the game the push was generated from — the same edge function writes
//  the row and sends the notification. ESPN is consulted second, and only to
//  *upgrade* what is already displayed, because the scoreboard carries team
//  logos and brand colours that the table does not.
//

import SwiftUI

struct SportsGameDetailLoader: View {
    let gameId: String

    @State private var game: SportsGame?
    @State private var didFinishResolving = false

    var body: some View {
        Group {
            if let game {
                SportsGameDetailView(game: game)
            } else if didFinishResolving {
                unavailable
            } else {
                loading
            }
        }
        .task(id: gameId) { await resolve() }
    }

    private var loading: some View {
        VStack(spacing: 14) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
            Text("Loading game…")
                .scaledFont(size: 13, weight: .medium)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrandBackground())
    }

    /// Only reached when the id is in neither source, which should not happen
    /// for a real push. Says so plainly rather than showing an empty screen.
    private var unavailable: some View {
        VStack(spacing: 10) {
            Image(systemName: "sportscourt")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Color.white.opacity(0.35))
            Text("Game unavailable")
                .scaledFont(size: 16, weight: .bold)
                .foregroundStyle(.white)
            Text("We couldn't load this game. It may have been removed from the schedule.")
                .scaledFont(size: 13)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrandBackground())
    }

    private func resolve() async {
        // Fast, reliable path first — one row, always present for a pushed game.
        if let row = await SportsService.shared.fetchGame(id: gameId) {
            game = row
        }

        // Then ESPN, purely to upgrade the display with logos and team colours.
        // Skipped once we already have the row *and* the fetch adds nothing.
        let scoreboard = await SportsService.shared.fetchAll()
        if let rich = scoreboard.first(where: { $0.id == gameId }) {
            game = rich
        }

        didFinishResolving = true
    }
}

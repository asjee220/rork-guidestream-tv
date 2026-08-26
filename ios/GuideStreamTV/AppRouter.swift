//
//  AppRouter.swift
//  GuideStreamTV
//

import SwiftUI

/// A buffered push/deep-link destination for a title (show, movie, or creator).
/// Carries the metadata captured from the notification payload so the detail
/// sheet can render the real name/poster immediately instead of a placeholder.
struct PendingTitleRoute: Equatable, Hashable {
    let titleId: String
    var titleName: String? = nil
    var posterUrl: String? = nil
    var isTV: Bool = true
}

@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var pendingSportsRoute: SportsRoute? = nil
    var pendingTitleRoute: PendingTitleRoute? = nil

    func showSportsSchedule() {
        selectedTab = .sports
        pendingSportsRoute = .allUpcoming
    }

    func showGameDetail(_ game: SportsGame) {
        selectedTab = .sports
        pendingSportsRoute = .gameDetail(game)
    }

    /// Buffers a game-detail route from a push, by id. Deliberately does no
    /// lookup: the destination resolves the game itself, so the tap navigates
    /// immediately instead of waiting on the network and possibly never
    /// arriving (GUI-46).
    func showGameDetail(id gameId: String) {
        selectedTab = .sports
        pendingSportsRoute = .gameDetailById(gameId)
    }

    /// Switch to the Home tab and buffer a title route. HomeView consumes
    /// `pendingTitleRoute` via onChange/onAppear, so this works from any tab
    /// and from cold launch (the route waits until HomeView first appears).
    func showTitle(_ route: PendingTitleRoute) {
        selectedTab = .home
        pendingTitleRoute = route
    }
}

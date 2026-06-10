//
//  AppRouter.swift
//  GuideStreamTV
//

import SwiftUI

@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var pendingSportsRoute: SportsRoute? = nil

    func showSportsSchedule() {
        selectedTab = .sports
        pendingSportsRoute = .allUpcoming
    }

    func showGameDetail(_ game: SportsGame) {
        selectedTab = .sports
        pendingSportsRoute = .gameDetail(game)
    }
}

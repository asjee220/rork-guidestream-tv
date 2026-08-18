//
//  TVMainView.swift
//  GuideStreamTVTV
//
//  Tab bar shell. tvOS renders TabView as a top focus bar.
//  Reels tab withheld for launch.
//

import SwiftUI

struct TVMainView: View {
    let onSignOut: () -> Void

    var body: some View {
        TabView {
            TVHomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }

            SportsView()
                .tabItem { Label("Sports", systemImage: "sportscourt.fill") }

            TVWatchListView()
                .tabItem { Label("Watch List", systemImage: "popcorn.fill") }

            ProfileView()
                .tabItem { Label("Account", systemImage: "person.crop.circle.fill") }
        }
        .background(TVTheme.bg.ignoresSafeArea())
    }
}

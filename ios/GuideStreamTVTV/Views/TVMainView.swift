//
//  TVMainView.swift
//  GuideStreamTVTV
//
//  Tab bar shell. tvOS renders TabView as a top focus bar.
//  Reels tab withheld for launch; code preserved in TVReelsView.swift.
//

import SwiftUI

struct TVMainView: View {
    let onSignOut: () -> Void

    var body: some View {
        TabView {
            TVHomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }

            TVWatchListView()
                .tabItem { Label("Watch List", systemImage: "popcorn.fill") }

            TVAccountView(onSignOut: onSignOut)
                .tabItem { Label("Account", systemImage: "person.crop.circle.fill") }
        }
        .background(TVTheme.bg.ignoresSafeArea())
    }
}

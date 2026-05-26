//
//  TVMainView.swift
//  GuideStreamTVTV
//
//  Tab bar shell. tvOS renders TabView as a top focus bar, which is
//  exactly the layout we want — three clear destinations: Home, Watch
//  List, Account.
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

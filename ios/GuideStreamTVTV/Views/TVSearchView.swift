//
//  TVSearchView.swift
//  GuideStreamTVTV
//
//  Placeholder for the tvOS Search destination. Wires the new side-menu
//  item so the menu structure matches the mockups; the full search screen
//  can be filled in later.
//

import SwiftUI

struct TVSearchView: View {
    var body: some View {
        ZStack {
            TVTheme.backgroundGradient

            VStack(spacing: 24) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 80, weight: .regular))
                    .foregroundStyle(TVTheme.textSecondary)

                Text("Search")
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(TVTheme.textPrimary)

                Text("Search for movies, shows, creators, and more.")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(TVTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 760)
            }
        }
        .ignoresSafeArea()
    }
}

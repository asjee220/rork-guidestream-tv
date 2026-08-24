//
//  TVReelsView.swift
//  GuideStreamTVTV
//
//  Placeholder for the tvOS Reels destination. Wires the new side-menu
//  item so the menu structure matches the mockups; the full Reels screen
//  can be filled in later.
//

import SwiftUI

struct TVReelsView: View {
    var body: some View {
        ZStack {
            TVTheme.backgroundGradient

            VStack(spacing: 24) {
                Image(systemName: "play.fill")
                    .font(.system(size: 80, weight: .regular))
                    .foregroundStyle(TVTheme.textSecondary)

                Text("Reels")
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(TVTheme.textPrimary)

                Text("Watch trailers and clips.")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(TVTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 760)
            }
        }
        .ignoresSafeArea()
    }
}

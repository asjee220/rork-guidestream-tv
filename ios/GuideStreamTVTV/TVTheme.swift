//
//  TVTheme.swift
//  GuideStreamTVTV
//
//  10-foot UI design tokens. tvOS uses larger type, denser focus accents,
//  and more saturated background gradients than the phone app so the
//  experience reads from the couch.
//

import SwiftUI

enum TVTheme {
    /// Deep midnight navy used across the app shell.
    static let bg = Color(red: 0x04 / 255, green: 0x09 / 255, blue: 0x0F / 255)
    /// Slightly raised surface for cards and elevated content.
    static let surface = Color(red: 0x0B / 255, green: 0x12 / 255, blue: 0x1C / 255)
    /// More-elevated surface for focused tiles.
    static let surfaceElevated = Color(red: 0x12 / 255, green: 0x1B / 255, blue: 0x2A / 255)

    /// Primary brand orange — used on the watch list pill and trending rail.
    static let orange = Color(red: 0xF5 / 255, green: 0x82 / 255, blue: 0x1F / 255)
    /// Cool brand blue — sports rail accent.
    static let blue = Color(red: 0x1A / 255, green: 0x6F / 255, blue: 0xE8 / 255)
    /// Brand teal-green — news rail accent.
    static let newsGreen = Color(red: 0x00 / 255, green: 0x9E / 255, blue: 0x8A / 255)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.65)
    static let textTertiary = Color.white.opacity(0.40)
    static let hairline = Color.white.opacity(0.10)

    /// Background gradient stack — sits behind every screen so the navy
    /// stays atmospheric instead of feeling flat.
    static var backgroundGradient: some View {
        ZStack {
            bg
            LinearGradient(
                colors: [
                    Color(red: 0x12 / 255, green: 0x06 / 255, blue: 0x2A / 255).opacity(0.85),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .center
            )
            LinearGradient(
                colors: [
                    Color.clear,
                    Color(red: 0x00 / 255, green: 0x10 / 255, blue: 0x2A / 255).opacity(0.75)
                ],
                startPoint: .center,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

//
//  Theme.swift
//  GuideStreamTV
//

import SwiftUI

extension Color {
    static let navy = Color(red: 0x04/255, green: 0x09/255, blue: 0x0F/255)
    static let orange = Color(red: 0xF5/255, green: 0x82/255, blue: 0x1F/255)
    static let blue = Color(red: 0x1A/255, green: 0x6F/255, blue: 0xE8/255)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.35)
    static let glassLight = Color.white.opacity(0.07)
}

extension Font {
    static func guideHeading(size: CGFloat, weight: Weight = .bold) -> Font {
        .custom("SF Pro Display", size: size).weight(weight)
    }

    static func guideBody(size: CGFloat, weight: Weight = .regular) -> Font {
        .custom("SF Pro Text", size: size).weight(weight)
    }
}

struct GlassCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .blur(radius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .clipShape(.rect(cornerRadius: 14))
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCardStyle())
    }
}

enum Theme {
    static let bg = Color.navy
    static let surface = Color(red: 0x0B/255, green: 0x12/255, blue: 0x1C/255)
    static let surfaceElevated = Color(red: 0x12/255, green: 0x1B/255, blue: 0x2A/255)
    static let orange = Color.orange
    static let blue = Color.blue
    static let textPrimary = Color.textPrimary
    static let textSecondary = Color.textSecondary
    static let textTertiary = Color.textTertiary
    static let hairline = Color.white.opacity(0.08)
}

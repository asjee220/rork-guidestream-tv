//
//  Theme.swift
//  GuideStreamTV
//

import SwiftUI

extension Color {
    static let navy = Color(red: 0x04/255, green: 0x09/255, blue: 0x0F/255)
    static let orange = Color(red: 0xF5/255, green: 0x82/255, blue: 0x1F/255)
    static let blue = Color(red: 0x1A/255, green: 0x6F/255, blue: 0xE8/255)
    /// Brand teal-green used for the news rail and news-specific CTAs so
    /// news content has its own visual identity across the app (carousel
    /// tiles, home panel header, breaking-news pulse).
    static let newsGreen = Color(red: 0x00/255, green: 0x9E/255, blue: 0x8A/255)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.35)
    static let glassLight = Color.white.opacity(0.07)
}

extension Font {
    static func guideHeading(size: CGFloat, weight: Weight = .bold) -> Font {
        .custom("SF Pro Display", size: size, relativeTo: .title3).weight(weight)
    }

    static func guideBody(size: CGFloat, weight: Weight = .regular) -> Font {
        .custom("SF Pro Text", size: size, relativeTo: .body).weight(weight)
    }
}

/// Picks a sensible Dynamic Type text-style anchor for a given point size so that
/// custom sizes still participate in proportional scaling.
private func defaultTextStyle(for size: CGFloat) -> Font.TextStyle {
    switch size {
    case ..<11: return .caption2
    case ..<13: return .caption
    case ..<15: return .footnote
    case ..<17: return .subheadline
    case ..<20: return .body
    case ..<22: return .title3
    case ..<28: return .title2
    case ..<34: return .title
    default: return .largeTitle
    }
}

/// View modifier that produces a system font that scales with Dynamic Type
/// while still letting designers specify an explicit point size.
struct ScaledFontModifier: ViewModifier {
    @ScaledMetric private var scaledSize: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    init(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        relativeTo textStyle: Font.TextStyle? = nil
    ) {
        let anchor = textStyle ?? defaultTextStyle(for: size)
        self._scaledSize = ScaledMetric(wrappedValue: size, relativeTo: anchor)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: scaledSize, weight: weight, design: design))
    }
}

extension View {
    /// Applies a system font that scales with Dynamic Type. Drop-in replacement
    /// for `.font(.system(size:weight:design:))`.
    func scaledFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        relativeTo textStyle: Font.TextStyle? = nil
    ) -> some View {
        modifier(ScaledFontModifier(size: size, weight: weight, design: design, relativeTo: textStyle))
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

/// A reusable full-screen background layer that renders the brand navy base
/// plus three soft radial glows (blue, orange, light-blue) for a consistent
/// "themed depth" effect across every screen, sheet, and destination in the app.
/// Replace any `Color.navy.ignoresSafeArea()` or `.background(Color.navy)` with
/// `BrandBackground()` to apply this effect.
struct BrandBackground: View {
    var body: some View {
        ZStack {
            Color.navy
            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.24))
                        .frame(width: geo.size.width * 0.95)
                        .blur(radius: 95)
                        .offset(x: -geo.size.width * 0.38, y: -geo.size.height * 0.22)
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: geo.size.width * 0.85)
                        .blur(radius: 90)
                        .offset(x: geo.size.width * 0.42, y: geo.size.height * 0.55)
                    Circle()
                        .fill(Color(red: 0x5B/255, green: 0xB0/255, blue: 0xFF/255).opacity(0.08))
                        .frame(width: geo.size.width * 0.7)
                        .blur(radius: 90)
                        .offset(x: -geo.size.width * 0.05, y: geo.size.height * 0.18)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
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

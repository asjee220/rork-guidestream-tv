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

    // MARK: - Sheet surface tokens

    /// Level-1 sheet fill — reuses the existing `#0B121C` surface constant
    /// so every sheet reads as visibly distinct from the `#04090F` app bg.
    static let sheetSurface = Theme.surface
    /// Level-2 sheet fill for sheets opened from inside another sheet.
    /// `#182335` is light enough that a nested sheet is clearly lifted.
    static let sheetSurfaceRaised = Color(red: 0x18/255, green: 0x23/255, blue: 0x35/255)

    /// Two-level elevation ladder so a nested sheet is always visibly lighter
    /// than its parent.
    enum SheetLevel: Hashable {
        case base
        case raised
    }
}

/// View modifier that applies the unified sheet surface: fill, custom drag
/// handle (36×4 capsule, white 45%), top hairline (1.5pt, white 28%), and
/// hides the system indicator. High-contrast variants (40% / 60% / 70% scrim)
/// activate via `@Environment(\.colorSchemeContrast)`.
struct SheetSurfaceModifier: ViewModifier {
    let level: Theme.SheetLevel
    let hairline: Bool
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var isHighContrast: Bool { colorSchemeContrast == .increased }

    private var surfaceColor: Color {
        level == .raised ? Theme.sheetSurfaceRaised : Theme.sheetSurface
    }

    private var handleOpacity: Double { isHighContrast ? 0.60 : 0.45 }
    private var hairlineOpacity: Double { isHighContrast ? 0.40 : 0.28 }

    func body(content: Content) -> some View {
        content
            .presentationDragIndicator(.hidden)
            .presentationBackground(surfaceColor)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    Capsule()
                        .fill(Color.white.opacity(handleOpacity))
                        .frame(width: 36, height: 4)
                        .padding(.top, 12)
                        .padding(.bottom, 12)
                    if hairline {
                        Rectangle()
                            .fill(Color.white.opacity(hairlineOpacity))
                            .frame(height: 1.5)
                    }
                }
                .frame(maxWidth: .infinity)
                .background(surfaceColor)
            }
    }
}

extension View {
    /// Unified sheet surface modifier — applies the level-appropriate fill,
    /// hides the system drag indicator, and inserts a 36×4 white-45% capsule
    /// handle with a 1.5pt white-28% top hairline via a top safe-area inset.
    /// High-contrast variants (40% hairline, 60% handle) activate
    /// automatically via `@Environment(\.colorSchemeContrast)`.
    /// Pass `hairline: false` for custom overlays that supply their own
    /// identity stroke (e.g. AskStreamSheet's orange border).
    func sheetSurface(_ level: Theme.SheetLevel = .base, hairline: Bool = true) -> some View {
        modifier(SheetSurfaceModifier(level: level, hairline: hairline))
    }

    /// Legacy alias — delegates to `sheetSurface(.base)` so existing call
    /// sites (CreatorDetailView, NotificationsSheet, etc.) inherit the new
    /// handle and hairline without code changes.
    func gsSheetChrome() -> some View {
        sheetSurface(.base)
    }
}

/// Standard header rendered directly beneath the `gsSheetChrome()` handle:
/// a 20-point bold title over an optional 13-point secondary subtitle
/// (3-point gap), inset 10 points horizontally with 8 above and 10 below.
/// The optional trailing slot renders end-aligned accessories such as count
/// pills and close buttons. Mirrors the Android `GsSheetHeader` so sheet
/// headers match across platforms.
struct GsSheetHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let trailing: () -> Trailing

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .scaledFont(size: 20, weight: .bold)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .scaledFont(size: 13)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}

extension GsSheetHeader where Trailing == EmptyView {
    /// Title-and-subtitle-only header with no trailing accessories.
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

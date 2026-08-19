//
//  Layout.swift
//  GuideStreamTV
//

import SwiftUI

/// Adaptive width classes shared by every surface that needs to reflow for
/// tablets and large windows. Breakpoints match the Android port exactly:
/// below 600pt is phone-like, 600..<840 is a small tablet or split view,
/// and 840+ is a full tablet or Stage Manager window.
enum GSWidthClass {
    case compact
    case medium
    case expanded

    /// Maps a point width to its width class.
    static func from(width: CGFloat) -> GSWidthClass {
        switch width {
        case ..<600: return .compact
        case ..<840: return .medium
        default: return .expanded
        }
    }

    /// Horizontal content clamp for full-width surfaces. `nil` means the
    /// surface keeps spanning the whole width (compact, unchanged).
    static func contentMaxWidth(for widthClass: GSWidthClass) -> CGFloat? {
        switch widthClass {
        case .compact: return nil
        case .medium: return 720
        case .expanded: return 1040
        }
    }

    /// Poster grid column count for grids that opt into adaptive columns.
    /// Exported for upcoming surfaces; Home does not use it yet.
    static func posterColumns(for widthClass: GSWidthClass) -> Int {
        switch widthClass {
        case .compact: return 3
        case .medium: return 5
        case .expanded: return 7
        }
    }
}

/// Clamps the modified view to `GSWidthClass.contentMaxWidth` for the
/// enclosing width and centres it horizontally, so wide-window content forms
/// even gutters instead of stretching edge to edge. The clamped content is
/// clipped to that frame horizontally so full-bleed rails can no longer draw
/// past the clamp's trailing edge — with vertical bleed so shadows, glows and
/// other intentional overflow keep drawing past the frame. Compact widths
/// pass through completely unchanged and unclipped.
struct GSContentWidthModifier: ViewModifier {

    /// Vertical drawing bleed kept outside the clip so effects that extend
    /// past the frame (pill shadows, FAB glows) are not cut.
    private static let clipBleed: CGFloat = 48

    @State private var widthClass: GSWidthClass = .compact

    func body(content: Content) -> some View {
        Group {
            if let maxWidth = GSWidthClass.contentMaxWidth(for: widthClass) {
                content
                    .frame(maxWidth: maxWidth)
                    .padding(.vertical, Self.clipBleed)
                    .clipped()
                    .padding(.vertical, -Self.clipBleed)
                    .frame(maxWidth: .infinity)
            } else {
                content
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            let resolved = GSWidthClass.from(width: width)
            if resolved != widthClass {
                widthClass = resolved
            }
        }
    }
}

extension View {
    /// Clamps this view to the adaptive content width for the current window,
    /// centres it horizontally, and clips the clamped content to its frame.
    /// No-op at compact widths.
    func gsContentWidth() -> some View {
        modifier(GSContentWidthModifier())
    }
}

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

extension GSWidthClass {
    /// Horizontal padding for home section containers. Full-width on tablets
    /// (expanded) so the content stretches edge-to-edge like Sports; phones
    /// and split-view windows keep their existing 12pt gutters.
    var homeHorizontalPadding: CGFloat {
        switch self {
        case .expanded: return 0
        case .medium, .compact: return 12
        }
    }

    /// Horizontal padding for the home search bar. Full-width on tablets,
    /// 16pt on phones.
    var homeSearchHorizontalPadding: CGFloat {
        switch self {
        case .expanded: return 0
        case .medium, .compact: return 16
        }
    }
}



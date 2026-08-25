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

    /// Height of the Home hero carousel.
    ///
    /// These were fixed at 250 (hero) and 200 (Today's Pick) for every width.
    /// On `.expanded` the cards go full-width, so a 13-inch iPad in landscape
    /// stretched the hero to roughly 1366x250 — a 5.5:1 slot that a 16:9
    /// backdrop drawn with `contentMode: .fill` can only fill by cropping away
    /// about two thirds of its height. Scaling the height with the width class
    /// keeps the crop near 3.4:1 on tablets; compact keeps its original value
    /// so phones are untouched.
    var homeHeroHeight: CGFloat {
        switch self {
        case .expanded: return 400
        case .medium: return 320
        case .compact: return 250
        }
    }

    /// Height of the Today's Pick backdrop. Same reasoning as `homeHeroHeight`
    /// — this one was the worse of the two at 6.8:1 on a 13-inch iPad.
    var homeTodaysPickBackdropHeight: CGFloat {
        switch self {
        case .expanded: return 380
        case .medium: return 260
        case .compact: return 200
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



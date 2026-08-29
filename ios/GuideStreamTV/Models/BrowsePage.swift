//
//  BrowsePage.swift
//  GuideStreamTV
//
//  Split out of BrowseFilters.swift when that file moved to Shared/ so the
//  tvOS target could read the genre catalogue. BrowsePage carries
//  [TMDBResult], which is an iOS-target type, so it stays on this side;
//  the tvOS target declares its own TVBrowsePage over [TVTMDBResult].
//

import Foundation

// MARK: - Page

/// One page of browse results plus the totals the count row needs.
struct BrowsePage: Hashable, Sendable {
    let results: [TMDBResult]
    let page: Int
    let totalPages: Int
    let totalResults: Int

    static let empty = BrowsePage(results: [], page: 1, totalPages: 1, totalResults: 0)
}

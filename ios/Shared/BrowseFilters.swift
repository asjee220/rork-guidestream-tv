//
//  BrowseFilters.swift
//  GuideStreamTV
//
//  Catalogue + filter model behind Search & Browse.
//
//  Deliberately free of SwiftUI: the view layer maps genre ids to artwork and
//  tint, and Android's BrowseFilters.kt is kept a line-for-line mirror of this
//  file so the two platforms cannot drift on genre ids or TMDB parameters.
//

import Foundation

// MARK: - Media type

enum BrowseMediaType: String, CaseIterable, Hashable, Sendable, Codable {
    case all, tv, movie

    var label: String {
        switch self {
        case .all: return "All"
        case .tv: return "Shows"
        case .movie: return "Movies"
        }
    }

    /// TMDB discover path component. `.all` has none — the caller runs both
    /// paths and interleaves them.
    var discoverPath: String? {
        switch self {
        case .all: return nil
        case .tv: return "tv"
        case .movie: return "movie"
        }
    }
}

// MARK: - Sort

enum BrowseSort: String, CaseIterable, Hashable, Sendable, Codable {
    case popularity, newest, rating, alphabetical

    var label: String {
        switch self {
        case .popularity: return "Most popular"
        case .newest: return "Newest"
        case .rating: return "Highest rated"
        case .alphabetical: return "A–Z"
        }
    }

    /// TMDB `sort_by`. The date and title keys differ between the tv and
    /// movie discover endpoints, so the path has to be passed in.
    func tmdbValue(for path: String) -> String {
        switch self {
        case .popularity: return "popularity.desc"
        case .newest: return path == "movie" ? "primary_release_date.desc" : "first_air_date.desc"
        case .rating: return "vote_average.desc"
        case .alphabetical: return path == "movie" ? "title.asc" : "name.asc"
        }
    }

    /// Sorting by rating without a vote floor puts 10.0-from-three-votes
    /// obscurities at the top of the grid.
    var needsVoteFloor: Bool { self == .rating }
}

// MARK: - Genre

/// One browsable genre. TMDB uses different genre ids per media type — Sci-Fi
/// is 10765 on TV but 878 on film — and two of the ten only exist on one side,
/// so both ids are carried and either may be nil.
struct BrowseGenre: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let tvGenreId: Int?
    let movieGenreId: Int?
    /// Pinned original language. Anime uses this: TMDB genre 16 is Animation,
    /// not anime, so it is narrowed to Japanese-language titles.
    let originalLanguage: String?
    /// Pipe-joined language pool, used by International, which has no genre id
    /// of its own.
    let languagePool: String?

    var supportsTV: Bool { tvGenreId != nil || languagePool != nil }
    var supportsMovie: Bool { movieGenreId != nil }

    /// The media type this genre is pinned to, or nil when it works on both.
    /// Drives the locked Type control in the filter sheet.
    var mediaLock: BrowseMediaType? {
        if supportsTV && supportsMovie { return nil }
        return supportsTV ? .tv : .movie
    }

    /// Shown under the Type control when this genre locks it.
    var lockReason: String? {
        switch mediaLock {
        case .tv: return "\(name) is a TV-only category."
        case .movie: return "\(name) titles are films."
        case .all, .none: return nil
        }
    }

    func genreId(for path: String) -> Int? {
        path == "movie" ? movieGenreId : tvGenreId
    }
}

enum BrowseCatalog {
    /// Non-English markets used by the International tile.
    static let internationalLanguages = "ko|ja|fr|de|es|it|pt|hi|ar|tr|sv|no|da|fi|nl|pl|th|zh"

    /// The ten browsable genres, in display order.
    ///
    /// Horror (27) and Romance (10749) are film-only in TMDB — there is no TV
    /// equivalent of either. Anime and International are TV-only by
    /// construction. Everything else carries a real id on both sides.
    static let genres: [BrowseGenre] = [
        BrowseGenre(id: "crime",         name: "Crime & Thriller", tvGenreId: 80,    movieGenreId: 80,    originalLanguage: nil,  languagePool: nil),
        BrowseGenre(id: "scifi",         name: "Sci-Fi",           tvGenreId: 10765, movieGenreId: 878,   originalLanguage: nil,  languagePool: nil),
        BrowseGenre(id: "horror",        name: "Horror",           tvGenreId: nil,   movieGenreId: 27,    originalLanguage: nil,  languagePool: nil),
        BrowseGenre(id: "anime",         name: "Anime",            tvGenreId: 16,    movieGenreId: nil,   originalLanguage: "ja", languagePool: nil),
        BrowseGenre(id: "comedy",        name: "Comedy",           tvGenreId: 35,    movieGenreId: 35,    originalLanguage: nil,  languagePool: nil),
        BrowseGenre(id: "drama",         name: "Drama",            tvGenreId: 18,    movieGenreId: 18,    originalLanguage: nil,  languagePool: nil),
        BrowseGenre(id: "action",        name: "Action",           tvGenreId: 10759, movieGenreId: 28,    originalLanguage: nil,  languagePool: nil),
        BrowseGenre(id: "documentary",   name: "Documentary",      tvGenreId: 99,    movieGenreId: 99,    originalLanguage: nil,  languagePool: nil),
        BrowseGenre(id: "romance",       name: "Romance",          tvGenreId: nil,   movieGenreId: 10749, originalLanguage: nil,  languagePool: nil),
        BrowseGenre(id: "international", name: "International",    tvGenreId: nil,   movieGenreId: nil,   originalLanguage: nil,  languagePool: internationalLanguages)
    ]

    static func genre(_ id: String) -> BrowseGenre? {
        genres.first { $0.id == id }
    }

    /// Selectable release-year window. The upper bound tracks the device clock
    /// so next year's titles appear without a code change.
    static var yearBounds: ClosedRange<Int> {
        let now = Calendar.current.component(.year, from: Date())
        return 1970...max(1970, now)
    }

    static let ratingOptions: [Double] = [6, 7, 8]
}

// MARK: - Filters

struct BrowseFilters: Hashable, Sendable {
    /// Selected genre slugs. Empty means "every genre".
    var genreIds: Set<String> = []
    var mediaType: BrowseMediaType = .all
    /// Restrict to the services the user actually has.
    var onlyMyServices: Bool = true
    /// TMDB provider ids, supplied by the caller from StreamsViewModel.
    var providerIds: [Int] = []
    /// Include ad-supported tiers alongside subscription ones.
    var includeFreeWithAds: Bool = true
    var yearRange: ClosedRange<Int>?
    var minRating: Double?
    var sort: BrowseSort = .popularity

    init(
        genreIds: Set<String> = [],
        mediaType: BrowseMediaType = .all,
        onlyMyServices: Bool = true,
        providerIds: [Int] = [],
        includeFreeWithAds: Bool = true,
        yearRange: ClosedRange<Int>? = nil,
        minRating: Double? = nil,
        sort: BrowseSort = .popularity
    ) {
        self.genreIds = genreIds
        self.mediaType = mediaType
        self.onlyMyServices = onlyMyServices
        self.providerIds = providerIds
        self.includeFreeWithAds = includeFreeWithAds
        self.yearRange = yearRange
        self.minRating = minRating
        self.sort = sort
    }

    var selectedGenres: [BrowseGenre] {
        BrowseCatalog.genres.filter { genreIds.contains($0.id) }
    }

    /// The genre forcing a media type, if any. When two locked genres disagree
    /// — Horror plus Anime — the first in catalogue order wins and the other is
    /// dropped by `resolved()`, because no single discover call can serve both.
    var lockingGenre: BrowseGenre? {
        selectedGenres.first { $0.mediaLock != nil }
    }

    /// Media type actually sent to TMDB once genre locks are applied.
    var resolvedMediaType: BrowseMediaType {
        lockingGenre?.mediaLock ?? mediaType
    }

    /// Drops genres that cannot run under the resolved media type, so a query
    /// is never built with an id the endpoint does not know.
    func resolved() -> BrowseFilters {
        var copy = self
        let type = resolvedMediaType
        copy.mediaType = type
        guard type != .all else { return copy }
        copy.genreIds = Set(selectedGenres.filter {
            type == .tv ? $0.supportsTV : $0.supportsMovie
        }.map(\.id))
        return copy
    }

    /// Effective provider list — empty means "do not filter by provider".
    var effectiveProviderIds: [Int] {
        onlyMyServices ? providerIds : []
    }

    /// Stable key for the results cache. Any change that alters the query has
    /// to change this string.
    var signature: String {
        let g = genreIds.sorted().joined(separator: ",")
        let p = effectiveProviderIds.sorted().map(String.init).joined(separator: ",")
        let y = yearRange.map { "\($0.lowerBound)-\($0.upperBound)" } ?? "any"
        let r = minRating.map { String(format: "%.1f", $0) } ?? "any"
        return "\(resolvedMediaType.rawValue)|\(g)|\(p)|\(includeFreeWithAds)|\(y)|\(r)|\(sort.rawValue)"
    }

    /// Count shown on the filter icon badge. Genre is excluded — it is the
    /// screen's subject, not a filter applied to it.
    var activeCount: Int {
        var n = 0
        if mediaType != .all { n += 1 }
        if onlyMyServices { n += 1 }
        if !includeFreeWithAds { n += 1 }
        if yearRange != nil { n += 1 }
        if minRating != nil { n += 1 }
        return n
    }

    var isDefault: Bool { activeCount == BrowseFilters().activeCount && mediaType == .all }
}

// MARK: - Applied-filter pills

/// One dismissible pill in the applied-filter bar.
struct BrowseFilterPill: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case mediaType, services, freeWithAds, year, rating
    }
    let kind: Kind
    let label: String
    /// True for the "My services" pill, which is tinted rather than neutral.
    let accented: Bool

    var id: String { kind.rawValue }
}

extension BrowseFilters {
    var pills: [BrowseFilterPill] {
        var out: [BrowseFilterPill] = []
        if onlyMyServices {
            out.append(BrowseFilterPill(kind: .services, label: "My services", accented: true))
        }
        if mediaType != .all {
            out.append(BrowseFilterPill(kind: .mediaType, label: mediaType.label, accented: false))
        }
        if let minRating {
            out.append(BrowseFilterPill(kind: .rating, label: "★ \(Int(minRating))+", accented: false))
        }
        if let yearRange {
            out.append(BrowseFilterPill(kind: .year, label: "\(yearRange.lowerBound)–\(yearRange.upperBound)", accented: false))
        }
        if !includeFreeWithAds {
            out.append(BrowseFilterPill(kind: .freeWithAds, label: "No ad-supported", accented: false))
        }
        return out
    }

    /// Removes one pill's filter, returning the relaxed set. Used by both the
    /// pill's ✕ and the empty-state recovery probe.
    func removing(_ kind: BrowseFilterPill.Kind) -> BrowseFilters {
        var copy = self
        switch kind {
        case .mediaType: copy.mediaType = .all
        case .services: copy.onlyMyServices = false
        case .freeWithAds: copy.includeFreeWithAds = true
        case .year: copy.yearRange = nil
        case .rating: copy.minRating = nil
        }
        return copy
    }
}

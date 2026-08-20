//
//  CountryCatalog.swift
//  GuideStreamTV (SHARED target — must compile into BOTH iOS and tvOS)
//
//  Curated destinations for the "Around the World" feature: region code,
//  display name, optional original-language code, and an ordered provider
//  list. A provider carries a region-specific TMDB id, display name, and an
//  optional original-language override that wins over the country's when set
//  (Crunchyroll is queried as Japanese anime in every market). TMDB provider
//  ids are region-specific — always use them exactly as listed here.
//
//  RORK MAX NOTE: this file lives in the SHARED group so both iOS and tvOS
//  targets compile it. It has no UIKit/SwiftUI imports.
//

import Foundation

/// One TMDB watch provider in a specific region.
nonisolated struct CountryProvider: Sendable, Equatable {
    let id: Int
    let name: String
    /// When set, this provider is queried in this language instead of the
    /// country's — lets Crunchyroll browse Japanese anime in every market.
    let originalLanguage: String?

    init(id: Int, name: String, originalLanguage: String? = nil) {
        self.id = id
        self.name = name
        self.originalLanguage = originalLanguage
    }
}

/// One curated "Around the World" destination.
nonisolated struct CountryCatalogEntry: Sendable, Equatable, Identifiable {
    /// ISO 3166-1 alpha-2 region code (also TMDB's `watch_region` value).
    let regionCode: String
    let displayName: String
    /// TMDB original-language filter for local-content discovery, or nil for
    /// English-speaking markets that browse without a language filter.
    let originalLanguage: String?
    /// Ordered TMDB provider entries — region-specific ids.
    let providers: [CountryProvider]

    var id: String { regionCode }

    /// Effective original language for a query against this provider — the
    /// provider override when present, else the country's.
    func effectiveOriginalLanguage(for provider: CountryProvider) -> String? {
        provider.originalLanguage ?? originalLanguage
    }

    /// Vote-count floor for a query. 100 for Japanese content — a
    /// content-safety requirement for animation: TMDB reports the titles it
    /// excludes as adult:false with genre [16], so no other filter catches
    /// them. 20 everywhere else. Do not lower it or make it uniform.
    func voteFloor(for provider: CountryProvider) -> Int {
        effectiveOriginalLanguage(for: provider) == "ja" ? 100 : 20
    }
}

nonisolated enum CountryCatalog {
    /// Curated destinations in rotation order (11 entries).
    static let entries: [CountryCatalogEntry] = [
        CountryCatalogEntry(regionCode: "JP", displayName: "Japan", originalLanguage: "ja", providers: [
            CountryProvider(id: 84, name: "U-NEXT"),
            CountryProvider(id: 8, name: "Netflix"),
            CountryProvider(id: 9, name: "Prime Video"),
            CountryProvider(id: 15, name: "Hulu"),
            CountryProvider(id: 337, name: "Disney+"),
        ]),
        CountryCatalogEntry(regionCode: "KR", displayName: "South Korea", originalLanguage: "ko", providers: [
            CountryProvider(id: 8, name: "Netflix"),
            CountryProvider(id: 1883, name: "TVING"),
            CountryProvider(id: 356, name: "wavve"),
            CountryProvider(id: 97, name: "Watcha"),
            CountryProvider(id: 283, name: "Crunchyroll", originalLanguage: "ja"),
        ]),
        CountryCatalogEntry(regionCode: "GB", displayName: "United Kingdom", originalLanguage: nil, providers: [
            CountryProvider(id: 38, name: "BBC iPlayer"),
            CountryProvider(id: 41, name: "ITVX"),
            CountryProvider(id: 103, name: "Channel 4"),
            CountryProvider(id: 29, name: "Sky Go"),
            CountryProvider(id: 39, name: "Now TV"),
            CountryProvider(id: 283, name: "Crunchyroll", originalLanguage: "ja"),
        ]),
        CountryCatalogEntry(regionCode: "FR", displayName: "France", originalLanguage: "fr", providers: [
            CountryProvider(id: 8, name: "Netflix"),
            CountryProvider(id: 119, name: "Prime Video"),
            CountryProvider(id: 337, name: "Disney+"),
            CountryProvider(id: 283, name: "Crunchyroll", originalLanguage: "ja"),
        ]),
        CountryCatalogEntry(regionCode: "DE", displayName: "Germany", originalLanguage: "de", providers: [
            CountryProvider(id: 8, name: "Netflix"),
            CountryProvider(id: 9, name: "Prime Video"),
            CountryProvider(id: 2750, name: "RTL+"),
            CountryProvider(id: 337, name: "Disney+"),
            CountryProvider(id: 30, name: "WOW"),
            CountryProvider(id: 29, name: "Sky Go"),
            CountryProvider(id: 283, name: "Crunchyroll", originalLanguage: "ja"),
        ]),
        CountryCatalogEntry(regionCode: "ES", displayName: "Spain", originalLanguage: "es", providers: [
            CountryProvider(id: 8, name: "Netflix"),
            CountryProvider(id: 62, name: "Atres Player"),
            CountryProvider(id: 119, name: "Prime Video"),
            CountryProvider(id: 2241, name: "Movistar+"),
            CountryProvider(id: 337, name: "Disney+"),
            CountryProvider(id: 541, name: "rtve"),
            CountryProvider(id: 1773, name: "SkyShowtime"),
            CountryProvider(id: 283, name: "Crunchyroll", originalLanguage: "ja"),
        ]),
        CountryCatalogEntry(regionCode: "IT", displayName: "Italy", originalLanguage: "it", providers: [
            CountryProvider(id: 8, name: "Netflix"),
            CountryProvider(id: 222, name: "Rai Play"),
            CountryProvider(id: 119, name: "Prime Video"),
            CountryProvider(id: 39, name: "Now TV"),
            CountryProvider(id: 29, name: "Sky Go"),
            CountryProvider(id: 337, name: "Disney+"),
            CountryProvider(id: 283, name: "Crunchyroll", originalLanguage: "ja"),
        ]),
        CountryCatalogEntry(regionCode: "IN", displayName: "India", originalLanguage: "hi", providers: [
            CountryProvider(id: 8, name: "Netflix"),
            CountryProvider(id: 119, name: "Prime Video"),
            CountryProvider(id: 2336, name: "JioHotstar"),
            CountryProvider(id: 283, name: "Crunchyroll", originalLanguage: "ja"),
        ]),
        CountryCatalogEntry(regionCode: "BR", displayName: "Brazil", originalLanguage: "pt", providers: [
            CountryProvider(id: 307, name: "Globoplay"),
            CountryProvider(id: 8, name: "Netflix"),
            CountryProvider(id: 119, name: "Prime Video"),
            CountryProvider(id: 283, name: "Crunchyroll", originalLanguage: "ja"),
        ]),
        CountryCatalogEntry(regionCode: "MX", displayName: "Mexico", originalLanguage: "es", providers: [
            CountryProvider(id: 8, name: "Netflix"),
            CountryProvider(id: 457, name: "VIX"),
            CountryProvider(id: 119, name: "Prime Video"),
            CountryProvider(id: 337, name: "Disney+"),
            CountryProvider(id: 167, name: "Claro video"),
            CountryProvider(id: 283, name: "Crunchyroll", originalLanguage: "ja"),
        ]),
        CountryCatalogEntry(regionCode: "AU", displayName: "Australia", originalLanguage: nil, providers: [
            CountryProvider(id: 21, name: "Stan"),
            CountryProvider(id: 385, name: "BINGE"),
            CountryProvider(id: 378, name: "9Now"),
            CountryProvider(id: 132, name: "SBS On Demand"),
            CountryProvider(id: 135, name: "ABC iview"),
            CountryProvider(id: 283, name: "Crunchyroll", originalLanguage: "ja"),
        ]),
    ]

    /// Rotating destination of the day: `floor(now / 86_400_000) mod 11`
    /// (11 = entry count), computed at read time so the pick advances at UTC
    /// midnight and iOS and Android agree on the country for any given day.
    /// The index is always coerced non-negative.
    static var countryOfDay: CountryCatalogEntry {
        let count = entries.count
        let millis = Date().timeIntervalSince1970 * 1000
        let day = Int(floor(millis / 86_400_000))
        let idx = ((day % count) + count) % count
        return entries[idx]
    }

    /// Entry for a region code, case-insensitive; nil on miss.
    static func entry(forRegionCode code: String) -> CountryCatalogEntry? {
        entries.first { $0.regionCode.caseInsensitiveCompare(code) == .orderedSame }
    }
}

//
//  CountryCatalog.swift
//  GuideStreamTV (SHARED target — must compile into BOTH iOS and tvOS)
//
//  Curated destinations for the "Around the World" feature: region code,
//  display name, optional original-language filter, and the ordered TMDB
//  watch providers that carry titles in that region. TMDB provider ids are
//  region-specific — always use them exactly as listed here.
//
//  RORK MAX NOTE: this file lives in the SHARED group so both iOS and tvOS
//  targets compile it. It has no UIKit/SwiftUI imports.
//

import Foundation

/// One TMDB watch provider in a specific region.
nonisolated struct CountryProvider: Sendable, Equatable {
    let id: Int
    let name: String
}

/// One curated "Around the World" destination.
nonisolated struct CountryCatalogEntry: Sendable, Equatable, Identifiable {
    /// ISO 3166-1 alpha-2 region code (also TMDB's `watch_region` value).
    let regionCode: String
    let displayName: String
    /// TMDB original-language filter for local-content discovery, or nil for
    /// English-speaking markets that browse without a language filter.
    let originalLanguage: String?
    /// Ordered TMDB provider id/name pairs — region-specific ids.
    let providers: [CountryProvider]

    var id: String { regionCode }
}

nonisolated enum CountryCatalog {
    /// Curated destinations in rotation order.
    static let entries: [CountryCatalogEntry] = [
        CountryCatalogEntry(regionCode: "JP", displayName: "Japan", originalLanguage: "ja", providers: [
            CountryProvider(id: 8, name: "Netflix"),
            CountryProvider(id: 84, name: "U-NEXT"),
            CountryProvider(id: 9, name: "Amazon Prime Video"),
            CountryProvider(id: 337, name: "Disney Plus"),
            CountryProvider(id: 15, name: "Hulu"),
        ]),
        CountryCatalogEntry(regionCode: "KR", displayName: "South Korea", originalLanguage: "ko", providers: [
            CountryProvider(id: 8, name: "Netflix"),
            CountryProvider(id: 356, name: "wavve"),
            CountryProvider(id: 1883, name: "TVING"),
            CountryProvider(id: 1881, name: "Coupang Play"),
            CountryProvider(id: 97, name: "Watcha"),
            CountryProvider(id: 119, name: "Amazon Prime Video"),
        ]),
        CountryCatalogEntry(regionCode: "GB", displayName: "United Kingdom", originalLanguage: nil, providers: [
            CountryProvider(id: 8, name: "Netflix"),
            CountryProvider(id: 38, name: "BBC iPlayer"),
            CountryProvider(id: 41, name: "ITVX"),
            CountryProvider(id: 103, name: "Channel 4"),
            CountryProvider(id: 29, name: "Sky Go"),
            CountryProvider(id: 39, name: "Now TV"),
            CountryProvider(id: 9, name: "Amazon Prime Video"),
            CountryProvider(id: 337, name: "Disney Plus"),
        ]),
        CountryCatalogEntry(regionCode: "FR", displayName: "France", originalLanguage: "fr", providers: [
            CountryProvider(id: 8, name: "Netflix"),
            CountryProvider(id: 119, name: "Amazon Prime Video"),
            CountryProvider(id: 337, name: "Disney Plus"),
            CountryProvider(id: 147, name: "M6+"),
            CountryProvider(id: 531, name: "Paramount Plus"),
            CountryProvider(id: 283, name: "Crunchyroll"),
        ]),
        CountryCatalogEntry(regionCode: "DE", displayName: "Germany", originalLanguage: "de", providers: [
            CountryProvider(id: 8, name: "Netflix"),
            CountryProvider(id: 9, name: "Amazon Prime Video"),
            CountryProvider(id: 2750, name: "RTL+"),
            CountryProvider(id: 304, name: "Joyn"),
            CountryProvider(id: 30, name: "WOW"),
            CountryProvider(id: 219, name: "ARD Mediathek"),
            CountryProvider(id: 337, name: "Disney Plus"),
            CountryProvider(id: 29, name: "Sky Go"),
        ]),
        CountryCatalogEntry(regionCode: "ES", displayName: "Spain", originalLanguage: "es", providers: [
            CountryProvider(id: 8, name: "Netflix"),
            CountryProvider(id: 119, name: "Amazon Prime Video"),
            CountryProvider(id: 2241, name: "Movistar Plus+"),
            CountryProvider(id: 62, name: "Atres Player"),
            CountryProvider(id: 541, name: "rtve"),
            CountryProvider(id: 1773, name: "SkyShowtime"),
            CountryProvider(id: 337, name: "Disney Plus"),
            CountryProvider(id: 63, name: "Filmin"),
        ]),
        CountryCatalogEntry(regionCode: "IT", displayName: "Italy", originalLanguage: "it", providers: [
            CountryProvider(id: 8, name: "Netflix"),
            CountryProvider(id: 119, name: "Amazon Prime Video"),
            CountryProvider(id: 222, name: "Rai Play"),
            CountryProvider(id: 359, name: "Mediaset Infinity"),
            CountryProvider(id: 39, name: "Now TV"),
            CountryProvider(id: 109, name: "Timvision"),
            CountryProvider(id: 337, name: "Disney Plus"),
            CountryProvider(id: 29, name: "Sky Go"),
        ]),
        CountryCatalogEntry(regionCode: "IN", displayName: "India", originalLanguage: "hi", providers: [
            CountryProvider(id: 8, name: "Netflix"),
            CountryProvider(id: 119, name: "Amazon Prime Video"),
            CountryProvider(id: 2336, name: "JioHotstar"),
            CountryProvider(id: 232, name: "Zee5"),
            CountryProvider(id: 237, name: "Sony Liv"),
            CountryProvider(id: 515, name: "MX Player"),
            CountryProvider(id: 532, name: "aha"),
        ]),
        CountryCatalogEntry(regionCode: "BR", displayName: "Brazil", originalLanguage: "pt", providers: [
            CountryProvider(id: 8, name: "Netflix"),
            CountryProvider(id: 119, name: "Amazon Prime Video"),
            CountryProvider(id: 307, name: "Globoplay"),
            CountryProvider(id: 337, name: "Disney Plus"),
            CountryProvider(id: 531, name: "Paramount Plus"),
            CountryProvider(id: 47, name: "Looke"),
        ]),
        CountryCatalogEntry(regionCode: "MX", displayName: "Mexico", originalLanguage: "es", providers: [
            CountryProvider(id: 8, name: "Netflix"),
            CountryProvider(id: 119, name: "Amazon Prime Video"),
            CountryProvider(id: 457, name: "VIX"),
            CountryProvider(id: 337, name: "Disney Plus"),
            CountryProvider(id: 531, name: "Paramount Plus"),
            CountryProvider(id: 167, name: "Claro video"),
        ]),
        CountryCatalogEntry(regionCode: "AU", displayName: "Australia", originalLanguage: nil, providers: [
            CountryProvider(id: 8, name: "Netflix"),
            CountryProvider(id: 119, name: "Amazon Prime Video"),
            CountryProvider(id: 21, name: "Stan"),
            CountryProvider(id: 385, name: "BINGE"),
            CountryProvider(id: 135, name: "ABC iview"),
            CountryProvider(id: 132, name: "SBS On Demand"),
            CountryProvider(id: 378, name: "9Now"),
            CountryProvider(id: 337, name: "Disney Plus"),
        ]),
        CountryCatalogEntry(regionCode: "CA", displayName: "Canada", originalLanguage: nil, providers: [
            CountryProvider(id: 8, name: "Netflix"),
            CountryProvider(id: 119, name: "Amazon Prime Video"),
            CountryProvider(id: 230, name: "Crave"),
            CountryProvider(id: 337, name: "Disney Plus"),
            CountryProvider(id: 531, name: "Paramount Plus"),
            CountryProvider(id: 283, name: "Crunchyroll"),
        ]),
    ]

    /// Rotating destination of the day: `floor(now / 86_400_000) mod count`,
    /// computed at read time so the pick advances at UTC midnight and iOS and
    /// Android agree on the country for any given day. The index is always
    /// coerced non-negative.
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

//
//  HomeView.swift
//  GuideStreamTV
//

import SwiftUI
import AppKit
import UserNotifications

// MARK: - Home Models

struct Platform {
    let name: String
    let color: Color
    var textColor: Color
    var catalogId: String?
    var displayName: String

    init(name: String, color: Color, textColor: Color = .white, catalogId: String? = nil, displayName: String? = nil) {
        self.name = name
        self.color = color
        self.textColor = textColor
        self.catalogId = catalogId
        self.displayName = displayName ?? name
    }

    // MARK: - Legacy pins (12 tvOS catalogue entries, exact label + colour)

    static let netflix     = Platform(name: "NETFLIX",     color: Color(red: 0xE5/255, green: 0x09/255, blue: 0x14/255), catalogId: "netflix",     displayName: "Netflix")
    static let hbo         = Platform(name: "HBO",         color: Color(red: 0x5A/255, green: 0x1F/255, blue: 0xCB/255), catalogId: "max",         displayName: "Max")
    static let appleTV     = Platform(name: "Apple TV+",   color: Color(red: 0x10/255, green: 0x10/255, blue: 0x10/255), catalogId: "appletv",     displayName: "Apple TV+")
    static let hulu        = Platform(name: "HULU",        color: Color(red: 0x1C/255, green: 0xE7/255, blue: 0x83/255), catalogId: "hulu",        displayName: "Hulu")
    static let prime       = Platform(name: "PRIME",       color: Color(red: 0x00/255, green: 0xA8/255, blue: 0xE1/255), catalogId: "prime",       displayName: "Prime Video")
    static let disney      = Platform(name: "DISNEY+",     color: Color(red: 0x11/255, green: 0x3C/255, blue: 0xCF/255), catalogId: "disney",      displayName: "Disney+")
    static let paramount   = Platform(name: "PARAMOUNT+", color: Color(red: 0x00/255, green: 0x64/255, blue: 0xFF/255), catalogId: "paramount",   displayName: "Paramount+")
    static let peacock     = Platform(name: "PEACOCK",     color: Color(red: 0x00/255, green: 0x00/255, blue: 0x00/255), catalogId: "peacock",     displayName: "Peacock")
    static let starz       = Platform(name: "STARZ",       color: Color(red: 0x00/255, green: 0x00/255, blue: 0x00/255), catalogId: "starz",       displayName: "Starz")
    static let showtime    = Platform(name: "SHOWTIME",    color: Color(red: 0xD8/255, green: 0x00/255, blue: 0x00/255), catalogId: "showtime",    displayName: "Showtime")
    static let crunchyroll = Platform(name: "CRUNCHYROLL", color: Color(red: 0xF4/255, green: 0x7B/255, blue: 0x20/255), catalogId: "crunchyroll", displayName: "Crunchyroll")
    static let youtube     = Platform(name: "YOUTUBE",     color: Color(red: 0xFF/255, green: 0x00/255, blue: 0x00/255), catalogId: "youtube",     displayName: "YouTube")

    // MARK: - hbo / max equivalence

    /// The server brand map uses the iPhone namespace where HBO is `hbo`,
    /// while the tvOS StreamingCatalog uses `max`. This normalises both
    /// directions so resolved catalog ids always match tvOS service ids.
    static func normalizeCatalogId(_ id: String) -> String {
        id == "hbo" ? "max" : id
    }

    // MARK: - Normalisation

    /// Lowercase, strip channel suffixes, strip leading "the", replace
    /// standalone "plus" with "+", then remove every character that is
    /// not a lowercase letter or digit.
    private static func normalise(_ raw: String) -> String {
        var s = raw.lowercased()
        let suffixes = ["amazon channel", "apple tv channel", "roku premium channel"]
        for suffix in suffixes where s.hasSuffix(suffix) {
            s = String(s.dropLast(suffix.count))
            break
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("the ") { s = String(s.dropFirst(4)) }
        s = s.split(separator: " ").map { $0 == "plus" ? "+" : String($0) }.joined(separator: " ")
        return s.filter { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") }
    }

    // MARK: - Text colour from luminance

    private static func textColor(for bg: Color) -> Color {
        let ui = NSColor(bg).usingColorSpace(.sRGB) ?? .white
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let lum = 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)
        return lum > 0.6
            ? Color(red: Double(r) * 0.15, green: Double(g) * 0.15, blue: Double(b) * 0.15)
            : .white
    }

    // MARK: - Hex colour parsing

    /// Parses a 6-digit hex string (no leading #) into a Color, or nil.
    private static func colorFromHex(_ hex: String) -> Color? {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    /// Builds a Platform from a server brand-map row, preferring the
    /// canonical badge_label and badge_hex columns. Returns nil when
    /// either field is absent, signalling the caller to try local fallback.
    private static func platformFromRow(_ row: TVProviderBrandRow, catalogId: String) -> Platform? {
        if let hex = row.badgeHex, let color = colorFromHex(hex),
           let label = row.badgeLabel, !label.isEmpty {
            return Platform(
                name: label.uppercased(),
                color: color,
                textColor: textColor(for: color),
                catalogId: catalogId,
                displayName: label
            )
        }
        return nil
    }

    // MARK: - Legacy lookup by catalog id

    private static func legacyByCatalogId(_ id: String) -> Platform? {
        switch id {
        case "netflix":     return .netflix
        case "max":         return .hbo
        case "appletv":     return .appleTV
        case "hulu":        return .hulu
        case "prime":       return .prime
        case "disney":      return .disney
        case "paramount":   return .paramount
        case "peacock":     return .peacock
        case "starz":       return .starz
        case "showtime":    return .showtime
        case "crunchyroll": return .crunchyroll
        case "youtube":     return .youtube
        default:            return nil
        }
    }

    // MARK: - Local fallback (12 tvOS catalogue entries)

    private static func localFallback(for normalised: String) -> Platform? {
        for service in StreamingCatalog.all {
            if normalise(service.name) == normalised {
                return legacyByCatalogId(service.id)
            }
        }
        return nil
    }

    // MARK: - Resolution: provider id (primary)

    /// Looks up a TMDB provider id in the server brand map. Returns a
    /// Platform only when the row carries a non-null catalog_id. Returns
    /// nil otherwise so callers hide the item rather than label it
    /// generically.
    static func from(providerId: Int) -> Platform? {
        guard providerId > 0 else { return nil }
        guard let row = TVProviderBrandMapService.shared.rows.first(where: { $0.tmdbProviderId == providerId }) else { return nil }
        guard let catalogId = row.catalogId else { return nil }
        let normalized = normalizeCatalogId(catalogId)
        if let legacy = legacyByCatalogId(normalized) { return legacy }
        // Prefer badge_hex and badge_label from the server map.
        if let p = platformFromRow(row, catalogId: normalized) { return p }
        // Fall back to local catalogue entry if one exists.
        if let legacy = localFallback(for: normalized) { return legacy }
        // Null or missing badge fields — hide the item.
        return nil
    }

    // MARK: - Resolution: provider name (fallback)

    /// Maps a TMDB watch-provider name to a branded Platform. Returns nil
    /// if we don't recognise the provider, so callers can hide items
    /// rather than label them generically. Resolution order: server map
    /// by alias, then local fallback, then nil. No substring or contains
    /// fallback at any stage — that is precisely the defect being removed.
    static func from(providerName raw: String?) -> Platform? {
        guard let raw, !raw.isEmpty else { return nil }
        let normalised = normalise(raw)

        // 1. Server map by alias
        for row in TVProviderBrandMapService.shared.rows {
            for alias in row.aliases {
                if normalise(alias) == normalised {
                    guard let catalogId = row.catalogId else { return nil }
                    let normalized = normalizeCatalogId(catalogId)
                    if let legacy = legacyByCatalogId(normalized) { return legacy }
                    // Prefer badge_hex and badge_label from the server map.
                    if let p = platformFromRow(row, catalogId: normalized) { return p }
                    // Fall back to local catalogue entry if one exists.
                    if let legacy = localFallback(for: normalized) { return legacy }
                    return nil
                }
            }
        }

        // 2. Local fallback (12 tvOS catalogue entries)
        return localFallback(for: normalised)
    }
}

struct Episode: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let season: String
    let duration: String
    let platform: String
    let platformColor: Color
    let isNew: Bool
    let progress: Double
    let posterColors: [Color]
    let symbol: String
    let posterUrl: String?
    let tmdbId: Int?

    init(title: String, season: String, duration: String, platform: Platform, isNew: Bool = false, progress: Double = 0, posterColors: [Color], symbol: String, posterUrl: String? = nil, tmdbId: Int? = nil) {
        self.title = title
        self.season = season
        self.duration = duration
        self.platform = platform.name
        self.platformColor = platform.color
        self.isNew = isNew
        self.progress = progress
        self.posterColors = posterColors
        self.symbol = symbol
        self.posterUrl = posterUrl
        self.tmdbId = tmdbId
    }
}

struct PosterShow: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let meta: String
    let posterColors: [Color]
    let symbol: String
    var posterUrl: String? = nil
    var tmdbId: Int? = nil
    /// nil when the source row does not say. GUI-70's glyph is simply omitted
    /// then — an unknown draws nothing rather than guessing, which is how the
    /// watchlist ended up labelling saved movies as series.
    var isTV: Bool? = nil
}

/// Default gradient colors used as a tasteful fallback while TMDB images load or when they fail.
enum HomeFallback {
    static let posterColors: [Color] = [
        Color(red: 0.20, green: 0.15, blue: 0.45),
        Color(red: 0.04, green: 0.02, blue: 0.10)
    ]
}

//
//  TVTitleID.swift
//  GuideStreamTVTV
//
//  Parses stored title identifiers into TMDB integer ids, media-type hints,
//  and YouTube channel ids for the tvOS target. Mirrors the semantics of
//  ios/GuideStreamTV/Models/TitleID.swift (duplicated deliberately per the
//  project convention of copying shared types into the tvOS target rather
//  than sharing file membership) and adds the two extra helpers the tvOS
//  detail sheet needs for bare-numeric ids and YouTube creator rows.
//

import Foundation

enum TVTitleID {
    /// Returns the TMDB integer id encoded in `raw`, or `nil` when `raw` is
    /// nil/empty, not a TMDB identifier, or does not parse as an integer.
    /// Accepts both the bare integer form ("94997") and the legacy prefixed
    /// form ("tmdb:tv:1396"), stripping the prefix case-insensitively.
    /// Identifiers for other content kinds ("yt:", "tw:", "pod:", sports ids
    /// such as "tt-chw-phi-mlb") return `nil` so they keep routing through
    /// their existing non-TMDB code paths.
    static func tmdbId(from raw: String?) -> Int? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let direct = Int(trimmed) { return direct }
        let lower = trimmed.lowercased()
        for prefix in ["tmdb:tv:", "tmdb:movie:"] {
            if lower.hasPrefix(prefix) {
                let remainder = String(trimmed.dropFirst(prefix.count))
                return Int(remainder.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return nil
    }

    /// Returns "tv" for a "tmdb:tv:" prefix, "movie" for a "tmdb:movie:"
    /// prefix, and `nil` for a bare numeric id or any non-TMDB identifier.
    static func mediaType(from raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("tmdb:tv:") { return "tv" }
        if lower.hasPrefix("tmdb:movie:") { return "movie" }
        return nil
    }

    /// Returns the substring after a case-insensitive leading "yt:" when the
    /// remainder is non-empty, and `nil` otherwise. Used to detect YouTube
    /// creator rows and extract their channel id.
    static func youtubeChannelId(from raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("yt:") else { return nil }
        let remainder = String(trimmed.dropFirst(3))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return remainder.isEmpty ? nil : remainder
    }
}

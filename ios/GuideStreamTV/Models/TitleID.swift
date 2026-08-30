//
//  TitleID.swift
//  GuideStreamTV
//

import Foundation

/// Parses stored title identifiers into TMDB integer ids.
///
/// Legacy watchlist rows may store a prefixed identifier such as
/// `"tmdb:tv:125988"` instead of the bare `"125988"`. `Int(titleId)`
/// returns `nil` for the prefixed form, which suppresses TMDB source
/// resolution and, combined with placeholder defaults, could render the
/// wrong title's content. This helper strips the known `tmdb:tv:` /
/// `tmdb:movie:` prefix (case-insensitively) before parsing.
///
/// Identifiers for other content kinds (`yt:`, `tw:`, `pod:`, sports ids
/// such as `tt-chw-phi-mlb`, etc.) intentionally return `nil` so they keep
/// routing through their existing non-TMDB code paths.
enum TitleID {
    /// Returns the TMDB integer id encoded in `raw`, or `nil` when `raw` is
    /// nil/empty, not a TMDB identifier, or does not parse as an integer.
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

    /// True for a TV title, false for a movie, nil when `raw` carries no media
    /// type — a bare integer, a creator/podcast/sports id, or nothing at all.
    ///
    /// The companion to `UserStream.isTV`, which is nil on legacy rows written
    /// before `is_tv` existed and on every non-TMDB entity. Callers that used
    /// to write `item.isTV ?? true` were guessing, and guessing "series" put a
    /// TV label on saved movies.
    static func isTV(from raw: String?) -> Bool? {
        guard let raw else { return nil }
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.hasPrefix("tmdb:tv:") { return true }
        if lower.hasPrefix("tmdb:movie:") { return false }
        return nil
    }
}

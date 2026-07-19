package com.rork.guidestreamtvandroid.data.models

/**
 * Parses stored title identifiers into TMDB integer ids.
 *
 * Legacy watchlist rows may store a prefixed identifier such as
 * `"tmdb:tv:125988"` instead of the bare `"125988"`. `String.toIntOrNull`
 * returns `null` for the prefixed form, which suppresses TMDB source
 * resolution. This helper strips the known `tmdb:tv:` / `tmdb:movie:`
 * prefix (case-insensitively) before parsing.
 *
 * Identifiers for other content kinds (`yt:`, `tw:`, `pod:`, sports ids
 * such as `tt-chw-phi-mlb`, etc.) intentionally return `null` so they keep
 * routing through their existing non-TMDB code paths.
 */
object TitleId {
    /**
     * Returns the TMDB integer id encoded in [raw], or `null` when [raw] is
     * null/blank, not a TMDB identifier, or does not parse as an integer.
     */
    fun tmdbId(raw: String?): Int? {
        if (raw == null) return null
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null
        trimmed.toIntOrNull()?.let { return it }
        val lower = trimmed.lowercase()
        for (prefix in listOf("tmdb:tv:", "tmdb:movie:")) {
            if (lower.startsWith(prefix)) {
                return trimmed.drop(prefix.length).trim().toIntOrNull()
            }
        }
        return null
    }
}

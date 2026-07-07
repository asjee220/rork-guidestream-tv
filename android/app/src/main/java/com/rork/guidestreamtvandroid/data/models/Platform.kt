package com.rork.guidestreamtvandroid.data.models

import androidx.compose.ui.graphics.Color

/**
 * Platform brand mapping — mirrors iOS Platform struct in HomeView.swift.
 * Maps TMDB watch-provider names to branded platform colors.
 */
data class Platform(
    val name: String,
    val color: Color,
) {
    companion object {
        val Netflix = Platform("NETFLIX", Color(0xFFE50914))
        val Hbo = Platform("HBO", Color(0xFF5A1FCB))
        val AppleTV = Platform("Apple TV+", Color(0xFF101010))
        val Hulu = Platform("HULU", Color(0xFF1CE783))
        val Prime = Platform("PRIME", Color(0xFF00A8E1))
        val Disney = Platform("DISNEY+", Color(0xFF113CCF))
        val Paramount = Platform("PARAMOUNT+", Color(0xFF0064FF))
        val Peacock = Platform("PEACOCK", Color(0xFF000000))
        val Starz = Platform("STARZ", Color(0xFF000000))
        val Showtime = Platform("SHOWTIME", Color(0xFFD80000))
        val Crunchyroll = Platform("CRUNCHYROLL", Color(0xFFF47B20))
        val YouTube = Platform("YOUTUBE", Color(0xFFFF0000))

        /** Default fallback color for unresolved platforms. */
        val Default = Platform("STREAM", Color(0xFFF5821F))

        /** Maps a TMDB watch-provider name to a branded Platform. */
        fun from(providerName: String?): Platform? {
            if (providerName.isNullOrEmpty()) return null
            val key = providerName.lowercase()
            return when {
                key.contains("netflix") -> Netflix
                key.contains("max") || key.contains("hbo") -> Hbo
                key.contains("apple tv") -> AppleTV
                key.contains("disney") -> Disney
                key.contains("hulu") -> Hulu
                key.contains("amazon") || key.contains("prime video") -> Prime
                key.contains("paramount") -> Paramount
                key.contains("peacock") -> Peacock
                key.contains("starz") -> Starz
                key.contains("showtime") -> Showtime
                key.contains("crunchyroll") -> Crunchyroll
                key.contains("youtube") -> YouTube
                else -> null
            }
        }

        /** Hex string for widget payloads. */
        fun colorHex(platform: Platform?): String {
            val c = platform?.color ?: Color(0xFFF5821F)
            return String.format("#%08X", c.value.toInt())
        }
    }
}

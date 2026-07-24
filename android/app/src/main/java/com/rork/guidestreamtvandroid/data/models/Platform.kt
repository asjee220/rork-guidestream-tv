package com.rork.guidestreamtvandroid.data.models

import androidx.compose.ui.graphics.Color
import com.rork.guidestreamtvandroid.data.remote.ProviderBrandMapService
import kotlin.math.absoluteValue

/**
 * Platform brand mapping — mirrors iOS Platform struct.
 * Resolves TMDB watch-provider ids and names to branded platform colours
 * via the server brand map (primary) with a local catalogue fallback.
 */
data class Platform(
    val name: String,
    val color: Color,
    val textColor: Color = Color.White,
    val catalogId: String? = null,
) {
    companion object {
        // 12 legacy pinned brands — exact label + colour + white text.
        val Netflix = Platform("NETFLIX", Color(0xFFE50914), Color.White, "netflix")
        val Hbo = Platform("HBO", Color(0xFF5A1FCB), Color.White, "hbo")
        val AppleTV = Platform("Apple TV+", Color(0xFF101010), Color.White, "appletv")
        val Hulu = Platform("HULU", Color(0xFF1CE783), Color.White, "hulu")
        val Prime = Platform("PRIME", Color(0xFF00A8E1), Color.White, "prime")
        val Disney = Platform("DISNEY+", Color(0xFF113CCF), Color.White, "disney")
        val Paramount = Platform("PARAMOUNT+", Color(0xFF0064FF), Color.White, "paramount")
        val Peacock = Platform("PEACOCK", Color(0xFF000000), Color.White, "peacock")
        val Starz = Platform("STARZ", Color(0xFF000000), Color.White, "starz")
        val Showtime = Platform("SHOWTIME", Color(0xFFD80000), Color.White, "showtime")
        val Crunchyroll = Platform("CRUNCHYROLL", Color(0xFFF47B20), Color.White, "crunchyroll")
        val YouTube = Platform("YOUTUBE", Color(0xFFFF0000), Color.White, "youtube")

        private val legacyPins = mapOf(
            "netflix" to Netflix, "hbo" to Hbo, "appletv" to AppleTV, "hulu" to Hulu,
            "prime" to Prime, "disney" to Disney, "paramount" to Paramount, "peacock" to Peacock,
            "starz" to Starz, "showtime" to Showtime, "crunchyroll" to Crunchyroll, "youtube" to YouTube,
        )

        /** Default fallback color for unresolved platforms. */
        val Default = Platform("STREAM", Color(0xFFF5821F))

        // ── Normalisation ──────────────────────────────────────────────

        private fun normalise(raw: String): String {
            var s = raw.lowercase()
            // Strip a single trailing parenthetical group, e.g. "starz (via amazon prime)" → "starz"
            val trimmed = s.trim()
            if (trimmed.endsWith(")") && trimmed.contains("(")) {
                val openIdx = trimmed.lastIndexOf("(")
                s = trimmed.substring(0, openIdx).trim()
            }
            for (suffix in listOf("amazon channel", "apple tv channel", "roku premium channel")) {
                if (s.endsWith(suffix)) s = s.dropLast(suffix.length)
            }
            s = s.trim()
            if (s.startsWith("the ")) s = s.drop(4)
            s = s.split(" ").joinToString(" ") { if (it == "plus") "+" else it }
            return s.filter { (it in 'a'..'z') || (it in '0'..'9') }
        }

        // ── Text colour from luminance ─────────────────────────────────

        private fun textColorFor(bg: Color): Color {
            val v = bg.value.toInt()
            val r = ((v shr 16) and 0xFF) / 255.0
            val g = ((v shr 8) and 0xFF) / 255.0
            val b = (v and 0xFF) / 255.0
            val lum = 0.299 * r + 0.587 * g + 0.114 * b
            return if (lum > 0.6) {
                Color(
                    red = (r * 0.15).toFloat(),
                    green = (g * 0.15).toFloat(),
                    blue = (b * 0.15).toFloat(),
                    alpha = 1f,
                )
            } else Color.White
        }

        // ── Hex colour parsing ───────────────────────────────────────

        /** Parses a 6-digit hex string (no leading #) into a Color, or null. */
        private fun colorFromHex(hex: String): Color? {
            val cleaned = if (hex.startsWith("#")) hex.drop(1) else hex
            if (cleaned.length != 6) return null
            val value = cleaned.toLongOrNull(16) ?: return null
            val r = ((value shr 16) and 0xFF) / 255.0
            val g = ((value shr 8) and 0xFF) / 255.0
            val b = (value and 0xFF) / 255.0
            return Color(
                red = r.toFloat(),
                green = g.toFloat(),
                blue = b.toFloat(),
                alpha = 1f,
            )
        }

        // ── ID-based resolution (primary) ──────────────────────────────

        /** Resolves a Platform from the stable TMDB provider id via the
         * server brand map. Returns null when the provider is not in the
         * app's catalogue (null catalog_id) or when the id is not in the map.
         * Prefers badge_hex and badge_label from the server map; falls back
         * to the local catalogue entry's glow colour and name when absent. */
        fun fromProviderId(providerId: Int): Platform? {
            if (providerId <= 0) return null
            val row = ProviderBrandMapService.get().rows.firstOrNull { it.tmdbProviderId == providerId }
                ?: return null
            val catalogId = row.catalogId ?: return null
            legacyPins[catalogId]?.let { return it }
            // Prefer badge_hex and badge_label from the server map.
            if (row.badgeHex != null && row.badgeLabel != null && row.badgeLabel!!.isNotEmpty()) {
                val color = colorFromHex(row.badgeHex!!)
                if (color != null) {
                    return Platform(row.badgeLabel!!, color, textColorFor(color), catalogId)
                }
            }
            // Fall back to local catalogue entry.
            val svc = StreamingCatalog.service(catalogId) ?: return null
            return Platform(svc.name, svc.glow, textColorFor(svc.glow), catalogId)
        }

        // ── Name-based resolution (fallback + legacy call sites) ───────

        /** Resolves a Platform from a display name. Resolution order:
         * 1. Legacy pins by normalised name
         * 2. Server map by alias
         * 3. Local catalogue derivation (by normalised name, then by id)
         * 4. null — title is hidden from provider-gated rails.
         * No generic substring/contains fallback at any stage. */
        fun from(providerName: String?): Platform? {
            if (providerName.isNullOrEmpty()) return null
            val normalised = normalise(providerName)
            if (normalised.isEmpty()) return null

            // 1. Legacy pins by normalised name
            for (pin in legacyPins.values) {
                if (normalise(pin.name) == normalised) return pin
            }

            // 2. Server map by alias
            for (row in ProviderBrandMapService.get().rows) {
                if (row.aliases.any { normalise(it) == normalised }) {
                    val catalogId = row.catalogId
                    if (catalogId != null) {
                        legacyPins[catalogId]?.let { return it }
                        // Prefer badge_hex and badge_label from the server map.
                        if (row.badgeHex != null && row.badgeLabel != null && row.badgeLabel!!.isNotEmpty()) {
                            val color = colorFromHex(row.badgeHex!!)
                            if (color != null) {
                                return Platform(row.badgeLabel!!, color, textColorFor(color), catalogId)
                            }
                        }
                        // Fall back to local catalogue entry.
                        val svc = StreamingCatalog.service(catalogId)
                        if (svc != null) return Platform(svc.name, svc.glow, textColorFor(svc.glow), catalogId)
                    }
                    return null
                }
            }

            // 3. Local catalogue derivation by normalised name, then by id
            for (svc in StreamingCatalog.all) {
                if (normalise(svc.name) == normalised) {
                    legacyPins[svc.id]?.let { return it }
                    return Platform(svc.name, svc.glow, textColorFor(svc.glow), svc.id)
                }
            }
            for (svc in StreamingCatalog.all) {
                if (svc.id == normalised) {
                    legacyPins[svc.id]?.let { return it }
                    return Platform(svc.name, svc.glow, textColorFor(svc.glow), svc.id)
                }
            }

            // 4. No match
            return null
        }

        /** Hex string for widget payloads. */
        fun colorHex(platform: Platform?): String {
            val c = platform?.color ?: Color(0xFFF5821F)
            return String.format("#%08X", c.value.toInt())
        }
    }
}

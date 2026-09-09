package com.rork.guidestreamtvandroid.ui.sports

import androidx.compose.ui.graphics.Color
import com.rork.guidestreamtvandroid.data.models.SportsGame
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** Card + surface colors mirroring the iOS Sports palette. */
internal val SportsBackground = Color(red = 0x04, green = 0x09, blue = 0x0F)
internal val SportsCard = Color(red = 0x16, green = 0x1B, blue = 0x27)
internal val SportsCardDim = Color(red = 0x12, green = 0x16, blue = 0x1F)
internal val SportsSheet = Color(red = 0x13, green = 0x18, blue = 0x1D)
internal val SportsRed = Color(red = 0xE5, green = 0x09, blue = 0x14)

/** Parse an ESPN team color hex (no leading #) into a Compose Color. */
internal fun hexToColor(hex: String?, fallback: Color = Color.White.copy(alpha = 0.2f)): Color {
    if (hex.isNullOrBlank()) return fallback
    val clean = hex.trim().removePrefix("#")
    return try {
        when (clean.length) {
            6 -> {
                val v = clean.toLong(16)
                Color(
                    red = ((v shr 16) and 0xFF) / 255f,
                    green = ((v shr 8) and 0xFF) / 255f,
                    blue = (v and 0xFF) / 255f,
                )
            }
            8 -> {
                val v = clean.toLong(16)
                Color(
                    red = ((v shr 24) and 0xFF) / 255f,
                    green = ((v shr 16) and 0xFF) / 255f,
                    blue = ((v shr 8) and 0xFF) / 255f,
                    alpha = (v and 0xFF) / 255f,
                )
            }
            else -> fallback
        }
    } catch (_: Exception) {
        fallback
    }
}

/** Broadcast badge background color, mirroring iOS broadcastColor(). */
internal fun broadcastColor(name: String): Color {
    val lower = name.lowercase()
    return when {
        lower.contains("espn") -> Color(0xFFCC0000)
        lower.contains("peacock") -> Color(0xFF1A1A1A)
        lower.contains("prime") || lower.contains("amazon") -> Color(0xFF00A8E0)
        lower.contains("apple") -> Color(0xFF1F1F1F)
        lower.contains("paramount") -> Color(0xFF0064FF)
        lower.contains("max") || lower.contains("hbo") -> Color(0xFF002BE7)
        lower.contains("nbc") -> Color(0xFFFCB900)
        lower.contains("fox") -> Color(0xFF003366)
        lower.contains("cbs") -> Color(0xFF003366)
        lower.contains("abc") -> Color(0xFF1A1A1A)
        lower.contains("tnt") || lower.contains("tbs") -> Color(0xFFE2231A)
        else -> Color.White.copy(alpha = 0.15f)
    }
}

/** Normalized names that are already streaming destinations — never get a companion. */
private val streamingDestinations = setOf(
    "peacock", "peacockpremium", "paramount", "paramountplus", "primevideo",
    "amazonprime", "netflix", "appletv", "appletvplus", "hbomax", "max",
    "hulu", "fubo", "fubotv", "slingtv", "youtube", "youtubetv", "tubi",
    "disneyplus", "espn", "espnplus", "nflplus", "nbaleaguepass", "mlbtv",
    "foxone",
)

/**
 * Exact normalized key → streaming companion. Matched exactly, never by
 * substring, so unexpected network names (MSG, FDSSO, …) yield nothing.
 */
private val simulcastCompanions = mapOf(
    "nbc" to "Peacock", "nbcsn" to "Peacock", "cnbc" to "Peacock",
    "usa" to "Peacock", "usanetwork" to "Peacock", "usanet" to "Peacock",
    "telemundo" to "Peacock",
    "universo" to "Peacock", "golf" to "Peacock", "golfchannel" to "Peacock",
    "cbs" to "Paramount+", "cbssn" to "Paramount+", "cbssportsnetwork" to "Paramount+",
    "abc" to "ESPN", "espn2" to "ESPN", "espnu" to "ESPN", "espnews" to "ESPN",
    "espndeportes" to "ESPN", "secn" to "ESPN", "secnetwork" to "ESPN",
    "secnplus" to "ESPN",
    "accn" to "ESPN", "accnetwork" to "ESPN",
    "fox" to "Fox One", "foxsports" to "Fox One", "fs1" to "Fox One",
    "fs2" to "Fox One", "btn" to "Fox One", "bigtennetwork" to "Fox One",
    "foxdeportes" to "Fox One",
    "tnt" to "HBO Max", "tbs" to "HBO Max", "trutv" to "HBO Max",
    "nfln" to "NFL+", "nflnetwork" to "NFL+",
    "nbatv" to "NBA League Pass",
    "mlbn" to "MLB.TV", "mlbnetwork" to "MLB.TV",
)

/** Lowercased with every non-alphanumeric character removed. */
private fun normalizeBroadcast(name: String): String =
    name.lowercase().filter { it.isLetterOrDigit() }

/**
 * Deterministic linear-network → streaming-companion lookup for the sports
 * Where to Watch chips, mirroring iOS SportsSimulcast.enrich(). ESPN's public
 * scoreboard only reports the linear carrier (e.g. "NBC") and never the
 * streaming simulcast (e.g. Peacock). Applied ONLY where the chips are built —
 * `SportsGame.broadcasts` itself is never mutated, so every other surface
 * keeps showing the linear network alone. Each companion is inserted
 * immediately after its network, deduplicated case-insensitively, and index
 * zero is always the original first broadcast. These mappings encode US
 * streaming rights only, so non-US locales get the input back unchanged.
 */
internal fun enrichBroadcasts(broadcasts: List<String>): List<String> {
    if (!Locale.getDefault().country.equals("US", ignoreCase = true)) return broadcasts
    val result = mutableListOf<String>()
    val seen = mutableSetOf<String>()
    for (name in broadcasts) {
        val key = normalizeBroadcast(name)
        if (seen.add(key)) result.add(name)
        if (key in streamingDestinations) continue
        val companion = simulcastCompanions[key] ?: continue
        if (seen.add(normalizeBroadcast(companion))) result.add(companion)
    }
    return result
}

private fun parseStart(timestamp: String?): Date? {
    if (timestamp == null) return null
    val patterns = listOf(
        "yyyy-MM-dd'T'HH:mm'Z'",
        "yyyy-MM-dd'T'HH:mmXXX",
        "yyyy-MM-dd'T'HH:mm:ss'Z'",
        "yyyy-MM-dd'T'HH:mm:ssXXX",
    )
    for (p in patterns) {
        try {
            val f = SimpleDateFormat(p, Locale.US)
            f.timeZone = TimeZone.getTimeZone("UTC")
            return f.parse(timestamp)
        } catch (_: Exception) {
            // try next pattern
        }
    }
    return null
}

/** Full local date + time for the game start (e.g. "Fri, Jul 9 · 7:30 PM"). */
internal fun formatStartLocal(timestamp: String?): String {
    val date = parseStart(timestamp) ?: return timestamp ?: ""
    return SimpleDateFormat("EEE, MMM d · h:mm a", Locale.getDefault()).format(date)
}

/** Short chip label for the "My Teams" row: LIVE, today's time, or weekday. */
internal fun teamStatusLabel(game: SportsGame?): String {
    if (game == null) return "No game scheduled"
    if (game.state == "live") return "LIVE"
    val date = parseStart(game.startTime) ?: return "TBA"
    val now = java.util.Calendar.getInstance()
    val cal = java.util.Calendar.getInstance().apply { time = date }
    val sameDay = now.get(java.util.Calendar.YEAR) == cal.get(java.util.Calendar.YEAR) &&
        now.get(java.util.Calendar.DAY_OF_YEAR) == cal.get(java.util.Calendar.DAY_OF_YEAR)
    return if (sameDay) {
        SimpleDateFormat("h:mm a", Locale.getDefault()).format(date)
    } else {
        SimpleDateFormat("EEE", Locale.getDefault()).format(date)
    }
}

/**
 * GUI-99 schedule clock. Every game time the app prints is Eastern
 * ("8:20 PM ET"), so "today" and "tomorrow" are bucketed in Eastern too —
 * otherwise the weekday and the clock beside it could disagree for a late
 * game. Mirrors iOS `SportsClock`.
 */
private val EASTERN: java.time.ZoneId = java.time.ZoneId.of("America/New_York")

private fun startDateEastern(timestamp: String?): java.time.ZonedDateTime? =
    parseStart(timestamp)?.toInstant()?.atZone(EASTERN)

/** Is the game start today in Eastern time (drives the "Tonight" section). */
internal fun isStartToday(timestamp: String?): Boolean {
    val start = startDateEastern(timestamp) ?: return false
    return start.toLocalDate() == java.time.LocalDate.now(EASTERN)
}

/** Hour of day (Eastern) the game starts, or null when the start is unknown. */
internal fun startHourEastern(timestamp: String?): Int? = startDateEastern(timestamp)?.hour

/**
 * What every card shows on its status line. `statusDetail` for a `pre` game is
 * a bare clock time, so a game two days out read exactly like one starting
 * tonight (GUI-99). Live and final games are unchanged.
 *
 * "8:20 PM ET" today, "Tomorrow · 8:20 PM ET", "Sat · 1:00 PM ET" inside a
 * week, "Sep 20 · 1:00 PM ET" beyond it.
 */
internal fun scheduleLabel(game: SportsGame): String {
    if (game.state != "pre") return game.statusDetail
    val start = startDateEastern(game.startTime) ?: return game.statusDetail
    val clock = java.time.format.DateTimeFormatter.ofPattern("h:mm a", Locale.US).format(start) + " ET"
    val today = java.time.LocalDate.now(EASTERN)
    val days = java.time.temporal.ChronoUnit.DAYS.between(today, start.toLocalDate())
    return when {
        days == 0L -> clock
        days == 1L -> "Tomorrow · $clock"
        days in 2..6 -> java.time.format.DateTimeFormatter.ofPattern("EEE", Locale.US).format(start) + " · " + clock
        else -> java.time.format.DateTimeFormatter.ofPattern("MMM d", Locale.US).format(start) + " · " + clock
    }
}

/** Sorting helper: soonest start first. */
internal fun startMillis(timestamp: String?): Long = parseStart(timestamp)?.time ?: Long.MAX_VALUE

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

/** Is the game start today (used for the "Tonight" section title). */
internal fun isStartToday(timestamp: String?): Boolean {
    val date = parseStart(timestamp) ?: return false
    val now = java.util.Calendar.getInstance()
    val cal = java.util.Calendar.getInstance().apply { time = date }
    return now.get(java.util.Calendar.YEAR) == cal.get(java.util.Calendar.YEAR) &&
        now.get(java.util.Calendar.DAY_OF_YEAR) == cal.get(java.util.Calendar.DAY_OF_YEAR)
}

/** Sorting helper: soonest start first. */
internal fun startMillis(timestamp: String?): Long = parseStart(timestamp)?.time ?: Long.MAX_VALUE

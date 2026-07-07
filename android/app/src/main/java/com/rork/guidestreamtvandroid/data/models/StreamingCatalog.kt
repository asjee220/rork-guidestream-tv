package com.rork.guidestreamtvandroid.data.models

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight

/**
 * Canonical catalogue of the top ~50 worldwide streaming services.
 * Mirrors iOS StreamingService.swift + StreamingCatalog enum.
 */
data class StreamingService(
    val id: String,
    val name: String,
    val bg: Color,
    val glow: Color,
    val display: Display,
) {
    /** Tile/icon visual treatment. */
    sealed class Display {
        data class Text(val text: String, val color: Color, val weight: FontWeight) : Display()
        data class SymbolText(val symbol: String, val text: String, val color: Color) : Display()
        data class Star(val color: Color) : Display()
    }
}

object StreamingCatalog {
    private val black = Color(0xFF000000)
    private val white = Color(0xFFFFFFFF)

    val all: List<StreamingService> = listOf(
        // ── Global / US giants (1–15) ──
        StreamingService("netflix", "Netflix", black, Color(0xFFE50914),
            StreamingService.Display.Text("N", Color(0xFFE50914), FontWeight.Black)),
        StreamingService("prime", "Prime Video", Color(0xFF1A202C), Color(0xFF00A8E1),
            StreamingService.Display.Text("prime\nvideo", white, FontWeight.Bold)),
        StreamingService("disney", "Disney+", Color(0xFF0E293F), Color(0xFF113CCF),
            StreamingService.Display.Text("Disney+", white, FontWeight.SemiBold)),
        StreamingService("hbo", "Max", Color(0xFF001EE0), Color(0xFF0055FF),
            StreamingService.Display.Text("max", white, FontWeight.Black)),
        StreamingService("hulu", "Hulu", Color(0xFF1CE783), Color(0xFF1CE783),
            StreamingService.Display.Text("hulu", black, FontWeight.Black)),
        StreamingService("appletv", "Apple TV+", black, white,
            StreamingService.Display.SymbolText("apple", "tv+", white)),
        StreamingService("paramount", "Paramount+", Color(0xFF0064FF), Color(0xFF0064FF),
            StreamingService.Display.Text("P+", white, FontWeight.Black)),
        StreamingService("peacock", "Peacock", black, Color(0xFFFF6600),
            StreamingService.Display.Text("peacock", white, FontWeight.Bold)),
        StreamingService("crunchyroll", "Crunchyroll", Color(0xFFF47B20), Color(0xFFF47B20),
            StreamingService.Display.Text("crunchyroll", white, FontWeight.Black)),
        StreamingService("starz", "Starz", Color(0xFF140514), Color(0xFFFFC81E),
            StreamingService.Display.Star(Color(0xFFFFC81E))),
        StreamingService("showtime", "Showtime", black, Color(0xFFD80000),
            StreamingService.Display.Text("SHO", Color(0xFFD80000), FontWeight.Black)),
        StreamingService("amc", "AMC+", black, Color(0xFFF5821F),
            StreamingService.Display.Text("amc+", white, FontWeight.Black)),
        StreamingService("espn", "ESPN+", Color(0xFF001A70), Color(0xFFD02131),
            StreamingService.Display.Text("ESPN+", white, FontWeight.Black)),
        StreamingService("discovery", "Discovery+", Color(0xFF004DFA), Color(0xFF009AFF),
            StreamingService.Display.Text("d+", white, FontWeight.Black)),
        StreamingService("youtube", "YouTube", black, Color(0xFFFF0000),
            StreamingService.Display.Text("YT", Color(0xFFFF0000), FontWeight.Black)),

        // ── US/Free + niche (16–26) ──
        StreamingService("tubi", "Tubi", Color(0xFFD31421), Color(0xFFFF4040),
            StreamingService.Display.Text("tubi", white, FontWeight.Black)),
        StreamingService("pluto", "Pluto TV", Color(0xFF181037), Color(0xFFFFE036),
            StreamingService.Display.Text("Pluto", Color(0xFFFFE036), FontWeight.Black)),
        StreamingService("roku", "Roku Channel", Color(0xFF662D91), Color(0xFFB453FF),
            StreamingService.Display.Text("Roku", white, FontWeight.Black)),
        StreamingService("plex", "Plex", black, Color(0xFFE5A017),
            StreamingService.Display.Text("P", Color(0xFFE5A017), FontWeight.Black)),
        StreamingService("crackle", "Crackle", black, Color(0xFFFFA800),
            StreamingService.Display.Text("crackle", Color(0xFFFFA800), FontWeight.Black)),
        StreamingService("mubi", "Mubi", black, white,
            StreamingService.Display.Text("MUBI", white, FontWeight.Black)),
        StreamingService("fubo", "Fubo", Color(0xFFEC1840), Color(0xFFEC1840),
            StreamingService.Display.Text("fubo", white, FontWeight.Black)),
        StreamingService("sling", "Sling TV", black, Color(0xFFFF7300),
            StreamingService.Display.Text("sling", Color(0xFFFF7300), FontWeight.Black)),
        StreamingService("youtubetv", "YouTube TV", white, Color(0xFFFF0000),
            StreamingService.Display.Text("YT TV", Color(0xFFFF0000), FontWeight.Black)),
        StreamingService("dazn", "DAZN", black, Color(0xFFF40029),
            StreamingService.Display.Text("DAZN", Color(0xFFF40029), FontWeight.Black)),
        StreamingService("shudder", "Shudder", black, Color(0xFF9A00FF),
            StreamingService.Display.Text("shudder", Color(0xFF9A00FF), FontWeight.Black)),

        // ── UK (27–32) ──
        StreamingService("bbciplayer", "BBC iPlayer", black, Color(0xFFFBB032),
            StreamingService.Display.Text("iPlayer", Color(0xFFFBB032), FontWeight.Black)),
        StreamingService("itvx", "ITVX", black, Color(0xFFFFC000),
            StreamingService.Display.Text("ITVX", white, FontWeight.Black)),
        StreamingService("channel4", "Channel 4", black, Color(0xFFAAFF00),
            StreamingService.Display.Text("4", Color(0xFFAAFF00), FontWeight.Black)),
        StreamingService("nowtv", "NOW", Color(0xFF0055A4), Color(0xFF00B7FF),
            StreamingService.Display.Text("NOW", white, FontWeight.Black)),
        StreamingService("britbox", "BritBox", Color(0xFF1233CC), Color(0xFFFF4B9C),
            StreamingService.Display.Text("Brit", white, FontWeight.Black)),
        StreamingService("acorntv", "Acorn TV", Color(0xFF21472A), Color(0xFF6EC16E),
            StreamingService.Display.Text("Acorn", white, FontWeight.Black)),

        // ── Europe / Australia / LatAm (33–41) ──
        StreamingService("canalplus", "Canal+", black, white,
            StreamingService.Display.Text("CANAL+", white, FontWeight.Black)),
        StreamingService("skyshowtime", "SkyShowtime", black, Color(0xFFFF0073),
            StreamingService.Display.Text("S+", Color(0xFFFF0073), FontWeight.Black)),
        StreamingService("stan", "Stan", black, Color(0xFF00D4FF),
            StreamingService.Display.Text("stan.", Color(0xFF00D4FF), FontWeight.Black)),
        StreamingService("binge", "Binge", Color(0xFFFF2900), Color(0xFFFF2900),
            StreamingService.Display.Text("binge", white, FontWeight.Black)),
        StreamingService("kayo", "Kayo Sports", black, Color(0xFF18E0C8),
            StreamingService.Display.Text("Kayo", Color(0xFF18E0C8), FontWeight.Black)),
        StreamingService("globoplay", "Globoplay", black, Color(0xFFFF2966),
            StreamingService.Display.Text("globo", white, FontWeight.Black)),
        StreamingService("vix", "ViX", Color(0xFFFF2900), Color(0xFFFFC000),
            StreamingService.Display.Text("ViX", white, FontWeight.Black)),
        StreamingService("rakutenviki", "Viki", Color(0xFF161829), Color(0xFFBC006C),
            StreamingService.Display.Text("VIKI", Color(0xFFBC006C), FontWeight.Black)),

        // ── India (42–45) ──
        StreamingService("hotstar", "Hotstar", Color(0xFF0A112E), Color(0xFF1847FF),
            StreamingService.Display.Text("hotstar", white, FontWeight.Black)),
        StreamingService("jiocinema", "JioCinema", Color(0xFFE41F1F), Color(0xFFFF6033),
            StreamingService.Display.Text("Jio", white, FontWeight.Black)),
        StreamingService("sonyliv", "SonyLIV", black, Color(0xFFFF6600),
            StreamingService.Display.Text("LIV", Color(0xFFFF6600), FontWeight.Black)),
        StreamingService("zee5", "Zee5", Color(0xFF6B18FF), Color(0xFFFF18A1),
            StreamingService.Display.Text("ZEE5", white, FontWeight.Black)),

        // ── East Asia (46–50) ──
        StreamingService("iqiyi", "iQIYI", Color(0xFF00C46A), Color(0xFF00F082),
            StreamingService.Display.Text("iQ", white, FontWeight.Black)),
        StreamingService("wetv", "WeTV", Color(0xFFFC5221), Color(0xFFFF8421),
            StreamingService.Display.Text("WeTV", white, FontWeight.Black)),
        StreamingService("viu", "Viu", Color(0xFFFFCC00), Color(0xFFFFCC00),
            StreamingService.Display.Text("Viu", black, FontWeight.Black)),
        StreamingService("unext", "U-NEXT", black, white,
            StreamingService.Display.Text("U", white, FontWeight.Black)),
        StreamingService("abema", "ABEMA", black, Color(0xFF00E666),
            StreamingService.Display.Text("ABEMA", Color(0xFF00E666), FontWeight.Black)),
    )

    fun service(id: String): StreamingService? = all.find { it.id == id }
    fun ordered(ids: Set<String>): List<StreamingService> = all.filter { it.id in ids }
}

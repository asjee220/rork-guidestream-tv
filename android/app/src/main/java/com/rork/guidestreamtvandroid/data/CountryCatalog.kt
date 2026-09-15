package com.rork.guidestreamtvandroid.data

/**
 * One TMDB watch provider in a specific region.
 */
data class CountryProvider(
    val id: Int,
    val name: String,
    /** When set, this provider is queried in this language instead of the
     *  country's — lets Crunchyroll browse Japanese anime in every market. */
    val originalLanguage: String? = null,
)

/**
 * One curated "Around the World" destination. Mirrors iOS CountryCatalogEntry.
 */
data class CountryCatalogEntry(
    /** ISO 3166-1 alpha-2 region code (also TMDB's `watch_region` value). */
    val regionCode: String,
    val displayName: String,
    /** TMDB original-language filter, or null for English-speaking markets. */
    val originalLanguage: String?,
    /** Ordered TMDB provider entries — region-specific ids. */
    val providers: List<CountryProvider>,
) {
    /** Effective original language for a query against this provider — the
     *  provider override when present, else the country's. */
    fun effectiveOriginalLanguage(provider: CountryProvider): String? =
        provider.originalLanguage ?: originalLanguage

    /**
     * Vote-count floor for a query. 100 for Japanese content — a
     * content-safety requirement for animation: TMDB reports the titles it
     * excludes as adult:false with genre [16], so no other filter catches
     * them. 20 everywhere else. Do not lower it or make it uniform.
     */
    fun voteFloor(provider: CountryProvider): Int =
        if (effectiveOriginalLanguage(provider) == "ja") 100 else 20
}

/**
 * Curated "Around the World" destinations. TMDB provider ids are
 * region-specific — always use them exactly as listed. Mirrors
 * ios/Shared/CountryCatalog.swift, and must stay in the SAME ORDER as it:
 * both platforms derive the daily pick from the list position, so a reorder
 * on one side makes them disagree.
 *
 * "Around the World" means AWAY FROM HOME, and home is the viewer's own
 * region — not the US. Until 15 Sep 2026 there was no US entry and the
 * rotation was a global `day mod 11`, so a viewer in Tokyo was shown "Around
 * the World: Japan" one day in eleven, and nobody outside the US could ever
 * look at the largest catalogue on earth. Read the destination list through
 * [destinations], never [entries] directly.
 */
object CountryCatalog {
    val entries: List<CountryCatalogEntry> = listOf(
        CountryCatalogEntry("JP", "Japan", "ja", listOf(
            CountryProvider(84, "U-NEXT"),
            CountryProvider(8, "Netflix"),
            CountryProvider(9, "Prime Video"),
            CountryProvider(15, "Hulu"),
            CountryProvider(337, "Disney+"),
        )),
        CountryCatalogEntry("KR", "South Korea", "ko", listOf(
            CountryProvider(8, "Netflix"),
            CountryProvider(1883, "TVING"),
            CountryProvider(356, "wavve"),
            CountryProvider(97, "Watcha"),
            CountryProvider(283, "Crunchyroll", originalLanguage = "ja"),
        )),
        CountryCatalogEntry("GB", "United Kingdom", null, listOf(
            CountryProvider(38, "BBC iPlayer"),
            CountryProvider(41, "ITVX"),
            CountryProvider(103, "Channel 4"),
            CountryProvider(29, "Sky Go"),
            CountryProvider(39, "Now TV"),
            CountryProvider(283, "Crunchyroll", originalLanguage = "ja"),
        )),
        CountryCatalogEntry("FR", "France", "fr", listOf(
            CountryProvider(8, "Netflix"),
            CountryProvider(119, "Prime Video"),
            CountryProvider(337, "Disney+"),
            CountryProvider(283, "Crunchyroll", originalLanguage = "ja"),
        )),
        CountryCatalogEntry("DE", "Germany", "de", listOf(
            CountryProvider(8, "Netflix"),
            CountryProvider(9, "Prime Video"),
            CountryProvider(2750, "RTL+"),
            CountryProvider(337, "Disney+"),
            CountryProvider(30, "WOW"),
            CountryProvider(29, "Sky Go"),
            CountryProvider(283, "Crunchyroll", originalLanguage = "ja"),
        )),
        CountryCatalogEntry("ES", "Spain", "es", listOf(
            CountryProvider(8, "Netflix"),
            CountryProvider(62, "Atres Player"),
            CountryProvider(119, "Prime Video"),
            CountryProvider(2241, "Movistar+"),
            CountryProvider(337, "Disney+"),
            CountryProvider(541, "rtve"),
            CountryProvider(1773, "SkyShowtime"),
            CountryProvider(283, "Crunchyroll", originalLanguage = "ja"),
        )),
        CountryCatalogEntry("IT", "Italy", "it", listOf(
            CountryProvider(8, "Netflix"),
            CountryProvider(222, "Rai Play"),
            CountryProvider(119, "Prime Video"),
            CountryProvider(39, "Now TV"),
            CountryProvider(29, "Sky Go"),
            CountryProvider(337, "Disney+"),
            CountryProvider(283, "Crunchyroll", originalLanguage = "ja"),
        )),
        CountryCatalogEntry("IN", "India", "hi", listOf(
            CountryProvider(8, "Netflix"),
            CountryProvider(119, "Prime Video"),
            CountryProvider(2336, "JioHotstar"),
            CountryProvider(283, "Crunchyroll", originalLanguage = "ja"),
        )),
        CountryCatalogEntry("BR", "Brazil", "pt", listOf(
            CountryProvider(307, "Globoplay"),
            CountryProvider(8, "Netflix"),
            CountryProvider(119, "Prime Video"),
            CountryProvider(283, "Crunchyroll", originalLanguage = "ja"),
        )),
        CountryCatalogEntry("MX", "Mexico", "es", listOf(
            CountryProvider(8, "Netflix"),
            CountryProvider(457, "VIX"),
            CountryProvider(119, "Prime Video"),
            CountryProvider(337, "Disney+"),
            CountryProvider(167, "Claro video"),
            CountryProvider(283, "Crunchyroll", originalLanguage = "ja"),
        )),
        CountryCatalogEntry("AU", "Australia", null, listOf(
            CountryProvider(21, "Stan"),
            CountryProvider(385, "BINGE"),
            CountryProvider(378, "9Now"),
            CountryProvider(132, "SBS On Demand"),
            CountryProvider(135, "ABC iview"),
            CountryProvider(283, "Crunchyroll", originalLanguage = "ja"),
        )),
        // Added 15 Sep 2026. Every id below was read from TMDB's own US
        // provider list and then probed with /discover/tv?watch_region=US to
        // confirm it returns titles: Hulu 906, HBO Max 508, Peacock 471,
        // Paramount+ 354, Netflix 2315, Prime Video 1347, Disney+ 473,
        // Apple TV+ 153, Tubi 1272, Crunchyroll 1045. Hulu leads because the
        // US-only services are the point of visiting, the same reason GB
        // leads with BBC iPlayer and BR with Globoplay. US is LAST so a US
        // viewer's rotation is unchanged from before this entry existed.
        CountryCatalogEntry("US", "United States", null, listOf(
            CountryProvider(15, "Hulu"),
            CountryProvider(1899, "HBO Max"),
            CountryProvider(386, "Peacock"),
            CountryProvider(2303, "Paramount+"),
            CountryProvider(8, "Netflix"),
            CountryProvider(9, "Prime Video"),
            CountryProvider(337, "Disney+"),
            CountryProvider(350, "Apple TV+"),
            CountryProvider(73, "Tubi"),
            CountryProvider(283, "Crunchyroll", originalLanguage = "ja"),
        )),
    )

    /**
     * Where a viewer in [homeRegion] can travel: the catalogue minus their own
     * country. A viewer in Manila gets all twelve including the US; a viewer in
     * Tokyo gets eleven without Japan. Falls back to the full list if the
     * filter would empty it.
     *
     * This is the list the destination picker shows and the rail rotates
     * through. [entryFor] deliberately still searches everything, so a deep
     * link to your own country resolves rather than silently becoming
     * somewhere else.
     */
    fun destinations(homeRegion: String): List<CountryCatalogEntry> {
        val home = homeRegion.uppercase()
        val away = entries.filter { !it.regionCode.equals(home, ignoreCase = true) }
        return away.ifEmpty { entries }
    }

    /**
     * Rotating destination of the day for a viewer at [homeRegion]:
     * floor(now / 86_400_000) mod destinationCount, computed at read time so
     * the pick advances at UTC midnight. Android and iOS agree because they
     * build the same pool (this file's order, minus home) from the same day
     * index. The index is always coerced non-negative.
     */
    fun countryOfDay(homeRegion: String): CountryCatalogEntry {
        val pool = destinations(homeRegion)
        val count = pool.size
        val day = (System.currentTimeMillis() / 86_400_000L).toInt()
        val idx = ((day % count) + count) % count
        return pool[idx]
    }

    /** Today's destination for this device's own region. */
    val countryOfDay: CountryCatalogEntry
        get() = countryOfDay(DeviceLocale.region)

    /** Entry for a region code, case-insensitive; null on miss. */
    fun entryFor(regionCode: String): CountryCatalogEntry? =
        entries.firstOrNull { it.regionCode.equals(regionCode, ignoreCase = true) }
}

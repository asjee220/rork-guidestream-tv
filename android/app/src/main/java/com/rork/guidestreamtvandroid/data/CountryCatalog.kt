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
 * ios/Shared/CountryCatalog.swift.
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
    )

    /**
     * Rotating destination of the day: floor(now / 86_400_000) mod 11
     * (11 = entry count), computed at read time so the pick advances at UTC
     * midnight and Android and iOS agree on the country for any given day.
     * The index is always coerced non-negative.
     */
    val countryOfDay: CountryCatalogEntry
        get() {
            val count = entries.size
            val day = (System.currentTimeMillis() / 86_400_000L).toInt()
            val idx = ((day % count) + count) % count
            return entries[idx]
        }

    /** Entry for a region code, case-insensitive; null on miss. */
    fun entryFor(regionCode: String): CountryCatalogEntry? =
        entries.firstOrNull { it.regionCode.equals(regionCode, ignoreCase = true) }
}

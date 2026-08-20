package com.rork.guidestreamtvandroid.data

/**
 * One TMDB watch provider in a specific region.
 */
data class CountryProvider(val id: Int, val name: String)

/**
 * One curated "Around the World" destination. Mirrors iOS CountryCatalogEntry.
 */
data class CountryCatalogEntry(
    /** ISO 3166-1 alpha-2 region code (also TMDB's `watch_region` value). */
    val regionCode: String,
    val displayName: String,
    /** TMDB original-language filter, or null for English-speaking markets. */
    val originalLanguage: String?,
    /** Ordered TMDB provider id/name pairs — region-specific ids. */
    val providers: List<CountryProvider>,
)

/**
 * Curated "Around the World" destinations. TMDB provider ids are
 * region-specific — always use them exactly as listed. Mirrors
 * ios/Shared/CountryCatalog.swift.
 */
object CountryCatalog {
    val entries: List<CountryCatalogEntry> = listOf(
        CountryCatalogEntry("JP", "Japan", "ja", listOf(
            CountryProvider(8, "Netflix"),
            CountryProvider(84, "U-NEXT"),
            CountryProvider(9, "Amazon Prime Video"),
            CountryProvider(337, "Disney Plus"),
            CountryProvider(15, "Hulu"),
        )),
        CountryCatalogEntry("KR", "South Korea", "ko", listOf(
            CountryProvider(8, "Netflix"),
            CountryProvider(356, "wavve"),
            CountryProvider(1883, "TVING"),
            CountryProvider(1881, "Coupang Play"),
            CountryProvider(97, "Watcha"),
            CountryProvider(119, "Amazon Prime Video"),
        )),
        CountryCatalogEntry("GB", "United Kingdom", null, listOf(
            CountryProvider(8, "Netflix"),
            CountryProvider(38, "BBC iPlayer"),
            CountryProvider(41, "ITVX"),
            CountryProvider(103, "Channel 4"),
            CountryProvider(29, "Sky Go"),
            CountryProvider(39, "Now TV"),
            CountryProvider(9, "Amazon Prime Video"),
            CountryProvider(337, "Disney Plus"),
        )),
        CountryCatalogEntry("FR", "France", "fr", listOf(
            CountryProvider(8, "Netflix"),
            CountryProvider(119, "Amazon Prime Video"),
            CountryProvider(337, "Disney Plus"),
            CountryProvider(147, "M6+"),
            CountryProvider(531, "Paramount Plus"),
            CountryProvider(283, "Crunchyroll"),
        )),
        CountryCatalogEntry("DE", "Germany", "de", listOf(
            CountryProvider(8, "Netflix"),
            CountryProvider(9, "Amazon Prime Video"),
            CountryProvider(2750, "RTL+"),
            CountryProvider(304, "Joyn"),
            CountryProvider(30, "WOW"),
            CountryProvider(219, "ARD Mediathek"),
            CountryProvider(337, "Disney Plus"),
            CountryProvider(29, "Sky Go"),
        )),
        CountryCatalogEntry("ES", "Spain", "es", listOf(
            CountryProvider(8, "Netflix"),
            CountryProvider(119, "Amazon Prime Video"),
            CountryProvider(2241, "Movistar Plus+"),
            CountryProvider(62, "Atres Player"),
            CountryProvider(541, "rtve"),
            CountryProvider(1773, "SkyShowtime"),
            CountryProvider(337, "Disney Plus"),
            CountryProvider(63, "Filmin"),
        )),
        CountryCatalogEntry("IT", "Italy", "it", listOf(
            CountryProvider(8, "Netflix"),
            CountryProvider(119, "Amazon Prime Video"),
            CountryProvider(222, "Rai Play"),
            CountryProvider(359, "Mediaset Infinity"),
            CountryProvider(39, "Now TV"),
            CountryProvider(109, "Timvision"),
            CountryProvider(337, "Disney Plus"),
            CountryProvider(29, "Sky Go"),
        )),
        CountryCatalogEntry("IN", "India", "hi", listOf(
            CountryProvider(8, "Netflix"),
            CountryProvider(119, "Amazon Prime Video"),
            CountryProvider(2336, "JioHotstar"),
            CountryProvider(232, "Zee5"),
            CountryProvider(237, "Sony Liv"),
            CountryProvider(515, "MX Player"),
            CountryProvider(532, "aha"),
        )),
        CountryCatalogEntry("BR", "Brazil", "pt", listOf(
            CountryProvider(8, "Netflix"),
            CountryProvider(119, "Amazon Prime Video"),
            CountryProvider(307, "Globoplay"),
            CountryProvider(337, "Disney Plus"),
            CountryProvider(531, "Paramount Plus"),
            CountryProvider(47, "Looke"),
        )),
        CountryCatalogEntry("MX", "Mexico", "es", listOf(
            CountryProvider(8, "Netflix"),
            CountryProvider(119, "Amazon Prime Video"),
            CountryProvider(457, "VIX"),
            CountryProvider(337, "Disney Plus"),
            CountryProvider(531, "Paramount Plus"),
            CountryProvider(167, "Claro video"),
        )),
        CountryCatalogEntry("AU", "Australia", null, listOf(
            CountryProvider(8, "Netflix"),
            CountryProvider(119, "Amazon Prime Video"),
            CountryProvider(21, "Stan"),
            CountryProvider(385, "BINGE"),
            CountryProvider(135, "ABC iview"),
            CountryProvider(132, "SBS On Demand"),
            CountryProvider(378, "9Now"),
            CountryProvider(337, "Disney Plus"),
        )),
        CountryCatalogEntry("CA", "Canada", null, listOf(
            CountryProvider(8, "Netflix"),
            CountryProvider(119, "Amazon Prime Video"),
            CountryProvider(230, "Crave"),
            CountryProvider(337, "Disney Plus"),
            CountryProvider(531, "Paramount Plus"),
            CountryProvider(283, "Crunchyroll"),
        )),
    )

    /**
     * Rotating destination of the day: floor(now / 86_400_000) mod count,
     * computed at read time so the pick advances at UTC midnight and Android
     * and iOS agree on the country for any given day. The index is always
     * coerced non-negative.
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

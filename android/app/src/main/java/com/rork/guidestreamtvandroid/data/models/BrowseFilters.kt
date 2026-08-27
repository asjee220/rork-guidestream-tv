package com.rork.guidestreamtvandroid.data.models

/**
 * Catalogue + filter model behind Search & Browse.
 *
 * Line-for-line mirror of iOS `BrowseFilters.swift`. Genre ids and TMDB
 * parameter mapping live here on both platforms so the two cannot drift; the
 * UI layer maps genre ids to artwork and tint.
 */

// MARK: - Media type

enum class BrowseMediaType(val label: String, val discoverPath: String?) {
    /** Runs both discover paths and interleaves them. */
    ALL("All", null),
    TV("Shows", "tv"),
    MOVIE("Movies", "movie"),
}

// MARK: - Sort

enum class BrowseSort(val label: String) {
    POPULARITY("Most popular"),
    NEWEST("Newest"),
    RATING("Highest rated"),
    ALPHABETICAL("A–Z");

    /**
     * TMDB `sort_by`. The date and title keys differ between the tv and movie
     * discover endpoints, so the path has to be passed in.
     */
    fun tmdbValue(path: String): String = when (this) {
        POPULARITY -> "popularity.desc"
        NEWEST -> if (path == "movie") "primary_release_date.desc" else "first_air_date.desc"
        RATING -> "vote_average.desc"
        ALPHABETICAL -> if (path == "movie") "title.asc" else "name.asc"
    }

    /**
     * Sorting by rating without a vote floor puts 10.0-from-three-votes
     * obscurities at the top of the grid.
     */
    val needsVoteFloor: Boolean get() = this == RATING
}

// MARK: - Genre

/**
 * One browsable genre. TMDB uses different genre ids per media type — Sci-Fi is
 * 10765 on TV but 878 on film — and two of the ten only exist on one side, so
 * both ids are carried and either may be null.
 */
data class BrowseGenre(
    val id: String,
    val displayName: String,
    val tvGenreId: Int? = null,
    val movieGenreId: Int? = null,
    /**
     * Pinned original language. Anime uses this: TMDB genre 16 is Animation,
     * not anime, so it is narrowed to Japanese-language titles.
     */
    val originalLanguage: String? = null,
    /**
     * Pipe-joined language pool, used by International, which has no genre id
     * of its own.
     */
    val languagePool: String? = null,
) {
    val supportsTV: Boolean get() = tvGenreId != null || languagePool != null
    val supportsMovie: Boolean get() = movieGenreId != null

    /**
     * The media type this genre is pinned to, or null when it works on both.
     * Drives the locked Type control in the filter sheet.
     */
    val mediaLock: BrowseMediaType?
        get() = when {
            supportsTV && supportsMovie -> null
            supportsTV -> BrowseMediaType.TV
            else -> BrowseMediaType.MOVIE
        }

    /** Shown under the Type control when this genre locks it. */
    val lockReason: String?
        get() = when (mediaLock) {
            BrowseMediaType.TV -> "$displayName is a TV-only category."
            BrowseMediaType.MOVIE -> "$displayName titles are films."
            else -> null
        }

    fun genreId(path: String): Int? = if (path == "movie") movieGenreId else tvGenreId
}

object BrowseCatalog {
    /** Non-English markets used by the International tile. */
    const val INTERNATIONAL_LANGUAGES = "ko|ja|fr|de|es|it|pt|hi|ar|tr|sv|no|da|fi|nl|pl|th|zh"

    /**
     * The ten browsable genres, in display order.
     *
     * Horror (27) and Romance (10749) are film-only in TMDB — there is no TV
     * equivalent of either. Anime and International are TV-only by
     * construction. Everything else carries a real id on both sides.
     */
    val genres: List<BrowseGenre> = listOf(
        BrowseGenre("crime", "Crime & Thriller", tvGenreId = 80, movieGenreId = 80),
        BrowseGenre("scifi", "Sci-Fi", tvGenreId = 10765, movieGenreId = 878),
        BrowseGenre("horror", "Horror", movieGenreId = 27),
        BrowseGenre("anime", "Anime", tvGenreId = 16, originalLanguage = "ja"),
        BrowseGenre("comedy", "Comedy", tvGenreId = 35, movieGenreId = 35),
        BrowseGenre("drama", "Drama", tvGenreId = 18, movieGenreId = 18),
        BrowseGenre("action", "Action", tvGenreId = 10759, movieGenreId = 28),
        BrowseGenre("documentary", "Documentary", tvGenreId = 99, movieGenreId = 99),
        BrowseGenre("romance", "Romance", movieGenreId = 10749),
        BrowseGenre("international", "International", languagePool = INTERNATIONAL_LANGUAGES),
    )

    fun genre(id: String): BrowseGenre? = genres.firstOrNull { it.id == id }

    /**
     * Selectable release-year window. The upper bound tracks the device clock
     * so next year's titles appear without a code change.
     */
    val yearBounds: IntRange
        get() {
            val now = java.util.Calendar.getInstance().get(java.util.Calendar.YEAR)
            return 1970..maxOf(1970, now)
        }

    val ratingOptions: List<Double> = listOf(6.0, 7.0, 8.0)
}

// MARK: - Filters

data class BrowseFilters(
    /** Selected genre slugs. Empty means "every genre". */
    val genreIds: Set<String> = emptySet(),
    val mediaType: BrowseMediaType = BrowseMediaType.ALL,
    /** Restrict to the services the user actually has. */
    val onlyMyServices: Boolean = true,
    /** TMDB provider ids, supplied by the caller from the streams store. */
    val providerIds: List<Int> = emptyList(),
    /** Include ad-supported tiers alongside subscription ones. */
    val includeFreeWithAds: Boolean = true,
    val yearRange: IntRange? = null,
    val minRating: Double? = null,
    val sort: BrowseSort = BrowseSort.POPULARITY,
) {
    val selectedGenres: List<BrowseGenre>
        get() = BrowseCatalog.genres.filter { genreIds.contains(it.id) }

    /**
     * The genre forcing a media type, if any. When two locked genres disagree —
     * Horror plus Anime — the first in catalogue order wins and the other is
     * dropped by [resolved], because no single discover call can serve both.
     */
    val lockingGenre: BrowseGenre?
        get() = selectedGenres.firstOrNull { it.mediaLock != null }

    /** Media type actually sent to TMDB once genre locks are applied. */
    val resolvedMediaType: BrowseMediaType
        get() = lockingGenre?.mediaLock ?: mediaType

    /**
     * Drops genres that cannot run under the resolved media type, so a query is
     * never built with an id the endpoint does not know.
     */
    fun resolved(): BrowseFilters {
        val type = resolvedMediaType
        if (type == BrowseMediaType.ALL) return copy(mediaType = type)
        val kept = selectedGenres
            .filter { if (type == BrowseMediaType.TV) it.supportsTV else it.supportsMovie }
            .map { it.id }
            .toSet()
        return copy(mediaType = type, genreIds = kept)
    }

    /** Effective provider list — empty means "do not filter by provider". */
    val effectiveProviderIds: List<Int>
        get() = if (onlyMyServices) providerIds else emptyList()

    /**
     * Stable key for the results cache. Any change that alters the query has to
     * change this string.
     */
    val signature: String
        get() {
            val g = genreIds.sorted().joinToString(",")
            val p = effectiveProviderIds.sorted().joinToString(",")
            val y = yearRange?.let { "${it.first}-${it.last}" } ?: "any"
            val r = minRating?.let { String.format(java.util.Locale.US, "%.1f", it) } ?: "any"
            return "${resolvedMediaType.name}|$g|$p|$includeFreeWithAds|$y|$r|${sort.name}"
        }

    /**
     * Count shown on the filter icon badge. Genre is excluded — it is the
     * screen's subject, not a filter applied to it.
     */
    val activeCount: Int
        get() {
            var n = 0
            if (mediaType != BrowseMediaType.ALL) n++
            if (onlyMyServices) n++
            if (!includeFreeWithAds) n++
            if (yearRange != null) n++
            if (minRating != null) n++
            return n
        }

    val pills: List<BrowseFilterPill>
        get() {
            val out = mutableListOf<BrowseFilterPill>()
            if (onlyMyServices) {
                out += BrowseFilterPill(BrowseFilterPill.Kind.SERVICES, "My services", accented = true)
            }
            if (mediaType != BrowseMediaType.ALL) {
                out += BrowseFilterPill(BrowseFilterPill.Kind.MEDIA_TYPE, mediaType.label)
            }
            minRating?.let {
                out += BrowseFilterPill(BrowseFilterPill.Kind.RATING, "★ ${it.toInt()}+")
            }
            yearRange?.let {
                out += BrowseFilterPill(BrowseFilterPill.Kind.YEAR, "${it.first}–${it.last}")
            }
            if (!includeFreeWithAds) {
                out += BrowseFilterPill(BrowseFilterPill.Kind.FREE_WITH_ADS, "No ad-supported")
            }
            return out
        }

    /**
     * Removes one pill's filter, returning the relaxed set. Used by both the
     * pill's ✕ and the empty-state recovery probe.
     */
    fun removing(kind: BrowseFilterPill.Kind): BrowseFilters = when (kind) {
        BrowseFilterPill.Kind.MEDIA_TYPE -> copy(mediaType = BrowseMediaType.ALL)
        BrowseFilterPill.Kind.SERVICES -> copy(onlyMyServices = false)
        BrowseFilterPill.Kind.FREE_WITH_ADS -> copy(includeFreeWithAds = true)
        BrowseFilterPill.Kind.YEAR -> copy(yearRange = null)
        BrowseFilterPill.Kind.RATING -> copy(minRating = null)
    }
}

// MARK: - Applied-filter pills

/** One dismissible pill in the applied-filter bar. */
data class BrowseFilterPill(
    val kind: Kind,
    val label: String,
    /** True for the "My services" pill, which is tinted rather than neutral. */
    val accented: Boolean = false,
) {
    enum class Kind { MEDIA_TYPE, SERVICES, FREE_WITH_ADS, YEAR, RATING }
}

// MARK: - Page

/** One page of browse results plus the totals the count row needs. */
data class BrowsePage(
    val results: List<TMDBResult> = emptyList(),
    val page: Int = 1,
    val totalPages: Int = 1,
    val totalResults: Int = 0,
) {
    companion object { val EMPTY = BrowsePage() }
}

package com.rork.guidestreamtvandroid.data.remote

import com.rork.guidestreamtvandroid.AppConfig
import com.rork.guidestreamtvandroid.data.models.TMDBResult
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.get
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * TMDB API service — mirrors iOS TMDBService.swift.
 * Fetches trending, on-the-air, popular, top-rated, discover-by-genre,
 * watch providers, season/episode details.
 */
class TMDBService {

    private val apiKey = "233f8054219ef58bc928549b4b5bab50"
    private val base = AppConfig.TMDB_BASE_URL

    private val client = HttpClient {
        install(ContentNegotiation) {
            json(Json { ignoreUnknownKeys = true })
        }
    }

    @Serializable
    private data class TMDBResultEnvelope(
        val results: List<TMDBResult> = emptyList(),
    )

    private suspend fun fetchList(url: String, mediaType: String = "tv"): List<TMDBResult> {
        return try {
            val response: TMDBResultEnvelope = client.get(url).body()
            response.results.map { it.copy(mediaType = mediaType) }
        } catch (_: Exception) {
            emptyList()
        }
    }

    /** Multi-search for shows, movies, creators. */
    suspend fun searchContent(query: String): List<TMDBResult> {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return emptyList()
        val encoded = java.net.URLEncoder.encode(trimmed, "UTF-8")
        val url = "$base/search/multi?query=$encoded&api_key=$apiKey&language=en-US&page=1&include_adult=false"
        return try {
            val response: TMDBResultEnvelope = client.get(url).body()
            response.results.filter { it.mediaType == "tv" || it.mediaType == "movie" }
        } catch (_: Exception) {
            emptyList()
        }
    }

    /** Trending TV shows this week. */
    suspend fun getTrendingTV(): List<TMDBResult> {
        return fetchList("$base/trending/tv/week?api_key=$apiKey&language=en-US", "tv")
    }

    /** Currently airing TV shows. */
    suspend fun getOnTheAir(): List<TMDBResult> {
        return fetchList("$base/tv/on_the_air?api_key=$apiKey&language=en-US&page=1", "tv")
    }

    /** Movies currently in theaters (US). */
    suspend fun getNowPlayingMovies(): List<TMDBResult> {
        return fetchList("$base/movie/now_playing?api_key=$apiKey&language=en-US&region=US&page=1", "movie")
    }

    /** Popular TV shows. */
    suspend fun getPopularTV(): List<TMDBResult> {
        return fetchList("$base/tv/popular?api_key=$apiKey&language=en-US&page=1", "tv")
    }

    /** Upcoming movies with known release dates. */
    suspend fun getUpcomingMovies(): List<TMDBResult> {
        return fetchList("$base/movie/upcoming?api_key=$apiKey&language=en-US&page=1", "movie")
    }

    /** Popular ended TV shows for "Binge Ready". */
    suspend fun getDiscoverEnded(): List<TMDBResult> {
        return fetchList("$base/discover/tv?api_key=$apiKey&language=en-US&sort_by=popularity.desc&with_status=Ended&page=1", "tv")
    }

    /** Popular shows for a single TMDB genre id. */
    suspend fun getDiscoverByGenre(genreId: Int, mediaType: String = "tv"): List<TMDBResult> {
        return fetchList("$base/discover/$mediaType?api_key=$apiKey&language=en-US&sort_by=popularity.desc&with_genres=$genreId&page=1", mediaType)
    }

    /** International / foreign-language TV. */
    suspend fun getDiscoverInternational(): List<TMDBResult> {
        val languages = "ko|ja|fr|de|es|it|pt|hi|ar|tr|sv|no|da|fi|nl|pl|th|zh"
        return fetchList("$base/discover/tv?api_key=$apiKey&language=en-US&sort_by=popularity.desc&with_original_language=$languages&page=1", "tv")
    }

    /** Discover by watch provider. */
    suspend fun discoverByProvider(providerId: Int, limit: Int = 15): List<TMDBResult> {
        val results = fetchList("$base/discover/tv?api_key=$apiKey&language=en-US&sort_by=popularity.desc&watch_region=US&with_watch_providers=$providerId&with_type=0&page=1", "tv")
        return results.take(limit)
    }

    /** Popular TV shows on a specific streaming service (flatrate + ads, US). */
    suspend fun getPopularOnService(providerId: Int, pages: Int = 2): List<TMDBResult> {
        val collected = mutableListOf<TMDBResult>()
        val seen = mutableSetOf<Int>()
        for (page in 1..maxOf(1, pages)) {
            val results = fetchList("$base/discover/tv?api_key=$apiKey&language=en-US&sort_by=popularity.desc&watch_region=US&with_watch_providers=$providerId&with_watch_monetization_types=flatrate%7Cads&page=$page", "tv")
            for (r in results) if (seen.add(r.id)) collected.add(r)
        }
        return collected
    }

    /** Popular movies on a specific streaming service (US). */
    suspend fun getPopularMoviesOnService(providerId: Int, pages: Int = 2): List<TMDBResult> {
        val collected = mutableListOf<TMDBResult>()
        val seen = mutableSetOf<Int>()
        for (page in 1..maxOf(1, pages)) {
            val results = fetchList("$base/discover/movie?api_key=$apiKey&language=en-US&sort_by=popularity.desc&watch_region=US&with_watch_providers=$providerId&page=$page", "movie")
            for (r in results) if (seen.add(r.id)) collected.add(r)
        }
        return collected
    }

    /** Popular titles on a service within a single genre (flatrate + ads, US). */
    suspend fun getPopularOnServiceByGenre(providerId: Int, genreId: Int, mediaType: String = "tv", pages: Int = 2): List<TMDBResult> {
        val collected = mutableListOf<TMDBResult>()
        val seen = mutableSetOf<Int>()
        for (page in 1..maxOf(1, pages)) {
            val results = fetchList("$base/discover/$mediaType?api_key=$apiKey&language=en-US&sort_by=popularity.desc&watch_region=US&with_watch_providers=$providerId&with_watch_monetization_types=flatrate%7Cads&with_genres=$genreId&page=$page", mediaType)
            for (r in results) if (seen.add(r.id)) collected.add(r)
        }
        return collected
    }

    /** Popular international / foreign-language titles on a service (flatrate + ads, US). */
    suspend fun getPopularOnServiceInternational(providerId: Int, pages: Int = 2): List<TMDBResult> {
        val languages = "ko|ja|fr|de|es|it|pt|hi|ar|tr|sv|no|da|fi|nl|pl|th|zh"
        val collected = mutableListOf<TMDBResult>()
        val seen = mutableSetOf<Int>()
        for (page in 1..maxOf(1, pages)) {
            val results = fetchList("$base/discover/tv?api_key=$apiKey&language=en-US&sort_by=popularity.desc&watch_region=US&with_watch_providers=$providerId&with_watch_monetization_types=flatrate%7Cads&with_original_language=$languages&page=$page", "tv")
            for (r in results) if (seen.add(r.id)) collected.add(r)
        }
        return collected
    }

    /** Top-rated TV shows. */
    suspend fun getTopRated(): List<TMDBResult> {
        return fetchList("$base/tv/top_rated?api_key=$apiKey&language=en-US&page=1", "tv")
    }

    // ── TV Detail ────────────────────────────────────────────────────

    @Serializable
    data class TMDBGenre(val id: Int = 0, val name: String = "")

    @Serializable
    data class TMDBEpisodeSummary(
        val id: Int = 0,
        val name: String? = null,
        val overview: String? = null,
        @SerialName("air_date") val airDate: String? = null,
        @SerialName("episode_number") val episodeNumber: Int? = null,
        @SerialName("season_number") val seasonNumber: Int? = null,
        val runtime: Int? = null,
        @SerialName("still_path") val stillPath: String? = null,
    )

    @Serializable
    data class TMDBTVDetail(
        val id: Int = 0,
        val name: String = "",
        val overview: String? = null,
        @SerialName("poster_path") val posterPath: String? = null,
        @SerialName("backdrop_path") val backdropPath: String? = null,
        @SerialName("vote_average") val voteAverage: Double? = null,
        val genres: List<TMDBGenre>? = null,
        @SerialName("number_of_seasons") val numberOfSeasons: Int? = null,
        @SerialName("episode_run_time") val episodeRunTime: List<Int>? = null,
        val status: String? = null,
        @SerialName("first_air_date") val firstAirDate: String? = null,
        @SerialName("last_episode_to_air") val lastEpisodeToAir: TMDBEpisodeSummary? = null,
        @SerialName("next_episode_to_air") val nextEpisodeToAir: TMDBEpisodeSummary? = null,
    )

    @Serializable
    data class TMDBSeason(
        val id: Int = 0,
        val name: String? = null,
        @SerialName("season_number") val seasonNumber: Int? = null,
        val episodes: List<TMDBEpisode> = emptyList(),
    )

    @Serializable
    data class TMDBEpisode(
        val id: Int = 0,
        @SerialName("episode_number") val episodeNumber: Int = 0,
        @SerialName("season_number") val seasonNumber: Int? = null,
        val name: String? = null,
        val overview: String? = null,
        @SerialName("still_path") val stillPath: String? = null,
        @SerialName("air_date") val airDate: String? = null,
        val runtime: Int? = null,
    )

    @Serializable
    data class TMDBVideo(
        val key: String = "",
        val name: String? = null,
        val site: String? = null,
        val type: String? = null,
    )

    @Serializable
    private data class TMDBVideosEnvelope(
        val results: List<TMDBVideo> = emptyList(),
    )

    suspend fun getTVDetail(tmdbId: Int): TMDBTVDetail? {
        return try {
            client.get("$base/tv/$tmdbId?api_key=$apiKey&language=en-US").body()
        } catch (_: Exception) { null }
    }

    @Serializable
    private data class TMDBMovieDetailDTO(
        val id: Int = 0,
        val title: String = "",
        val overview: String? = null,
        @SerialName("poster_path") val posterPath: String? = null,
        @SerialName("backdrop_path") val backdropPath: String? = null,
        @SerialName("vote_average") val voteAverage: Double? = null,
        val genres: List<TMDBGenre>? = null,
        @SerialName("release_date") val releaseDate: String? = null,
        val runtime: Int? = null,
    )

    /**
     * Movie metadata from TMDB — the movie counterpart to [getTVDetail].
     * Maps the movie payload into [TMDBTVDetail] so the detail screen renders
     * movies with the same overview/rating/genres/backdrop fields as TV.
     */
    suspend fun getMovieDetail(tmdbId: Int): TMDBTVDetail? {
        return try {
            val movie: TMDBMovieDetailDTO = client.get("$base/movie/$tmdbId?api_key=$apiKey&language=en-US").body()
            TMDBTVDetail(
                id = movie.id,
                name = movie.title,
                overview = movie.overview,
                posterPath = movie.posterPath,
                backdropPath = movie.backdropPath,
                voteAverage = movie.voteAverage,
                genres = movie.genres,
                numberOfSeasons = null,
                firstAirDate = movie.releaseDate,
            )
        } catch (_: Exception) { null }
    }

    suspend fun getSeason(tmdbId: Int, seasonNumber: Int): TMDBSeason? {
        return try {
            client.get("$base/tv/$tmdbId/season/$seasonNumber?api_key=$apiKey&language=en-US").body()
        } catch (_: Exception) { null }
    }

    /** Get YouTube trailer key for a TV show. */
    suspend fun getTrailerKey(tmdbId: Int): String? {
        return try {
            val response: TMDBVideosEnvelope = client.get("$base/tv/$tmdbId/videos?api_key=$apiKey&language=en-US").body()
            response.results
                .filter { it.site == "YouTube" && it.type == "Trailer" }
                .firstOrNull()?.key
        } catch (_: Exception) { null }
    }

    /**
     * Trailers & clips attached to a title, for the detail-screen
     * "Trailers & Clips" row and its title-scoped Reels player. Returns only
     * YouTube videos whose type is Trailer, Teaser, Featurette, or Clip,
     * ordered Trailer → Teaser → Featurette → Clip (stable within each type).
     */
    suspend fun getTitleVideos(tmdbId: Int, isTV: Boolean): List<TMDBVideo> {
        val kind = if (isTV) "tv" else "movie"
        return try {
            val response: TMDBVideosEnvelope = client.get("$base/$kind/$tmdbId/videos?api_key=$apiKey&language=en-US").body()
            val order = mapOf("Trailer" to 0, "Teaser" to 1, "Featurette" to 2, "Clip" to 3)
            response.results
                .filter { it.site == "YouTube" && order.containsKey(it.type) }
                .sortedBy { order[it.type] ?: 99 }
        } catch (_: Exception) { emptyList() }
    }

    // ── Watch Providers ──────────────────────────────────────────────

    @Serializable
    data class TMDBWatchProvider(
        @SerialName("provider_id") val providerId: Int = 0,
        @SerialName("provider_name") val providerName: String = "",
        @SerialName("logo_path") val logoPath: String? = null,
    )

    @Serializable
    data class TMDBProviderRegion(
        val flatrate: List<TMDBWatchProvider>? = null,
        val ads: List<TMDBWatchProvider>? = null,
        val free: List<TMDBWatchProvider>? = null,
    )

    @Serializable
    private data class TMDBProvidersEnvelope(
        val results: Map<String, TMDBProviderRegion> = emptyMap(),
    )

    /** Returns the top US streaming provider for a title. */
    suspend fun getTopWatchProvider(tmdbId: Int): TMDBWatchProvider? {
        return try {
            val response: TMDBProvidersEnvelope = client.get("$base/tv/$tmdbId/watch/providers?api_key=$apiKey").body()
            val us = response.results["US"]
            us?.flatrate?.firstOrNull() ?: us?.ads?.firstOrNull() ?: us?.free?.firstOrNull()
        } catch (_: Exception) { null }
    }

    // ── Genres ───────────────────────────────────────────────────────

    @Serializable
    private data class TMDBGenreListEnvelope(
        val genres: List<TMDBGenre> = emptyList(),
    )

    suspend fun getTVGenres(): List<TMDBGenre> {
        return try {
            val response: TMDBGenreListEnvelope = client.get("$base/genre/tv/list?api_key=$apiKey&language=en-US").body()
            response.genres
        } catch (_: Exception) { emptyList() }
    }

    companion object {
        @Volatile private var instance: TMDBService? = null
        fun get(): TMDBService = instance ?: synchronized(this) {
            instance ?: TMDBService().also { instance = it }
        }
    }
}

package com.rork.guidestreamtvandroid.data.remote

import android.util.Log
import com.rork.guidestreamtvandroid.data.models.SportsGame
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.plugins.DefaultRequest
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.http.HttpHeaders
import io.ktor.serialization.kotlinx.json.json
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Sports service — mirrors iOS SportsService.swift.
 * Fetches live + upcoming games from ESPN's public scoreboard endpoints.
 */
class SportsService {

    private val client = HttpClient {
        // ESPN's CDN (Akamai) 403s requests whose User-Agent doesn't match the
        // client's fingerprint. Ktor's Android engine sends no UA by default,
        // so every scoreboard request returned 403 with an HTML error page
        // (which then broke JSON parsing downstream). The engine is
        // HttpURLConnection, which is backed by OkHttp internally, so an
        // okhttp UA is fingerprint-coherent and verified accepted by ESPN;
        // desktop browser agent strings get blocked on fingerprint mismatch.
        install(DefaultRequest) {
            header(HttpHeaders.UserAgent, "okhttp/4.12.0")
            header(HttpHeaders.Accept, "application/json")
        }
        install(ContentNegotiation) {
            json(Json { ignoreUnknownKeys = true; coerceInputValues = true; isLenient = true })
        }
    }

    private data class Endpoint(val sport: String, val path: String)

    private val endpoints = listOf(
        Endpoint("NBA", "basketball/nba/scoreboard"),
        Endpoint("NBA Summer", "basketball/nba-summer-las-vegas/scoreboard"),
        Endpoint("NBA Summer", "basketball/nba-summer-utah/scoreboard"),
        Endpoint("NBA Summer", "basketball/nba-summer-sacramento/scoreboard"),
        Endpoint("NFL", "football/nfl/scoreboard"),
        Endpoint("Soccer", "soccer/eng.1/scoreboard"),
        Endpoint("Soccer", "soccer/fifa.world/scoreboard"),
        Endpoint("MLB", "baseball/mlb/scoreboard"),
        Endpoint("UFC", "mma/ufc/scoreboard"),
    )

    @Serializable
    private data class ESPNResponse(
        val events: List<ESPNEvent> = emptyList(),
    )

    @Serializable
    private data class ESPNEvent(
        val id: String = "",
        val date: String = "",
        val status: ESPNStatus? = null,
        val competitions: List<ESPNCompetition> = emptyList(),
        val season: ESPNSeason? = null,
    )

    @Serializable
    private data class ESPNStatus(
        val type: ESPNStatusType? = null,
    )

    @Serializable
    private data class ESPNStatusType(
        val state: String = "pre",
        val shortDetail: String = "",
    )

    @Serializable
    private data class ESPNCompetition(
        val competitors: List<ESPNCompetitor> = emptyList(),
        val broadcasts: List<ESPNBroadcast> = emptyList(),
    )

    @Serializable
    private data class ESPNCompetitor(
        val id: String? = null,
        val uid: String? = null,
        val score: String = "",
        @SerialName("homeAway") val homeAway: String = "home",
        val team: ESPNTeam? = null,
        val winner: Boolean? = null,
    )

    @Serializable
    private data class ESPNTeam(
        val id: String? = null,
        val uid: String? = null,
        val abbreviation: String = "",
        @SerialName("displayName") val displayName: String = "",
        @SerialName("shortDisplayName") val shortDisplayName: String = "",
        val name: String = "",
        val color: String? = null,
        val logo: String? = null,
    )

    @Serializable
    private data class ESPNBroadcast(
        val names: List<String> = emptyList(),
    )

    @Serializable
    private data class ESPNSeason(
        val slug: String? = null,
    )

    /** Fetch all games across all sports, sorted live-first then by start time. */
    suspend fun fetchAll(): List<SportsGame> = withContext(Dispatchers.IO) {
        coroutineScope {
            val results = endpoints.map { ep ->
                async { fetch(ep) }
            }.awaitAll()
            val all = results.flatten()
            all.sortedWith(compareByDescending<SportsGame> { it.state == "live" }.thenBy { it.startDate ?: Long.MAX_VALUE })
        }
    }

    private suspend fun fetch(endpoint: Endpoint): List<SportsGame> {
        return try {
            val url = "https://site.api.espn.com/apis/site/v2/sports/${endpoint.path}"
            val response: ESPNResponse = client.get(url).body()
            response.events.mapNotNull { ev ->
                val comp = ev.competitions.firstOrNull() ?: return@mapNotNull null
                val home = comp.competitors.find { it.homeAway == "home" } ?: return@mapNotNull null
                val away = comp.competitors.find { it.homeAway == "away" } ?: return@mapNotNull null
                // ESPN reports state as "pre" | "in" | "post"; normalize "in" to "live".
                val rawState = ev.status?.type?.state ?: "pre"
                val state = if (rawState == "in") "live" else rawState
                val detail = ev.status?.type?.shortDetail ?: ""
                val startDate = parseDate(ev.date)
                val statusDetail = when (state) {
                    "live" -> detail
                    "post" -> detail.ifEmpty { "Final" }
                    else -> startDate?.let { formatGameTime(it) } ?: detail
                }
                val broadcasts = comp.broadcasts.flatMap { it.names }
                SportsGame(
                    id = ev.id,
                    sport = endpoint.sport,
                    leagueShort = ev.season?.slug ?: endpoint.sport,
                    state = state,
                    statusDetail = statusDetail,
                    home = makeTeam(home),
                    away = makeTeam(away),
                    startTime = ev.date,
                    startDate = startDate?.toEpochMilli(),
                    broadcasts = broadcasts,
                    homeScore = home.score.toIntOrNull(),
                    awayScore = away.score.toIntOrNull(),
                )
            }
        } catch (e: Exception) {
            Log.w("SportsService", "Fetch failed for ${endpoint.path}", e)
            emptyList()
        }
    }

    private fun makeTeam(c: ESPNCompetitor): SportsGame.TeamSummary {
        val team = c.team
        val fallbackAbbrev = team?.shortDisplayName?.takeIf { it.isNotBlank() }?.take(3)?.uppercase() ?: "—"
        val abbreviation = team?.abbreviation?.takeIf { it.isNotBlank() } ?: fallbackAbbrev
        val displayName = team?.displayName?.takeIf { it.isNotBlank() }
            ?: team?.name?.takeIf { it.isNotBlank() }
            ?: abbreviation
        val shortName = team?.shortDisplayName?.takeIf { it.isNotBlank() }
            ?: team?.name?.takeIf { it.isNotBlank() }
            ?: abbreviation
        return SportsGame.TeamSummary(
            name = displayName,
            abbreviation = abbreviation,
            logoUrl = team?.logo,
            record = null,
            uid = team?.uid ?: c.uid,
            displayName = displayName,
            shortName = shortName,
            score = c.score,
            primaryHex = team?.color,
            isWinner = c.winner ?: false,
        )
    }

    private fun parseDate(s: String?): java.time.Instant? {
        if (s.isNullOrBlank()) return null
        return try {
            java.time.Instant.parse(s)
        } catch (_: Exception) {
            try {
                java.time.OffsetDateTime.parse(s).toInstant()
            } catch (_: Exception) {
                null
            }
        }
    }

    private fun formatGameTime(instant: java.time.Instant): String {
        val formatter = java.time.format.DateTimeFormatter.ofPattern("h:mm a")
            .withZone(java.time.ZoneId.of("America/New_York"))
        return "${formatter.format(instant)} ET"
    }

    companion object {
        @Volatile private var instance: SportsService? = null
        fun get(): SportsService = instance ?: synchronized(this) {
            instance ?: SportsService().also { instance = it }
        }
    }
}

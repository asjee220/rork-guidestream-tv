package com.rork.guidestreamtvandroid.data.remote

import com.rork.guidestreamtvandroid.data.models.SportsGame
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.get
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
        install(ContentNegotiation) {
            json(Json { ignoreUnknownKeys = true })
        }
    }

    private data class Endpoint(val sport: String, val path: String)

    private val endpoints = listOf(
        Endpoint("NBA", "basketball/nba/scoreboard"),
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
        val name: String = "",
        val date: String = "",
        @SerialName("shortName") val shortName: String? = null,
        val status: ESPNStatus? = null,
        val competitions: List<ESPNCompetition> = emptyList(),
        val broadcasts: List<ESPNBroadcast> = emptyList(),
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
    )

    @Serializable
    private data class ESPNCompetitor(
        val id: String? = null,
        val uid: String? = null,
        val abbreviation: String = "",
        @SerialName("displayName") val displayNameStr: String = "",
        @SerialName("shortDisplayName") val shortDisplayNameStr: String = "",
        val score: String = "",
        @SerialName("homeAway") val homeAway: String = "home",
        val team: ESPNTeam? = null,
        val winner: Boolean? = null,
    )

    @Serializable
    private data class ESPNTeam(
        val color: String? = null,
        val logo: String? = null,
    )

    @Serializable
    private data class ESPNBroadcast(
        val names: List<String> = emptyList(),
    )

    /** Fetch all games across all sports, sorted live-first then by start time. */
    suspend fun fetchAll(): List<SportsGame> = withContext(Dispatchers.IO) {
        coroutineScope {
            val results = endpoints.map { ep ->
                async { fetch(ep) }
            }.awaitAll()
            val all = results.flatten()
            all.sortedWith(compareByDescending<SportsGame> { it.state == "live" }.thenBy { it.startTime ?: "" })
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
                val state = ev.status?.type?.state ?: "pre"
                val detail = ev.status?.type?.shortDetail ?: ""
                SportsGame(
                    id = ev.id,
                    sport = endpoint.sport,
                    state = state,
                    home = SportsGame.TeamSummary(
                        name = home.displayNameStr.ifEmpty { home.abbreviation },
                        abbreviation = home.abbreviation,
                        logoUrl = home.team?.logo,
                        record = home.shortDisplayNameStr,
                    ),
                    away = SportsGame.TeamSummary(
                        name = away.displayNameStr.ifEmpty { away.abbreviation },
                        abbreviation = away.abbreviation,
                        logoUrl = away.team?.logo,
                        record = away.shortDisplayNameStr,
                    ),
                    startTime = ev.date,
                    broadcasts = ev.broadcasts.flatMap { it.names },
                    homeScore = home.score.toIntOrNull(),
                    awayScore = away.score.toIntOrNull(),
                )
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    companion object {
        @Volatile private var instance: SportsService? = null
        fun get(): SportsService = instance ?: synchronized(this) {
            instance ?: SportsService().also { instance = it }
        }
    }
}

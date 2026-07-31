package com.rork.guidestreamtvandroid.data.remote

import com.rork.guidestreamtvandroid.data.models.TMDBResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext

/**
 * One title surfaced inside an Ask Stream reply. Carries enough to render a
 * poster card AND tap through to the existing detail screen.
 * Mirrors iOS `AgentTitleMatch` / `AgentTitleMatchModel`.
 */
data class AgentTitleMatch(
    val id: Int,
    val title: String,
    val posterUrl: String?,
    val backdropUrl: String?,
    val year: Int?,
    val isTV: Boolean,
    val providerName: String?,
)

/**
 * Resolves the titles an Ask Stream answer mentions into TMDB matches so the
 * chat can render real poster art under the bubble — mirrors iOS
 * `StreamAgentService.resolveTitleMatches`.
 */
class StreamAgentService private constructor() {

    /** A title parsed out of the agent prose, with an optional disambiguating year. */
    data class TitleCandidate(val name: String, val year: Int?)

    /**
     * Extracts `**Bolded**` titles from the reply and resolves each against
     * TMDB (plus its top US watch provider). Capped at 6 to keep the API
     * budget tight, de-duplicated by TMDB id, and returned in reply order.
     */
    suspend fun resolveTitleMatches(answer: String): List<AgentTitleMatch> =
        withContext(Dispatchers.IO) {
            val candidates = extractTitles(answer).take(MAX_MATCHES)
            if (candidates.isEmpty()) return@withContext emptyList()

            val tmdb = TMDBService.get()
            val resolved = coroutineScope {
                candidates.map { candidate ->
                    async {
                        try {
                            val results = tmdb.searchContent(candidate.name)
                            val pick = bestMatch(results, candidate) ?: return@async null
                            val provider = tmdb.getTopWatchProvider(pick.id, pick.isTV)
                            AgentTitleMatch(
                                id = pick.id,
                                title = pick.displayName,
                                posterUrl = pick.posterUrl,
                                backdropUrl = pick.backdropUrl,
                                year = pick.year,
                                isTV = pick.isTV,
                                providerName = provider?.providerName?.takeIf { it.isNotBlank() },
                            )
                        } catch (_: Exception) {
                            null
                        }
                    }
                }.awaitAll()
            }

            val seen = mutableSetOf<Int>()
            resolved.filterNotNull().filter { seen.add(it.id) }
        }

    companion object {
        private const val MAX_MATCHES = 6

        /** `**Title**` / `**Title (2024)**` captures from the markdown reply. */
        private val BOLD_REGEX = Regex("""\*\*([^*]+?)\*\*""")
        private val TRAILING_YEAR_REGEX = Regex("""\((\d{4})\)\s*$""")

        /**
         * Pulls bolded title candidates out of the agent reply, splitting a
         * trailing "(2024)" into a separate year so franchise reboots resolve
         * to the right entry.
         */
        fun extractTitles(text: String): List<TitleCandidate> =
            BOLD_REGEX.findAll(text).mapNotNull { match ->
                val raw = match.groupValues.getOrNull(1)?.trim().orEmpty()
                if (raw.isEmpty() || raw.length > 120) return@mapNotNull null
                val yearMatch = TRAILING_YEAR_REGEX.find(raw)
                if (yearMatch != null) {
                    val name = raw.removeRange(yearMatch.range).trim()
                    if (name.isNotEmpty()) {
                        return@mapNotNull TitleCandidate(
                            name = name,
                            year = yearMatch.groupValues[1].toIntOrNull(),
                        )
                    }
                }
                TitleCandidate(name = raw, year = null)
            }.toList()

        /** Exact name match wins, then year proximity, then TMDB's own ranking. */
        private fun bestMatch(results: List<TMDBResult>, candidate: TitleCandidate): TMDBResult? {
            if (results.isEmpty()) return null
            val lowered = candidate.name.lowercase()
            results.firstOrNull { it.displayName.lowercase() == lowered }?.let { return it }
            candidate.year?.let { year ->
                results.firstOrNull { it.year == year }?.let { return it }
            }
            return results.firstOrNull()
        }

        @Volatile private var instance: StreamAgentService? = null

        fun get(): StreamAgentService = instance ?: synchronized(this) {
            instance ?: StreamAgentService().also { instance = it }
        }
    }
}

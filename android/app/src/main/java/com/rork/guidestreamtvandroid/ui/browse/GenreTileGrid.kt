package com.rork.guidestreamtvandroid.ui.browse

import androidx.compose.foundation.background
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rork.guidestreamtvandroid.data.models.BrowseCatalog
import com.rork.guidestreamtvandroid.data.models.BrowseFilters
import com.rork.guidestreamtvandroid.data.models.BrowseGenre
import com.rork.guidestreamtvandroid.data.remote.TMDBService
import com.rork.guidestreamtvandroid.ui.components.RemoteImage
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * The genre entry point for Search & Browse: artwork tiles, two up.
 * Mirrors iOS `GenreTileGrid.swift`.
 *
 * A tinted square with an icon (the Home treatment) does not sell a category —
 * the tile has to show what is inside it. Each tile pulls the top backdrop for
 * its genre once per process and falls back to its brand tint until that lands,
 * so the grid is never empty and never janks.
 */

// ---------------------------------------------------------------------------
// Tint
// ---------------------------------------------------------------------------

/**
 * Per-genre gradient, used as the tile's resting state and as the fallback
 * behind artwork that has not loaded yet.
 */
object BrowseTint {
    private val ramps: Map<String, Pair<Long, Long>> = mapOf(
        "crime" to (0xFFC0392B to 0xFF2B0A0E),
        "scifi" to (0xFF1A6FE8 to 0xFF06111F),
        "horror" to (0xFF5A1416 to 0xFF050203),
        "anime" to (0xFF6C3BF5 to 0xFF00C2E0),
        "comedy" to (0xFF2ECC71 to 0xFF07160E),
        "drama" to (0xFF8E44AD to 0xFF120620),
        "action" to (0xFFF5821F to 0xFF1C0E02),
        "documentary" to (0xFF00A99D to 0xFF02171A),
        "romance" to (0xFFFF4785 to 0xFF1C0413),
        "international" to (0xFF3D7EA6 to 0xFF050D18),
    )

    fun brush(genreId: String): Brush {
        val ramp = ramps[genreId] ?: (0xFF2D1454 to 0xFF04090F)
        return Brush.linearGradient(listOf(Color(ramp.first), Color(ramp.second)))
    }
}

// ---------------------------------------------------------------------------
// Artwork
// ---------------------------------------------------------------------------

/**
 * Process-wide cache of one backdrop per genre.
 *
 * Ten concurrent discover calls, once, the first time a browse surface appears.
 * The tiles are decoration, so a stale-by-an-hour backdrop is not worth a
 * refetch.
 */
object BrowseArtworkStore {
    private val _backdrops = MutableStateFlow<Map<String, String>>(emptyMap())
    val backdrops: StateFlow<Map<String, String>> = _backdrops.asStateFlow()

    private val lock = Mutex()

    /**
     * How many backdrops each genre offers up for the assignment pass. One was
     * not enough: a title that tops two genres claimed both tiles.
     */
    private const val CANDIDATE_DEPTH = 8

    suspend fun loadIfNeeded() {
        if (_backdrops.value.size >= BrowseCatalog.genres.size) return
        lock.withLock {
            val current = _backdrops.value
            val pending = BrowseCatalog.genres.filter { current[it.id] == null }
            if (pending.isEmpty()) return
            val tmdb = TMDBService.get()
            val candidates: Map<String, List<String>> = coroutineScope {
                pending.map { genre ->
                    async {
                        // No provider filter here: the tile should show the
                        // genre's best-known title, not whatever the user has.
                        val page = tmdb.discoverBrowse(
                            BrowseFilters(genreIds = setOf(genre.id), onlyMyServices = false)
                        )
                        genre.id to page.results
                            .mapNotNull { it.backdropUrl }
                            .take(CANDIDATE_DEPTH)
                    }
                }.map { it.await() }.toMap()
            }

            // Assign in catalogue order rather than in completion order, so
            // which tile gets first claim on a shared title does not depend on
            // which network call happened to return first.
            //
            // Each tile takes its most popular backdrop that no earlier tile
            // has taken. Reacher tops both Crime & Thriller and Action, and the
            // two tiles used to show the identical image.
            val used = current.values.toMutableSet()
            val resolved = mutableMapOf<String, String>()
            for (genre in BrowseCatalog.genres) {
                val options = candidates[genre.id].orEmpty()
                if (options.isEmpty()) continue
                // If every candidate is already spoken for, take the first
                // anyway: a repeated tile still reads better than an empty one.
                val pick = options.firstOrNull { it !in used } ?: options[0]
                used += pick
                resolved[genre.id] = pick
            }

            _backdrops.value = current + resolved
        }
    }
}

// ---------------------------------------------------------------------------
// Grid
// ---------------------------------------------------------------------------

@Composable
fun GenreTileGrid(
    onSelect: (BrowseGenre) -> Unit,
    modifier: Modifier = Modifier,
) {
    val backdrops by BrowseArtworkStore.backdrops.collectAsStateWithLifecycle()
    LaunchedEffect(Unit) { BrowseArtworkStore.loadIfNeeded() }

    // A plain Column of Rows, not a LazyVerticalGrid: this sits inside another
    // scrolling container, and nesting lazy grids crashes at measure time.
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        BrowseCatalog.genres.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                row.forEach { genre ->
                    GenreTile(
                        genre = genre,
                        backdropUrl = backdrops[genre.id],
                        onClick = { onSelect(genre) },
                        modifier = Modifier.weight(1f),
                    )
                }
                // Keeps a lone trailing tile at half width instead of stretching.
                if (row.size == 1) Box(modifier = Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun GenreTile(
    genre: BrowseGenre,
    backdropUrl: String?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .height(84.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(BrowseTint.brush(genre.id))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() },
        contentAlignment = Alignment.BottomStart,
    ) {
        if (backdropUrl != null) {
            RemoteImage(
                url = backdropUrl,
                contentDescription = genre.displayName,
                modifier = Modifier.fillMaxSize(),
                cornerRadius = 12,
            )
        }

        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        listOf(Color.Transparent, Color.Black.copy(alpha = 0.72f))
                    )
                )
        )

        Text(
            text = genre.displayName,
            fontSize = 13.sp,
            fontWeight = FontWeight.Bold,
            color = Color.White,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(10.dp),
        )
    }
}

package com.rork.guidestreamtvandroid.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items as gridItems
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.guidestreamtvandroid.data.models.StreamingCatalog
import com.rork.guidestreamtvandroid.data.models.TMDBResult
import com.rork.guidestreamtvandroid.data.remote.TMDBService
import com.rork.guidestreamtvandroid.data.repository.WatchIntentLogger
import com.rork.guidestreamtvandroid.ui.components.RemoteImage
import com.rork.guidestreamtvandroid.ui.home.HomeViewModel
import com.rork.guidestreamtvandroid.ui.navigation.PendingTitleRoute
import com.rork.guidestreamtvandroid.ui.navigation.PopularCategoriesTarget
import com.rork.guidestreamtvandroid.ui.theme.Navy
import com.rork.guidestreamtvandroid.ui.theme.systemBottomInset
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary

/**
 * Full-screen "Popular on {service}" category browser reached via the
 * "See all" link on each home rail. Mirrors iOS PopularOnServiceCategoriesView:
 * a horizontally-scrolling pill row (All + genre tabs) pinned above a
 * two-column poster grid. Each category loads lazily and is cached; the All
 * tab combines TV + movies and is seeded from the rail's already-loaded
 * results so it never blanks.
 */
@Composable
fun PopularOnServiceCategoriesScreen(
    target: PopularCategoriesTarget,
    onBack: () -> Unit,
    onOpenTitle: (PendingTitleRoute) -> Unit,
    modifier: Modifier = Modifier,
) {
    val service = remember(target.serviceId) { StreamingCatalog.service(target.serviceId) }
    val glow = service?.glow ?: Color(0xFF6B7280)
    val bg = service?.bg ?: Navy
    val name = service?.name ?: "Streaming"

    val categories = remember {
        listOf(
            CategoryTab("all", "All", null, "tv", false),
            CategoryTab("crime", "Crime & Thriller", 80, "tv", false),
            CategoryTab("scifi", "Sci-Fi", 10765, "tv", false),
            CategoryTab("comedy", "Comedy", 35, "tv", false),
            CategoryTab("drama", "Drama", 18, "tv", false),
            CategoryTab("action", "Action", 10759, "tv", false),
            CategoryTab("documentary", "Documentary", 99, "tv", false),
            CategoryTab("romance", "Romance", 10749, "movie", false),
            CategoryTab("international", "International", null, "tv", true),
        )
    }

    var selectedCategory by remember { mutableStateOf("all") }
    val results = remember { mutableStateMapOf<String, List<TMDBResult>>() }
    val loading = remember { mutableStateMapOf<String, Boolean>() }

    // Seed the All tab instantly from the rail, then replace with the full
    // combined TV + movie list. Never blocks.
    LaunchedEffect(Unit) {
        val seed = HomeViewModel.get().popularByService.value[target.serviceId] ?: emptyList()
        if (results["all"] == null) results["all"] = seed.take(25)
        loading["all"] = true
        try {
            val tmdb = TMDBService.get()
            val tv = tmdb.getPopularOnService(target.providerId)
            val movies = tmdb.getPopularMoviesOnService(target.providerId)
            val interleaved = mutableListOf<TMDBResult>()
            val maxCount = maxOf(tv.size, movies.size)
            for (i in 0 until maxCount) {
                if (i < tv.size) interleaved.add(tv[i])
                if (i < movies.size) interleaved.add(movies[i])
            }
            val seen = mutableSetOf<Int>()
            val merged = mutableListOf<TMDBResult>()
            for (r in interleaved) {
                if (seen.add(r.id)) {
                    merged.add(r)
                    if (merged.size >= 25) break
                }
            }
            if (merged.isNotEmpty()) results["all"] = merged
        } catch (_: Exception) { /* keep seed */ }
        loading["all"] = false
    }

    // Lazily load genre / international tabs on first selection.
    LaunchedEffect(selectedCategory) {
        if (selectedCategory == "all") return@LaunchedEffect
        if (results[selectedCategory] != null) return@LaunchedEffect
        val cat = categories.firstOrNull { it.id == selectedCategory } ?: return@LaunchedEffect
        loading[cat.id] = true
        try {
            val tmdb = TMDBService.get()
            val fetched = when {
                cat.international -> tmdb.getPopularOnServiceInternational(target.providerId)
                cat.genreId != null -> tmdb.getPopularOnServiceByGenre(target.providerId, cat.genreId, cat.mediaType)
                else -> emptyList()
            }
            results[cat.id] = fetched.take(25)
        } catch (_: Exception) {
            results[cat.id] = emptyList()
        }
        loading[cat.id] = false
    }

    val currentShows = results[selectedCategory] ?: emptyList()
    val isLoading = loading[selectedCategory] == true

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(Navy),
    ) {
        Spacer(Modifier.height(12.dp))

        // Top bar — back chevron + title
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onBack() },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Filled.ArrowBack,
                    contentDescription = "Back",
                    tint = TextPrimary,
                    modifier = Modifier.size(24.dp),
                )
            }
            Spacer(Modifier.width(4.dp))
            Text(
                text = "Popular on $name",
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
            )
        }

        Spacer(Modifier.height(8.dp))

        // Category pills — single non-wrapping row with a trailing fade to Navy
        Box {
            LazyRow(
                modifier = Modifier.fillMaxWidth(),
                contentPadding = PaddingValues(horizontal = 20.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(categories) { cat ->
                    val selected = cat.id == selectedCategory
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(50))
                            .background(if (selected) glow else Color.White.copy(alpha = 0.10f))
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                            ) { selectedCategory = cat.id }
                            .padding(horizontal = 14.dp, vertical = 8.dp),
                    ) {
                        Text(
                            text = cat.name,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = if (selected) Color.Black else TextPrimary.copy(alpha = 0.85f),
                            maxLines = 1,
                        )
                    }
                }
            }
            Box(
                modifier = Modifier
                    .align(Alignment.CenterEnd)
                    .fillMaxHeight()
                    .width(44.dp)
                    .background(
                        Brush.horizontalGradient(listOf(Color.Transparent, Navy)),
                    ),
            )
        }

        Spacer(Modifier.height(6.dp))

        // Content — grid / loading / empty
        when {
            currentShows.isEmpty() && isLoading -> {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator(color = Color.White)
                }
            }
            currentShows.isEmpty() -> {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = "Nothing here yet",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = TextSecondary,
                    )
                }
            }
            else -> {
                LazyVerticalGrid(
                    columns = GridCells.Fixed(2),
                    contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 12.dp, bottom = systemBottomInset() + 24.dp),
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                    modifier = Modifier.fillMaxSize(),
                ) {
                    gridItems(currentShows) { r ->
                        PosterGridCell(
                            show = r,
                            accentColor = glow,
                            onClick = {
                                WatchIntentLogger.get().log(
                                    WatchIntentLogger.IntentEventType.CARD_TAPPED,
                                    titleId = r.id.toString(),
                                    metadata = mapOf("section" to "popular_on_${target.serviceId}_category_$selectedCategory"),
                                )
                                onOpenTitle(
                                    PendingTitleRoute(
                                        titleId = r.id.toString(),
                                        titleName = r.displayName,
                                        isTv = r.isTV,
                                    ),
                                )
                            },
                        )
                    }
                }
            }
        }
    }
}

/** A single category tab descriptor. */
private data class CategoryTab(
    val id: String,
    val name: String,
    val genreId: Int?,
    val mediaType: String,
    val international: Boolean,
)

@Composable
private fun PosterGridCell(
    show: TMDBResult,
    accentColor: Color,
    onClick: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() },
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(0.67f)
                .clip(RoundedCornerShape(10.dp)),
        ) {
            RemoteImage(
                url = show.posterUrl,
                contentDescription = show.displayName,
                modifier = Modifier.fillMaxSize(),
                cornerRadius = 10,
                placeholderText = show.displayName.take(2).uppercase(),
                placeholderFontSize = 22.sp,
            )
            Box(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .height(3.dp)
                    .background(accentColor),
            )
        }
        Spacer(Modifier.height(6.dp))
        Text(
            text = show.displayName,
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            color = TextPrimary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            text = show.year?.toString() ?: if (show.isTV) "Series" else "Movie",
            fontSize = 11.sp,
            color = TextTertiary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

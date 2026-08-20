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
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
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
import com.rork.guidestreamtvandroid.data.CountryCatalog
import com.rork.guidestreamtvandroid.data.models.TMDBResult
import com.rork.guidestreamtvandroid.data.remote.TMDBService
import com.rork.guidestreamtvandroid.data.repository.WatchIntentLogger
import com.rork.guidestreamtvandroid.ui.components.RemoteImage
import com.rork.guidestreamtvandroid.ui.navigation.PendingTitleRoute
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.Navy
import com.rork.guidestreamtvandroid.ui.theme.SurfaceContainer
import com.rork.guidestreamtvandroid.ui.theme.systemBottomInset
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary
import kotlinx.coroutines.CancellationException

/**
 * Full-screen "Around the World" country browser reached via the
 * "Around the World" home rail. Mirrors iOS AroundTheWorldView: a country
 * pill row and a service pill row above a two-column poster grid. Every
 * country + provider combination loads lazily and is cached in memory. Pure
 * TMDB — provider ids are region-specific and come verbatim from
 * [CountryCatalog]. The country row seeds to the passed region and the
 * service row seeds to that country's first provider, reseeding whenever the
 * country changes.
 */
@Composable
fun AroundTheWorldScreen(
    regionCode: String,
    onBack: () -> Unit,
    onOpenTitle: (PendingTitleRoute) -> Unit,
    modifier: Modifier = Modifier,
) {
    val initialEntry = remember(regionCode) {
        CountryCatalog.entryFor(regionCode) ?: CountryCatalog.countryOfDay
    }
    var selectedRegion by remember { mutableStateOf(initialEntry.regionCode) }
    var selectedProviderId by remember { mutableStateOf(initialEntry.providers.firstOrNull()?.id ?: 0) }

    val country = CountryCatalog.entryFor(selectedRegion) ?: CountryCatalog.countryOfDay
    val selectedProvider = country.providers.firstOrNull { it.id == selectedProviderId }
        ?: country.providers.firstOrNull()
    val resolvedProviderId = selectedProvider?.id ?: 0

    val cacheKey = "${country.regionCode}-$resolvedProviderId"
    val results = remember { mutableStateMapOf<String, List<TMDBResult>>() }
    val loading = remember { mutableStateMapOf<String, Boolean>() }

    // Lazily load each country + provider combination once; cached in memory.
    LaunchedEffect(cacheKey) {
        if (results[cacheKey] != null || loading[cacheKey] == true) return@LaunchedEffect
        val provider = selectedProvider ?: return@LaunchedEffect
        loading[cacheKey] = true
        val fetched = try {
            TMDBService.get().discoverByProvider(
                providerId = provider.id,
                limit = 40,
                region = country.regionCode,
                originalLanguage = country.originalLanguage,
                voteCountGte = 100,
                withoutKeywords = "198385",
            )
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            emptyList()
        }
        results[cacheKey] = fetched
        loading[cacheKey] = false
    }

    val currentShows = results[cacheKey] ?: emptyList()
    val isLoading = loading[cacheKey] == true

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(Navy),
    ) {
        // statusBarsPadding keeps the back-arrow tap target below the system
        // status bar — without it the status bar consumes the touch.
        Spacer(Modifier.statusBarsPadding().height(12.dp))

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
                text = "Around the World",
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
            )
        }

        Spacer(Modifier.height(8.dp))

        // Country pills — seeded to the passed region
        Box {
            LazyRow(
                modifier = Modifier.fillMaxWidth(),
                contentPadding = PaddingValues(horizontal = 20.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(CountryCatalog.entries) { e ->
                    val selected = e.regionCode == country.regionCode
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(50))
                            .background(if (selected) BrandOrange else SurfaceContainer)
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                            ) {
                                if (e.regionCode != country.regionCode) {
                                    // Reseed the service row to the new
                                    // country's first provider.
                                    selectedProviderId = e.providers.firstOrNull()?.id ?: 0
                                    selectedRegion = e.regionCode
                                }
                            }
                            .padding(horizontal = 14.dp, vertical = 8.dp),
                    ) {
                        Text(
                            text = e.displayName,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = if (selected) Color.Black else TextPrimary.copy(alpha = 0.85f),
                            maxLines = 1,
                        )
                    }
                }
            }
            // Trailing fade to Navy — matchParentSize so the overlay measures
            // at the pill row's size without contributing to it.
            Box(
                modifier = Modifier
                    .matchParentSize()
                    .background(
                        Brush.horizontalGradient(
                            0f to Color.Transparent,
                            0.86f to Color.Transparent,
                            1f to Navy,
                        ),
                    ),
            )
        }

        Spacer(Modifier.height(6.dp))

        // Service pills — seeded to the country's first provider
        Box {
            LazyRow(
                modifier = Modifier.fillMaxWidth(),
                contentPadding = PaddingValues(horizontal = 20.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(country.providers) { provider ->
                    val selected = provider.id == resolvedProviderId
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(50))
                            .background(if (selected) BrandOrange else SurfaceContainer)
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                            ) { selectedProviderId = provider.id }
                            .padding(horizontal = 14.dp, vertical = 8.dp),
                    ) {
                        Text(
                            text = provider.name,
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
                    .matchParentSize()
                    .background(
                        Brush.horizontalGradient(
                            0f to Color.Transparent,
                            0.86f to Color.Transparent,
                            1f to Navy,
                        ),
                    ),
            )
        }

        Spacer(Modifier.height(8.dp))

        // Header line
        Text(
            text = "${currentShows.size} titles · availability shown for ${country.displayName}",
            fontSize = 12.sp,
            color = TextSecondary,
            modifier = Modifier.padding(horizontal = 20.dp),
        )

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
                            accentColor = BrandOrange,
                            onClick = {
                                WatchIntentLogger.get().log(
                                    WatchIntentLogger.IntentEventType.CARD_TAPPED,
                                    titleId = r.id.toString(),
                                    metadata = mapOf("section" to "around_the_world"),
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

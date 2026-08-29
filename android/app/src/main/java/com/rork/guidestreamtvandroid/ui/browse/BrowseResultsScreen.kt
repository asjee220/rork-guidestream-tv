package com.rork.guidestreamtvandroid.ui.browse

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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rork.guidestreamtvandroid.data.models.BrowseCatalog
import com.rork.guidestreamtvandroid.data.models.BrowseFilterPill
import com.rork.guidestreamtvandroid.data.models.StreamingCatalog
import com.rork.guidestreamtvandroid.data.models.TMDBResult
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.ui.ads.InlineAdSlot
import com.rork.guidestreamtvandroid.ui.components.RemoteImage
import com.rork.guidestreamtvandroid.ui.home.HomeViewModel
import com.rork.guidestreamtvandroid.ui.navigation.PendingTitleRoute
import com.rork.guidestreamtvandroid.ui.theme.BottomSafeSpacer
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.Navy
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary

/**
 * Filter-driven results grid behind a genre tile. Mirrors iOS
 * `BrowseResultsView.swift`.
 *
 * This is the service-category browser generalised: the same pill row over a
 * two-column poster grid with per-selection caching, freed from its single
 * provider and given an applied-filter bar, a result count, sort and paging.
 */
@Composable
fun BrowseResultsScreen(
    genreId: String,
    onBack: () -> Unit,
    onOpenTitle: (PendingTitleRoute) -> Unit,
    modifier: Modifier = Modifier,
) {
    val scope = rememberCoroutineScope()
    val auth = remember { AuthViewModel.get() }
    val home = remember { HomeViewModel.get() }
    val selectedServices by auth.selectedServices.collectAsStateWithLifecycle()

    val controller = remember(genreId) { BrowseController(scope, genreId, emptyList()) }

    val filters by controller.filters.collectAsStateWithLifecycle()
    val results by controller.results.collectAsStateWithLifecycle()
    val totalResults by controller.totalResults.collectAsStateWithLifecycle()
    val isLoading by controller.isLoading.collectAsStateWithLifecycle()
    val isPaging by controller.isPaging.collectAsStateWithLifecycle()
    val recovery by controller.recovery.collectAsStateWithLifecycle()

    var showFilters by remember { mutableStateOf(false) }
    var showSort by remember { mutableStateOf(false) }

    LaunchedEffect(selectedServices) {
        controller.attachProviders(
            StreamingCatalog.ordered(selectedServices).mapNotNull { home.providerIdFor(it.id) }
        )
        controller.reload()
    }

    Column(modifier = modifier.fillMaxSize().background(Navy).statusBarsPadding()) {
        // Header
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(36.dp)
                    .clip(CircleShape)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onBack() },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = "Back to search",
                    tint = Color.White,
                )
            }
            Text(
                text = BrowseCatalog.genre(genreId)?.displayName ?: "Browse",
                fontSize = 17.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(start = 4.dp),
            )
        }

        // Genre rail
        LazyRow(
            contentPadding = PaddingValues(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.padding(vertical = 6.dp),
        ) {
            items(BrowseCatalog.genres, key = { it.id }) { genre ->
                val selected = filters.genreIds.contains(genre.id)
                Text(
                    text = genre.displayName,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = if (selected) Color.White else TextSecondary,
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(if (selected) BrandOrange else Color.White.copy(alpha = 0.08f))
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) { controller.selectGenre(genre.id) }
                        .padding(horizontal = 14.dp, vertical = 8.dp),
                )
            }
        }

        // Applied filters
        if (filters.pills.isNotEmpty()) {
            LazyRow(
                contentPadding = PaddingValues(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(7.dp),
                modifier = Modifier.padding(bottom = 6.dp),
            ) {
                items(filters.pills, key = { it.id() }) { pill ->
                    FilterPill(
                        label = pill.label,
                        accented = pill.accented,
                        onRemove = { controller.remove(pill.kind) },
                    )
                }
            }
        }

        // Count + controls
        Row(
            modifier = Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = if (isLoading) "Loading…" else "$totalResults titles · ${filters.sort.label}",
                fontSize = 12.sp,
                color = Color.White.copy(alpha = 0.5f),
                modifier = Modifier.weight(1f),
            )
            Icon(
                imageVector = Icons.Filled.SwapVert,
                contentDescription = "Sort",
                tint = Color.White.copy(alpha = 0.75f),
                modifier = Modifier
                    .size(22.dp)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { showSort = true },
            )
            Box(modifier = Modifier.padding(start = 16.dp)) {
                Icon(
                    imageVector = Icons.Filled.Tune,
                    contentDescription = "Filters, ${filters.activeCount} active",
                    tint = Color.White.copy(alpha = 0.75f),
                    modifier = Modifier
                        .size(22.dp)
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) { showFilters = true },
                )
                if (filters.activeCount > 0) {
                    Text(
                        text = "${filters.activeCount}",
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Black,
                        color = Navy,
                        textAlign = TextAlign.Center,
                        modifier = Modifier
                            .offset(x = 12.dp, y = (-6).dp)
                            .size(14.dp)
                            .clip(CircleShape)
                            .background(BrandOrange),
                    )
                }
            }
        }

        Box(modifier = Modifier.fillMaxWidth().height(1.dp).background(Color.White.copy(alpha = 0.07f)))

        // Content
        when {
            isLoading && results.isEmpty() -> {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
                    CircularProgressIndicator(
                        color = BrandOrange,
                        modifier = Modifier.padding(top = 48.dp).size(28.dp),
                    )
                }
            }

            results.isEmpty() -> {
                BrowseEmptyState(
                    recovery = recovery,
                    onRelax = { controller.remove(it) },
                    onClearAll = { controller.clearAll() },
                )
            }

            else -> {
                val dismissedAdSlots = remember { mutableStateMapOf<Int, Boolean>() }
                LazyVerticalGrid(
                    columns = GridCells.Fixed(2),
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 14.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    results.chunked(6).forEachIndexed { chunkIdx, chunk ->
                        items(chunk, key = { it.id }) { result ->
                            BrowsePosterCell(result) {
                                onOpenTitle(
                                    PendingTitleRoute(
                                        titleId = result.id.toString(),
                                        titleName = result.displayName,
                                        isTv = result.isTV,
                                    )
                                )
                            }
                        }
                        if (chunk.size == 6) {
                            item(span = { GridItemSpan(maxLineSpan) }) {
                                InlineAdSlot(
                                    slotIndex = chunkIdx,
                                    selectedServices = selectedServices,
                                    adSource = "browse_grid",
                                    sectionKey = "browse_grid_ad",
                                    dismissed = dismissedAdSlots,
                                )
                            }
                        }
                    }

                    item(span = { GridItemSpan(maxLineSpan) }) {
                        // Pages two rows early so the grid never shows a
                        // spinner mid-scroll.
                        LaunchedEffect(results.size) { controller.loadNextPage() }
                        if (isPaging) {
                            Box(
                                modifier = Modifier.fillMaxWidth().padding(vertical = 20.dp),
                                contentAlignment = Alignment.Center,
                            ) {
                                CircularProgressIndicator(
                                    color = BrandOrange,
                                    modifier = Modifier.size(24.dp),
                                )
                            }
                        }
                    }

                    item(span = { GridItemSpan(maxLineSpan) }) { BottomSafeSpacer(withTabBar = false) }
                }
            }
        }
    }

    if (showFilters) {
        BrowseFilterSheet(
            filters = filters,
            onApply = { controller.update(it) },
            onDismiss = { showFilters = false },
        )
    }

    if (showSort) {
        BrowseSortSheet(
            sort = filters.sort,
            onSelect = { controller.update(filters.copy(sort = it)) },
            onDismiss = { showSort = false },
        )
    }
}

private fun BrowseFilterPill.id(): String = kind.name

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

@Composable
private fun FilterPill(label: String, accented: Boolean, onRemove: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier
            .clip(CircleShape)
            .background(
                if (accented) BrandOrange.copy(alpha = 0.18f) else Color.White.copy(alpha = 0.12f)
            )
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onRemove() }
            .padding(start = 12.dp, end = 9.dp, top = 6.dp, bottom = 6.dp),
    ) {
        Text(
            text = label,
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            color = if (accented) BrandOrange else Color.White,
            maxLines = 1,
        )
        Text(
            text = "✕",
            fontSize = 11.sp,
            color = (if (accented) BrandOrange else Color.White).copy(alpha = 0.6f),
        )
    }
}

@Composable
private fun BrowsePosterCell(result: TMDBResult, onClick: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() },
    ) {
        RemoteImage(
            url = result.posterUrl,
            contentDescription = result.displayName,
            modifier = Modifier.fillMaxWidth().aspectRatio(2f / 3f),
            cornerRadius = 10,
            placeholderText = result.displayName.take(2).uppercase(),
            placeholderFontSize = 18.sp,
        )
        Text(
            text = result.displayName,
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            color = Color.White,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 7.dp),
        )
        Text(
            text = buildString {
                append(if (result.isTV) "Show" else "Movie")
                result.year?.let { append(" · $it") }
                result.voteAverage?.takeIf { it > 0 }?.let {
                    append(" · ★ ${String.format(java.util.Locale.US, "%.1f", it)}")
                }
            },
            fontSize = 11.sp,
            color = Color.White.copy(alpha = 0.45f),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 2.dp),
        )
    }
}

@Composable
private fun BrowseEmptyState(
    recovery: BrowseRecovery?,
    onRelax: (BrowseFilterPill.Kind) -> Unit,
    onClearAll: () -> Unit,
) {
    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 30.dp, vertical = 52.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            imageVector = Icons.Filled.Search,
            contentDescription = null,
            tint = Color.White.copy(alpha = 0.35f),
            modifier = Modifier.size(30.dp),
        )
        Spacer(modifier = Modifier.height(14.dp))
        Text(
            text = if (recovery == null) {
                "Nothing matches these filters"
            } else {
                "Nothing matches all of these filters"
            },
            fontSize = 17.sp,
            fontWeight = FontWeight.Bold,
            color = Color.White,
            textAlign = TextAlign.Center,
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = recovery?.let {
                "Dropping ${it.label} brings back ${it.count} titles."
            } ?: "Try widening the filters.",
            fontSize = 13.sp,
            color = Color.White.copy(alpha = 0.5f),
            textAlign = TextAlign.Center,
        )
        if (recovery != null) {
            Spacer(modifier = Modifier.height(20.dp))
            Text(
                text = "Drop ${recovery.label}",
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold,
                color = Navy,
                modifier = Modifier
                    .clip(CircleShape)
                    .background(BrandOrange)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onRelax(recovery.kind) }
                    .padding(horizontal = 22.dp, vertical = 12.dp),
            )
        }
        Spacer(modifier = Modifier.height(14.dp))
        Text(
            text = "Clear all filters",
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            color = BrandOrange,
            modifier = Modifier.clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClearAll() },
        )
    }
}

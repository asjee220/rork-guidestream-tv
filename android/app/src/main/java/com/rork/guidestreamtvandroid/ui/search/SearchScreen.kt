package com.rork.guidestreamtvandroid.ui.search

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rork.guidestreamtvandroid.ui.components.RemoteImage
import com.rork.guidestreamtvandroid.ui.components.glassCard
import com.rork.guidestreamtvandroid.ui.navigation.PendingTitleRoute
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.GlassFill
import com.rork.guidestreamtvandroid.ui.theme.GlassStroke
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary

/**
 * Search screen — mirrors iOS SearchView.swift.
 * Scope chips (All, Shows, Creators, Podcasts), debounced query,
 * grouped results, popular trending when empty.
 */
@Composable
fun SearchScreen(
    onClose: () -> Unit,
    onOpenTitle: (PendingTitleRoute) -> Unit,
    onOpenCreator: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val vm = SearchViewModel.get()
    val query by vm.query.collectAsStateWithLifecycle()
    val scope by vm.scope.collectAsStateWithLifecycle()
    val isSearching by vm.isSearching.collectAsStateWithLifecycle()
    val tmdbResults by vm.tmdbResults.collectAsStateWithLifecycle()
    val creatorResults by vm.creatorResults.collectAsStateWithLifecycle()
    val popular by vm.popular.collectAsStateWithLifecycle()

    LaunchedEffect(Unit) { vm.loadPopular() }

    Column(
        modifier = modifier.fillMaxSize(),
    ) {
        // Search bar
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onClose() },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Filled.ArrowBack,
                    contentDescription = "Back",
                    tint = TextPrimary,
                    modifier = Modifier.size(22.dp),
                )
            }
            Spacer(Modifier.width(8.dp))
            Row(
                modifier = Modifier
                    .weight(1f)
                    .glassCard(14)
                    .padding(horizontal = 12.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    imageVector = Icons.Filled.Search,
                    contentDescription = "Search",
                    tint = TextTertiary,
                    modifier = Modifier.size(18.dp),
                )
                Spacer(Modifier.width(8.dp))
                BasicTextField(
                    value = query,
                    onValueChange = { vm.setQuery(it) },
                    modifier = Modifier.weight(1f),
                    textStyle = TextStyle(
                        color = TextPrimary,
                        fontSize = 15.sp,
                    ),
                    cursorBrush = SolidColor(BrandOrange),
                    singleLine = true,
                    decorationBox = { inner ->
                        if (query.isEmpty()) {
                            Text(
                                text = "Search shows, creators, podcasts…",
                                fontSize = 14.sp,
                                color = TextTertiary,
                            )
                        }
                        inner()
                    },
                )
                if (query.isNotEmpty()) {
                    Box(
                        modifier = Modifier
                            .size(20.dp)
                            .clip(CircleShape)
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                            ) { vm.setQuery("") },
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            imageVector = Icons.Filled.Clear,
                            contentDescription = "Clear",
                            tint = TextTertiary,
                            modifier = Modifier.size(16.dp),
                        )
                    }
                }
            }
        }

        // Scope chips
        LazyRow(
            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(SearchViewModel.Scope.entries) { s ->
                val selected = scope == s
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(16.dp))
                        .background(if (selected) BrandOrange else GlassFill)
                        .border(1.dp, if (selected) BrandOrange else GlassStroke, RoundedCornerShape(16.dp))
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) { vm.setScope(s) }
                        .padding(horizontal = 14.dp, vertical = 7.dp),
                ) {
                    Text(
                        text = s.label,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = if (selected) Color.White else TextSecondary,
                    )
                }
            }
        }

        // Results
        if (query.isBlank()) {
            // Popular trending
            Text(
                text = "Popular This Week",
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp),
            )
            if (popular.isEmpty()) {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.TopCenter,
                ) {
                    CircularProgressIndicator(
                        color = BrandOrange,
                        modifier = Modifier.padding(top = 40.dp).size(28.dp),
                    )
                }
            } else {
                LazyColumn(
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 20.dp, vertical = 4.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    items(popular) { result ->
                        SearchResultRow(
                            title = result.title,
                            posterUrl = result.posterUrl,
                            subtitle = "${result.year ?: ""} · ${result.platform?.name ?: "TV"}",
                            onClick = {
                                onOpenTitle(PendingTitleRoute(
                                    titleId = result.id.toString(),
                                    titleName = result.title,
                                    isTv = result.isTV,
                                ))
                            },
                        )
                    }
                }
            }
        } else if (isSearching && tmdbResults.isEmpty() && creatorResults.isEmpty()) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.TopCenter,
            ) {
                CircularProgressIndicator(
                    color = BrandOrange,
                    modifier = Modifier.padding(top = 40.dp).size(28.dp),
                )
            }
        } else if (tmdbResults.isEmpty() && creatorResults.isEmpty() && !isSearching) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = "No results for \"$query\"",
                    fontSize = 15.sp,
                    color = TextTertiary,
                )
            }
        } else {
            LazyColumn(
                contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                if (tmdbResults.isNotEmpty()) {
                    item {
                        Text(
                            text = "Shows & Movies",
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold,
                            color = TextPrimary,
                            modifier = Modifier.padding(horizontal = 20.dp),
                        )
                    }
                    items(tmdbResults) { result ->
                        SearchResultRow(
                            title = result.title,
                            posterUrl = result.posterUrl,
                            subtitle = "${result.year ?: ""} · ${if (result.isTV) "Series" else "Movie"}",
                            onClick = {
                                onOpenTitle(PendingTitleRoute(
                                    titleId = result.id.toString(),
                                    titleName = result.title,
                                    isTv = result.isTV,
                                ))
                            },
                        )
                    }
                }
                if (creatorResults.isNotEmpty()) {
                    item {
                        Spacer(Modifier.height(8.dp))
                        Text(
                            text = "Creators & Podcasts",
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold,
                            color = TextPrimary,
                            modifier = Modifier.padding(horizontal = 20.dp),
                        )
                    }
                    items(creatorResults) { creator ->
                        SearchResultRow(
                            title = creator.displayName,
                            posterUrl = creator.imageUrl,
                            subtitle = creator.sourceType.uppercase() + (creator.category?.let { " · $it" } ?: ""),
                            isCircle = true,
                            onClick = { onOpenCreator(creator.titleId) },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun SearchResultRow(
    title: String,
    posterUrl: String?,
    subtitle: String,
    isCircle: Boolean = false,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() }
            .glassCard(12)
            .padding(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (isCircle) {
            RemoteImage(
                url = posterUrl,
                contentDescription = title,
                modifier = Modifier.size(48.dp),
                cornerRadius = 24,
                placeholderText = title.take(2).uppercase(),
                placeholderFontSize = 16.sp,
            )
        } else {
            RemoteImage(
                url = posterUrl,
                contentDescription = title,
                modifier = Modifier
                    .width(44.dp)
                    .aspectRatio(0.67f),
                cornerRadius = 6,
                placeholderText = title.take(2).uppercase(),
                placeholderFontSize = 14.sp,
            )
        }
        Spacer(Modifier.width(12.dp))
        Column {
            Text(
                text = title,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = TextPrimary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = subtitle,
                fontSize = 12.sp,
                color = TextSecondary,
                maxLines = 1,
            )
        }
    }
}

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
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
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
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rork.guidestreamtvandroid.ui.ads.InlineAdSlot
import com.rork.guidestreamtvandroid.ui.components.RemoteImage
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.ui.components.glassCard
import com.rork.guidestreamtvandroid.ui.navigation.PendingTitleRoute
import com.rork.guidestreamtvandroid.ui.theme.BottomSafeSpacer
import com.rork.guidestreamtvandroid.ui.theme.AppleTVBlack
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.CrunchyrollOrange
import com.rork.guidestreamtvandroid.ui.theme.DisneyBlue
import com.rork.guidestreamtvandroid.ui.theme.GlassFill
import com.rork.guidestreamtvandroid.ui.theme.GlassStroke
import com.rork.guidestreamtvandroid.ui.theme.HboPurple
import com.rork.guidestreamtvandroid.ui.theme.HuluGreen
import com.rork.guidestreamtvandroid.ui.theme.KickGreen
import com.rork.guidestreamtvandroid.ui.theme.NetflixRed
import com.rork.guidestreamtvandroid.ui.theme.ParamountBlue
import com.rork.guidestreamtvandroid.ui.theme.PrimeBlue
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary
import com.rork.guidestreamtvandroid.ui.theme.TwitchPurple
import com.rork.guidestreamtvandroid.ui.theme.YouTubeRed

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
    val auth = AuthViewModel.get()
    val selectedServices by auth.selectedServices.collectAsStateWithLifecycle()
    val query by vm.query.collectAsStateWithLifecycle()
    val scope by vm.scope.collectAsStateWithLifecycle()
    val isSearching by vm.isSearching.collectAsStateWithLifecycle()
    val tmdbResults by vm.tmdbResults.collectAsStateWithLifecycle()
    val creatorResults by vm.creatorResults.collectAsStateWithLifecycle()
    val popular by vm.popular.collectAsStateWithLifecycle()

    LaunchedEffect(Unit) { vm.loadPopular() }

    Column(
        modifier = modifier.fillMaxSize().statusBarsPadding(),
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
                    .glassCard()
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
                val dismissedPopularAdSlots = remember { mutableStateMapOf<Int, Boolean>() }
                LazyVerticalGrid(
                    columns = GridCells.Fixed(3),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(
                        horizontal = 12.dp,
                        vertical = 4.dp,
                    ),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    popular.chunked(9).forEachIndexed { chunkIdx, chunk ->
                        items(chunk) { result ->
                            SearchPosterCard(
                                title = result.title,
                                posterUrl = result.posterUrl,
                                serviceName = result.platform?.name,
                                onClick = {
                                    onOpenTitle(PendingTitleRoute(
                                        titleId = result.id.toString(),
                                        titleName = result.title,
                                        isTv = result.isTV,
                                    ))
                                },
                            )
                        }
                        if (chunk.size >= 9) {
                            item(span = { GridItemSpan(maxLineSpan) }) {
                                InlineAdSlot(
                                    slotIndex = chunkIdx,
                                    selectedServices = selectedServices,
                                    adSource = "search_inline",
                                    sectionKey = "search_inline_ad",
                                    dismissed = dismissedPopularAdSlots,
                                )
                            }
                        }
                    }
                    item { BottomSafeSpacer(withTabBar = false) }
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
            val dismissedSearchAdSlots = remember { mutableStateMapOf<Int, Boolean>() }
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
                    tmdbResults.chunked(6).forEachIndexed { chunkIdx, chunk ->
                        itemsIndexed(chunk) { idx, result ->
                            SearchResultRow(
                                title = result.title,
                                posterUrl = result.posterUrl,
                                subtitle = "${result.year ?: ""} · ${if (result.isTV) "Series" else "Movie"}",
                                isLargePoster = true,
                                onClick = {
                                    onOpenTitle(PendingTitleRoute(
                                        titleId = result.id.toString(),
                                        titleName = result.title,
                                        isTv = result.isTV,
                                    ))
                                },
                            )
                        }
                        if (chunk.size >= 6) {
                            item {
                                InlineAdSlot(
                                    slotIndex = chunkIdx,
                                    selectedServices = selectedServices,
                                    adSource = "search_inline",
                                    sectionKey = "search_inline_ad",
                                    dismissed = dismissedSearchAdSlots,
                                )
                            }
                        }
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
                    creatorResults.chunked(6).forEachIndexed { chunkIdx, chunk ->
                        itemsIndexed(chunk) { idx, creator ->
                            SearchResultRow(
                                title = creator.displayName,
                                posterUrl = creator.imageUrl,
                                subtitle = creator.sourceType.uppercase() + (creator.category?.let { " · $it" } ?: ""),
                                isCircle = true,
                                onClick = { onOpenCreator(creator.titleId) },
                            )
                        }
                        if (chunk.size >= 6) {
                            item {
                                InlineAdSlot(
                                    slotIndex = chunkIdx,
                                    selectedServices = selectedServices,
                                    adSource = "search_inline",
                                    sectionKey = "search_inline_ad",
                                    dismissed = dismissedSearchAdSlots,
                                )
                            }
                        }
                    }
                }
                item { BottomSafeSpacer(withTabBar = false) }
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
    isLargePoster: Boolean = false,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = if (isLargePoster) 16.dp else 20.dp)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() }
            .glassCard()
            .padding(if (isLargePoster) 12.dp else 10.dp),
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
        } else if (isLargePoster) {
            RemoteImage(
                url = posterUrl,
                contentDescription = title,
                modifier = Modifier
                    .width(100.dp)
                    .aspectRatio(2f / 3f),
                cornerRadius = 10,
                placeholderText = title.take(2).uppercase(),
                placeholderFontSize = 18.sp,
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
        Spacer(Modifier.width(if (isLargePoster) 14.dp else 12.dp))
        Column(
            modifier = Modifier.weight(1f),
        ) {
            Text(
                text = title,
                fontSize = if (isLargePoster) 16.sp else 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = TextPrimary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = subtitle,
                fontSize = if (isLargePoster) 13.sp else 12.sp,
                color = TextSecondary,
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun SearchPosterCard(
    title: String,
    posterUrl: String?,
    serviceName: String?,
    onClick: () -> Unit,
) {
    Column(
        modifier = Modifier
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() }
            .fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(2f / 3f)
                .clip(RoundedCornerShape(10.dp))
                .glassCard(),
            contentAlignment = Alignment.Center,
        ) {
            RemoteImage(
                url = posterUrl,
                contentDescription = title,
                modifier = Modifier.fillMaxSize(),
                cornerRadius = 10,
                placeholderText = title.take(2).uppercase(),
                placeholderFontSize = 18.sp,
            )

            // Bottom gradient + title
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        Brush.verticalGradient(
                            listOf(Color.Transparent, Color.Black.copy(alpha = 0.9f)),
                            startY = 0.5f,
                            endY = Float.POSITIVE_INFINITY,
                        )
                    )
            )

            Text(
                text = title,
                fontSize = 9.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .padding(6.dp),
            )

            // Service badge
            serviceName?.let { name ->
                val short = serviceShort(name)
                val color = serviceColor(name)
                Text(
                    text = short,
                    fontSize = 8.sp,
                    fontWeight = FontWeight.Black,
                    color = Color.White,
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(5.dp)
                        .background(
                            color = color,
                            shape = RoundedCornerShape(4.dp),
                        )
                        .padding(horizontal = 5.dp, vertical = 2.dp),
                )
            }
        }
    }
}

private fun serviceShort(name: String): String {
    return when (name.uppercase()) {
        "NETFLIX" -> "NFLX"
        "HBO", "HBO MAX" -> "MAX"
        "APPLE TV+", "APPLE TV" -> "ATV+"
        "HULU" -> "HULU"
        "PRIME VIDEO", "AMAZON PRIME" -> "PRIME"
        "DISNEY+", "DISNEY PLUS" -> "D+"
        "PARAMOUNT+", "PARAMOUNT PLUS" -> "P+"
        "CRUNCHYROLL" -> "CR"
        "YOUTUBE" -> "YT"
        "TWITCH" -> "TTV"
        "KICK" -> "KICK"
        else -> name.take(4).uppercase()
    }
}

private fun serviceColor(name: String): Color {
    return when (name.uppercase()) {
        "NETFLIX" -> NetflixRed
        "HBO", "HBO MAX" -> HboPurple
        "APPLE TV+", "APPLE TV" -> AppleTVBlack
        "HULU" -> HuluGreen
        "PRIME VIDEO", "AMAZON PRIME" -> PrimeBlue
        "DISNEY+", "DISNEY PLUS" -> DisneyBlue
        "PARAMOUNT+", "PARAMOUNT PLUS" -> ParamountBlue
        "CRUNCHYROLL" -> CrunchyrollOrange
        "YOUTUBE" -> YouTubeRed
        "TWITCH" -> TwitchPurple
        "KICK" -> KickGreen
        else -> BrandOrange
    }
}

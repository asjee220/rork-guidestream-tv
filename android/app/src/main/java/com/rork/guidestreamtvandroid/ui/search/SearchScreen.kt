package com.rork.guidestreamtvandroid.ui.search

import androidx.compose.foundation.background
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
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
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
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rork.guidestreamtvandroid.ui.browse.BrowseResultsScreen
import com.rork.guidestreamtvandroid.ui.browse.GenreTileGrid
import com.rork.guidestreamtvandroid.ui.ads.InlineAdSlot
import com.rork.guidestreamtvandroid.ui.components.RemoteImage
import com.rork.guidestreamtvandroid.data.models.SourceKind
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.data.repository.StreamsViewModel
import com.rork.guidestreamtvandroid.data.repository.WatchIntentLogger
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

/** Local red for the live pill, matching SportsScreen.kt's LiveRed. */
private val LiveRed = Color(0xFFE50914)

/** Local purple for podcast source color, matching the iOS sourceColor mapping. */
private val PodcastPurple = Color(0xFF7C3AED)

/**
 * Search screen — mirrors iOS SearchView.swift.
 * Scope chips (All, Live, Shows, Creators, Podcasts), debounced query,
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

    val streamsVm = remember { StreamsViewModel.get() }
    val userStreams by streamsVm.userStreams.collectAsStateWithLifecycle()
    val followedIds = remember(userStreams) { userStreams.map { it.titleId }.toSet() }

    LaunchedEffect(Unit) { vm.loadPopular() }

    // Genre browse is pushed inside Search rather than through the app graph,
    // because Search itself is a full-screen overlay, not a nav destination.
    var browseGenreId by remember { mutableStateOf<String?>(null) }
    browseGenreId?.let { genreId ->
        BrowseResultsScreen(
            genreId = genreId,
            onBack = { browseGenreId = null },
            onOpenTitle = onOpenTitle,
            modifier = modifier,
        )
        return
    }

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
                        .clip(CircleShape)
                        .background(if (selected) BrandOrange else GlassFill)
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) { vm.setScope(s) }
                        .padding(horizontal = 14.dp, vertical = 8.dp),
                ) {
                    Text(
                        text = s.label,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = if (selected) Color.White else TextSecondary,
                    )
                }
            }
        }

        // Results
        if (query.isBlank()) {
            // Browse landing: genre tiles first, then the popular grid that
            // used to stand alone here. Both live inside the one lazy grid so
            // they scroll together — a fixed tile block above a scrolling grid
            // leaves almost no room for the grid on a phone.
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
                item(span = { GridItemSpan(maxLineSpan) }) {
                    Column {
                        SectionHeader(
                            text = "BROWSE BY GENRE",
                            topPadding = 12.dp,
                            bottomPadding = 10.dp,
                        )
                        GenreTileGrid(
                            onSelect = { genre -> browseGenreId = genre.id },
                            modifier = Modifier.padding(horizontal = 4.dp),
                        )
                        SectionHeader(
                            text = "POPULAR ON YOUR SERVICES",
                            topPadding = 22.dp,
                            bottomPadding = 10.dp,
                        )
                    }
                }

                if (popular.isEmpty()) {
                    item(span = { GridItemSpan(maxLineSpan) }) {
                        Box(
                            modifier = Modifier.fillMaxWidth(),
                            contentAlignment = Alignment.TopCenter,
                        ) {
                            CircularProgressIndicator(
                                color = BrandOrange,
                                modifier = Modifier.padding(top = 24.dp).size(28.dp),
                            )
                        }
                    }
                } else {
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
                }

                item(span = { GridItemSpan(maxLineSpan) }) { BottomSafeSpacer(withTabBar = false) }
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
            val liveCreators = remember(creatorResults) { creatorResults.filter { it.isLive } }
            val nonLiveCreators = remember(creatorResults) { creatorResults.filter { !it.isLive } }

            LazyColumn(
                contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                // Live creators section
                if (liveCreators.isNotEmpty()) {
                    item {
                        SectionHeader(
                            text = "LIVE NOW",
                            topPadding = 14.dp,
                            bottomPadding = 4.dp,
                        )
                    }
                    liveCreators.chunked(6).forEachIndexed { chunkIdx, chunk ->
                        itemsIndexed(chunk) { _, creator ->
                            CreatorSearchRow(
                                creator = creator,
                                isFollowed = followedIds.contains(creator.titleId),
                                onToggleFollow = { follow ->
                                    if (follow) {
                                        streamsVm.addToMyStreams(
                                            titleId = creator.titleId,
                                            title = creator.displayName,
                                            posterUrl = creator.imageUrl,
                                            platform = creator.sourceType,
                                        )
                                        WatchIntentLogger.get().log(
                                            WatchIntentLogger.IntentEventType.STREAM_ADDED,
                                            titleId = creator.titleId,
                                            platformId = creator.sourceType,
                                            metadata = mapOf("source" to "search"),
                                        )
                                    } else {
                                        streamsVm.removeFromMyStreams(creator.titleId)
                                        WatchIntentLogger.get().log(
                                            WatchIntentLogger.IntentEventType.STREAM_REMOVED,
                                            titleId = creator.titleId,
                                            platformId = creator.sourceType,
                                            metadata = mapOf("source" to "search"),
                                        )
                                    }
                                },
                                onClick = {
                                    WatchIntentLogger.get().log(
                                        WatchIntentLogger.IntentEventType.CARD_TAPPED,
                                        titleId = creator.titleId,
                                        platformId = creator.sourceType,
                                        metadata = mapOf(
                                            "section" to "search",
                                            "kind" to creator.sourceType,
                                        ),
                                    )
                                    onOpenCreator(creator.titleId)
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

                // Shows & movies section
                if (tmdbResults.isNotEmpty()) {
                    item {
                        SectionHeader(
                            text = "SHOWS & MOVIES",
                            topPadding = 14.dp,
                            bottomPadding = 4.dp,
                        )
                    }
                    tmdbResults.chunked(6).forEachIndexed { chunkIdx, chunk ->
                        itemsIndexed(chunk) { idx, result ->
                            SearchResultRow(
                                title = result.title,
                                query = query,
                                posterUrl = result.posterUrl,
                                year = result.year,
                                isTV = result.isTV,
                                onClick = {
                                    onOpenTitle(PendingTitleRoute(
                                        titleId = result.id.toString(),
                                        titleName = result.title,
                                        isTv = result.isTV,
                                    ))
                                },
                                showDivider = idx < chunk.lastIndex,
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

                // Non-live creators section
                if (nonLiveCreators.isNotEmpty()) {
                    item {
                        SectionHeader(
                            text = "CREATORS & PODCASTS",
                            topPadding = 14.dp,
                            bottomPadding = 4.dp,
                        )
                    }
                    nonLiveCreators.chunked(6).forEachIndexed { chunkIdx, chunk ->
                        itemsIndexed(chunk) { _, creator ->
                            CreatorSearchRow(
                                creator = creator,
                                isFollowed = followedIds.contains(creator.titleId),
                                onToggleFollow = { follow ->
                                    if (follow) {
                                        streamsVm.addToMyStreams(
                                            titleId = creator.titleId,
                                            title = creator.displayName,
                                            posterUrl = creator.imageUrl,
                                            platform = creator.sourceType,
                                        )
                                        WatchIntentLogger.get().log(
                                            WatchIntentLogger.IntentEventType.STREAM_ADDED,
                                            titleId = creator.titleId,
                                            platformId = creator.sourceType,
                                            metadata = mapOf("source" to "search"),
                                        )
                                    } else {
                                        streamsVm.removeFromMyStreams(creator.titleId)
                                        WatchIntentLogger.get().log(
                                            WatchIntentLogger.IntentEventType.STREAM_REMOVED,
                                            titleId = creator.titleId,
                                            platformId = creator.sourceType,
                                            metadata = mapOf("source" to "search"),
                                        )
                                    }
                                },
                                onClick = {
                                    WatchIntentLogger.get().log(
                                        WatchIntentLogger.IntentEventType.CARD_TAPPED,
                                        titleId = creator.titleId,
                                        platformId = creator.sourceType,
                                        metadata = mapOf(
                                            "section" to "search",
                                            "kind" to creator.sourceType,
                                        ),
                                    )
                                    onOpenCreator(creator.titleId)
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
                item { BottomSafeSpacer(withTabBar = false) }
            }
        }
    }
}

@Composable
private fun SectionHeader(
    text: String,
    topPadding: androidx.compose.ui.unit.Dp,
    bottomPadding: androidx.compose.ui.unit.Dp,
) {
    Text(
        text = text,
        fontSize = 11.sp,
        fontWeight = FontWeight.Bold,
        color = TextPrimary.copy(alpha = 0.40f),
        letterSpacing = 0.8.sp,
        modifier = Modifier.padding(
            start = 16.dp,
            end = 16.dp,
            top = topPadding,
            bottom = bottomPadding,
        ),
    )
}

@Composable
private fun SearchResultRow(
    title: String,
    query: String,
    posterUrl: String?,
    year: Int?,
    isTV: Boolean,
    onClick: () -> Unit,
    showDivider: Boolean,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() }
            .padding(horizontal = 16.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
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
            Spacer(Modifier.width(14.dp))
            Column(
                modifier = Modifier.weight(1f),
            ) {
                Text(
                    text = highlightedTitle(title, query),
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = if (isTV) "TV Series" else "Movie",
                    fontSize = 13.sp,
                    color = TextPrimary.copy(alpha = 0.40f),
                    maxLines = 1,
                )
                if (year != null) {
                    Text(
                        text = year.toString(),
                        fontSize = 12.sp,
                        color = TextPrimary.copy(alpha = 0.30f),
                        maxLines = 1,
                    )
                }
            }
            Icon(
                imageVector = Icons.Filled.ChevronRight,
                contentDescription = null,
                tint = TextPrimary.copy(alpha = 0.20f),
                modifier = Modifier.size(14.dp),
            )
        }
        if (showDivider) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 130.dp)
                    .height(1.dp)
                    .background(TextPrimary.copy(alpha = 0.06f)),
            )
        }
    }
}

private fun highlightedTitle(title: String, query: String): androidx.compose.ui.text.AnnotatedString {
    return try {
        val lowerTitle = title.lowercase()
        val lowerQuery = query.lowercase()
        val index = lowerTitle.indexOf(lowerQuery)
        if (query.isBlank() || index < 0) {
            buildAnnotatedString { withStyle(SpanStyle(color = TextPrimary)) { append(title) } }
        } else {
            buildAnnotatedString {
                withStyle(SpanStyle(color = TextPrimary)) { append(title.substring(0, index)) }
                withStyle(SpanStyle(color = BrandOrange)) {
                    append(title.substring(index, index + query.length))
                }
                withStyle(SpanStyle(color = TextPrimary)) {
                    append(title.substring(index + query.length))
                }
            }
        }
    } catch (_: Exception) {
        buildAnnotatedString { withStyle(SpanStyle(color = TextPrimary)) { append(title) } }
    }
}

@Composable
private fun CreatorSearchRow(
    creator: SearchViewModel.CreatorResult,
    isFollowed: Boolean,
    onToggleFollow: (Boolean) -> Unit,
    onClick: () -> Unit,
) {
    val sourceKind = SourceKind.from(creator.titleId)
    val sourceColor = sourceKindColor(sourceKind)

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() }
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .clip(CircleShape)
                .background(sourceColor.copy(alpha = 0.15f)),
            contentAlignment = Alignment.Center,
        ) {
            RemoteImage(
                url = creator.imageUrl,
                contentDescription = creator.displayName,
                modifier = Modifier.fillMaxSize(),
                cornerRadius = 22,
                placeholderText = creator.displayName.take(2).uppercase(),
                placeholderFontSize = 16.sp,
            )
        }
        Spacer(Modifier.width(12.dp))
        Column(
            modifier = Modifier.weight(1f),
        ) {
            Text(
                text = creator.displayName,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = TextPrimary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (creator.isLive) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(
                        modifier = Modifier
                            .size(6.dp)
                            .clip(CircleShape)
                            .background(LiveRed),
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(
                        text = "LIVE",
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Black,
                        color = LiveRed,
                    )
                }
            }
            Row(
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = sourceKind.displayLabel,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = sourceColor,
                    modifier = Modifier
                        .background(sourceColor.copy(alpha = 0.20f), RoundedCornerShape(4.dp))
                        .padding(horizontal = 5.dp, vertical = 2.dp),
                )
                creator.handle?.let { rawHandle ->
                    val handle = rawHandle.removePrefix("@")
                    Text(
                        text = "@$handle",
                        fontSize = 12.sp,
                        color = TextTertiary,
                        modifier = Modifier.padding(start = 8.dp),
                        maxLines = 1,
                    )
                }
            }
            if (creator.isLive && creator.streamTitle != null) {
                Text(
                    text = creator.streamTitle,
                    fontSize = 12.sp,
                    color = TextSecondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        Spacer(Modifier.width(8.dp))
        Box(
            modifier = Modifier
                .clip(CircleShape)
                .background(if (isFollowed) Color.White.copy(alpha = 0.10f) else BrandOrange)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) { onToggleFollow(!isFollowed) }
                .padding(horizontal = 14.dp, vertical = 7.dp),
        ) {
            Text(
                text = if (isFollowed) "Following" else "Follow",
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                color = if (isFollowed) TextSecondary else Color.White,
            )
        }
    }
}

private fun sourceKindColor(kind: SourceKind): Color {
    return when (kind) {
        SourceKind.YOUTUBE -> YouTubeRed
        SourceKind.TWITCH -> TwitchPurple
        SourceKind.KICK -> KickGreen
        SourceKind.TMDB -> BrandOrange
        SourceKind.PODCAST -> PodcastPurple
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
                .background(Color.White.copy(alpha = 0.06f)),
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

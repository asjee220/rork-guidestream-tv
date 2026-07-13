package com.rork.guidestreamtvandroid.ui.detail

import android.content.Intent
import android.net.Uri
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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rork.guidestreamtvandroid.data.models.DeepDiveCreator
import com.rork.guidestreamtvandroid.data.models.Platform
import com.rork.guidestreamtvandroid.data.models.StreamingCatalog
import com.rork.guidestreamtvandroid.data.remote.TMDBService
import com.rork.guidestreamtvandroid.data.remote.WatchmodeResolveService
import com.rork.guidestreamtvandroid.data.remote.WatchmodeSrc
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.data.repository.SocialViewModel
import com.rork.guidestreamtvandroid.data.repository.StreamsViewModel
import com.rork.guidestreamtvandroid.data.repository.WatchIntentLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import com.rork.guidestreamtvandroid.ui.comments.TitleCommentsSheet
import com.rork.guidestreamtvandroid.ui.components.RemoteImage
import com.rork.guidestreamtvandroid.ui.components.SocialCounterRow
import com.rork.guidestreamtvandroid.ui.components.glassCard
import com.rork.guidestreamtvandroid.ui.reels.ReelTab
import com.rork.guidestreamtvandroid.ui.reels.ReelsScreen
import com.rork.guidestreamtvandroid.ui.reels.TrailerItem
import com.rork.guidestreamtvandroid.ui.theme.BrandBlue
import com.rork.guidestreamtvandroid.ui.theme.BottomSafeSpacer
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.GlassFill
import com.rork.guidestreamtvandroid.ui.theme.GlassStroke
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.Navy
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary

/**
 * Show detail screen — mirrors iOS ShowDetailScreen.swift.
 * Backdrop hero, poster, title, meta, watch button, add/remove watchlist,
 * season/episode browser, overview.
 */
@Composable
fun ShowDetailScreen(
    titleId: String,
    titleName: String,
    isTV: Boolean = true,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val vm = ShowDetailViewModel.get()
    val streamsVm = StreamsViewModel.get()
    val context = LocalContext.current

    val detail by vm.detail.collectAsStateWithLifecycle()
    val season by vm.season.collectAsStateWithLifecycle()
    val platform by vm.platform.collectAsStateWithLifecycle()
    val topProvider by vm.topProvider.collectAsStateWithLifecycle()
    val trailerKey by vm.trailerKey.collectAsStateWithLifecycle()
    val isLoading by vm.isLoading.collectAsStateWithLifecycle()
    val errorMessage by vm.errorMessage.collectAsStateWithLifecycle()
    val currentSeason by vm.currentSeasonNumber.collectAsStateWithLifecycle()
    val userStreams by streamsVm.userStreams.collectAsStateWithLifecycle()
    val watchedIds by streamsVm.watchedIds.collectAsStateWithLifecycle()

    // Social (likes + comments) state.
    val socialVm = SocialViewModel.get()
    val likeCounts by socialVm.likeCounts.collectAsStateWithLifecycle()
    val likedByMe by socialVm.likedByMe.collectAsStateWithLifecycle()
    val commentCounts by socialVm.commentCounts.collectAsStateWithLifecycle()
    var showComments by remember { mutableStateOf(false) }
    androidx.compose.runtime.LaunchedEffect(titleId) { socialVm.refreshCounts(titleId) }

    val tmdbId = titleId.toIntOrNull()
    val isSaved = userStreams.any { it.titleId == titleId }
    val isWatched = watchedIds.contains(titleId)

    // Streaming-source switcher state. When the user is subscribed to two or
    // more of the title's services, tapping a chip makes it the active source
    // and the Watch button follows the selection.
    val authVm = AuthViewModel.get()
    val selectedServices by authVm.selectedServices.collectAsStateWithLifecycle()
    var usSources by remember { mutableStateOf<List<WatchmodeSrc>>(emptyList()) }
    var selectedSource by remember { mutableStateOf<WatchmodeSrc?>(null) }
    val isSourceSubscribed: (String) -> Boolean = { name ->
        val n = name.lowercase()
        StreamingCatalog.ordered(selectedServices).any { svc ->
            val s = svc.name.lowercase()
            n.contains(s) || s.contains(n)
        }
    }
    androidx.compose.runtime.LaunchedEffect(titleId) {
        val tid = titleId.toIntOrNull()
        if (tid != null) {
            val resolved = try {
                withContext(Dispatchers.IO) { WatchmodeResolveService.resolve(tid, isTV) }
            } catch (_: Exception) {
                emptyList()
            }
            usSources = resolved
            selectedSource = resolved.firstOrNull { isSourceSubscribed(it.name) } ?: resolved.firstOrNull()
        }
    }

    // Deep Dives + Trailers & Clips state
    val deepVm = DeepDivesViewModel.get()
    val creators by deepVm.creators.collectAsStateWithLifecycle()
    var trailerVideos by remember { mutableStateOf<List<TMDBService.TMDBVideo>>(emptyList()) }
    // Title-scoped Reels player state (holds the injected feed locally).
    var reelsFeed by remember { mutableStateOf<List<TrailerItem>?>(null) }
    var reelsStartIndex by remember { mutableStateOf(0) }

    // Load on first composition
    androidx.compose.runtime.LaunchedEffect(titleId) {
        vm.loadIfNeeded(titleId, isTV)
        val tid = titleId.toIntOrNull()
        trailerVideos = if (tid != null) {
            try { TMDBService.get().getTitleVideos(tid, isTV) } catch (_: Exception) { emptyList() }
        } else emptyList()
    }
    androidx.compose.runtime.LaunchedEffect(detail?.name) {
        val name = detail?.name
        val tid = titleId.toIntOrNull()
        if (!name.isNullOrBlank() && tid != null) {
            deepVm.load(tid, if (isTV) "tv" else "movie", name)
        }
    }

    Box(modifier = modifier.fillMaxSize()) {
        if (isLoading && detail == null) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center,
            ) {
                CircularProgressIndicator(color = BrandOrange)
            }
        } else {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState()),
            ) {
                // Hero backdrop
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(1.5f),
                ) {
                    val backdropUrl = detail?.backdropPath?.let {
                        "https://image.tmdb.org/t/p/w1280${if (it.startsWith("/")) it else "/$it"}"
                    }
                    RemoteImage(
                        url = backdropUrl,
                        contentDescription = titleName,
                        modifier = Modifier.fillMaxSize(),
                        cornerRadius = 0,
                        placeholderText = titleName.take(2).uppercase(),
                        placeholderFontSize = 32.sp,
                    )
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(
                                Brush.verticalGradient(
                                    colors = listOf(
                                        Color.Black.copy(alpha = 0.3f),
                                        Color.Transparent,
                                        Color.Black.copy(alpha = 0.6f),
                                    ),
                                ),
                            ),
                    )
                    // Back button
                    Box(
                        modifier = Modifier
                            .align(Alignment.TopStart)
                            .statusBarsPadding()
                            .padding(12.dp)
                            .size(40.dp)
                            .clip(CircleShape)
                            .background(Color.Black.copy(alpha = 0.5f))
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
                            modifier = Modifier.size(22.dp),
                        )
                    }
                    // Title + meta
                    Column(
                        modifier = Modifier
                            .align(Alignment.BottomStart)
                            .padding(16.dp),
                    ) {
                        Text(
                            text = detail?.name ?: titleName,
                            fontSize = 24.sp,
                            fontWeight = FontWeight.Bold,
                            color = TextPrimary,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Spacer(Modifier.height(4.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            if (detail?.voteAverage != null) {
                                Text(
                                    text = "★ ${String.format("%.1f", detail?.voteAverage)}",
                                    fontSize = 14.sp,
                                    color = BrandOrange,
                                    fontWeight = FontWeight.SemiBold,
                                )
                                Spacer(Modifier.width(12.dp))
                            }
                            if (detail?.numberOfSeasons != null) {
                                Text(
                                    text = "${detail?.numberOfSeasons} season${if (detail?.numberOfSeasons == 1) "" else "s"}",
                                    fontSize = 13.sp,
                                    color = TextSecondary,
                                )
                                Spacer(Modifier.width(12.dp))
                            }
                            if (platform != null) {
                                Text(
                                    text = platform!!.name,
                                    fontSize = 13.sp,
                                    color = platform!!.color,
                                    fontWeight = FontWeight.Bold,
                                )
                            }
                        }
                        Spacer(Modifier.height(10.dp))
                        SocialCounterRow(
                            isLiked = likedByMe.contains(titleId),
                            likeCount = likeCounts[titleId] ?: 0,
                            commentCount = commentCounts[titleId] ?: 0,
                            onLike = {
                                socialVm.toggleLike(
                                    titleId,
                                    mediaType = if (isTV) "tv" else "movie",
                                    tmdbId = titleId.toIntOrNull(),
                                )
                            },
                            onComment = {
                                showComments = true
                                WatchIntentLogger.get().log(
                                    WatchIntentLogger.IntentEventType.COMMENTS_OPENED,
                                    titleId = titleId,
                                    metadata = mapOf("source" to "show_detail"),
                                )
                            },
                        )
                    }
                }

                // Where to Watch — selectable streaming-source chips
                WhereToWatchRow(
                    sources = usSources,
                    selectedSource = selectedSource,
                    isSourceSubscribed = isSourceSubscribed,
                    onSelect = { selectedSource = it },
                    onOpen = { url ->
                        if (url.isNotBlank()) {
                            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                        }
                    },
                )

                // Action buttons
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    // Watch button
                    if (topProvider != null || usSources.isNotEmpty()) {
                        val watchLabel = "Watch on " + (
                            selectedSource?.name
                                ?: platform?.name
                                ?: topProvider?.providerName
                                ?: "Streaming"
                        )
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .clip(RoundedCornerShape(12.dp))
                                .background(BrandOrange)
                                .clickable(
                                    interactionSource = remember { MutableInteractionSource() },
                                    indication = null,
                                ) {
                                    val target = selectedSource?.webUrl?.takeIf { it.isNotBlank() }
                                        ?: "https://www.themoviedb.org/${if (isTV) "tv" else "movie"}/$tmdbId/watch"
                                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(target)))
                                }
                                .padding(vertical = 14.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(
                                    imageVector = Icons.Filled.PlayArrow,
                                    contentDescription = null,
                                    tint = Color.White,
                                    modifier = Modifier.size(20.dp),
                                )
                                Spacer(Modifier.width(6.dp))
                                Text(
                                    text = watchLabel,
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = Color.White,
                                )
                            }
                        }
                    }
                    // Add/Remove watchlist
                    Box(
                        modifier = Modifier
                            .size(50.dp)
                            .clip(RoundedCornerShape(12.dp))
                            .background(GlassFill)
                            .border(1.dp, GlassStroke, RoundedCornerShape(12.dp))
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                            ) {
                                if (isSaved) {
                                    streamsVm.removeFromMyStreams(titleId)
                                    WatchIntentLogger.get().log(
                                        WatchIntentLogger.IntentEventType.WATCHLIST_REMOVED,
                                        titleId = titleId,
                                    )
                                } else {
                                    streamsVm.addToMyStreams(
                                        titleId = titleId,
                                        title = detail?.name ?: titleName,
                                        posterUrl = detail?.posterPath?.let {
                                            "https://image.tmdb.org/t/p/w342${if (it.startsWith("/")) it else "/$it"}"
                                        },
                                        platform = platform?.name,
                                    )
                                    WatchIntentLogger.get().log(
                                        WatchIntentLogger.IntentEventType.WATCHLIST_ADDED,
                                        titleId = titleId,
                                        platformId = platform?.name?.lowercase(),
                                    )
                                }
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            imageVector = if (isSaved) Icons.Filled.Check else Icons.Filled.Add,
                            contentDescription = if (isSaved) "In watchlist" else "Add to watchlist",
                            tint = if (isSaved) BrandOrange else TextPrimary,
                            modifier = Modifier.size(22.dp),
                        )
                    }
                    // Watched toggle
                    Box(
                        modifier = Modifier
                            .size(50.dp)
                            .clip(RoundedCornerShape(12.dp))
                            .background(GlassFill)
                            .border(1.dp, GlassStroke, RoundedCornerShape(12.dp))
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                            ) {
                                streamsVm.toggleWatched(
                                    titleId = titleId,
                                    titleName = detail?.name ?: titleName,
                                    mediaType = if (isTV) "tv" else "movie",
                                    tmdbId = tmdbId,
                                )
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            imageVector = Icons.Filled.Visibility,
                            contentDescription = "Watched",
                            tint = if (isWatched) BrandBlue else TextPrimary,
                            modifier = Modifier.size(22.dp),
                        )
                    }
                    // Share
                    Box(
                        modifier = Modifier
                            .size(50.dp)
                            .clip(RoundedCornerShape(12.dp))
                            .background(GlassFill)
                            .border(1.dp, GlassStroke, RoundedCornerShape(12.dp))
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                            ) {
                                val shareIntent = Intent(Intent.ACTION_SEND).apply {
                                    type = "text/plain"
                                    putExtra(Intent.EXTRA_TEXT, "https://www.themoviedb.org/${if (isTV) "tv" else "movie"}/$tmdbId")
                                }
                                context.startActivity(Intent.createChooser(shareIntent, "Share"))
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            imageVector = Icons.Filled.Share,
                            contentDescription = "Share",
                            tint = TextPrimary,
                            modifier = Modifier.size(20.dp),
                        )
                    }
                }

                // Trailers & Clips
                TitleTrailersRow(
                    videos = trailerVideos,
                    onTrailerTap = { idx ->
                        val tid = titleId.toIntOrNull() ?: 0
                        val posterU = detail?.posterPath?.let {
                            "https://image.tmdb.org/t/p/w342${if (it.startsWith("/")) it else "/$it"}"
                        }
                        val backdropU = detail?.backdropPath?.let {
                            "https://image.tmdb.org/t/p/w1280${if (it.startsWith("/")) it else "/$it"}"
                        }
                        val genreLabel = detail?.genres?.firstOrNull()?.name ?: if (isTV) "Series" else "Movie"
                        val plat = platform
                        reelsStartIndex = idx
                        reelsFeed = trailerVideos.map { v ->
                            TrailerItem(
                                id = v.key,
                                tmdbId = tid,
                                showName = detail?.name ?: titleName,
                                synopsis = detail?.overview ?: "",
                                genre = genreLabel,
                                runtime = "",
                                platformId = plat?.name?.lowercase() ?: "",
                                platformName = plat?.name ?: "TRAILER",
                                platformColor = plat?.color ?: BrandOrange,
                                backdropUrl = backdropU,
                                posterUrl = posterU,
                                trailerKey = v.key,
                                thumbnailUrl = "https://img.youtube.com/vi/${v.key}/hqdefault.jpg",
                                voteAverage = detail?.voteAverage ?: 0.0,
                                tab = ReelTab.FOR_YOU,
                                isTV = isTV,
                                videoType = v.type,
                                videoName = v.name,
                            )
                        }
                    },
                )

                // Deep Dives
                DeepDivesSection(
                    creators = creators,
                    onOpenChannel = { url ->
                        if (url.isNotBlank()) {
                            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                        }
                    },
                )

                // Overview
                if (!detail?.overview.isNullOrBlank()) {
                    Text(
                        text = "Overview",
                        fontSize = 17.sp,
                        fontWeight = FontWeight.Bold,
                        color = TextPrimary,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                    Text(
                        text = detail?.overview ?: "",
                        fontSize = 14.sp,
                        color = TextSecondary,
                        lineHeight = 20.sp,
                        modifier = Modifier.padding(horizontal = 16.dp),
                    )
                }

                // Seasons selector + episodes
                if (isTV && detail?.numberOfSeasons != null && detail!!.numberOfSeasons!! > 0) {
                    Spacer(Modifier.height(20.dp))
                    Text(
                        text = "Episodes",
                        fontSize = 17.sp,
                        fontWeight = FontWeight.Bold,
                        color = TextPrimary,
                        modifier = Modifier.padding(horizontal = 16.dp),
                    )
                    // Season chips
                    LazyRow(
                        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        items((1..detail!!.numberOfSeasons!!).toList()) { s ->
                            val selected = currentSeason == s
                            Box(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(16.dp))
                                    .background(if (selected) BrandOrange else GlassFill)
                                    .border(1.dp, if (selected) BrandOrange else GlassStroke, RoundedCornerShape(16.dp))
                                    .clickable(
                                        interactionSource = remember { MutableInteractionSource() },
                                        indication = null,
                                    ) { vm.loadSeason(s) }
                                    .padding(horizontal = 14.dp, vertical = 7.dp),
                            ) {
                                Text(
                                    text = "Season $s",
                                    fontSize = 13.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = if (selected) Color.White else TextSecondary,
                                )
                            }
                        }
                    }
                    // Episode list
                    season?.episodes?.forEach { ep ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 4.dp)
                                .glassCard(10)
                                .padding(10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(48.dp)
                                    .clip(RoundedCornerShape(8.dp))
                                    .background(GlassFill),
                                contentAlignment = Alignment.Center,
                            ) {
                                Text(
                                    text = "${ep.episodeNumber}",
                                    fontSize = 18.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = BrandOrange,
                                )
                            }
                            Spacer(Modifier.width(10.dp))
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = ep.name ?: "Episode ${ep.episodeNumber}",
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = TextPrimary,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                                if (ep.airDate != null) {
                                    Text(
                                        text = ep.airDate ?: "",
                                        fontSize = 12.sp,
                                        color = TextTertiary,
                                    )
                                }
                            }
                        }
                    }
                }

                if (errorMessage != null) {
                    Text(
                        text = errorMessage ?: "",
                        fontSize = 13.sp,
                        color = BrandOrange,
                        modifier = Modifier.padding(16.dp),
                    )
                }

                BottomSafeSpacer(withTabBar = false)
            }
        }

        // Title-scoped Reels player (Trailers & Clips) — full-screen overlay
        // holding the injected feed in local state (no nav-graph serialization).
        reelsFeed?.let { feed ->
            // System back closes the player instead of leaving the detail screen.
            androidx.activity.compose.BackHandler { reelsFeed = null }
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Navy)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { },
            ) {
                ReelsScreen(
                    onDismiss = { reelsFeed = null },
                    injectedReels = feed,
                    injectedStartIndex = reelsStartIndex,
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }

        if (showComments) {
            TitleCommentsSheet(
                titleId = titleId,
                title = detail?.name ?: titleName,
                subtitle = null,
                posterUrl = detail?.posterPath?.let {
                    "https://image.tmdb.org/t/p/w342${if (it.startsWith("/")) it else "/$it"}"
                },
                onDismiss = { showComments = false },
            )
        }
    }
}

/**
 * "Where to Watch" chip row. Renders one chip per US streaming source. When the
 * user is subscribed to two or more of the title's services, tapping a
 * subscribed chip makes it the active source (Watch button follows); every
 * other tap opens the source's web URL directly. Hidden when there are no
 * sources.
 */
@Composable
private fun WhereToWatchRow(
    sources: List<WatchmodeSrc>,
    selectedSource: WatchmodeSrc?,
    isSourceSubscribed: (String) -> Boolean,
    onSelect: (WatchmodeSrc) -> Unit,
    onOpen: (String) -> Unit,
) {
    if (sources.isEmpty()) return
    val subscribedCount = sources.count { isSourceSubscribed(it.name) }
    Spacer(Modifier.height(8.dp))
    Text(
        text = "Where to Watch",
        fontSize = 17.sp,
        fontWeight = FontWeight.Bold,
        color = TextPrimary,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
    )
    LazyRow(
        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        items(sources) { source ->
            val subscribed = isSourceSubscribed(source.name)
            val selected = selectedSource?.sourceId == source.sourceId
            val dotColor = Platform.from(source.name)?.color ?: BrandOrange
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(12.dp))
                    .background(dotColor.copy(alpha = if (subscribed) 0.28f else 0.18f))
                    .border(
                        width = if (selected) 2.dp else 1.dp,
                        color = if (selected) dotColor else dotColor.copy(alpha = if (subscribed) 0.70f else 0.45f),
                        shape = RoundedCornerShape(12.dp),
                    )
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) {
                        if (subscribedCount >= 2 && subscribed) {
                            onSelect(source)
                        } else {
                            source.webUrl?.let { onOpen(it) }
                        }
                    }
                    .padding(horizontal = 14.dp, vertical = 10.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = Modifier
                            .size(8.dp)
                            .clip(CircleShape)
                            .background(dotColor),
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        text = source.name,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = TextPrimary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    if (subscribed) {
                        Spacer(Modifier.width(8.dp))
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(4.dp))
                                .background(Color(0xFF34C759).copy(alpha = 0.85f))
                                .padding(horizontal = 6.dp, vertical = 2.dp),
                        ) {
                            Text(
                                text = "Subscribed",
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Black,
                                color = Color.White,
                            )
                        }
                    }
                    if (selected) {
                        Spacer(Modifier.width(6.dp))
                        Box(
                            modifier = Modifier
                                .size(16.dp)
                                .clip(CircleShape)
                                .background(BrandOrange),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(
                                imageVector = Icons.Filled.Check,
                                contentDescription = "Selected",
                                tint = Color.White,
                                modifier = Modifier.size(10.dp),
                            )
                        }
                    }
                }
            }
        }
    }
}

/**
 * Trailers & Clips row for the title detail screen. Up to 6 2:3 poster cards
 * showing YouTube thumbnails; tapping opens the title-scoped Reels player.
 * Hidden entirely when there are no qualifying videos.
 */
@Composable
private fun TitleTrailersRow(
    videos: List<TMDBService.TMDBVideo>,
    onTrailerTap: (Int) -> Unit,
) {
    if (videos.isEmpty()) return
    Spacer(Modifier.height(8.dp))
    Text(
        text = "Trailers & Clips",
        fontSize = 17.sp,
        fontWeight = FontWeight.Bold,
        color = TextPrimary,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
    )
    LazyRow(
        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        itemsIndexed(videos.take(6)) { idx, v ->
            Box(
                modifier = Modifier
                    .width(120.dp)
                    .aspectRatio(2f / 3f)
                    .clip(RoundedCornerShape(12.dp))
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onTrailerTap(idx) },
            ) {
                RemoteImage(
                    url = "https://img.youtube.com/vi/${v.key}/hqdefault.jpg",
                    contentDescription = v.name,
                    modifier = Modifier.fillMaxSize(),
                    cornerRadius = 12,
                )
                Icon(
                    imageVector = Icons.Filled.PlayArrow,
                    contentDescription = "Play",
                    tint = Color.White,
                    modifier = Modifier
                        .align(Alignment.Center)
                        .size(34.dp),
                )
                if (!v.type.isNullOrBlank()) {
                    Box(
                        modifier = Modifier
                            .align(Alignment.TopStart)
                            .padding(6.dp)
                            .clip(RoundedCornerShape(5.dp))
                            .background(Color.Black.copy(alpha = 0.6f))
                            .padding(horizontal = 6.dp, vertical = 3.dp),
                    ) {
                        Text(
                            text = v.type!!,
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White,
                        )
                    }
                }
            }
        }
    }
}

/**
 * Deep Dives section — up to 4 YouTube creator channels that publish analysis
 * content about the title. Hidden entirely when the list is empty.
 */
@Composable
private fun DeepDivesSection(
    creators: List<DeepDiveCreator>,
    onOpenChannel: (String) -> Unit,
) {
    if (creators.isEmpty()) return
    Spacer(Modifier.height(16.dp))
    Text(
        text = "Deep Dives",
        fontSize = 17.sp,
        fontWeight = FontWeight.Bold,
        color = TextPrimary,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
    )
    LazyRow(
        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        items(creators.take(4)) { creator ->
            Column(
                modifier = Modifier
                    .width(150.dp)
                    .glassCard(10)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onOpenChannel(creator.channelUrl) }
                    .padding(10.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                RemoteImage(
                    url = creator.avatarUrl,
                    contentDescription = creator.name,
                    modifier = Modifier.size(48.dp),
                    cornerRadius = 24,
                    placeholderText = creator.name.take(1).uppercase(),
                    placeholderFontSize = 18.sp,
                )
                Spacer(Modifier.height(8.dp))
                Text(
                    text = creator.name,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = TextPrimary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                val label = creator.subscriberLabel
                if (label != null) {
                    Spacer(Modifier.height(2.dp))
                    Text(
                        text = "$label subscribers",
                        fontSize = 10.sp,
                        color = TextSecondary,
                        maxLines = 1,
                    )
                }
            }
        }
    }
}

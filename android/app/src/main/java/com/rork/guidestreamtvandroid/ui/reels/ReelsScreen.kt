package com.rork.guidestreamtvandroid.ui.reels

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
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.pager.VerticalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VolumeOff
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
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
import com.rork.guidestreamtvandroid.data.models.Platform
import com.rork.guidestreamtvandroid.data.remote.WatchmodeResolveService
import com.rork.guidestreamtvandroid.data.remote.WatchmodeSrc
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.data.repository.StreamsViewModel
import com.rork.guidestreamtvandroid.data.repository.WatchIntentLogger
import com.rork.guidestreamtvandroid.ui.components.RemoteImage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import com.rork.guidestreamtvandroid.ui.theme.BrandBlue
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.systemBottomInset
import com.rork.guidestreamtvandroid.ui.theme.GlassFill
import com.rork.guidestreamtvandroid.ui.theme.GlassStroke
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary

/**
 * Reels screen — vertical paging trailer feed.
 * Mirrors iOS ReelsScreen.swift: category pills, vertical pager of YouTube
 * trailer thumbnails, center play/pause, mute toggle, right rail (title, add
 * to watchlist, share), swipe-to-dismiss chevron, WatchIntentLogger events.
 *
 * Uses a VerticalPager with backdrop thumbnails (the cloud emulator has no
 * YouTube IFrame player; tapping "Play" opens the YouTube app or web URL).
 */
@Composable
fun ReelsScreen(
    onDismiss: () -> Unit = {},
    injectedReels: List<TrailerItem>? = null,
    injectedStartIndex: Int = 0,
    modifier: Modifier = Modifier,
) {
    // Title-scoped mode (Trailers & Clips): render the injected feed only,
    // never touching the shared ReelsViewModel or its global loader.
    if (injectedReels != null) {
        InjectedReelsScreen(
            reels = injectedReels,
            startIndex = injectedStartIndex,
            onDismiss = onDismiss,
            modifier = modifier,
        )
        return
    }
    val vm = ReelsViewModel.get()
    val streamsVm = StreamsViewModel.get()
    val context = LocalContext.current

    val trailers by vm.trailers.collectAsStateWithLifecycle()
    val isLoading by vm.isLoading.collectAsStateWithLifecycle()
    val currentTab by vm.currentTab.collectAsStateWithLifecycle()
    val userStreams by streamsVm.userStreams.collectAsStateWithLifecycle()
    val watchedIds by streamsVm.watchedIds.collectAsStateWithLifecycle()

    // Tab-filtered trailers
    val filteredTrailers = remember(trailers, currentTab) {
        vm.trailersForTab(currentTab)
    }

    var isPlaying by remember { mutableStateOf(true) }
    var isMuted by remember { mutableStateOf(true) }

    // Load trailers on first composition
    LaunchedEffect(Unit) {
        vm.loadTrailers()
    }

    Box(modifier = modifier.fillMaxSize().background(Color.Black)) {
        if (isLoading && trailers.isEmpty()) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center,
            ) {
                CircularProgressIndicator(color = BrandOrange)
            }
        } else if (filteredTrailers.isEmpty()) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center,
            ) {
                Text("No trailers available", color = TextTertiary, fontSize = 15.sp)
            }
        } else {
            // Key the pager to the current tab so switching categories fully
            // rebuilds the pager (fresh page 0 + fresh content) instead of
            // keeping the previous tab's cached pages.
            key(currentTab) {
            val pagerState = rememberPagerState(pageCount = { filteredTrailers.size })

            // Reset autoplay on page change
            LaunchedEffect(pagerState.currentPage) {
                isPlaying = true
                val item = filteredTrailers.getOrNull(pagerState.currentPage) ?: return@LaunchedEffect
                vm.setCurrentIndex(pagerState.currentPage)
                WatchIntentLogger.get().log(
                    WatchIntentLogger.IntentEventType.TRAILER_VIEWED,
                    titleId = item.tmdbId.toString(),
                    platformId = item.platformId,
                    metadata = mapOf("section" to "reels", "tab" to item.tab.key),
                )
            }

            VerticalPager(
                state = pagerState,
                modifier = Modifier.fillMaxSize(),
            ) { page ->
                val reel = filteredTrailers[page]
                val isCurrent = page == pagerState.currentPage
                val isSaved = userStreams.any { it.titleId == reel.tmdbId.toString() }
                val isWatched = watchedIds.contains(reel.tmdbId.toString())

                ReelView(
                    reel = reel,
                    isCurrent = isCurrent,
                    isPlaying = isPlaying,
                    isMuted = isMuted,
                    isSaved = isSaved,
                    isWatched = isWatched,
                    onTogglePlay = {
                        isPlaying = !isPlaying
                        WatchIntentLogger.get().log(
                            WatchIntentLogger.IntentEventType.TRAILER_WATCHED,
                            titleId = reel.tmdbId.toString(),
                            watchDurationSeconds = if (isPlaying) 0.0 else 1.0,
                        )
                    },
                    onToggleMute = {
                        isMuted = !isMuted
                        WatchIntentLogger.get().log(
                            WatchIntentLogger.IntentEventType.MUTE_TOGGLED,
                            titleId = reel.tmdbId.toString(),
                        )
                    },
                    onPlayYoutube = {
                        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(reel.youtubeUrl)))
                        WatchIntentLogger.get().log(
                            WatchIntentLogger.IntentEventType.TRAILER_WATCHED,
                            titleId = reel.tmdbId.toString(),
                            platformId = "youtube",
                        )
                    },
                    onToggleSave = {
                        if (isSaved) {
                            streamsVm.removeFromMyStreams(reel.tmdbId.toString())
                            WatchIntentLogger.get().log(
                                WatchIntentLogger.IntentEventType.WATCHLIST_REMOVED,
                                titleId = reel.tmdbId.toString(),
                            )
                        } else {
                            streamsVm.addToMyStreams(
                                titleId = reel.tmdbId.toString(),
                                title = reel.showName,
                                posterUrl = reel.posterUrl,
                                platform = reel.platformName,
                            )
                            WatchIntentLogger.get().log(
                                WatchIntentLogger.IntentEventType.WATCHLIST_ADDED,
                                titleId = reel.tmdbId.toString(),
                                platformId = reel.platformId,
                            )
                        }
                    },
                    onToggleWatched = {
                        streamsVm.toggleWatched(
                            titleId = reel.tmdbId.toString(),
                            titleName = reel.showName,
                            mediaType = if (reel.isTV) "tv" else "movie",
                            tmdbId = reel.tmdbId,
                        )
                    },
                    onShare = {
                        val shareIntent = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, reel.youtubeUrl)
                        }
                        context.startActivity(Intent.createChooser(shareIntent, "Share trailer"))
                    },
                )
            }
            }

            // Top overlay: dismiss chevron + category pills
            Row(
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .fillMaxWidth()
                    .statusBarsPadding()
                    .padding(horizontal = 12.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // Dismiss chevron
                Box(
                    modifier = Modifier
                        .size(40.dp)
                        .clip(CircleShape)
                        .background(Color.Black.copy(alpha = 0.4f))
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) { onDismiss() },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.Filled.KeyboardArrowDown,
                        contentDescription = "Dismiss",
                        tint = TextPrimary,
                        modifier = Modifier.size(26.dp),
                    )
                }
                // Category pills — plain tappable buttons, left-aligned
                Row(
                    modifier = Modifier.padding(start = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(13.dp),
                ) {
                    ReelTab.entries.forEach { tab ->
                        val isActive = currentTab == tab
                        Text(
                            text = tab.label,
                            fontSize = 14.sp,
                            fontWeight = if (isActive) FontWeight.Bold else FontWeight.Normal,
                            color = if (isActive) TextPrimary else TextTertiary,
                            modifier = Modifier.clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                            ) {
                                vm.setTab(tab)
                                WatchIntentLogger.get().log(
                                    WatchIntentLogger.IntentEventType.CARD_TAPPED,
                                    metadata = mapOf("section" to "reels_tab", "tab" to tab.key),
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
private fun ReelView(
    reel: TrailerItem,
    isCurrent: Boolean,
    isPlaying: Boolean,
    isMuted: Boolean,
    isSaved: Boolean,
    isWatched: Boolean,
    onTogglePlay: () -> Unit,
    onToggleMute: () -> Unit,
    onPlayYoutube: () -> Unit,
    onToggleSave: () -> Unit,
    onToggleWatched: () -> Unit,
    onShare: () -> Unit,
    injected: Boolean = false,
    sources: List<WatchmodeSrc>? = null,
    onOpenSource: (WatchmodeSrc) -> Unit = {},
) {
    Box(modifier = Modifier.fillMaxSize()) {
        // Backdrop image
        RemoteImage(
            url = reel.backdropUrl ?: reel.thumbnailUrl ?: reel.posterUrl,
            contentDescription = reel.showName,
            modifier = Modifier.fillMaxSize(),
            cornerRadius = 0,
            placeholderText = reel.showName.take(2).uppercase(),
            placeholderFontSize = 36.sp,
        )

        // Dark gradient for readability
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        colors = listOf(
                            Color.Black.copy(alpha = 0.35f),
                            Color.Transparent,
                            Color.Black.copy(alpha = 0.25f),
                            Color.Black.copy(alpha = 0.75f),
                        ),
                    ),
                ),
        )

        // Center play/pause button (only when current and paused or controls shown)
        if (isCurrent && !isPlaying) {
            Box(
                modifier = Modifier
                    .align(Alignment.Center)
                    .size(68.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.5f))
                    .border(2.dp, Color.White.copy(alpha = 0.4f), CircleShape)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onTogglePlay() },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Filled.PlayArrow,
                    contentDescription = "Play",
                    tint = Color.White,
                    modifier = Modifier.size(36.dp),
                )
            }
        }

        // Mute button — repositions when paused (centered above play button)
        if (isCurrent) {
            val muteY: androidx.compose.ui.unit.Dp
            val muteX: androidx.compose.ui.unit.Dp
            if (!isPlaying) {
                // Centered above the 68pt play button with 16dp gap
                muteY = androidx.compose.ui.unit.Dp(34f + 16f + 20f) // half play + gap + half mute (approx)
                muteX = 0.dp
            } else {
                muteY = 0.dp
                muteX = 0.dp
            }
            Box(
                modifier = Modifier
                    .align(if (!isPlaying) Alignment.Center else Alignment.BottomStart)
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.45f))
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onToggleMute() }
                    .padding(0.dp),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = if (isMuted) Icons.Filled.VolumeOff else Icons.Filled.VolumeUp,
                    contentDescription = if (isMuted) "Unmute" else "Mute",
                    tint = Color.White,
                    modifier = Modifier.size(22.dp),
                )
            }
        }

        // Right rail: title, add to watchlist, share, play on YouTube
        Column(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(end = 12.dp, bottom = 24.dp + systemBottomInset()),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            // Add to watchlist
            RailButton(
                icon = if (isSaved) Icons.Filled.Check else Icons.Filled.Add,
                label = if (isSaved) "Saved" else "Save",
                tint = if (isSaved) BrandOrange else TextPrimary,
                onClick = onToggleSave,
            )
            // Watched
            RailButton(
                icon = Icons.Filled.Visibility,
                label = "Watched",
                tint = if (isWatched) BrandBlue else TextPrimary,
                onClick = onToggleWatched,
            )
            // Share
            RailButton(
                icon = Icons.Filled.Share,
                label = "Share",
                tint = TextPrimary,
                onClick = onShare,
            )
            // Play on YouTube
            RailButton(
                icon = Icons.Filled.PlayArrow,
                label = "Play",
                tint = BrandOrange,
                onClick = onPlayYoutube,
            )
        }

        // Bottom-left: title + meta
        Column(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(start = 16.dp, bottom = 24.dp + systemBottomInset())
                .fillMaxWidth(if (injected) 0.72f else 0.65f),
        ) {
            // Platform badge + optional video-type chip (title-scoped mode)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(6.dp))
                        .background(reel.platformColor)
                        .padding(horizontal = 8.dp, vertical = 3.dp),
                ) {
                    Text(
                        text = reel.platformName,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                    )
                }
                if (injected && !reel.videoType.isNullOrBlank()) {
                    Spacer(Modifier.width(6.dp))
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .background(Color.White.copy(alpha = 0.12f))
                            .padding(horizontal = 8.dp, vertical = 3.dp),
                    ) {
                        Text(
                            text = reel.videoType!!,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White,
                        )
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
            Text(
                text = reel.showName,
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.height(4.dp))
            Text(
                text = "★ ${String.format("%.1f", reel.voteAverage)}  ·  ${reel.genre}",
                fontSize = 13.sp,
                color = TextSecondary,
            )
            if (reel.synopsis.isNotBlank()) {
                Spacer(Modifier.height(6.dp))
                Text(
                    text = reel.synopsis,
                    fontSize = 12.sp,
                    color = TextTertiary,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            if (injected) {
                Spacer(Modifier.height(12.dp))
                WatchNowSwitcher(sources = sources, onOpenSource = onOpenSource)
            }
        }
    }
}

/**
 * Title-scoped Reels player (Trailers & Clips). Renders the injected feed in
 * the same vertical pager starting at [startIndex], with the embedded
 * streaming-service switcher and no category pills. Never touches the shared
 * ReelsViewModel.
 */
@Composable
private fun InjectedReelsScreen(
    reels: List<TrailerItem>,
    startIndex: Int,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val streamsVm = StreamsViewModel.get()
    val userStreams by streamsVm.userStreams.collectAsStateWithLifecycle()
    val watchedIds by streamsVm.watchedIds.collectAsStateWithLifecycle()

    var isPlaying by remember { mutableStateOf(true) }
    var isMuted by remember { mutableStateOf(true) }

    // All injected reels share the same title, so resolve sources once.
    val sharedTmdbId = remember(reels) { reels.firstOrNull()?.tmdbId ?: 0 }
    val sharedIsTV = remember(reels) { reels.firstOrNull()?.isTV ?: true }
    // null = still loading; empty = loaded but nothing streamable.
    var sources by remember { mutableStateOf<List<WatchmodeSrc>?>(null) }

    LaunchedEffect(sharedTmdbId) {
        if (sharedTmdbId <= 0) {
            sources = emptyList()
            return@LaunchedEffect
        }
        val resolved = try {
            withContext(Dispatchers.IO) { WatchmodeResolveService.resolve(sharedTmdbId, sharedIsTV) }
        } catch (_: Exception) {
            emptyList()
        }
        val auth = AuthViewModel.get()
        val subscribed = resolved.filter { auth.subscribesToService(it.name) }
        val others = resolved.filter { !auth.subscribesToService(it.name) }
        sources = subscribed + others
    }

    Box(modifier = modifier.fillMaxSize().background(Color.Black)) {
        if (reels.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("No trailers available", color = TextTertiary, fontSize = 15.sp)
            }
        } else {
            val pagerState = rememberPagerState(
                initialPage = startIndex.coerceIn(0, reels.size - 1),
                pageCount = { reels.size },
            )
            LaunchedEffect(pagerState.currentPage) {
                isPlaying = true
                val item = reels.getOrNull(pagerState.currentPage) ?: return@LaunchedEffect
                WatchIntentLogger.get().log(
                    WatchIntentLogger.IntentEventType.TRAILER_VIEWED,
                    titleId = item.tmdbId.toString(),
                    platformId = item.platformId,
                    metadata = mapOf(
                        "section" to "title_trailers",
                        "video_type" to (item.videoType ?: ""),
                    ),
                )
            }
            VerticalPager(state = pagerState, modifier = Modifier.fillMaxSize()) { page ->
                val reel = reels[page]
                val isCurrent = page == pagerState.currentPage
                val isSaved = userStreams.any { it.titleId == reel.tmdbId.toString() }
                val isWatched = watchedIds.contains(reel.tmdbId.toString())
                ReelView(
                    reel = reel,
                    isCurrent = isCurrent,
                    isPlaying = isPlaying,
                    isMuted = isMuted,
                    isSaved = isSaved,
                    isWatched = isWatched,
                    onTogglePlay = { isPlaying = !isPlaying },
                    onToggleMute = { isMuted = !isMuted },
                    onPlayYoutube = {
                        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(reel.youtubeUrl)))
                    },
                    onToggleSave = {
                        if (isSaved) {
                            streamsVm.removeFromMyStreams(reel.tmdbId.toString())
                            WatchIntentLogger.get().log(
                                WatchIntentLogger.IntentEventType.WATCHLIST_REMOVED,
                                titleId = reel.tmdbId.toString(),
                            )
                        } else {
                            streamsVm.addToMyStreams(
                                titleId = reel.tmdbId.toString(),
                                title = reel.showName,
                                posterUrl = reel.posterUrl,
                                platform = reel.platformName,
                            )
                            WatchIntentLogger.get().log(
                                WatchIntentLogger.IntentEventType.WATCHLIST_ADDED,
                                titleId = reel.tmdbId.toString(),
                                platformId = reel.platformId,
                            )
                        }
                    },
                    onToggleWatched = {
                        streamsVm.toggleWatched(
                            titleId = reel.tmdbId.toString(),
                            titleName = reel.showName,
                            mediaType = if (reel.isTV) "tv" else "movie",
                            tmdbId = reel.tmdbId,
                        )
                    },
                    onShare = {
                        val shareIntent = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, reel.youtubeUrl)
                        }
                        context.startActivity(Intent.createChooser(shareIntent, "Share trailer"))
                    },
                    injected = true,
                    sources = sources,
                    onOpenSource = { src ->
                        val url = src.webUrl
                        if (!url.isNullOrBlank()) {
                            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                        }
                    },
                )
            }
            // Top overlay: dismiss chevron only (no category pills).
            // statusBarsPadding keeps the tap target below the system status bar
            // so the status bar doesn't swallow the tap.
            Box(
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .statusBarsPadding()
                    .padding(12.dp)
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.4f))
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onDismiss() },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Filled.KeyboardArrowDown,
                    contentDescription = "Dismiss",
                    tint = TextPrimary,
                    modifier = Modifier.size(26.dp),
                )
            }
        }
    }
}

/**
 * Expanding "Watch now" pill for the title-scoped reel. Tapping expands it into
 * a horizontal row of streaming-service chips (subscribed-first, resolved once
 * by the host). Shows a disabled state when nothing is streamable.
 */
@Composable
private fun WatchNowSwitcher(
    sources: List<WatchmodeSrc>?,
    onOpenSource: (WatchmodeSrc) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }

    when {
        !expanded -> {
            Row(
                modifier = Modifier
                    .clip(RoundedCornerShape(26.dp))
                    .background(BrandOrange)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { expanded = true }
                    .padding(horizontal = 20.dp, vertical = 13.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    imageVector = Icons.Filled.PlayArrow,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(18.dp),
                )
                Spacer(Modifier.width(6.dp))
                Text("Watch now", fontSize = 15.sp, fontWeight = FontWeight.Bold, color = Color.White)
            }
        }
        sources == null -> {
            Row(
                modifier = Modifier
                    .clip(RoundedCornerShape(26.dp))
                    .background(BrandOrange.copy(alpha = 0.6f))
                    .padding(horizontal = 20.dp, vertical = 13.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(8.dp))
                Text("Finding services…", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
            }
        }
        sources.isEmpty() -> {
            Row(
                modifier = Modifier
                    .clip(RoundedCornerShape(26.dp))
                    .background(Color.White.copy(alpha = 0.12f))
                    .padding(horizontal = 20.dp, vertical = 13.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Not available to stream", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = TextSecondary)
            }
        }
        else -> {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(sources) { src ->
                    val color = Platform.from(src.name)?.color ?: BrandOrange
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(22.dp))
                            .background(color)
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                            ) { onOpenSource(src) }
                            .padding(horizontal = 16.dp, vertical = 11.dp),
                    ) {
                        Text(src.name, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = Color.White)
                    }
                }
            }
        }
    }
}

@Composable
private fun RailButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    tint: Color,
    onClick: () -> Unit,
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            modifier = Modifier
                .size(48.dp)
                .clip(CircleShape)
                .background(Color.Black.copy(alpha = 0.4f))
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) { onClick() },
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = label,
                tint = tint,
                modifier = Modifier.size(24.dp),
            )
        }
        Spacer(Modifier.height(4.dp))
        Text(
            text = label,
            fontSize = 11.sp,
            color = TextSecondary,
            fontWeight = FontWeight.Medium,
        )
    }
}

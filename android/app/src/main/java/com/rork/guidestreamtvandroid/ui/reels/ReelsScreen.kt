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
import androidx.compose.foundation.layout.fillMaxHeight
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
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.VerticalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
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
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rork.guidestreamtvandroid.BuildConfig
import com.rork.guidestreamtvandroid.data.models.Platform
import com.rork.guidestreamtvandroid.data.models.StreamingCatalog
import com.rork.guidestreamtvandroid.data.remote.WatchmodeResolveService
import com.rork.guidestreamtvandroid.data.remote.WatchmodeSrc
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.data.repository.DebugLog
import com.rork.guidestreamtvandroid.data.repository.RakutenManager
import com.rork.guidestreamtvandroid.data.repository.StreamsViewModel
import com.rork.guidestreamtvandroid.data.repository.WatchIntentLogger
import com.rork.guidestreamtvandroid.ui.components.RemoteImage
import kotlin.math.abs
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
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
                                isTv = reel.isTV,
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
    // Ordered candidate playback: index 0 is reel.trailerKey, index N is
    // reel.fallbackKeys[N-1]. Only genuinely fatal owner-disabled-embed codes
    // (101/150) advance to the next candidate; once every candidate has failed
    // the reel collapses to its poster. Other error codes keep the WebView
    // mounted exactly as before.
    var candidateIndex by remember(reel.id) { mutableStateOf(0) }
    var allCandidatesFailed by remember(reel.id) { mutableStateOf(false) }
    // Last error code from the player, surfaced only as a debug-build badge so a
    // failing reel is visible on device without a photograph.
    var lastErrorCode by remember(reel.id) { mutableStateOf<Int?>(null) }
    val activeKey = if (candidateIndex == 0) reel.trailerKey
        else reel.fallbackKeys.getOrNull(candidateIndex - 1) ?: reel.trailerKey

    Box(modifier = Modifier.fillMaxSize()) {
        // Backdrop image — stays underneath the player so the reel is never blank
        // while the embed loads and collapses cleanly back to the poster on error.
        RemoteImage(
            url = reel.backdropUrl ?: reel.thumbnailUrl ?: reel.posterUrl,
            contentDescription = reel.showName,
            modifier = Modifier.fillMaxSize(),
            cornerRadius = 0,
            placeholderText = reel.showName.take(2).uppercase(),
            placeholderFontSize = 36.sp,
        )

        // Inline YouTube player — only for the current page with a valid embed.
        // Non-current pages never instantiate a WebView, so swiping never leaves
        // two players (or two audio streams) alive at once.
        if (isCurrent && reel.trailerKey.isNotBlank() && !allCandidatesFailed) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .clip(RoundedCornerShape(0.dp)),
                contentAlignment = Alignment.Center,
            ) {
                YouTubeReelPlayer(
                    videoId = activeKey,
                    isMuted = isMuted,
                    isPlaying = isPlaying,
                    onPlayerError = { code ->
                        // Every error code is logged so a dead player is never a
                        // silent backdrop with no explanation.
                        DebugLog.log(
                            event = "reel_player_error",
                            platform = "android",
                            title = reel.showName,
                            contentUrl = "https://www.youtube.com/watch?v=$activeKey",
                            deviceName = "code=$code candidate=$candidateIndex",
                            matched = false,
                        )
                        lastErrorCode = code
                        // Only owner-disabled-embed codes (101/150) are fatal:
                        // walk the server-verified fallback keys, then collapse
                        // to the poster once every candidate is exhausted. Every
                        // other code leaves the WebView mounted exactly as before
                        // so transient states can still recover.
                        if (code == 101 || code == 150) {
                            if (candidateIndex < reel.fallbackKeys.size) {
                                candidateIndex += 1
                            } else {
                                allCandidatesFailed = true
                            }
                        }
                    },
                    onPlayerReady = {
                        allCandidatesFailed = false
                        lastErrorCode = null
                        DebugLog.log(
                            event = "reel_player_ready",
                            platform = "android",
                            title = reel.showName,
                            contentUrl = "https://www.youtube.com/watch?v=$activeKey",
                            matched = true,
                        )
                    },
                    onEnded = { /* loop=1 playlist restarts automatically */ },
                    modifier = Modifier
                        .fillMaxHeight()
                        .aspectRatio(16f / 9f),
                )
            }
        }

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
                active = isSaved,
                onClick = onToggleSave,
            )
            // Watched
            RailButton(
                icon = Icons.Filled.Visibility,
                label = "Watched",
                tint = if (isWatched) BrandBlue else TextPrimary,
                active = isWatched,
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
            if (!reel.isSponsored) {
                Spacer(Modifier.height(12.dp))
                ReelAdCarousel(reel = reel, isCurrent = isCurrent)
            }
        }

        // Debug-only failure badge — never rendered in a release build.
        if (BuildConfig.DEBUG && isCurrent && lastErrorCode != null) {
            Box(
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .statusBarsPadding()
                    .padding(start = 12.dp, top = 60.dp)
                    .clip(RoundedCornerShape(6.dp))
                    .background(Color.Red.copy(alpha = 0.85f))
                    .padding(horizontal = 8.dp, vertical = 4.dp),
            ) {
                Text(
                    text = "err ${lastErrorCode}",
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                )
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
            withContext(Dispatchers.IO) { WatchmodeResolveService.resolve(sharedTmdbId, sharedIsTV).usSources }
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
                                isTv = reel.isTV,
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
                        // Prefer the native Android link, then the Android TV
                        // link, then web — Watchmode placeholder strings
                        // filtered out. intent:// URIs launch via parseUri.
                        val target = listOf(src.androidUrl, src.androidTvUrl, src.webUrl)
                            .firstOrNull { isUsableReelUrl(it) }
                        if (target != null) {
                            try {
                                val intent = if (target.startsWith("intent:")) {
                                    Intent.parseUri(target, Intent.URI_INTENT_SCHEME)
                                } else {
                                    Intent(Intent.ACTION_VIEW, Uri.parse(target))
                                }
                                context.startActivity(intent)
                            } catch (_: Exception) {
                                src.webUrl?.takeIf { isUsableReelUrl(it) }?.let {
                                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(it)))
                                }
                            }
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
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(src.name, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = Color.White)
                            val tag = reelMonetizationTag(src)
                            if (tag != null) {
                                Spacer(Modifier.width(6.dp))
                                Box(
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(10.dp))
                                        .background(Color.Black.copy(alpha = 0.28f))
                                        .padding(horizontal = 6.dp, vertical = 2.dp),
                                ) {
                                    Text(tag, fontSize = 9.sp, fontWeight = FontWeight.Black, color = Color.White)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/**
 * Compact monetization tag for a Reels source pill — Rent/Buy with price,
 * Free, TV; nothing for subscription tiers.
 */
private fun reelMonetizationTag(src: WatchmodeSrc): String? {
    val price = src.price?.let { String.format(java.util.Locale.US, "$%.2f", it) }
    return when (src.type.lowercase()) {
        "rent" -> if (price != null) "Rent $price" else "Rent"
        "purchase", "buy" -> if (price != null) "Buy $price" else "Buy"
        "free" -> "Free"
        "tve" -> "TV"
        else -> null
    }
}

/**
 * True when [url] is openable: contains a scheme separator and is not one of
 * Watchmode's free-tier placeholder strings.
 */
private fun isUsableReelUrl(url: String?): Boolean {
    if (url.isNullOrBlank()) return false
    val lower = url.lowercase()
    if (!lower.contains("://")) return false
    if (lower.contains("deeplinks available") || lower.contains("paid plan")) return false
    return true
}

@Composable
private fun RailButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    tint: Color,
    active: Boolean = false,
    onClick: () -> Unit,
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            modifier = Modifier
                .size(42.dp)
                .clip(CircleShape)
                .background(if (active) Color.Black.copy(alpha = 0.17f) else Color.Transparent)
                .then(
                    if (active) Modifier.border(1.dp, Color.White.copy(alpha = 0.15f), CircleShape)
                    else Modifier,
                )
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
                modifier = Modifier
                    .size(17.dp)
                    .shadow(
                        elevation = 3.dp,
                        shape = CircleShape,
                        clip = false,
                        ambientColor = Color.Black.copy(alpha = 0.55f),
                        spotColor = Color.Black.copy(alpha = 0.55f),
                    ),
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

// ── Reel affiliate ad carousel ──────────────────────────────────────

/**
 * Rotating pool of the eight affiliate offers, matching the iOS inline ad
 * pool and the home inlineAdPool exactly (serviceId, headline, subtitle).
 */
private val reelAdPool: List<Triple<String, String, String>> = listOf(
    Triple("netflix", "Stream more on Netflix", "Unlimited shows & movies · Try free"),
    Triple("hbo", "Watch more on Max", "HBO, Max Originals & more · Try free"),
    Triple("hulu", "Live TV + streaming on Hulu", "Starting at $7.99/mo · Try free"),
    Triple("disney", "Disney+, Hulu & ESPN+ bundle", "Disney Bundle · Try free"),
    Triple("appletv", "Award-winning originals", "Apple TV+ · First month free"),
    Triple("prime", "Included with Prime", "Prime Video · Try free"),
    Triple("paramount", "NFL on CBS & live sports", "Paramount+ · Try free"),
    Triple("peacock", "Stream free on Peacock", "NBC shows & live sports · Free tier"),
)

/**
 * Mirrors iOS resolveGlassAds: build "preferred" = pool entries whose
 * serviceId != currentPlatform and not in selected; "secondary" = entries
 * whose serviceId != currentPlatform; pick eligible = preferred.ifEmpty {
 * secondary.ifEmpty { reelAdPool } }; rotate by shift = abs(tmdbId) %
 * eligible.size so different titles lead with different services.
 */
private fun resolveReelAds(
    currentPlatform: String,
    selected: Set<String>,
    tmdbId: Int,
    count: Int = 5,
): List<Triple<String, String, String>> {
    val current = currentPlatform.lowercase()
    val preferred = reelAdPool.filter { it.first != current && it.first !in selected }
    val secondary = reelAdPool.filter { it.first != current }
    val eligible: List<Triple<String, String, String>> = when {
        preferred.isNotEmpty() -> preferred
        secondary.isNotEmpty() -> secondary
        else -> reelAdPool
    }
    if (eligible.isEmpty()) return emptyList()
    val shift = abs(tmdbId) % eligible.size
    val rotated = eligible.drop(shift) + eligible.take(shift)
    return rotated.take(count)
}

/**
 * Compact reel affiliate carousel that mirrors the iOS adCarousel. Renders a
 * HorizontalPager of [ReelAffiliateCard] items with dot indicators beneath.
 * Fades in after a short delay only while the reel is the current page; logs a
 * single AD_IMPRESSION on first show; dismissible for the session.
 */
@Composable
private fun ReelAdCarousel(
    reel: TrailerItem,
    isCurrent: Boolean,
) {
    val auth = AuthViewModel.get()
    val selectedServices by auth.selectedServices.collectAsStateWithLifecycle()
    val offers = remember(reel.id, selectedServices) {
        resolveReelAds(reel.platformId, selectedServices, reel.tmdbId)
    }
    var dismissed by remember(reel.id) { mutableStateOf(false) }
    var visible by remember(reel.id) { mutableStateOf(false) }

    LaunchedEffect(isCurrent) {
        visible = false
        if (isCurrent) {
            delay(600)
            visible = true
        }
    }

    LaunchedEffect(reel.id, visible) {
        if (visible) {
            WatchIntentLogger.get().log(
                WatchIntentLogger.IntentEventType.AD_IMPRESSION,
                metadata = mapOf(
                    "ad_type" to "reel_ad_carousel",
                    "source" to "reel_ad_carousel",
                ),
            )
        }
    }

    if (offers.isEmpty() || dismissed || !isCurrent || !visible) return

    val pagerState = rememberPagerState(pageCount = { offers.size })

    Column {
        HorizontalPager(
            state = pagerState,
            modifier = Modifier.fillMaxWidth(),
        ) { page ->
            ReelAffiliateCard(
                offer = offers[page],
                reel = reel,
                onDismiss = { dismissed = true },
            )
        }
        Spacer(Modifier.height(6.dp))
        Row(
            horizontalArrangement = Arrangement.spacedBy(5.dp),
            modifier = Modifier.padding(start = 2.dp),
        ) {
            repeat(offers.size) { idx ->
                Box(
                    modifier = Modifier
                        .size(5.dp)
                        .clip(CircleShape)
                        .background(
                            if (idx == pagerState.currentPage) BrandOrange
                            else Color.White.copy(alpha = 0.28f),
                        ),
                )
            }
        }
    }
}

/**
 * Compact glass affiliate card for the reel carousel — a rounded 14dp
 * container with a dark backing and a hairline border so text stays legible
 * over bright trailer frames. Tapping the card (excluding the dismiss icon)
 * opens the Rakuten affiliate link and logs AFFILIATE_LINK_TAPPED.
 */
@Composable
private fun ReelAffiliateCard(
    offer: Triple<String, String, String>,
    reel: TrailerItem,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val service = StreamingCatalog.service(offer.first)

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(Color.Black.copy(alpha = 0.55f))
            .border(1.dp, GlassStroke, RoundedCornerShape(14.dp))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) {
                RakutenManager.get().openAffiliateLink(
                    serviceId = offer.first,
                    context = context,
                    metadata = mapOf(
                        "source" to "reel_ad_carousel",
                        "reel_platform" to reel.platformId,
                        "show" to reel.showName,
                    ),
                )
                WatchIntentLogger.get().log(
                    WatchIntentLogger.IntentEventType.AFFILIATE_LINK_TAPPED,
                    metadata = mapOf(
                        "source" to "reel_ad_carousel",
                        "show_platform" to reel.platformId,
                    ),
                )
            },
    ) {
        Column(modifier = Modifier.padding(10.dp)) {
            // Header: Sponsored pill + dismiss
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(4.dp))
                        .background(BrandOrange.copy(alpha = 0.2f))
                        .padding(horizontal = 6.dp, vertical = 2.dp),
                ) {
                    Text(
                        text = "Sponsored",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        color = BrandOrange,
                    )
                }
                Spacer(Modifier.weight(1f))
                Icon(
                    imageVector = Icons.Filled.Close,
                    contentDescription = "Dismiss ad",
                    tint = TextTertiary,
                    modifier = Modifier
                        .size(18.dp)
                        .clip(CircleShape)
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) { onDismiss() },
                )
            }
            Spacer(Modifier.height(8.dp))
            // Body: brand tile + headline/subtitle + get offer
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(44.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(service?.bg ?: Color.Black),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = (service?.name ?: offer.second).take(3).uppercase(),
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Black,
                        color = Color.White,
                    )
                }
                Spacer(Modifier.width(10.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = offer.second,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                        color = TextPrimary,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Spacer(Modifier.height(2.dp))
                    Text(
                        text = offer.third,
                        fontSize = 10.sp,
                        color = TextSecondary,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Spacer(Modifier.height(3.dp))
                    Text(
                        text = "Sponsored · Rakuten",
                        fontSize = 9.sp,
                        color = TextTertiary,
                    )
                }
                Spacer(Modifier.width(8.dp))
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(14.dp))
                        .background(BrandOrange)
                        .padding(horizontal = 12.dp, vertical = 7.dp),
                ) {
                    Text(
                        text = "Get offer",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                    )
                }
            }
        }
    }
}

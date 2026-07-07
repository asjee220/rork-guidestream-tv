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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
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
import androidx.compose.material.icons.filled.VolumeOff
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import com.rork.guidestreamtvandroid.data.repository.StreamsViewModel
import com.rork.guidestreamtvandroid.data.repository.WatchIntentLogger
import com.rork.guidestreamtvandroid.ui.components.RemoteImage
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
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
    modifier: Modifier = Modifier,
) {
    val vm = ReelsViewModel.get()
    val streamsVm = StreamsViewModel.get()
    val context = LocalContext.current

    val trailers by vm.trailers.collectAsStateWithLifecycle()
    val isLoading by vm.isLoading.collectAsStateWithLifecycle()
    val currentTab by vm.currentTab.collectAsStateWithLifecycle()
    val userStreams by streamsVm.userStreams.collectAsStateWithLifecycle()

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

                ReelView(
                    reel = reel,
                    isCurrent = isCurrent,
                    isPlaying = isPlaying,
                    isMuted = isMuted,
                    isSaved = isSaved,
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
                    onShare = {
                        val shareIntent = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, reel.youtubeUrl)
                        }
                        context.startActivity(Intent.createChooser(shareIntent, "Share trailer"))
                    },
                )
            }

            // Top overlay: dismiss chevron + category pills
            Row(
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .fillMaxWidth()
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
    onTogglePlay: () -> Unit,
    onToggleMute: () -> Unit,
    onPlayYoutube: () -> Unit,
    onToggleSave: () -> Unit,
    onShare: () -> Unit,
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
                .padding(end = 12.dp, bottom = 100.dp),
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
                .padding(start = 16.dp, bottom = 100.dp)
                .fillMaxWidth(0.65f),
        ) {
            // Platform badge
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

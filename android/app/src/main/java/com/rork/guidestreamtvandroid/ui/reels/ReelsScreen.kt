package com.rork.guidestreamtvandroid.ui.reels

import android.app.Activity
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.net.Uri
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredHeight
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.foundation.layout.widthIn
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
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VolumeOff
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.max
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rork.guidestreamtvandroid.BuildConfig
import com.rork.guidestreamtvandroid.data.ShareLinks
import com.rork.guidestreamtvandroid.data.models.Platform
import com.rork.guidestreamtvandroid.data.models.StreamingCatalog
import com.rork.guidestreamtvandroid.data.remote.WatchmodeResolveService
import com.rork.guidestreamtvandroid.data.remote.WatchmodeSrc
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.data.repository.DebugLog
import com.rork.guidestreamtvandroid.data.repository.RakutenManager
import com.rork.guidestreamtvandroid.data.repository.SocialViewModel
import com.rork.guidestreamtvandroid.data.repository.StreamsViewModel
import com.rork.guidestreamtvandroid.data.repository.WatchIntentLogger
import com.rork.guidestreamtvandroid.ui.ads.NativeAdCard
import com.rork.guidestreamtvandroid.ui.ads.RakutenAffiliatePresentation
import com.rork.guidestreamtvandroid.ui.comments.TitleCommentsSheet
import com.rork.guidestreamtvandroid.ui.components.RemoteImage
import com.rork.guidestreamtvandroid.ui.navigation.PendingTitleRoute
import java.util.Locale
import kotlin.math.abs
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import com.rork.guidestreamtvandroid.ui.theme.BrandBlue
import com.rork.guidestreamtvandroid.ui.theme.SheetLevel
import com.rork.guidestreamtvandroid.ui.theme.SheetSurfaceBase
import androidx.compose.foundation.layout.navigationBarsPadding
import com.rork.guidestreamtvandroid.ui.components.GsSheetDragHandle
import com.rork.guidestreamtvandroid.ui.components.GsSheetHeader
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.sheetTopInset
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
    onOpenTitle: (PendingTitleRoute) -> Unit = {},
    injectedReels: List<TrailerItem>? = null,
    injectedStartIndex: Int = 0,
    modifier: Modifier = Modifier,
) {
    // Reels is the only screen allowed to rotate. SCREEN_ORIENTATION_USER (never
    // SENSOR) so a device with auto-rotate switched off stays in portrait. The
    // previous value is captured and restored rather than hardcoding portrait,
    // because MainActivity already sets FULL_USER on 600dp+ tablets and
    // hardcoding portrait would break tablet rotation. Declared above the
    // injected early-return so Trailers & Clips rotates identically.
    val orientationContext = LocalContext.current
    DisposableEffect(Unit) {
        val activity = orientationContext as? Activity
        val previousOrientation = activity?.requestedOrientation
        activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_USER
        onDispose {
            if (activity != null && previousOrientation != null) {
                activity.requestedOrientation = previousOrientation
            }
        }
    }

    // Landscape Reels is fully immersive: both the status bar and the navigation
    // bar hide so the trailer is genuinely full-bleed. MainActivity's
    // enableEdgeToEdge() only draws content *behind* the bars and its default
    // SystemBarStyle.auto paints a light scrim behind three-button navigation —
    // that scrim is the grey trailing-edge bar. Keyed on the orientation value
    // and never on Unit, because AndroidManifest declares configChanges for
    // orientation|screenSize, so the activity is not recreated on rotation and a
    // Unit-keyed effect would never re-fire. Declared above the injected
    // early-return so Trailers & Clips goes immersive identically.
    val immersiveLandscape =
        LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE
    val immersiveLifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(immersiveLandscape) {
        val activity = orientationContext as? Activity
        val controller = activity?.window?.let { window ->
            WindowCompat.getInsetsController(window, window.decorView)
        }
        val applyImmersive: () -> Unit = {
            if (controller != null) {
                if (immersiveLandscape) {
                    // Transient behavior: an edge swipe surfaces the bars
                    // temporarily and they auto-hide again on their own, so the
                    // hidden state is never permanently lost.
                    controller.systemBarsBehavior =
                        WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                    controller.hide(WindowInsetsCompat.Type.systemBars())
                } else {
                    controller.show(WindowInsetsCompat.Type.systemBars())
                }
            }
        }
        applyImmersive()
        // Returning from the background — or back from the YouTube app — can drop
        // the hidden state, so re-apply it on every resume.
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                applyImmersive()
            }
        }
        immersiveLifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            immersiveLifecycleOwner.lifecycle.removeObserver(observer)
            // Leaving Reels by any route (chevron, swipe-down, tab change, system
            // back) must hand the bars back to the rest of the app.
            controller?.show(WindowInsetsCompat.Type.systemBars())
            controller?.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_DEFAULT
        }
    }

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
    val social = SocialViewModel.get()
    val context = LocalContext.current

    val trailers by vm.trailers.collectAsStateWithLifecycle()
    val isLoading by vm.isLoading.collectAsStateWithLifecycle()
    val currentTab by vm.currentTab.collectAsStateWithLifecycle()
    val userStreams by streamsVm.userStreams.collectAsStateWithLifecycle()
    val watchedIds by streamsVm.watchedIds.collectAsStateWithLifecycle()
    val likeCounts by social.likeCounts.collectAsStateWithLifecycle()
    val likedByMe by social.likedByMe.collectAsStateWithLifecycle()
    val commentCounts by social.commentCounts.collectAsStateWithLifecycle()

    // Reel that opened the comment sheet (tmdbId), null when sheet is closed.
    var commentsReelTmdb by remember { mutableStateOf<Int?>(null) }
    // Reel that opened the More sheet (tmdbId), null when sheet is closed.
    var showMoreTmdb by remember { mutableStateOf<Int?>(null) }

    // Tab-filtered trailers
    val filteredTrailers = remember(trailers, currentTab) {
        vm.trailersForTab(currentTab)
    }

    var isPlaying by remember { mutableStateOf(true) }
    var isMuted by remember { mutableStateOf(true) }

    val isLandscape = LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE
    val (landscapeLeading, landscapeTrailing) = landscapeSideInsets()

    // Landscape-only: the transient chrome (top bar, metadata, social rail,
    // scrubber) auto-hides 3s after the last touch and returns on any tap.
    // landscapeChromePresent keeps the transient row in layout until 0.55s
    // after the fade starts, when it leaves layout so the persistent group
    // (ad, chips, CTA) settles into the vacated space. Independent of
    // ReelView's showControls / 2.2s flash timer, which keeps driving the
    // center play-pause exactly as before.
    var landscapeChromeVisible by remember { mutableStateOf(true) }
    var landscapeChromePresent by remember { mutableStateOf(true) }
    var chromeHideJob by remember { mutableStateOf<Job?>(null) }
    val chromeScope = rememberCoroutineScope()
    val chromeAlpha by animateFloatAsState(
        targetValue = if (!isLandscape || landscapeChromeVisible) 1f else 0f,
        animationSpec = tween(durationMillis = 450, easing = EaseOut),
        label = "reelChromeAlpha",
    )
    fun revealChrome() {
        chromeHideJob?.cancel()
        landscapeChromeVisible = true
        landscapeChromePresent = true
        // Portrait never hides chrome, so no countdown is armed there.
        if (!isLandscape) return
        chromeHideJob = chromeScope.launch {
            delay(3000)
            landscapeChromeVisible = false
            // 0.55s after the fade started the transient row leaves layout.
            delay(550)
            landscapeChromePresent = false
        }
    }

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

            // Chrome reappears for each new reel, and rotating back to portrait
            // pins it visible with the pending hide task cancelled.
            LaunchedEffect(isLandscape, pagerState.currentPage) { revealChrome() }

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
                if (item.tmdbId > 0) social.refreshCounts(item.tmdbId.toString())
            }

            VerticalPager(
                state = pagerState,
                modifier = Modifier.fillMaxSize(),
            ) { page ->
                val reel = filteredTrailers[page]
                val isCurrent = page == pagerState.currentPage
                val isSaved = userStreams.any { it.titleId == reel.tmdbId.toString() }
                val isWatched = watchedIds.contains(reel.tmdbId.toString())

                val tid = reel.tmdbId.toString()
                val reelIsLiked = tid in likedByMe
                val reelLikeCount = likeCounts[tid] ?: 0
                val reelCommentCount = commentCounts[tid] ?: 0
                ReelView(
                    reel = reel,
                    isCurrent = isCurrent,
                    isLandscape = isLandscape,
                    landscapeLeading = landscapeLeading,
                    landscapeTrailing = landscapeTrailing,
                    chromeVisible = landscapeChromeVisible,
                    chromePresent = landscapeChromePresent,
                    chromeAlpha = chromeAlpha,
                    onRevealChrome = { revealChrome() },
                    isPlaying = isPlaying,
                    isMuted = isMuted,
                    isSaved = isSaved,
                    isWatched = isWatched,
                    isLiked = reelIsLiked,
                    likeCount = reelLikeCount,
                    commentCount = reelCommentCount,
                    onLike = {
                        social.toggleLike(
                            titleId = tid,
                            mediaType = if (reel.isTV) "tv" else "movie",
                            tmdbId = reel.tmdbId,
                        )
                        WatchIntentLogger.get().log(
                            WatchIntentLogger.IntentEventType.TRAILER_LIKED,
                            metadata = mapOf("tmdb_id" to reel.tmdbId, "source" to "reels"),
                        )
                    },
                    onComments = { commentsReelTmdb = reel.tmdbId },
                    onMore = { showMoreTmdb = reel.tmdbId },
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
                    onShowDetail = {
                        // Sponsored reels have no title behind them, and a
                        // missing tmdbId would open an empty sheet — both are
                        // no-ops rather than a broken destination.
                        if (!reel.isSponsored && reel.tmdbId > 0) {
                            WatchIntentLogger.get().log(
                                WatchIntentLogger.IntentEventType.DEEPLINK_FIRED,
                                titleId = reel.tmdbId.toString(),
                                platformId = reel.platformId,
                                metadata = mapOf("source" to "reels_play_pill"),
                            )
                            onOpenTitle(
                                PendingTitleRoute(
                                    titleId = reel.tmdbId.toString(),
                                    titleName = reel.showName,
                                    posterUrl = reel.posterUrl,
                                    isTv = reel.isTV,
                                )
                            )
                        }
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
                        if (reel.tmdbId > 0 && !reel.isSponsored) {
                            ShareLinks.share(
                                context,
                                if (reel.isTV) ShareLinks.Kind.TV else ShareLinks.Kind.MOVIE,
                                reel.tmdbId.toString(),
                                reel.showName,
                            )
                            WatchIntentLogger.get().log(
                                WatchIntentLogger.IntentEventType.SHARE_TAPPED,
                                titleId = reel.tmdbId.toString(),
                                metadata = mapOf(
                                    "surface" to "reels_trailer",
                                    "kind" to if (reel.isTV) "tv" else "movie",
                                ),
                            )
                        }
                    },
                )
            }
            }

            commentsReelTmdb?.let { openedTmdb ->
                val openedReel = filteredTrailers.firstOrNull { it.tmdbId == openedTmdb }
                if (openedReel != null && openedTmdb > 0) {
                    TitleCommentsSheet(
                        titleId = openedTmdb.toString(),
                        title = openedReel.showName,
                        subtitle = openedReel.genre,
                        posterUrl = openedReel.posterUrl,
                        onDismiss = { commentsReelTmdb = null },
                    )
                } else if (openedTmdb <= 0) {
                    commentsReelTmdb = null
                }
            }
            showMoreTmdb?.let { openedTmdb ->
                val openedReel = filteredTrailers.firstOrNull { it.tmdbId == openedTmdb }
                if (openedReel != null) {
                    ReelMoreSheet(
                        commentCount = if (openedTmdb > 0) (commentCounts[openedTmdb.toString()] ?: 0) else 0,
                        onDismiss = { showMoreTmdb = null },
                        onComment = {
                            showMoreTmdb = null
                            if (openedTmdb > 0) commentsReelTmdb = openedTmdb
                        },
                        onShare = {
                            showMoreTmdb = null
                            if (openedReel.tmdbId > 0 && !openedReel.isSponsored) {
                                ShareLinks.share(
                                    context,
                                    if (openedReel.isTV) ShareLinks.Kind.TV else ShareLinks.Kind.MOVIE,
                                    openedReel.tmdbId.toString(),
                                    openedReel.showName,
                                )
                                WatchIntentLogger.get().log(
                                    WatchIntentLogger.IntentEventType.SHARE_TAPPED,
                                    titleId = openedReel.tmdbId.toString(),
                                    metadata = mapOf(
                                        "surface" to "reels_trailer",
                                        "kind" to if (openedReel.isTV) "tv" else "movie",
                                    ),
                                )
                            }
                        },
                        onPlayYoutube = {
                            showMoreTmdb = null
                            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(openedReel.youtubeUrl)))
                        },
                    )
                }
            }
            // Top overlay: dismiss chevron + category pills. In landscape the
            // pills are hidden and the bar carries the mute toggle (rendered by
            // ReelView on the trailing side) instead. Not composed at all once
            // the chrome has faded out, so taps fall through to the reel.
            if (chromeAlpha > 0.01f) {
            Row(
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .fillMaxWidth()
                    .statusBarsPadding()
                    .padding(
                        start = if (isLandscape) landscapeLeading else 12.dp,
                        end = if (isLandscape) landscapeTrailing else 12.dp,
                        top = 12.dp,
                        bottom = 12.dp,
                    )
                    .alpha(chromeAlpha),
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
                if (!isLandscape) {
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
    }
}

/**
 * Landscape horizontal safe-area floors. 44dp is a floor, not a ceiling — a
 * display cutout reports considerably more than that in landscape, and pinning
 * to a fixed 44dp would tuck the chrome underneath it.
 */
@Composable
private fun landscapeSideInsets(): Pair<Dp, Dp> {
    val sides = WindowInsets.displayCutout.union(WindowInsets.navigationBars).asPaddingValues()
    return max(44.dp, sides.calculateLeftPadding(LayoutDirection.Ltr)) to
        max(44.dp, sides.calculateRightPadding(LayoutDirection.Ltr))
}

@Composable
private fun ReelView(
    reel: TrailerItem,
    isCurrent: Boolean,
    isPlaying: Boolean,
    isMuted: Boolean,
    isSaved: Boolean,
    isWatched: Boolean,
    isLandscape: Boolean = false,
    landscapeLeading: Dp = 44.dp,
    landscapeTrailing: Dp = 44.dp,
    chromeVisible: Boolean = true,
    chromePresent: Boolean = true,
    chromeAlpha: Float = 1f,
    onRevealChrome: () -> Unit = {},
    isLiked: Boolean = false,
    likeCount: Int = 0,
    commentCount: Int = 0,
    onLike: () -> Unit = {},
    onComments: () -> Unit = {},
    onMore: () -> Unit = {},
    onTogglePlay: () -> Unit,
    onToggleMute: () -> Unit,
    onPlayYoutube: () -> Unit,
    /** Opens the title's quick-look detail sheet — driven by the Watch pill. */
    onShowDetail: () -> Unit = {},
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
    // Playback progress for the bottom scrubber.
    var progress by remember(reel.id) { mutableStateOf(0f) }
    var seekToFraction by remember(reel.id) { mutableStateOf<Float?>(null) }
    // Media controls flash when the user taps the reel while playing.
    var showControls by remember { mutableStateOf(false) }
    val coroutineScope = rememberCoroutineScope()
    var controlsFlashJob by remember { mutableStateOf<Job?>(null) }
    fun flashControls() {
        controlsFlashJob?.cancel()
        controlsFlashJob = coroutineScope.launch {
            showControls = true
            delay(2200)
            showControls = false
        }
    }
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
            // iOS sizes the player to the full screen height while preserving a
            // 16:9 aspect ratio, then clips the sides so the video fills the
            // entire screen without letterboxing.
            BoxWithConstraints(
                modifier = Modifier
                    .fillMaxSize()
                    .clipToBounds(),
                contentAlignment = Alignment.Center,
            ) {
                val pageW = maxWidth
                val pageH = maxHeight
                val fillW = max(pageW, pageH * 16f / 9f)
                val fillH = fillW * 9f / 16f
                Box(
                    modifier = Modifier
                        .requiredWidth(fillW)
                        .requiredHeight(fillH),
                ) {
                    YouTubeReelPlayer(
                        modifier = Modifier.fillMaxSize(),
                        videoId = activeKey,
                        isMuted = isMuted,
                        isPlaying = isPlaying,
                        seekToFraction = seekToFraction,
                        onSeekConsumed = { seekToFraction = null },
                        onProgress = { seconds, duration ->
                            progress = if (duration > 0f) seconds / duration else 0f
                        },
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
                            // Fatal per-video codes walk the server-verified
                            // fallback keys, then collapse to the poster once every
                            // candidate is exhausted: 100 = removed/private,
                            // 101/150 = owner disabled embedding, 152/153 = embed
                            // blocked/restricted for this referrer. Every other
                            // code leaves the WebView mounted exactly as before so
                            // transient states can still recover.
                            if (code == 100 || code == 101 || code == 150 || code == 152 || code == 153) {
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
                            progress = 0f
                            DebugLog.log(
                                event = "reel_player_ready",
                                platform = "android",
                                title = reel.showName,
                                contentUrl = "https://www.youtube.com/watch?v=$activeKey",
                                matched = true,
                            )
                        },
                        onEnded = { /* looping is handled inside the player */ },
                    )
                }
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
                            Color.Black.copy(alpha = 0.34f),
                        ),
                    ),
                ),
        )

        // Full-screen tap target for play/pause toggle.
        // Rendered beneath interactive overlays so the right rail, ad chips, and
        // scrubber always receive taps first.
        if (isCurrent) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) {
                        // Landscape with the chrome hidden: the first tap only
                        // brings the chrome back, it never toggles playback.
                        if (isLandscape && !chromeVisible) {
                            onRevealChrome()
                        } else {
                            onTogglePlay()
                            flashControls()
                            if (isLandscape) onRevealChrome()
                        }
                    },
                contentAlignment = Alignment.Center,
            ) {}
        }

        // Right rail: Like, List, Watched, More — positioned at 27% down the
        // screen to match iOS Layer 15. Landscape folds these buttons into the
        // bottom row instead, so the vertical rail is suppressed there.
        if (!isLandscape) {
        Column(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(end = 18.dp)
                .padding(top = LocalConfiguration.current.screenHeightDp.dp * 0.27f),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            ReelRailButtons(
                reel = reel,
                isLiked = isLiked,
                likeCount = likeCount,
                isSaved = isSaved,
                isWatched = isWatched,
                onLike = onLike,
                onToggleSave = onToggleSave,
                onToggleWatched = onToggleWatched,
                onMore = onMore,
                onShare = onShare,
                iconSize = 20.dp,
            )
        }
        }

        // Bottom-left content (Layer 17) — matches iOS layout and typography.
        // Landscape replaces this stacked block (plus the right rail) with a
        // single horizontal row further down.
        if (!isLandscape) {
        Column(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(start = 22.dp, end = 16.dp)
                .padding(bottom = 27.dp + systemBottomInset())
                .fillMaxWidth(),
        ) {
            // Platform / genre / video-type chips
            ReelChipsRow(reel = reel, injected = injected)
            Spacer(Modifier.height(8.dp))
            Text(
                text = reel.showName,
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(end = 90.dp),
            )
            if (reel.synopsis.isNotBlank()) {
                Spacer(Modifier.height(10.dp))
                Text(
                    text = reel.synopsis,
                    fontSize = 14.sp,
                    color = Color.White.copy(alpha = 0.80f),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(end = 90.dp),
                )
            }
            Spacer(Modifier.height(14.dp))
            Text(
                text = "Trailer",
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
                color = Color.White.copy(alpha = 0.55f),
                modifier = Modifier.padding(end = 90.dp),
            )

            Spacer(Modifier.height(14.dp))
            // Watch / CTA row + ad carousel on the trailing side.
            if (reel.isSponsored) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = "Learn more",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White,
                    )
                    Spacer(Modifier.width(6.dp))
                    Icon(
                        imageVector = Icons.Filled.KeyboardArrowDown,
                        contentDescription = null,
                        tint = Color.White.copy(alpha = 0.70f),
                        modifier = Modifier.size(16.dp),
                    )
                }
            } else if (injected) {
                Box(Modifier.fillMaxWidth().padding(end = 16.dp)) {
                    ReelAdCarousel(reel = reel, isCurrent = isCurrent)
                }
                Spacer(Modifier.height(4.dp))
                WatchNowSwitcher(sources = sources, onOpenSource = onOpenSource)
            } else {
                Box(Modifier.fillMaxWidth().padding(end = 16.dp)) {
                    ReelAdCarousel(reel = reel, isCurrent = isCurrent)
                }
                Spacer(Modifier.height(4.dp))
                PlayOnPill(onClick = onShowDetail)
            }
        }
        }

        // Landscape chrome — the scrubber sits directly above the transient
        // row (metadata leading, rail trailing) inside the same bottom
        // container, so the gap holds regardless of how tall the metadata
        // renders. The persistent group (ad carousel, chips, CTA) never
        // fades; only the metadata row and scrubber auto-hide.
        if (isLandscape) {
            Column(
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .fillMaxWidth()
                    .padding(start = landscapeLeading, end = landscapeTrailing)
                    .padding(bottom = 15.dp + systemBottomInset()),
            ) {
                // Persistent: the ad carousel (with its dots) never fades.
                if (isCurrent && !reel.isSponsored) {
                    ReelAdCarousel(
                        reel = reel,
                        isCurrent = isCurrent,
                        maxWidth = 370.dp,
                    )
                    Spacer(Modifier.height(9.dp))
                }
                // Transient: the scrubber fades with the chrome but keeps
                // its layout slot.
                if (isCurrent && !allCandidatesFailed) {
                    ReelScrubber(
                        progress = progress,
                        onSeek = { fraction -> seekToFraction = fraction },
                        modifier = Modifier
                            .fillMaxWidth()
                            .alpha(chromeAlpha),
                    )
                    Spacer(Modifier.height(9.dp))
                }
                // Transient row: metadata leading, rail trailing. Fades
                // with the chrome, then leaves layout 0.55s after the fade
                // started so the persistent group slides into the vacated
                // space.
                AnimatedVisibility(
                    visible = chromePresent,
                    enter = expandVertically(animationSpec = tween(500, easing = EaseOut)),
                    exit = shrinkVertically(animationSpec = tween(500, easing = EaseOut)),
                ) {
                    Row(
                        verticalAlignment = Alignment.Bottom,
                        modifier = Modifier.alpha(chromeAlpha),
                    ) {
                        // Metadata — no trailing gutter reserved, the rail is in-row.
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = reel.showName,
                                fontSize = 16.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color.White,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                            if (reel.synopsis.isNotBlank()) {
                                Spacer(Modifier.height(6.dp))
                                Text(
                                    text = reel.synopsis,
                                    fontSize = 12.sp,
                                    color = Color.White.copy(alpha = 0.80f),
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }
                        }
                        Spacer(Modifier.width(16.dp))
                        // Actions — the same rail buttons laid out horizontally.
                        // The action pill moved into the persistent row below so
                        // the fading row's alpha can't take it with the rail.
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(22.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            ReelRailButtons(
                                reel = reel,
                                isLiked = isLiked,
                                likeCount = likeCount,
                                isSaved = isSaved,
                                isWatched = isWatched,
                                onLike = onLike,
                                onToggleSave = onToggleSave,
                                onToggleWatched = onToggleWatched,
                                onMore = onMore,
                                onShare = onShare,
                                iconSize = 19.dp,
                            )
                        }
                    }
                }
                // Persistent: the chips row with the CTA pill pinned to the
                // trailing edge, bottom-aligned with the chips.
                Row(verticalAlignment = Alignment.Bottom) {
                    ReelChipsRow(reel = reel, injected = injected)
                    Spacer(Modifier.weight(1f))
                    if (reel.isSponsored) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                text = "Learn more",
                                fontSize = 13.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = Color.White,
                            )
                            Spacer(Modifier.width(6.dp))
                            Icon(
                                imageVector = Icons.Filled.KeyboardArrowDown,
                                contentDescription = null,
                                tint = Color.White.copy(alpha = 0.70f),
                                modifier = Modifier.size(16.dp),
                            )
                        }
                    } else if (injected) {
                        WatchNowSwitcher(sources = sources, onOpenSource = onOpenSource)
                    } else {
                        PlayOnPill(onClick = onShowDetail)
                    }
                }
            }
        }

        // Landscape top bar trailing edge — the mute toggle moves up here, level
        // with the dismiss chevron the screen renders on the leading side. Same
        // 40dp circle, same icons, same action, same flash.
        if (isLandscape && isCurrent && chromeAlpha > 0.01f) {
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .statusBarsPadding()
                    .padding(end = landscapeTrailing, top = 12.dp)
                    .alpha(chromeAlpha)
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.45f))
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) {
                        onToggleMute()
                        flashControls()
                        onRevealChrome()
                    },
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

        // Layer 19 — interactive video scrubber. Landscape renders it inside the
        // bottom container above the row instead of anchoring it here.
        if (isCurrent && !allCandidatesFailed && !isLandscape) {
            ReelScrubber(
                progress = progress,
                onSeek = { fraction -> seekToFraction = fraction },
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .padding(horizontal = 22.dp)
                    .padding(bottom = 14.dp + systemBottomInset()),
            )
        }

        // Layer 21 — media controls overlay (play/pause + mute).
        if (isCurrent && (showControls || !isPlaying)) {
            // Center play/pause button
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
                    ) {
                        onTogglePlay()
                        flashControls()
                    },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                    contentDescription = if (isPlaying) "Pause" else "Play",
                    tint = Color.White,
                    modifier = Modifier.size(36.dp),
                )
            }

            // Mute button — bottom-leading when playing, centered above the play
            // button when paused, matching iOS. Landscape relocates it to the
            // trailing edge of the top bar, so it is suppressed here.
            val muteIcon = if (isMuted) Icons.Filled.VolumeOff else Icons.Filled.VolumeUp
            val muteDescription = if (isMuted) "Unmute" else "Mute"
            if (isLandscape) {
                // Relocated to the top bar.
            } else if (isPlaying) {
                Box(
                    modifier = Modifier
                        .align(Alignment.BottomStart)
                        .padding(start = 16.dp, bottom = 64.dp + systemBottomInset())
                        .size(40.dp)
                        .clip(CircleShape)
                        .background(Color.Black.copy(alpha = 0.45f))
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) {
                            onToggleMute()
                            flashControls()
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = muteIcon,
                        contentDescription = muteDescription,
                        tint = Color.White,
                        modifier = Modifier.size(22.dp),
                    )
                }
            } else {
                Box(
                    modifier = Modifier
                        .align(Alignment.Center)
                        .offset(y = -(34.dp + 16.dp + 20.dp))
                        .size(40.dp)
                        .clip(CircleShape)
                        .background(Color.Black.copy(alpha = 0.45f))
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) {
                            onToggleMute()
                            flashControls()
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = muteIcon,
                        contentDescription = muteDescription,
                        tint = Color.White,
                        modifier = Modifier.size(22.dp),
                    )
                }
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
    val social = SocialViewModel.get()
    val userStreams by streamsVm.userStreams.collectAsStateWithLifecycle()
    val watchedIds by streamsVm.watchedIds.collectAsStateWithLifecycle()
    val likeCounts by social.likeCounts.collectAsStateWithLifecycle()
    val likedByMe by social.likedByMe.collectAsStateWithLifecycle()
    val commentCounts by social.commentCounts.collectAsStateWithLifecycle()

    // Reel that opened the comment sheet (tmdbId), null when sheet is closed.
    var commentsReelTmdb by remember { mutableStateOf<Int?>(null) }
    // Reel that opened the More sheet (tmdbId), null when sheet is closed.
    var showMoreTmdb by remember { mutableStateOf<Int?>(null) }

    var isPlaying by remember { mutableStateOf(true) }
    var isMuted by remember { mutableStateOf(true) }

    val isLandscape = LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE
    val (landscapeLeading, landscapeTrailing) = landscapeSideInsets()

    // Landscape-only auto-hiding chrome, identical to the main feed.
    var landscapeChromeVisible by remember { mutableStateOf(true) }
    var landscapeChromePresent by remember { mutableStateOf(true) }
    var chromeHideJob by remember { mutableStateOf<Job?>(null) }
    val chromeScope = rememberCoroutineScope()
    val chromeAlpha by animateFloatAsState(
        targetValue = if (!isLandscape || landscapeChromeVisible) 1f else 0f,
        animationSpec = tween(durationMillis = 450, easing = EaseOut),
        label = "injectedReelChromeAlpha",
    )
    fun revealChrome() {
        chromeHideJob?.cancel()
        landscapeChromeVisible = true
        landscapeChromePresent = true
        if (!isLandscape) return
        chromeHideJob = chromeScope.launch {
            delay(3000)
            landscapeChromeVisible = false
            // 0.55s after the fade started the transient row leaves layout.
            delay(550)
            landscapeChromePresent = false
        }
    }

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
            // Chrome reappears for each new reel; rotating back to portrait pins
            // it visible with the pending hide task cancelled.
            LaunchedEffect(isLandscape, pagerState.currentPage) { revealChrome() }
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
                if (item.tmdbId > 0) social.refreshCounts(item.tmdbId.toString())
            }
            VerticalPager(state = pagerState, modifier = Modifier.fillMaxSize()) { page ->
                val reel = reels[page]
                val isCurrent = page == pagerState.currentPage
                val isSaved = userStreams.any { it.titleId == reel.tmdbId.toString() }
                val isWatched = watchedIds.contains(reel.tmdbId.toString())
                val tid = reel.tmdbId.toString()
                val reelIsLiked = tid in likedByMe
                val reelLikeCount = likeCounts[tid] ?: 0
                val reelCommentCount = commentCounts[tid] ?: 0
                ReelView(
                    reel = reel,
                    isCurrent = isCurrent,
                    isLandscape = isLandscape,
                    landscapeLeading = landscapeLeading,
                    landscapeTrailing = landscapeTrailing,
                    chromeVisible = landscapeChromeVisible,
                    chromePresent = landscapeChromePresent,
                    chromeAlpha = chromeAlpha,
                    onRevealChrome = { revealChrome() },
                    isPlaying = isPlaying,
                    isMuted = isMuted,
                    isSaved = isSaved,
                    isWatched = isWatched,
                    isLiked = reelIsLiked,
                    likeCount = reelLikeCount,
                    commentCount = reelCommentCount,
                    onLike = {
                        social.toggleLike(
                            titleId = tid,
                            mediaType = if (reel.isTV) "tv" else "movie",
                            tmdbId = reel.tmdbId,
                        )
                        WatchIntentLogger.get().log(
                            WatchIntentLogger.IntentEventType.TRAILER_LIKED,
                            metadata = mapOf("tmdb_id" to reel.tmdbId, "source" to "reels"),
                        )
                    },
                    onComments = { commentsReelTmdb = reel.tmdbId },
                    onMore = { showMoreTmdb = reel.tmdbId },
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
                        if (reel.tmdbId > 0 && !reel.isSponsored) {
                            ShareLinks.share(
                                context,
                                if (reel.isTV) ShareLinks.Kind.TV else ShareLinks.Kind.MOVIE,
                                reel.tmdbId.toString(),
                                reel.showName,
                            )
                            WatchIntentLogger.get().log(
                                WatchIntentLogger.IntentEventType.SHARE_TAPPED,
                                titleId = reel.tmdbId.toString(),
                                metadata = mapOf(
                                    "surface" to "reels_trailer",
                                    "kind" to if (reel.isTV) "tv" else "movie",
                                ),
                            )
                        }
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
            commentsReelTmdb?.let { openedTmdb ->
                val openedReel = reels.firstOrNull { it.tmdbId == openedTmdb } ?: reels.getOrNull(pagerState.currentPage)
                if (openedReel != null && openedTmdb > 0) {
                    TitleCommentsSheet(
                        titleId = openedTmdb.toString(),
                        title = openedReel.showName,
                        subtitle = openedReel.genre,
                        posterUrl = openedReel.posterUrl,
                        onDismiss = { commentsReelTmdb = null },
                    )
                } else if (openedTmdb <= 0) {
                    commentsReelTmdb = null
                }
            }
            showMoreTmdb?.let { openedTmdb ->
                val openedReel = reels.firstOrNull { it.tmdbId == openedTmdb } ?: reels.getOrNull(pagerState.currentPage)
                if (openedReel != null) {
                    ReelMoreSheet(
                        commentCount = if (openedTmdb > 0) (commentCounts[openedTmdb.toString()] ?: 0) else 0,
                        onDismiss = { showMoreTmdb = null },
                        onComment = {
                            showMoreTmdb = null
                            if (openedTmdb > 0) commentsReelTmdb = openedTmdb
                        },
                        onShare = {
                            showMoreTmdb = null
                            if (openedReel.tmdbId > 0 && !openedReel.isSponsored) {
                                ShareLinks.share(
                                    context,
                                    if (openedReel.isTV) ShareLinks.Kind.TV else ShareLinks.Kind.MOVIE,
                                    openedReel.tmdbId.toString(),
                                    openedReel.showName,
                                )
                                WatchIntentLogger.get().log(
                                    WatchIntentLogger.IntentEventType.SHARE_TAPPED,
                                    titleId = openedReel.tmdbId.toString(),
                                    metadata = mapOf(
                                        "surface" to "reels_trailer",
                                        "kind" to if (openedReel.isTV) "tv" else "movie",
                                    ),
                                )
                            }
                        },
                        onPlayYoutube = {
                            showMoreTmdb = null
                            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(openedReel.youtubeUrl)))
                        },
                    )
                }
            }
            // Top overlay: dismiss chevron only (no category pills).
            // statusBarsPadding keeps the tap target below the system status bar
            // so the status bar doesn't swallow the tap. Not composed at all once
            // the landscape chrome has faded, so taps fall through to the reel.
            if (chromeAlpha > 0.01f) {
            Box(
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .statusBarsPadding()
                    .padding(
                        start = if (isLandscape) landscapeLeading else 12.dp,
                        end = 12.dp,
                        top = 12.dp,
                        bottom = 12.dp,
                    )
                    .alpha(chromeAlpha)
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
}

/**
 * Compact count formatter mirroring [SocialCounterRow]'s formatCount (K/M with
 * one decimal) so the reel rail labels match the detail-screen counter row.
 */
private fun formatReelCount(n: Int): String = when {
    n >= 1_000_000 -> String.format(Locale.US, "%.1fM", n / 1_000_000.0)
    n >= 1_000 -> String.format(Locale.US, "%.1fK", n / 1_000.0)
    else -> n.toString()
}

/**
 * Slide-up More sheet for the reels rail — a Material3 ModalBottomSheet with
 * Comment, Share, and Play on YouTube rows. Closes itself and dispatches to
 * the screen-level comment sheet, share intent, or YouTube handoff.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReelMoreSheet(
    commentCount: Int,
    onDismiss: () -> Unit,
    onComment: () -> Unit,
    onShare: () -> Unit,
    onPlayYoutube: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = SheetSurfaceBase,
        scrimColor = Color.Black.copy(alpha = 0.60f),
        tonalElevation = 0.dp,
        dragHandle = { GsSheetDragHandle(level = SheetLevel.Base) },
        contentWindowInsets = { sheetTopInset() },
    ) {
        Column(Modifier.navigationBarsPadding()) {
            GsSheetHeader(title = "More")
            // Comment row
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onComment() }
                    .padding(horizontal = 20.dp, vertical = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    imageVector = Icons.Outlined.ChatBubbleOutline,
                    contentDescription = null,
                    tint = TextPrimary,
                    modifier = Modifier.size(24.dp),
                )
                Spacer(Modifier.width(14.dp))
                Text(
                    text = "Comment",
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Medium,
                    color = TextPrimary,
                )
                Spacer(Modifier.weight(1f))
                Text(
                    text = formatReelCount(commentCount),
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                    color = TextSecondary,
                )
            }
            // Share row
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onShare() }
                    .padding(horizontal = 20.dp, vertical = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    imageVector = Icons.Filled.Share,
                    contentDescription = null,
                    tint = TextPrimary,
                    modifier = Modifier.size(24.dp),
                )
                Spacer(Modifier.width(14.dp))
                Text(
                    text = "Share",
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Medium,
                    color = TextPrimary,
                )
            }
            // Play on YouTube row
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onPlayYoutube() }
                    .padding(horizontal = 20.dp, vertical = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    imageVector = Icons.Filled.PlayArrow,
                    contentDescription = null,
                    tint = TextPrimary,
                    modifier = Modifier.size(24.dp),
                )
                Spacer(Modifier.width(14.dp))
                Text(
                    text = "Play on YouTube",
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Medium,
                    color = TextPrimary,
                )
            }
            Spacer(Modifier.height(16.dp))
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
/**
 * iOS-style "Watch" pill: orange capsule with a play icon and bold white text.
 * Tapping the pill opens the show detail or, in the reels feed, the YouTube trailer.
 */
@Composable
private fun PlayOnPill(onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(26.dp))
            .background(BrandOrange)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() }
            .padding(horizontal = 22.dp, vertical = 13.dp),
        contentAlignment = Alignment.Center,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                imageVector = Icons.Filled.PlayArrow,
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier.size(18.dp),
            )
            Spacer(Modifier.width(6.dp))
            Text(
                text = "Watch",
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
            )
        }
    }
}

/**
 * iOS-style thin video scrubber. An orange thumb moves along a translucent
 * track; tapping or dragging anywhere on the track seeks the player.
 */
@Composable
private fun ReelScrubber(
    progress: Float,
    onSeek: (fraction: Float) -> Unit,
    modifier: Modifier = Modifier,
) {
    val density = LocalDensity.current
    BoxWithConstraints(
        modifier = modifier.height(6.dp),
        contentAlignment = Alignment.CenterStart,
    ) {
        val trackWidth = maxWidth
        // Track
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(6.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.18f)),
        )
        // Progress fill
        Box(
            modifier = Modifier
                .width(trackWidth * progress)
                .height(6.dp)
                .clip(CircleShape)
                .background(BrandOrange),
        )
        // Orange thumb at the current position
        val thumbX = with(density) { (trackWidth * progress - 3.dp).toPx() }.toInt()
        Box(
            modifier = Modifier
                .offset { IntOffset(thumbX, 0) }
                .size(6.dp)
                .clip(CircleShape)
                .background(BrandOrange),
        )
        // Wider, invisible hit target for tapping and dragging.
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(32.dp)
                .pointerInput(Unit) {
                    detectHorizontalDragGestures(
                        onDragStart = { offset ->
                            onSeek((offset.x / size.width.toFloat()).coerceIn(0f, 1f))
                        },
                        onHorizontalDrag = { change, _ ->
                            onSeek((change.position.x / size.width.toFloat()).coerceIn(0f, 1f))
                        },
                    )
                },
        )
    }
}

private fun isUsableReelUrl(url: String?): Boolean {
    if (url.isNullOrBlank()) return false
    val lower = url.lowercase()
    if (!lower.contains("://")) return false
    if (lower.contains("deeplinks available") || lower.contains("paid plan")) return false
    return true
}

/**
 * Platform / genre / video-type chips. Shared verbatim by the portrait stacked
 * block and the landscape row so the chips are pixel-identical in both.
 */
@Composable
private fun ReelChipsRow(reel: TrailerItem, injected: Boolean) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(6.dp))
                .background(
                    if (reel.isSponsored) reel.platformColor.copy(alpha = 0.25f) else reel.platformColor
                )
                .padding(horizontal = 10.dp, vertical = 5.dp),
        ) {
            Text(
                text = reel.platformName,
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
            )
        }
        Spacer(Modifier.width(8.dp))
        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(6.dp))
                .background(Color.White.copy(alpha = if (reel.isSponsored) 0.06f else 0.12f))
                .border(1.dp, Color.White.copy(alpha = if (reel.isSponsored) 0.10f else 0.20f), RoundedCornerShape(6.dp))
                .padding(horizontal = 10.dp, vertical = 5.dp),
        ) {
            Text(
                text = reel.genre,
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White.copy(alpha = if (reel.isSponsored) 0.75f else 1f),
            )
        }
        if (!reel.videoType.isNullOrBlank() && (injected || !reel.videoType.equals("Trailer", ignoreCase = true))) {
            Spacer(Modifier.width(8.dp))
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(6.dp))
                    .background(Color.White.copy(alpha = 0.12f))
                    .border(1.dp, Color.White.copy(alpha = 0.20f), RoundedCornerShape(6.dp))
                    .padding(horizontal = 10.dp, vertical = 5.dp),
            ) {
                Text(
                    text = reel.videoType,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                )
            }
        }
    }
}

/**
 * The action buttons in the one canonical order — Like, Save, Watched, More for
 * normal reels; Save, Share for sponsored ones. Portrait stacks them vertically
 * at 20dp icons, landscape lays them out horizontally at 19dp. The caller owns
 * the container, so the same set serves both orientations.
 */
@Composable
private fun ReelRailButtons(
    reel: TrailerItem,
    isLiked: Boolean,
    likeCount: Int,
    isSaved: Boolean,
    isWatched: Boolean,
    onLike: () -> Unit,
    onToggleSave: () -> Unit,
    onToggleWatched: () -> Unit,
    onMore: () -> Unit,
    onShare: () -> Unit,
    iconSize: Dp = 20.dp,
) {
    if (reel.tmdbId > 0) {
        // Like
        RailButton(
            icon = if (isLiked) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
            label = formatReelCount(likeCount),
            tint = if (isLiked) Color(0xFFFF3B5C) else TextPrimary,
            iconSize = iconSize,
            onClick = onLike,
        )
        // List (Save)
        RailButton(
            icon = if (isSaved) Icons.Filled.Check else Icons.Filled.Add,
            label = if (isSaved) "Saved" else "Save",
            tint = BrandOrange,
            iconSize = iconSize,
            onClick = onToggleSave,
        )
        // Watched
        RailButton(
            icon = Icons.Filled.Visibility,
            label = if (isWatched) "Watched" else "Watched?",
            tint = if (isWatched) BrandBlue else TextPrimary,
            iconSize = iconSize,
            onClick = onToggleWatched,
        )
        // More
        RailButton(
            icon = Icons.Filled.MoreHoriz,
            label = "More",
            tint = TextPrimary,
            iconSize = iconSize,
            onClick = onMore,
        )
    } else {
        // Sponsored reels: Save + Share only
        RailButton(
            icon = if (isSaved) Icons.Filled.Check else Icons.Filled.Add,
            label = if (isSaved) "Saved" else "Save",
            tint = BrandOrange,
            iconSize = iconSize,
            onClick = onToggleSave,
        )
        RailButton(
            icon = Icons.Filled.Share,
            label = "Share",
            tint = TextPrimary,
            iconSize = iconSize,
            onClick = onShare,
        )
    }
}

@Composable
private fun RailButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    tint: Color,
    onClick: () -> Unit,
    /** Glyph size only. The 48dp tap target and 11sp label never change. */
    iconSize: Dp = 20.dp,
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            modifier = Modifier
                .size(48.dp)
                .clip(CircleShape)
                .background(Color.Transparent)
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
                    .size(iconSize)
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
            color = Color.White,
            fontWeight = FontWeight.SemiBold,
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
 * Mirrors iOS resolveGlassAds: hard filter — returns only pool entries whose
 * serviceId != currentPlatform and that are not in selected. When that set
 * is empty ReelAdCarousel falls back to a native-ad-only slot instead of
 * rendering affiliate cards. Rotates by shift = abs(tmdbId) % eligible.size
 * so different titles lead with different services.
 * titles lead with different services.
 */
private fun resolveReelAds(
    currentPlatform: String,
    selected: Set<String>,
    tmdbId: Int,
    count: Int = 8,
): List<Triple<String, String, String>> {
    val current = currentPlatform.lowercase()
    val owned = selected.map { it.lowercase() }.toSet()
    val eligible = reelAdPool.filter { it.first != current && it.first !in owned }
    if (eligible.isEmpty()) return emptyList()
    val shift = abs(tmdbId) % eligible.size
    val rotated = eligible.drop(shift) + eligible.take(shift)
    return rotated.take(count)
}

/**
 * Compact reel affiliate carousel that mirrors the iOS adCarousel. Renders a
 * HorizontalPager of [ReelAffiliateCard] items with dot indicators beneath.
 * Fades in after a short delay only while the reel is the current page, logs
 * a single AD_IMPRESSION on first show, and auto-advances every 5.5s.
 *
 * When no affiliate offer is eligible (every pool service is owned or is
 * the reel's own platform), a 3-page native-ad pager replaces the affiliate
 * carousel: a failed page collapses to a transparent spacer, dots render
 * only while at least one page can still fill, and the pager auto-advances
 * on the same 5.5s cadence.
 */
@Composable
private fun ReelAdCarousel(
    reel: TrailerItem,
    isCurrent: Boolean,
    maxWidth: Dp? = null,
) {
    val auth = AuthViewModel.get()
    val selectedServices by auth.selectedServices.collectAsStateWithLifecycle()
    val offers = remember(reel.id, selectedServices) {
        resolveReelAds(reel.platformId, selectedServices, reel.tmdbId)
    }
    var dismissed by remember(reel.id) { mutableStateOf(false) }
    var visible by remember(reel.id) { mutableStateOf(false) }
    val nativeAdFailed = remember(reel.id) { mutableStateMapOf<Int, Boolean>() }
    val nativeImpressionLogged = remember(reel.id) { mutableStateMapOf<Int, Boolean>() }

    LaunchedEffect(isCurrent) {
        visible = false
        if (isCurrent) {
            delay(600)
            visible = true
        }
    }

    LaunchedEffect(reel.id, visible) {
        if (visible && offers.isNotEmpty()) {
            WatchIntentLogger.get().log(
                WatchIntentLogger.IntentEventType.AD_IMPRESSION,
                metadata = mapOf(
                    "ad_type" to "reel_ad_carousel",
                    "source" to "reel_ad_carousel",
                ),
            )
        }
    }

    if (dismissed || !isCurrent || !visible) return

    if (offers.isEmpty()) {
        // Native-only path: every affiliate offer would advertise an owned or
        // current-platform service. A 3-page native-ad pager replaces the
        // affiliate carousel — a failed page collapses to a transparent 96dp
        // spacer so the pager geometry stays stable, dots render only while
        // at least one page can still fill, and the pager auto-advances on
        // the same 5.5s cadence as the affiliate path.
        val nativePagerState = rememberPagerState(pageCount = { 3 })

        LaunchedEffect(reel.id, visible, isCurrent) {
            if (!visible || dismissed || !isCurrent) return@LaunchedEffect
            while (visible && !dismissed && isCurrent) {
                delay(5500)
                if (nativePagerState.isScrollInProgress) continue
                nativePagerState.animateScrollToPage((nativePagerState.currentPage + 1) % 3)
            }
        }

        Column(modifier = Modifier.alpha(0.83f).let { m ->
            if (maxWidth != null) m.widthIn(max = maxWidth) else m
        }) {
            HorizontalPager(
                state = nativePagerState,
                modifier = Modifier.fillMaxWidth(),
            ) { page ->
                if (nativeAdFailed[page] == true) {
                    Spacer(Modifier.height(96.dp))
                } else {
                    ReelAdChip(onDismiss = { dismissed = true }) {
                        NativeAdCard(
                            feedStyle = true,
                            onAdFailedToLoad = { nativeAdFailed[page] = true },
                        )
                    }
                    // Log native impression once when the page first shows.
                    LaunchedEffect(nativePagerState.currentPage, page) {
                        if (nativePagerState.currentPage == page && nativeImpressionLogged[page] != true) {
                            nativeImpressionLogged[page] = true
                            WatchIntentLogger.get().log(
                                WatchIntentLogger.IntentEventType.AD_IMPRESSION,
                                metadata = mapOf(
                                    "ad_type" to "native",
                                    "source" to "reel_ad_carousel",
                                ),
                            )
                        }
                    }
                }
            }
            if ((0 until 3).any { nativeAdFailed[it] != true }) {
                Spacer(Modifier.height(6.dp))
                Row(
                    horizontalArrangement = Arrangement.spacedBy(5.dp),
                    modifier = Modifier.padding(start = 2.dp),
                ) {
                    repeat(3) { idx ->
                        Box(
                            modifier = Modifier
                                .size(5.dp)
                                .clip(CircleShape)
                                .background(
                                    if (idx == nativePagerState.currentPage) BrandOrange
                                    else Color.White.copy(alpha = 0.28f),
                                ),
                        )
                    }
                }
            }
        }
        return
    }

    val pagerState = rememberPagerState(pageCount = { offers.size })

    // Auto-advance the carousel on the same 5.5s cadence as iOS. A manual
    // swipe skips that cycle (isScrollInProgress) and the timer resumes from
    // wherever the user lands; the effect restarts when the reel, its
    // visibility, or the offer count changes.
    LaunchedEffect(reel.id, visible, offers.size) {
        if (!visible || dismissed || !isCurrent || offers.size <= 1) return@LaunchedEffect
        while (visible && !dismissed && isCurrent && offers.size > 1) {
            delay(5500)
            if (pagerState.isScrollInProgress) continue
            pagerState.animateScrollToPage((pagerState.currentPage + 1) % pagerState.pageCount)
        }
    }

    Column(modifier = Modifier.alpha(0.83f).let { m ->
        if (maxWidth != null) m.widthIn(max = maxWidth) else m
    }) {
        HorizontalPager(
            state = pagerState,
            modifier = Modifier.fillMaxWidth(),
        ) { page ->
            if (page in setOf(1, 2, 4, 5, 7) && nativeAdFailed[page] != true) {
                ReelAdChip(onDismiss = { dismissed = true }) {
                    NativeAdCard(
                        feedStyle = true,
                        onAdFailedToLoad = { nativeAdFailed[page] = true },
                    )
                }
                // Log native impression once when the page first shows.
                LaunchedEffect(pagerState.currentPage, page) {
                    if (pagerState.currentPage == page && nativeImpressionLogged[page] != true) {
                        nativeImpressionLogged[page] = true
                        WatchIntentLogger.get().log(
                            WatchIntentLogger.IntentEventType.AD_IMPRESSION,
                            metadata = mapOf(
                                "ad_type" to "native",
                                "source" to "reel_ad_carousel",
                            ),
                        )
                    }
                }
            } else {
                ReelAffiliateCard(
                    offer = offers[page],
                    reel = reel,
                    onDismiss = { dismissed = true },
                )
            }
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
 * The 96dp inline ad chip that hosts one Reels carousel page. Surface, border
 * and close control live here so the affiliate and banner presentations sit in
 * an identically sized box — the same chip the inline slots draw, so Reels no
 * longer has an ad format of its own.
 */
@Composable
private fun ReelAdChip(
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(96.dp)
            .clip(RoundedCornerShape(14.dp))
            // Translucent, not the opaque SurfaceElevated the other inline
            // slots use — this chip sits over a playing trailer and the frame
            // behind it has to stay visible.
            .background(Color.Black.copy(alpha = 0.44f))
            .border(1.dp, GlassStroke, RoundedCornerShape(14.dp)),
    ) {
        content()

        // Close — drawn above the card so its tap never opens the offer.
        Box(
            modifier = Modifier
                // 44dp target for the Material minimum; the glyph still reads
                // as a small X because the box is transparent.
                .align(Alignment.TopEnd)
                .size(44.dp)
                .clip(CircleShape)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) { onDismiss() },
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Rounded.Close,
                contentDescription = "Hide this ad",
                tint = Color.White.copy(alpha = 0.55f),
                modifier = Modifier.size(15.dp),
            )
        }
    }
}

/**
 * Affiliate page of the reel carousel, drawn as the shared 96dp chip: a flush
 * 96dp creative, up to three lines of headline and an "advertiser · Sponsored"
 * line. Tapping opens the Rakuten affiliate link and logs
 * AFFILIATE_LINK_TAPPED — same destination and same event as before.
 */
@Composable
private fun ReelAffiliateCard(
    offer: Triple<String, String, String>,
    reel: TrailerItem,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val service = StreamingCatalog.service(offer.first)

    ReelAdChip(onDismiss = onDismiss) {
        RakutenAffiliatePresentation(
            service = service,
            headline = offer.second,
            subtitle = offer.third,
            feedStyle = true,
            onClick = {
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
        )
    }
}

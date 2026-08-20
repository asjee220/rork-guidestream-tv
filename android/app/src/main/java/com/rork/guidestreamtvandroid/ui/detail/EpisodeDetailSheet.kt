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
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.outlined.NotificationsNone
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rork.guidestreamtvandroid.data.models.Platform
import com.rork.guidestreamtvandroid.data.models.StreamingCatalog
import com.rork.guidestreamtvandroid.data.models.TitleId
import com.rork.guidestreamtvandroid.data.remote.TMDBService
import com.rork.guidestreamtvandroid.data.remote.WatchmodeResolveResponse
import com.rork.guidestreamtvandroid.data.remote.WatchmodeResolveService
import com.rork.guidestreamtvandroid.data.remote.WatchmodeSrc
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.data.repository.ReleaseReminderService
import com.rork.guidestreamtvandroid.data.repository.SocialViewModel
import com.rork.guidestreamtvandroid.data.repository.StreamsViewModel
import com.rork.guidestreamtvandroid.data.repository.CoachMarkManager
import com.rork.guidestreamtvandroid.data.repository.WatchIntentLogger
import com.rork.guidestreamtvandroid.ui.components.CoachMarkOverlay
import com.rork.guidestreamtvandroid.ui.ads.PooledAdSource
import com.rork.guidestreamtvandroid.ui.ads.SponsoredSlot
import com.rork.guidestreamtvandroid.ui.ads.inlineAdPool
import com.rork.guidestreamtvandroid.ui.cast.CastToTVSheet
import com.rork.guidestreamtvandroid.ui.comments.TitleCommentsSheet
import com.rork.guidestreamtvandroid.ui.components.CircleAction
import com.rork.guidestreamtvandroid.ui.components.GsSheetDragHandle
import com.rork.guidestreamtvandroid.ui.components.GsSheetHeader
import com.rork.guidestreamtvandroid.ui.components.RemoteImage
import com.rork.guidestreamtvandroid.ui.components.SocialCounterRow
import com.rork.guidestreamtvandroid.ui.navigation.PendingTitleRoute
import com.rork.guidestreamtvandroid.ui.theme.BrandBlue
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.Hairline
import com.rork.guidestreamtvandroid.ui.theme.SheetLevel
import com.rork.guidestreamtvandroid.ui.theme.SheetSurfaceBase
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.sheetTopInset
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.util.Locale
import kotlin.math.roundToInt

/**
 * Quick-look bottom sheet for a title — Android port of iOS `EpisodeDetailSheet`.
 *
 * Two layouts share the same header. Titles that arrived from the "Coming to
 * Streaming" rail ([PendingTitleRoute.isComingToStreaming]) get a reduced body
 * with just Notify + Share and the synopsis, because there is nothing to watch
 * yet. Every other title gets the full body: Watched / Share / Send to TV
 * circle actions, the Where to Watch chip row, the orange watch CTA with the
 * watchlist circle, an availability caption, and a "Full details" pill that
 * pushes on to [ShowDetailScreen].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EpisodeDetailSheet(
    route: PendingTitleRoute,
    onDismiss: () -> Unit,
    onFullDetails: (PendingTitleRoute) -> Unit,
) {
    val context = LocalContext.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    val streamsVm = StreamsViewModel.get()
    val socialVm = SocialViewModel.get()
    val authVm = AuthViewModel.get()
    val reminders = ReleaseReminderService.get()
    val coachMark = CoachMarkManager.get()

    val tmdbId = TitleId.tmdbId(route.titleId)
    val isTV = route.isTv
    val titleName = route.titleName?.takeIf { it.isNotBlank() }

    /**
     * Social scope key — the bare TMDB id when resolvable so likes and comments
     * line up with every other surface, otherwise a slug of the title so
     * creator-style ids still get a stable home.
     */
    val socialKey = remember(route.titleId, titleName) {
        tmdbId?.toString() ?: WatchIntentLogger.get().titleSlug(titleName ?: route.titleId)
    }

    val userStreams by streamsVm.userStreams.collectAsStateWithLifecycle()
    val watchedIds by streamsVm.watchedIds.collectAsStateWithLifecycle()
    val likeCounts by socialVm.likeCounts.collectAsStateWithLifecycle()
    val likedByMe by socialVm.likedByMe.collectAsStateWithLifecycle()
    val commentCounts by socialVm.commentCounts.collectAsStateWithLifecycle()
    val remindedIds by reminders.remindedTitleIds.collectAsStateWithLifecycle()
    val selectedServices by authVm.selectedServices.collectAsStateWithLifecycle()

    var detail by remember { mutableStateOf<TMDBService.TMDBTVDetail?>(null) }
    var usSources by remember { mutableStateOf<List<WatchmodeSrc>>(emptyList()) }
    var selectedSource by remember { mutableStateOf<WatchmodeSrc?>(null) }
    var episodeSource by remember { mutableStateOf<WatchmodeSrc?>(null) }
    var isResolvingSources by remember { mutableStateOf(false) }
    var showComments by remember { mutableStateOf(false) }
    var showCast by remember { mutableStateOf(false) }
    var adDismissed by remember(route.titleId) { mutableStateOf(false) }

    val isSaved = userStreams.any { it.titleId == route.titleId }
    val isWatched = watchedIds.contains(route.titleId)
    val reminderKey = tmdbId?.toString().orEmpty()
    val isReminded = reminderKey.isNotEmpty() && remindedIds.contains(reminderKey)

    val isSourceSubscribed: (String) -> Boolean = { name ->
        val n = name.lowercase().filter { it.isLetterOrDigit() }
        StreamingCatalog.ordered(selectedServices).any { svc ->
            val s = svc.name.lowercase().filter { it.isLetterOrDigit() }
            s.isNotEmpty() && (n.contains(s) || s.contains(n))
        }
    }

    val displayTitle = detail?.name?.takeIf { it.isNotBlank() } ?: titleName ?: "Title"
    val posterUrl = route.posterUrl
        ?: detail?.posterPath?.let { path ->
            "https://image.tmdb.org/t/p/w342${if (path.startsWith("/")) path else "/$path"}"
        }

    LaunchedEffect(socialKey) { socialVm.refreshCounts(socialKey) }

    LaunchedEffect(reminderKey, route.isComingToStreaming) {
        if (route.isComingToStreaming && reminderKey.isNotEmpty()) {
            reminders.refreshReminded(reminderKey)
        }
    }

    LaunchedEffect(tmdbId, isTV) {
        val tid = tmdbId ?: return@LaunchedEffect
        detail = try {
            withContext(Dispatchers.IO) {
                if (isTV) TMDBService.get().getTVDetail(tid) else TMDBService.get().getMovieDetail(tid)
            }
        } catch (_: Exception) {
            null
        }
    }

    // Streaming sources are pointless for a title that has not landed yet, so
    // the coming-to-streaming layout skips the Watchmode round trip entirely.
    LaunchedEffect(tmdbId, isTV, detail?.id, route.isComingToStreaming) {
        val tid = tmdbId ?: return@LaunchedEffect
        if (route.isComingToStreaming) return@LaunchedEffect
        if (isTV && detail == null) return@LaunchedEffect
        isResolvingSources = true
        val response = try {
            withContext(Dispatchers.IO) {
                WatchmodeResolveService.resolve(
                    tid, isTV,
                    subscribedServices = StreamingCatalog.ordered(selectedServices).map { it.name },
                    season = if (isTV) detail?.lastEpisodeToAir?.seasonNumber else null,
                    episode = if (isTV) detail?.lastEpisodeToAir?.episodeNumber else null,
                )
            }
        } catch (_: Exception) {
            WatchmodeResolveResponse()
        }
        usSources = response.usSources
        episodeSource = response.episodeSource
        selectedSource = response.primarySource
            ?: response.usSources.firstOrNull {
                isSourceSubscribed(it.name) && it.type.lowercase() in setOf("sub", "free", "tve")
            }
            ?: response.usSources.firstOrNull()
        isResolvingSources = false

        // Start the sheet coach-mark tour once sources have resolved and the
        // sheet is showing the full (non-coming-soon) layout. Guard on
        // !isShowing so nested sheets don't double-trigger.
        if (!route.isComingToStreaming && coachMark.shouldStartSheetTour(sourcesResolved = true)) {
            coachMark.startSheetTour()
        }
    }

    val serviceLabel = selectedSource?.name
    val platformColor = serviceLabel?.let { Platform.from(it)?.color } ?: BrandOrange

    val sheetScrollState = rememberScrollState()
    val density = LocalDensity.current

    // Root-coordinate top of the sheet's scroll viewport. measuredRects are
    // in root coordinates, NOT scroll-content offsets, so the scroll target
    // must be derived: contentOffset = currentScroll + (targetTop - viewportTop).
    // bringIntoView is unreliable inside ModalBottomSheet's nested-scroll
    // chain, so the scroll is driven on sheetScrollState directly.
    var scrollViewportTop by remember { mutableFloatStateOf(0f) }

    // Coach-mark scroll coordination: when the sheet tour requests a scroll,
    // scroll the target row into the upper part of the viewport, then settle
    // after 350ms so the overlay measures the target at its resting position.
    LaunchedEffect(coachMark.isShowing, coachMark.currentMark?.key) {
        if (!coachMark.isShowing) return@LaunchedEffect
        coachMark.currentMark ?: return@LaunchedEffect
        // Only service the SHEET tour — the home tour is handled by HomeScreen.
        if (coachMark.activeTourIsHome) return@LaunchedEffect
        val id = coachMark.scrollRequestId
        if (id == "cmSheetActions" || id == "cmSheetWatch" || id == "cmSheetWatchlist") {
            coachMark.clearScrollRequest()
            val targetKey = when (id) {
                "cmSheetActions" -> "sheet_play_on"
                "cmSheetWatch" -> "sheet_where_to_watch"
                "cmSheetWatchlist" -> "sheet_watchlist"
                else -> null
            }
            val rect = targetKey?.let { key -> coachMark.measuredRects[key] }
            if (rect != null && !rect.isEmpty) {
                val marginPx = with(density) { 96.dp.toPx() }
                val desired = (sheetScrollState.value + (rect.top - scrollViewportTop) - marginPx)
                    .roundToInt()
                    .coerceIn(0, sheetScrollState.maxValue)
                sheetScrollState.animateScrollTo(desired)
            }
            delay(350)
        }
        coachMark.markScrollSettled()
    }

    // Dismiss the active sheet tour when the sheet itself is dismissed.
    LaunchedEffect(sheetState.isVisible) {
        if (!sheetState.isVisible) {
            coachMark.handleBackground()
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = SheetSurfaceBase,
        scrimColor = Color.Black.copy(alpha = 0.60f),
        tonalElevation = 0.dp,
        dragHandle = { GsSheetDragHandle(level = SheetLevel.Base) },
        contentWindowInsets = { sheetTopInset() },
    ) {
        // iOS .presentationDetents([.fraction(0.8), .large]) → cap Android sheet at 80%
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .fillMaxHeight(0.8f)
                .navigationBarsPadding()
                .onGloballyPositioned { coords ->
                    scrollViewportTop = coords.boundsInRoot().top
                },
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .fillMaxHeight()
                    .verticalScroll(sheetScrollState)
                    .padding(bottom = 28.dp),
            ) {
            // ── Header ────────────────────────────────────────────────
            val genre = detail?.genres?.firstOrNull()?.name
            val metaLine = listOfNotNull(
                if (isTV) "Series" else "Movie",
                genre,
                detail?.numberOfSeasons?.takeIf { isTV && it > 0 }?.let { "$it season${if (it == 1) "" else "s"}" },
            ).joinToString(" · ")
            GsSheetHeader(title = displayTitle, subtitle = metaLine)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp)
                    .padding(bottom = 18.dp),
                horizontalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                RemoteImage(
                    url = posterUrl,
                    contentDescription = displayTitle,
                    cornerRadius = 12,
                    placeholderText = displayTitle.take(2).uppercase(Locale.US),
                    modifier = Modifier.width(110.dp).height(150.dp),
                )
                Column(modifier = Modifier.weight(1f)) {
                    if (serviceLabel != null || route.isComingToStreaming) {
                        Spacer(Modifier.height(10.dp))
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(20.dp))
                                .background(if (route.isComingToStreaming) BrandBlue else platformColor)
                                .padding(horizontal = 10.dp, vertical = 5.dp),
                        ) {
                            Text(
                                text = (if (route.isComingToStreaming) "Coming Soon" else serviceLabel.orEmpty())
                                    .uppercase(Locale.US),
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Black,
                                color = Color.White,
                                maxLines = 1,
                            )
                        }
                    }
                    val rating = detail?.voteAverage
                    if (rating != null && rating > 0.0) {
                        Spacer(Modifier.height(10.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                imageVector = Icons.Filled.Star,
                                contentDescription = null,
                                tint = Color(0xFFFFC43D),
                                modifier = Modifier.size(13.dp),
                            )
                            Spacer(Modifier.width(5.dp))
                            Text(
                                text = String.format(Locale.US, "%.1f", rating),
                                fontSize = 13.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = TextPrimary,
                            )
                        }
                    }
                    Spacer(Modifier.height(6.dp))
                    SocialCounterRow(
                        isLiked = likedByMe.contains(socialKey),
                        likeCount = likeCounts[socialKey] ?: 0,
                        commentCount = commentCounts[socialKey] ?: 0,
                        onLike = {
                            socialVm.toggleLike(
                                titleId = socialKey,
                                mediaType = if (isTV) "tv" else "movie",
                                tmdbId = tmdbId,
                            )
                        },
                        onComment = {
                            showComments = true
                            WatchIntentLogger.get().log(
                                WatchIntentLogger.IntentEventType.COMMENTS_OPENED,
                                titleId = socialKey,
                                metadata = mapOf("source" to "episode_detail_sheet"),
                            )
                        },
                    )
                }
            }

            if (route.isComingToStreaming) {
                // ── Coming-soon body: Notify + Share, then the synopsis ──
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp, vertical = 18.dp),
                    horizontalArrangement = Arrangement.Center,
                ) {
                    CircleAction(
                        icon = if (isReminded) Icons.Filled.Notifications else Icons.Outlined.NotificationsNone,
                        label = "Notify",
                        tint = if (isReminded) BrandOrange else TextPrimary,
                        showDot = isReminded,
                        enabled = reminderKey.isNotEmpty(),
                    ) {
                        reminders.toggleReminder(
                            titleId = reminderKey,
                            tmdbId = tmdbId,
                            source = "coming_to_streaming_sheet",
                        )
                    }
                    Spacer(Modifier.width(40.dp))
                    CircleAction(
                        icon = Icons.Filled.Share,
                        label = "Share",
                        tint = TextPrimary,
                        showDot = false,
                    ) {
                        shareTitle(context, displayTitle, tmdbId, isTV)
                    }
                }
                AboutSection(
                    overview = detail?.overview,
                    fallback = "We'll let you know the moment $displayTitle lands on streaming.",
                )
            } else {
                Hairline()

                // ── Watched / Share / Send to TV ─────────────────────
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp, vertical = 18.dp)
                        .onGloballyPositioned { coords ->
                            coachMark.setMeasuredRect("sheet_play_on", coords.boundsInRoot())
                        },
                    horizontalArrangement = Arrangement.SpaceEvenly,
                ) {
                    CircleAction(
                        icon = Icons.Filled.Visibility,
                        label = if (isWatched) "Watched" else "Watched?",
                        tint = if (isWatched) BrandBlue else TextPrimary,
                        showDot = false,
                    ) {
                        streamsVm.toggleWatched(
                            titleId = route.titleId,
                            titleName = displayTitle,
                            mediaType = if (isTV) "tv" else "movie",
                            tmdbId = tmdbId,
                        )
                    }
                    CircleAction(
                        icon = Icons.Filled.Share,
                        label = "Share",
                        tint = TextPrimary,
                        showDot = false,
                    ) {
                        shareTitle(context, displayTitle, tmdbId, isTV)
                    }
                    CircleAction(
                        icon = Icons.Filled.Tv,
                        label = "Send to TV",
                        tint = TextPrimary,
                        showDot = false,
                    ) {
                        showCast = true
                    }
                }

                Hairline()

                // ── Affiliate sponsored slot ─────────────────────
                if (!adDismissed) {
                    val offer = selectAffiliateOffer(
                        currentSourceName = selectedSource?.name,
                        selectedServices = selectedServices,
                    )
                    Box(Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) {
                        SponsoredSlot(
                            preferredSource = PooledAdSource.RAKUTEN_FIRST,
                            service = offer?.let { StreamingCatalog.service(it.first) },
                            serviceId = offer?.first ?: "",
                            headline = offer?.second ?: "",
                            subtitle = offer?.third ?: "",
                            onDismiss = { adDismissed = true },
                            adSource = "episode_detail_sheet",
                            sectionKey = "episode_detail_sheet_ad",
                            allowRakutenFallback = offer != null,
                        )
                    }
                }

                // Column, not Box: WhereToWatchRow emits three siblings
                // (spacer, section title, chip row) — a Box stacks them on
                // top of each other so the title overlaps the chips.
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .onGloballyPositioned { coords ->
                            coachMark.setMeasuredRect("sheet_where_to_watch", coords.boundsInRoot())
                        },
                ) {
                    WhereToWatchRow(
                        sources = usSources,
                        selectedSource = selectedSource,
                        isSourceSubscribed = isSourceSubscribed,
                        onSelect = { selectedSource = it },
                    )
                }

                // ── Watch CTA + watchlist circle ─────────────────────
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp)
                        .padding(top = 20.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.Top,
                ) {
                    if (selectedSource != null || isResolvingSources) {
                        val srcName = selectedSource?.name
                        val srcType = selectedSource?.type?.lowercase().orEmpty()
                        val verb = when {
                            srcType == "rent" -> "Rent on"
                            srcType == "purchase" || srcType == "buy" -> "Buy on"
                            srcType == "sub" && srcName != null && !isSourceSubscribed(srcName) -> "Get on"
                            else -> "Watch on"
                        }
                        val label = if (srcName == null) "Finding service…" else "$verb $srcName"
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .height(54.dp)
                                .clip(RoundedCornerShape(27.dp))
                                .background(BrandOrange)
                                .onGloballyPositioned { coords ->
                                    coachMark.setMeasuredRect("sheet_watch_button", coords.boundsInRoot())
                                }
                                .clickable(
                                    interactionSource = remember { MutableInteractionSource() },
                                    indication = null,
                                    enabled = srcName != null && tmdbId != null,
                                ) {
                                    openWatchTarget(
                                        context = context,
                                        selectedSource = selectedSource,
                                        episodeSource = if (isTV) episodeSource else null,
                                        tmdbId = tmdbId,
                                        isTV = isTV,
                                    )
                                    WatchIntentLogger.get().log(
                                        WatchIntentLogger.IntentEventType.DEEPLINK_FIRED,
                                        titleId = route.titleId,
                                        platformId = srcName?.lowercase(),
                                        metadata = mapOf("source" to "episode_detail_sheet"),
                                    )
                                    streamsVm.markWatchlistSeenIfSaved(route.titleId)
                                    onDismiss()
                                },
                            contentAlignment = Alignment.Center,
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                if (isResolvingSources && srcName == null) {
                                    CircularProgressIndicator(
                                        color = Color.White,
                                        strokeWidth = 2.dp,
                                        modifier = Modifier.size(16.dp),
                                    )
                                    Spacer(Modifier.width(8.dp))
                                } else {
                                    Icon(
                                        imageVector = Icons.Filled.PlayArrow,
                                        contentDescription = null,
                                        tint = Color.White,
                                        modifier = Modifier.size(20.dp),
                                    )
                                    Spacer(Modifier.width(6.dp))
                                }
                                Text(
                                    text = label,
                                    fontSize = 15.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = Color.White,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }
                        }
                    }
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Box(
                            modifier = Modifier
                                .size(54.dp)
                                .clip(CircleShape)
                                .onGloballyPositioned { coords ->
                                    coachMark.setMeasuredRect("sheet_watchlist", coords.boundsInRoot())
                                }
                                .then(
                                    if (isSaved) Modifier.border(1.8.dp, Color.White, CircleShape)
                                    else Modifier.background(BrandOrange)
                                )
                                .clickable(
                                    interactionSource = remember { MutableInteractionSource() },
                                    indication = null,
                                ) {
                                    if (isSaved) {
                                        streamsVm.removeFromMyStreams(route.titleId)
                                        WatchIntentLogger.get().log(
                                            WatchIntentLogger.IntentEventType.WATCHLIST_REMOVED,
                                            titleId = route.titleId,
                                        )
                                    } else {
                                        streamsVm.addToMyStreams(
                                            titleId = route.titleId,
                                            title = displayTitle,
                                            posterUrl = posterUrl,
                                            platform = serviceLabel,
                                            isTv = isTV,
                                        )
                                        WatchIntentLogger.get().log(
                                            WatchIntentLogger.IntentEventType.WATCHLIST_ADDED,
                                            titleId = route.titleId,
                                            platformId = serviceLabel?.lowercase(),
                                        )
                                    }
                                },
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(
                                imageVector = if (isSaved) Icons.Filled.Check else Icons.Filled.Add,
                                contentDescription = if (isSaved) "In watch list" else "Add to watch list",
                                tint = Color.White,
                                modifier = Modifier.size(22.dp),
                            )
                        }
                        Spacer(Modifier.height(6.dp))
                        Text(
                            text = if (isSaved) "Saved" else "Watch List",
                            fontSize = 11.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = TextPrimary,
                            maxLines = 1,
                        )
                    }
                }

                // Availability caption — identical wording rules to iOS
                // (nothing rendered for a sub the user already has).
                val src = selectedSource
                if (src != null) {
                    val t = src.type.lowercase()
                    val priceLabel = src.price?.let { String.format(Locale.US, "$%.2f", it) }
                    val caption = when {
                        t == "free" -> "Free on ${src.name}"
                        t == "tve" -> "Available on ${src.name} with a TV provider"
                        t == "sub" -> if (isSourceSubscribed(src.name)) null else "Requires a ${src.name} subscription"
                        t == "rent" -> if (priceLabel != null) "Rent from $priceLabel on ${src.name}" else "Rent on ${src.name}"
                        t == "purchase" || t == "buy" -> if (priceLabel != null) "Buy from $priceLabel on ${src.name}" else "Buy on ${src.name}"
                        else -> null
                    }
                    if (caption != null) {
                        Text(
                            text = caption,
                            fontSize = 13.sp,
                            color = TextSecondary,
                            modifier = Modifier.padding(horizontal = 20.dp, vertical = 6.dp),
                        )
                    }
                }

                // ── Full details pill ────────────────────────────────
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp)
                        .padding(top = 14.dp)
                        .height(44.dp)
                        .clip(RoundedCornerShape(22.dp))
                        .border(1.dp, BrandOrange, RoundedCornerShape(22.dp))
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) {
                            coachMark.handleBackground()
                            onFullDetails(route)
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = Icons.Filled.Info,
                            contentDescription = null,
                            tint = BrandOrange,
                            modifier = Modifier.size(15.dp),
                        )
                        Spacer(Modifier.width(6.dp))
                        Text(
                            text = "Full details",
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Medium,
                            color = BrandOrange,
                        )
                    }
                }

                AboutSection(
                    overview = detail?.overview,
                    fallback = serviceLabel?.let {
                        "Tap Watch on $it to open this title in the streaming app."
                    } ?: "Pick a service above to start watching.",
                )
            }
        }

        CoachMarkOverlay(
            manager = coachMark,
            topInset = 72.dp,
            bottomInset = 40.dp,
        )
    }
    }

    if (showComments) {
        TitleCommentsSheet(
            titleId = socialKey,
            title = displayTitle,
            subtitle = if (isTV) "Series" else "Movie",
            posterUrl = posterUrl,
            onDismiss = { showComments = false },
        )
    }

    if (showCast) {
        CastToTVSheet(
            onClose = { showCast = false },
            showTitle = displayTitle,
            platform = selectedSource?.name.orEmpty(),
            tmdbId = tmdbId,
            isTV = isTV,
            watchmodeSource = selectedSource,
            episodeRokuUrl = episodeSource?.rokuUrl,
        )
    }
}

/** 1dp inset hairline separator matching the iOS sheet's divider rules. */
@Composable
private fun Hairline() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp)
            .height(1.dp)
            .background(Hairline),
    )
}

/** "ABOUT" caption plus the synopsis, or a service-aware fallback line. */
@Composable
private fun AboutSection(overview: String?, fallback: String) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp)
            .padding(top = 24.dp),
    ) {
        Text(
            text = "ABOUT",
            fontSize = 12.sp,
            fontWeight = FontWeight.Black,
            color = TextPrimary.copy(alpha = 0.45f),
        )
        Spacer(Modifier.height(8.dp))
        Text(
            text = overview?.takeIf { it.isNotBlank() } ?: fallback,
            fontSize = 15.sp,
            color = TextPrimary.copy(alpha = 0.85f),
            lineHeight = 21.sp,
        )
    }
}

/** Fires the platform share sheet with a canonical TMDB link for the title. */
private fun shareTitle(
    context: android.content.Context,
    title: String,
    tmdbId: Int?,
    isTV: Boolean,
) {
    val link = tmdbId?.let { "https://www.themoviedb.org/${if (isTV) "tv" else "movie"}/$it" }
        ?: "https://guidestream.tv"
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_SUBJECT, title)
        putExtra(Intent.EXTRA_TEXT, "Watch $title on GuideStream TV\n$link")
    }
    try {
        context.startActivity(Intent.createChooser(intent, "Share"))
    } catch (_: Exception) {
        // No share target available — nothing to recover from.
    }
}

/**
 * Opens the best available link for the active source: the episode-level
 * Android app link first, then the source's own Android / Android TV / web
 * links, falling back to TMDB's watch page. Placeholder strings returned by
 * Watchmode's free tier are filtered out before we try to launch them.
 */
private fun openWatchTarget(
    context: android.content.Context,
    selectedSource: WatchmodeSrc?,
    episodeSource: WatchmodeSrc?,
    tmdbId: Int?,
    isTV: Boolean,
) {
    val epSrc = episodeSource?.takeIf { it.sourceId == selectedSource?.sourceId }
    val fallback = "https://www.themoviedb.org/${if (isTV) "tv" else "movie"}/${tmdbId ?: 0}/watch"
    val target = listOf(
        epSrc?.androidUrl, epSrc?.androidTvUrl, epSrc?.webUrl,
        selectedSource?.androidUrl, selectedSource?.androidTvUrl, selectedSource?.webUrl,
    ).firstOrNull { isOpenableStreamUrl(it) } ?: fallback
    try {
        val intent = if (target.startsWith("intent:")) {
            Intent.parseUri(target, Intent.URI_INTENT_SCHEME)
        } else {
            Intent(Intent.ACTION_VIEW, Uri.parse(target))
        }
        context.startActivity(intent)
    } catch (_: Exception) {
        try {
            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(fallback)))
        } catch (_: Exception) {
            // No browser installed — nothing further to try.
        }
    }
}

/**
 * Selects an affiliate offer from the pool, mirroring iOS `affiliateAdData`.
 * Hard filter: only a service the user doesn't already have and that isn't
 * the title's current platform. Returns null when every entry is owned —
 * the caller then suppresses the Rakuten card instead of advertising an
 * owned service.
 */
private fun selectAffiliateOffer(
    currentSourceName: String?,
    selectedServices: Set<String>,
): Triple<String, String, String>? {
    val current = normalisedServiceKey(currentSourceName.orEmpty())
    val owned = selectedServices.map { normalisedServiceKey(it) }.toSet()
    return inlineAdPool.firstOrNull { it.first != current && it.first !in owned }
}

/**
 * Normalises a raw service name into a canonical pool key — mirrors iOS
 * `normalisedServiceKey` so the same offer selection logic works on both.
 */
private fun normalisedServiceKey(raw: String): String {
    val k = raw.lowercase()
    if (k.contains("netflix")) return "netflix"
    if (k.contains("max") || k.contains("hbo")) return "hbo"
    if (k.contains("hulu")) return "hulu"
    if (k.contains("disney")) return "disney"
    if (k.contains("apple")) return "appletv"
    if (k.contains("prime") || k.contains("amazon")) return "prime"
    if (k.contains("paramount")) return "paramount"
    if (k.contains("peacock")) return "peacock"
    return k
}

/** True when [url] has a scheme and is not a Watchmode paid-plan placeholder. */
private fun isOpenableStreamUrl(url: String?): Boolean {
    if (url.isNullOrBlank()) return false
    val lower = url.lowercase()
    if (!lower.contains("://") && !lower.startsWith("intent:")) return false
    if (lower.contains("deeplinks available") || lower.contains("paid plan")) return false
    return true
}

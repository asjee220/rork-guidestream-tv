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
import androidx.compose.material.icons.filled.Tv
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
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rork.guidestreamtvandroid.data.ShareLinks
import com.rork.guidestreamtvandroid.data.models.DeepDiveCreator
import com.rork.guidestreamtvandroid.data.models.Platform
import com.rork.guidestreamtvandroid.ui.components.rememberLockOn
import com.rork.guidestreamtvandroid.ui.components.SheetMotion
import com.rork.guidestreamtvandroid.ui.components.PendingWhereToWatchStrip
import com.rork.guidestreamtvandroid.data.models.StreamingCatalog
import com.rork.guidestreamtvandroid.data.models.TitleId
import com.rork.guidestreamtvandroid.data.remote.TMDBService
import com.rork.guidestreamtvandroid.data.remote.WatchmodeResolveResponse
import com.rork.guidestreamtvandroid.data.remote.WatchmodeResolveService
import com.rork.guidestreamtvandroid.data.remote.WatchmodeSrc
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.data.repository.SocialViewModel
import com.rork.guidestreamtvandroid.data.repository.StreamsViewModel
import com.rork.guidestreamtvandroid.data.repository.WatchIntentLogger
import com.rork.guidestreamtvandroid.ui.cast.CastToTVSheet
import com.rork.guidestreamtvandroid.ui.components.CircleAction
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.coroutines.launch
import androidx.compose.runtime.rememberCoroutineScope
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
import com.rork.guidestreamtvandroid.ui.theme.horizontalCutoutInsets

/**
 * Show detail screen — mirrors iOS ShowDetailScreen.swift.
 * Backdrop hero, poster, title, meta, watch button, add/remove watchlist,
 * season/episode browser, overview.
 */
@Composable
fun ShowDetailScreen(
    titleId: String,
    titleName: String,
    isTV: Boolean,
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
    val effectiveIsTV by vm.effectiveIsTV.collectAsStateWithLifecycle()
    val userStreams by streamsVm.userStreams.collectAsStateWithLifecycle()
    val watchedIds by streamsVm.watchedIds.collectAsStateWithLifecycle()

    // Social (likes + comments) state.
    val socialVm = SocialViewModel.get()
    val likeCounts by socialVm.likeCounts.collectAsStateWithLifecycle()
    val likedByMe by socialVm.likedByMe.collectAsStateWithLifecycle()
    val commentCounts by socialVm.commentCounts.collectAsStateWithLifecycle()
    var showComments by remember { mutableStateOf(false) }
    var showCast by remember { mutableStateOf(false) }
    androidx.compose.runtime.LaunchedEffect(titleId) { socialVm.refreshCounts(titleId) }

    val tmdbId = TitleId.tmdbId(titleId)
    val isSaved = userStreams.any { it.titleId == titleId }
    val isWatched = watchedIds.contains(titleId)

    // Streaming-source switcher state. When the user is subscribed to two or
    // more of the title's services, tapping a chip makes it the active source
    // and the Watch button follows the selection.
    val authVm = AuthViewModel.get()
    val selectedServices by authVm.selectedServices.collectAsStateWithLifecycle()
    var usSources by remember { mutableStateOf<List<WatchmodeSrc>>(emptyList()) }
    // True from the very first frame when a lookup is going to happen, so the
    // Where to Watch row is already mounted at its final height rather than
    // appearing a frame later and pushing the page down.
    var isResolvingSources by remember { mutableStateOf(TitleId.tmdbId(titleId) != null) }
    var availabilityRegions by remember { mutableStateOf<List<String>>(emptyList()) }
    var selectedSource by remember { mutableStateOf<WatchmodeSrc?>(null) }
    var episodeSource by remember { mutableStateOf<WatchmodeSrc?>(null) }
    val isSourceSubscribed: (String) -> Boolean = { name ->
        val n = name.lowercase().filter { it.isLetterOrDigit() }
        StreamingCatalog.ordered(selectedServices).any { svc ->
            val s = svc.name.lowercase().filter { it.isLetterOrDigit() }
            s.isNotEmpty() && (n.contains(s) || s.contains(n))
        }
    }
    androidx.compose.runtime.LaunchedEffect(titleId, detail?.id, effectiveIsTV) {
        val tid = TitleId.tmdbId(titleId)
        if (tid != null) {
            if (effectiveIsTV && detail == null) return@LaunchedEffect
            isResolvingSources = true
            val seasonNum = if (effectiveIsTV) detail?.lastEpisodeToAir?.seasonNumber else null
            val episodeNum = if (effectiveIsTV) detail?.lastEpisodeToAir?.episodeNumber else null
            val subscribedNames = StreamingCatalog.ordered(selectedServices).map { it.name }
            val response = try {
                withContext(Dispatchers.IO) {
                    WatchmodeResolveService.resolve(
                        tid, effectiveIsTV,
                        subscribedServices = subscribedNames,
                        season = seasonNum,
                        episode = episodeNum,
                    )
                }
            } catch (_: Exception) {
                WatchmodeResolveResponse()
            }
            usSources = response.usSources
            availabilityRegions = response.availabilityRegions
            episodeSource = response.episodeSource
            selectedSource = response.primarySource
                ?: response.usSources.firstOrNull {
                    isSourceSubscribed(it.name) && it.type.lowercase() in setOf("sub", "free", "tve")
                }
                ?: response.usSources.firstOrNull()
            isResolvingSources = false
        } else {
            isResolvingSources = false
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
        vm.loadIfNeeded(titleId, isTV, expectedTitle = titleName)
    }
    // Trailers & clips — keyed on the healed media type so a legacy TV row
    // that heals to a movie refetches videos from the movie endpoint.
    androidx.compose.runtime.LaunchedEffect(titleId, effectiveIsTV) {
        val tid = TitleId.tmdbId(titleId)
        trailerVideos = if (tid != null) {
            try { TMDBService.get().getTitleVideos(tid, effectiveIsTV) } catch (_: Exception) { emptyList() }
        } else emptyList()
    }
    androidx.compose.runtime.LaunchedEffect(detail?.name) {
        val name = detail?.name
        val tid = TitleId.tmdbId(titleId)
        if (!name.isNullOrBlank() && tid != null) {
            deepVm.load(tid, if (isTV) "tv" else "movie", name)
        }
    }

    val detailScrollState = rememberScrollState()

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
                    .statusBarsPadding()
                    .verticalScroll(detailScrollState),
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
                            .padding(horizontalCutoutInsets())
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
                            .padding(horizontalCutoutInsets())
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
                                    tmdbId = TitleId.tmdbId(titleId),
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
                val scope = androidx.compose.runtime.rememberCoroutineScope()
                // Column, not Box: WhereToWatchRow emits three siblings (spacer,
                // heading, chip row) and Box would stack them on the Z axis,
                // drawing the heading underneath the chips.
                Column(modifier = Modifier.fillMaxWidth()) {
                    WhereToWatchRow(
                        sources = usSources,
                        selectedSource = selectedSource,
                        isSourceSubscribed = isSourceSubscribed,
                        availabilityRegions = availabilityRegions,
                        grouped = true,
                        pending = isResolvingSources,
                        onSelect = { source ->
                            selectedSource = source
                            episodeSource = null
                            val tid = TitleId.tmdbId(titleId)
                            if (tid != null) {
                                val seasonNum = if (effectiveIsTV) detail?.lastEpisodeToAir?.seasonNumber else null
                                val episodeNum = if (effectiveIsTV) detail?.lastEpisodeToAir?.episodeNumber else null
                                scope.launch {
                                    val resp = try {
                                        withContext(Dispatchers.IO) {
                                            WatchmodeResolveService.resolve(
                                                tid, effectiveIsTV,
                                                sourceId = source.sourceId,
                                                season = seasonNum,
                                                episode = episodeNum,
                                            )
                                        }
                                    } catch (_: Exception) {
                                        WatchmodeResolveResponse()
                                    }
                                    withContext(Dispatchers.Main) {
                                        episodeSource = resp.episodeSource
                                    }
                                }
                            }
                        },
                    )
                }

                // Action buttons — two rows: secondary tiles stretch across the
                // first, the Watch CTA + watchlist tile share the second, so all
                // five actions fit without wrapping the Watch label.
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceEvenly,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                    // Watched toggle
                    CircleAction(
                        icon = Icons.Filled.Visibility,
                        label = if (isWatched) "Watched" else "Watched?",
                        tint = if (isWatched) BrandBlue else TextPrimary,
                        showDot = false,
                    ) {
                        streamsVm.toggleWatched(
                            titleId = titleId,
                            titleName = detail?.name ?: titleName,
                            mediaType = if (isTV) "tv" else "movie",
                            tmdbId = tmdbId,
                        )
                    }
                    // Share
                    CircleAction(
                        icon = Icons.Filled.Share,
                        label = "Share",
                        tint = TextPrimary,
                        showDot = false,
                    ) {
                        val tid = tmdbId
                        if (tid != null && tid > 0) {
                            ShareLinks.share(
                                context,
                                if (isTV) ShareLinks.Kind.TV else ShareLinks.Kind.MOVIE,
                                tid.toString(),
                                detail?.name ?: titleName,
                            )
                            WatchIntentLogger.get().log(
                                WatchIntentLogger.IntentEventType.SHARE_TAPPED,
                                titleId = tid.toString(),
                                metadata = mapOf("surface" to "show_detail", "kind" to if (isTV) "tv" else "movie"),
                            )
                        }
                    }
                    // Send to TV
                    CircleAction(
                        icon = Icons.Filled.Tv,
                        label = "Send to TV",
                        tint = TextPrimary,
                        showDot = false,
                        modifier = Modifier,
                    ) { showCast = true }
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        verticalAlignment = Alignment.Top,
                    ) {
                    // Watch button
                    if (topProvider != null || usSources.isNotEmpty()) {
                        // CTA verb mirrors iOS ctaVerb: Rent/Buy for transactional
                        // tiers, Get for unsubscribed subs, Watch otherwise.
                        val srcName = selectedSource?.name
                        val srcType = selectedSource?.type?.lowercase().orEmpty()
                        val watchVerb = when {
                            srcType == "rent" -> "Rent on"
                            srcType == "purchase" || srcType == "buy" -> "Buy on"
                            srcType == "sub" && srcName != null && !isSourceSubscribed(srcName) -> "Get on"
                            else -> "Watch on"
                        }
                        val watchLabel = "$watchVerb " + (
                            selectedSource?.name
                                ?: platform?.name
                                ?: topProvider?.providerName
                                ?: "Streaming"
                        )
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .height(54.dp)
                                .clip(RoundedCornerShape(27.dp))
                                .background(BrandOrange)
                                .clickable(
                                    interactionSource = remember { MutableInteractionSource() },
                                    indication = null,
                                ) {
                                    // Prefer the native Android app link, then the
                                    // Android TV link, then the web URL — episode-level
                                    // source first for TV — with Watchmode placeholder
                                    // strings filtered out. Falls back to TMDB's watch
                                    // page when nothing is usable.
                                    val epSrc = if (isTV) episodeSource?.takeIf { it.sourceId == selectedSource?.sourceId } else null
                                    val fallback = "https://www.themoviedb.org/${if (isTV) "tv" else "movie"}/$tmdbId/watch"
                                    val target = listOf(
                                        epSrc?.androidUrl, epSrc?.androidTvUrl, epSrc?.webUrl,
                                        selectedSource?.androidUrl, selectedSource?.androidTvUrl, selectedSource?.webUrl,
                                    ).firstOrNull { isUsableStreamUrl(it) } ?: fallback
                                    try {
                                        val intent = if (target.startsWith("intent:")) {
                                            Intent.parseUri(target, Intent.URI_INTENT_SCHEME)
                                        } else {
                                            Intent(Intent.ACTION_VIEW, Uri.parse(target))
                                        }
                                        context.startActivity(intent)
                                    } catch (_: Exception) {
                                        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(fallback)))
                                    }
                                    streamsVm.markWatchlistSeenIfSaved(titleId)
                                },
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
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }
                        }
                    }
                    // Add/Remove watchlist
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Box(
                            modifier = Modifier
                                .size(54.dp)
                                .clip(CircleShape)
                                .then(
                                    if (isSaved) {
                                        Modifier.border(1.8.dp, Color.White, CircleShape)
                                    } else {
                                        Modifier.background(BrandOrange)
                                    }
                                )
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
                                            isTv = isTV,
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
                }

                // Availability caption — identical wording rules to iOS
                // availabilityCaption (nothing rendered when sub + subscribed).
                run {
                    val src = selectedSource
                    if (src != null) {
                        val t = src.type.lowercase()
                        val priceLabel = src.price?.let { String.format(java.util.Locale.US, "$%.2f", it) }
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
                                fontSize = 12.sp,
                                color = TextSecondary,
                                modifier = Modifier.padding(horizontal = 16.dp),
                            )
                        }
                    }
                }

                // Trailers & Clips
                TitleTrailersRow(
                    videos = trailerVideos,
                    onTrailerTap = { idx ->
                        val tid = TitleId.tmdbId(titleId) ?: 0
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

        if (showCast) {
            CastToTVSheet(
                onClose = { showCast = false },
                showTitle = detail?.name ?: titleName,
                platform = selectedSource?.name.orEmpty(),
                tmdbId = tmdbId,
                isTV = isTV,
                watchmodeSource = selectedSource,
            )
        }

    }
}

/** Home-region display name, mapped from the literal "US" code (not DeviceLocale). */
private val homeRegionName: String by lazy { regionDisplayName("US") }

/** Localized country name for an ISO region code; raw code on miss. */
private fun regionDisplayName(code: String): String {
    val trimmed = code.trim().uppercase()
    if (trimmed.isEmpty()) return code
    val name = java.util.Locale("", trimmed).displayCountry
    return if (name.isBlank() || name == trimmed) trimmed else name
}

/** Up to three comma-separated country names, then " +N more". */
private fun regionNamesSummary(codes: List<String>): String {
    val names = codes.map { regionDisplayName(it) }
    val shown = names.take(3).joinToString(", ")
    val extra = names.size - 3
    return if (extra > 0) "$shown +$extra more" else shown
}

/**
 * "Where to Watch" chip row. Renders one chip per US streaming source. When the
 * user is subscribed to two or more of the title's services, tapping a
 * subscribed chip makes it the active source (Watch button follows); every
 * other tap opens the source's web URL directly. When there are no US sources
 * but the title streams elsewhere, renders the header plus an unavailable
 * state listing the regions that carry it. Hidden only when there are no
 * sources and no regions.
 */
@Composable
internal fun WhereToWatchRow(
    sources: List<WatchmodeSrc>,
    selectedSource: WatchmodeSrc?,
    isSourceSubscribed: (String) -> Boolean,
    onSelect: (WatchmodeSrc) -> Unit,
    availabilityRegions: List<String> = emptyList(),
    grouped: Boolean = false,
    pending: Boolean = false,
) {
    if (sources.isEmpty() && availabilityRegions.isEmpty() && !pending) return
    Spacer(Modifier.height(8.dp))
    Text(
        text = "Where to Watch",
        fontSize = 17.sp,
        fontWeight = FontWeight.Bold,
        color = TextPrimary,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
    )
    if (sources.isEmpty() && pending) {
        // Reserved Frame: the row holds its final height for the whole lookup,
        // so the CTA and everything below it never move when the sources land.
        // A finished lookup with no sources still collapses — that is a final
        // answer, and the one honest height change on this surface.
        PendingWhereToWatchStrip(Modifier.padding(horizontal = 16.dp))
        return
    }
    if (sources.isEmpty()) {
        // No US sources, but the title streams elsewhere — read as
        // unavailable instead of an empty row.
        Column(Modifier.padding(horizontal = 16.dp)) {
            Text(
                text = "Not available in the $homeRegionName",
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = TextPrimary,
            )
            Text(
                text = "Streaming in ${regionNamesSummary(availabilityRegions)}",
                fontSize = 13.sp,
                color = TextSecondary,
            )
        }
        return
    }
    if (grouped) {
        GroupedWhereToWatch(
            sources = sources,
            selectedSource = selectedSource,
            isSourceSubscribed = isSourceSubscribed,
            onSelect = onSelect,
        )
    } else {
        LazyRow(
            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(sources.size) { index ->
                val source = sources[index]
                WhereToWatchChip(
                    source = source,
                    selected = selectedSource?.sourceId == source.sourceId,
                    subscribed = isSourceSubscribed(source.name),
                    onSelect = onSelect,
                    entryIndex = index,
                )
            }
        }
    }
}

/**
 * Sheet layout for [WhereToWatchRow]: a single "Cheapest tonight" summary
 * above four labelled groups (subscription, free, rent, buy), rent and buy
 * ordered by price ascending with null-priced entries last. Uses only the
 * already-resolved sources — no extra network call.
 */
@Composable
private fun GroupedWhereToWatch(
    sources: List<WatchmodeSrc>,
    selectedSource: WatchmodeSrc?,
    isSourceSubscribed: (String) -> Boolean,
    onSelect: (WatchmodeSrc) -> Unit,
) {
    val groups = whereToWatchGroups(sources)
    val cheapest = sources
        .filter { src ->
            val t = src.type.lowercase()
            (t == "rent" || t == "purchase" || t == "buy") && src.price != null
        }
        .minByOrNull { it.price ?: 0.0 }
    val anySubscribed = sources.any {
        it.type.lowercase() == "sub" && isSourceSubscribed(it.name)
    }
    Column {
        if (cheapest != null && !anySubscribed) {
            CheapestTonightLine(cheapest)
        }
        groups.forEach { (label, groupSources) ->
            Text(
                text = label.uppercase(),
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                color = TextSecondary,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
            )
            LazyRow(
                contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                items(groupSources.size) { index ->
                    val source = groupSources[index]
                    WhereToWatchChip(
                        source = source,
                        selected = selectedSource?.sourceId == source.sourceId,
                        subscribed = isSourceSubscribed(source.name),
                        onSelect = onSelect,
                        entryIndex = index,
                    )
                }
            }
        }
    }
}

/**
 * Single summary line naming the lowest-priced transactional option.
 * Rendered on the literal sheet depth tokens (#1B2739 fill, #2E3E58
 * hairline) rather than theme aliases.
 */
@Composable
private fun CheapestTonightLine(source: WatchmodeSrc) {
    val verb = if (source.type.lowercase() == "rent") "rent" else "buy"
    val priceText = String.format(java.util.Locale.US, "$$%.2f", source.price ?: 0.0)
    Text(
        text = "Cheapest tonight: $priceText $verb on ${source.name}",
        fontSize = 13.sp,
        fontWeight = FontWeight.SemiBold,
        color = Color.White.copy(alpha = 0.85f),
        modifier = Modifier
            .padding(horizontal = 16.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(Color(0xFF1B2739))
            .border(1.dp, Color(0xFF2E3E58), RoundedCornerShape(10.dp))
            .padding(horizontal = 12.dp, vertical = 8.dp),
    )
}

/**
 * Splits sources into the four labelled display groups. `tve` and untyped
 * legacy sources ride with subscription; purchase/buy fold into buy.
 */
private fun whereToWatchGroups(
    sources: List<WatchmodeSrc>,
): List<Pair<String, List<WatchmodeSrc>>> {
    val subscription = mutableListOf<WatchmodeSrc>()
    val free = mutableListOf<WatchmodeSrc>()
    val rent = mutableListOf<WatchmodeSrc>()
    val buy = mutableListOf<WatchmodeSrc>()
    for (source in sources) {
        when (source.type.lowercase()) {
            "free" -> free.add(source)
            "rent" -> rent.add(source)
            "purchase", "buy" -> buy.add(source)
            else -> subscription.add(source) // sub, tve, untyped legacy
        }
    }
    // Price ascending, nulls last.
    val byPrice = Comparator<WatchmodeSrc> { a, b ->
        when {
            a.price != null && b.price != null -> a.price!!.compareTo(b.price!!)
            a.price != null -> -1
            b.price != null -> 1
            else -> 0
        }
    }
    return listOf(
        "Subscription" to subscription,
        "Free" to free,
        "Rent" to rent.sortedWith(byPrice),
        "Buy" to buy.sortedWith(byPrice),
    ).filter { it.second.isNotEmpty() }
}

/**
 * One service chip — identical rendering in the flat and grouped layouts.
 * "Subscribed" tag only for sub-typed sources the user has; transactional
 * tiers always show their tier so a rent/buy brand match never reads as owned.
 */
@Composable
private fun WhereToWatchChip(
    source: WatchmodeSrc,
    selected: Boolean,
    subscribed: Boolean,
    onSelect: (WatchmodeSrc) -> Unit,
    entryIndex: Int = 0,
) {
    val dotColor = Platform.from(source.name)?.color ?: BrandOrange
    // Lock-On: the chip is created at the moment the lookup resolves, so the
    // snap fires on entry rather than on a state change.
    val lock = rememberLockOn(
        resolved = true,
        delayMs = entryIndex * SheetMotion.LOCK_STAGGER_MS,
    )
    Box(
        modifier = Modifier
            .scale(lock.scale)
            .clip(RoundedCornerShape(12.dp))
            .background(dotColor.copy(alpha = if (subscribed) 0.28f else 0.18f))
            .border(
                width = if (selected) 2.dp else 1.dp,
                color = if (selected) dotColor else dotColor.copy(alpha = if (subscribed) 0.70f else 0.45f),
                shape = RoundedCornerShape(12.dp),
            )
            .then(
                if (lock.rimAlpha > 0f) {
                    Modifier.border(
                        1.5.dp,
                        Color.White.copy(alpha = lock.rimAlpha),
                        RoundedCornerShape(12.dp),
                    )
                } else {
                    Modifier
                }
            )
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) {
                onSelect(source)
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
            // Monetization tag: "Subscribed" only for sub-typed sources
            // the user has — a rent/buy brand match never reads as owned.
            val srcTier = source.type.lowercase()
            val priceLabel = source.price?.let { String.format(java.util.Locale.US, "$%.2f", it) }
            val tag = when {
                subscribed && srcTier == "sub" -> "Subscribed"
                srcTier == "rent" -> if (priceLabel != null) "Rent $priceLabel" else "Rent"
                srcTier == "purchase" || srcTier == "buy" -> if (priceLabel != null) "Buy $priceLabel" else "Buy"
                srcTier == "free" -> "Free"
                srcTier == "tve" -> "TV"
                else -> null
            }
            if (tag != null) {
                Spacer(Modifier.width(8.dp))
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(4.dp))
                        .background(
                            if (tag == "Subscribed") Color(0xFF34C759).copy(alpha = 0.85f)
                            else Color.White.copy(alpha = 0.18f),
                        )
                        .padding(horizontal = 6.dp, vertical = 2.dp),
                ) {
                    Text(
                        text = tag,
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

/**
 * True when [url] is an openable link: it must contain a scheme separator and
 * must not be one of Watchmode's free-tier placeholder strings
 * ("Deeplinks available for paid plans only.").
 */
private fun isUsableStreamUrl(url: String?): Boolean {
    if (url.isNullOrBlank()) return false
    val lower = url.lowercase()
    if (!lower.contains("://")) return false
    if (lower.contains("deeplinks available") || lower.contains("paid plan")) return false
    return true
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

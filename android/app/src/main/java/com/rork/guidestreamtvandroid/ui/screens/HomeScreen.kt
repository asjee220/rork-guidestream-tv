package com.rork.guidestreamtvandroid.ui.screens

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import com.rork.guidestreamtvandroid.ui.components.MediaTypeGlyph
import com.rork.guidestreamtvandroid.ui.components.NewEpisodeCard
import com.rork.guidestreamtvandroid.ui.components.newEpisodeShowName
import com.rork.guidestreamtvandroid.data.models.NewEpisodeRow
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import com.rork.guidestreamtvandroid.data.remote.TMDBService
import com.rork.guidestreamtvandroid.data.repository.CoachMarkManager
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import kotlinx.coroutines.delay
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.rork.guidestreamtvandroid.data.models.Platform
import com.rork.guidestreamtvandroid.data.models.SourceKind
import com.rork.guidestreamtvandroid.ui.sports.SportsViewModel
import com.rork.guidestreamtvandroid.ui.home.heroSourceColor
import com.rork.guidestreamtvandroid.ui.home.buildHeroRail
import com.rork.guidestreamtvandroid.ui.home.HeroItem
import com.rork.guidestreamtvandroid.data.models.SportsGame
import com.rork.guidestreamtvandroid.data.models.StreamingCatalog
import com.rork.guidestreamtvandroid.data.models.selectionAccent
import com.rork.guidestreamtvandroid.data.models.selectionGlyphColor
import com.rork.guidestreamtvandroid.data.models.TitleId
import com.rork.guidestreamtvandroid.data.models.TMDBResult
import com.rork.guidestreamtvandroid.data.remote.RecommendedCreator
import com.rork.guidestreamtvandroid.data.remote.StreamingReleasesService
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.data.repository.StreamsViewModel
import com.rork.guidestreamtvandroid.data.repository.WatchIntentLogger
import com.rork.guidestreamtvandroid.ui.components.GsTopBar
import com.rork.guidestreamtvandroid.ui.components.PushReauthBanner
import com.rork.guidestreamtvandroid.ui.components.PosterCard
import com.rork.guidestreamtvandroid.ui.components.RemoteImage
import com.rork.guidestreamtvandroid.ui.components.ServicesBottomSheet
import com.rork.guidestreamtvandroid.ui.components.ServicesPill
import com.rork.guidestreamtvandroid.ui.components.ShimmerHero
import com.rork.guidestreamtvandroid.ui.components.ShimmerSection
import com.rork.guidestreamtvandroid.ui.ads.InlineAdSlot
import com.rork.guidestreamtvandroid.ui.ads.PooledAdSource
import com.rork.guidestreamtvandroid.ui.ads.SponsoredSlot
import com.rork.guidestreamtvandroid.ui.components.glassCard
import com.rork.guidestreamtvandroid.ui.home.HomeViewModel
import com.rork.guidestreamtvandroid.ui.home.NowNextEntry
import com.rork.guidestreamtvandroid.ui.navigation.HomeListTarget
import com.rork.guidestreamtvandroid.ui.navigation.PendingTitleRoute
import com.rork.guidestreamtvandroid.ui.theme.BottomSafeSpacer
import com.rork.guidestreamtvandroid.ui.theme.BrandBlue
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.KickGreen
import com.rork.guidestreamtvandroid.ui.theme.PodcastPurple
import com.rork.guidestreamtvandroid.ui.theme.TwitchPurple
import com.rork.guidestreamtvandroid.ui.theme.YouTubeRed
import com.rork.guidestreamtvandroid.ui.theme.GlassFill
import com.rork.guidestreamtvandroid.ui.theme.GlassStroke
import com.rork.guidestreamtvandroid.ui.theme.LightBlue
import com.rork.guidestreamtvandroid.ui.theme.Navy
import com.rork.guidestreamtvandroid.ui.theme.SurfaceDark
import com.rork.guidestreamtvandroid.ui.components.GsSheetDragHandle
import com.rork.guidestreamtvandroid.ui.theme.NewsGreen
import com.rork.guidestreamtvandroid.ui.theme.OutlineVariant
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.statusBars
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.pulltorefresh.PullToRefreshDefaults
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.runtime.rememberCoroutineScope
import com.rork.guidestreamtvandroid.ui.theme.SurfaceContainer
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary
import com.rork.guidestreamtvandroid.ui.theme.GSWidthClass
import com.rork.guidestreamtvandroid.ui.theme.homeHorizontalPadding
import com.rork.guidestreamtvandroid.ui.theme.homeSearchHorizontalPadding
import com.rork.guidestreamtvandroid.ui.theme.rememberWidthClass
import kotlinx.coroutines.launch

/**
 * Home feed — mirrors iOS HomeView.swift.
 * Search bar, hero carousel, watch list, trending, top rated, genre discovery,
 * platform rows, coming to streaming, what's new, top picks, leaving soon,
 * binge worthy, widget promo banner.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    onOpenTitle: (PendingTitleRoute) -> Unit = {},
    onOpenSearch: () -> Unit = {},
    onSeeAllPopular: (serviceId: String, providerId: Int) -> Unit = { _, _ -> },
    onOpenAroundTheWorld: (regionCode: String) -> Unit = {},
    onSeeAllList: (HomeListTarget) -> Unit = {},
    /** Creators/Podcasts for You See all — the rail's filtered recommendations
     *  and the followed non-TMDB ids the recommender scores against. */
    onSeeAllCreators: (creators: List<RecommendedCreator>, followedIds: List<String>) -> Unit = { _, _ -> },
    onOpenWatchList: () -> Unit = {},
    /** New Episodes See all — opens the full list of everything new. */
    onOpenNewEpisodes: () -> Unit = {},
    onOpenWidgetSetup: () -> Unit = {},
    /** Opens the sports game detail for a hero rail game card. */
    onOpenGame: (SportsGame) -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val homeVm = HomeViewModel.get()
    val streamsVm = StreamsViewModel.get()
    val authVm = AuthViewModel.get()

    // Hero rail inputs. Games come from SportsViewModel so Home and the Sports
    // tab share one fetch; HomeViewModel kicks that load on its deferred pass.
    val heroGames by SportsViewModel.get().games.collectAsStateWithLifecycle()
    val heroLiveCreators by homeVm.heroLiveCreators.collectAsStateWithLifecycle()
    val heroCreatorUploads by homeVm.heroCreatorUploads.collectAsStateWithLifecycle()

    val homeReady by homeVm.homeContentReady.collectAsStateWithLifecycle()
    val trending by homeVm.trending.collectAsStateWithLifecycle()
    val onAir by homeVm.onAir.collectAsStateWithLifecycle()
    val leavingSoon by homeVm.leavingSoon.collectAsStateWithLifecycle()
    val topRated by homeVm.topRated.collectAsStateWithLifecycle()
    val newReleases by homeVm.newReleases.collectAsStateWithLifecycle()
    val todaysPick by homeVm.todaysPick.collectAsStateWithLifecycle()
    val upcoming by homeVm.upcoming.collectAsStateWithLifecycle()
    val bingeReady by homeVm.bingeReady.collectAsStateWithLifecycle()
    val genreShows by homeVm.genreShows.collectAsStateWithLifecycle()
    val selectedGenreName by homeVm.selectedGenreName.collectAsStateWithLifecycle()
    val selectedGenreId by homeVm.selectedGenreId.collectAsStateWithLifecycle()
    val recommendedCreators by homeVm.recommendedCreators.collectAsStateWithLifecycle()
    val popularByService by homeVm.popularByService.collectAsStateWithLifecycle()
    val aroundTheWorldRail by homeVm.aroundTheWorld.collectAsStateWithLifecycle()
    val nowNextByService by homeVm.nowNextByService.collectAsStateWithLifecycle()
    val providerByTmdb by homeVm.providerByTmdb.collectAsStateWithLifecycle()
    val preferredGenres by homeVm.preferredGenres.collectAsStateWithLifecycle()
    val userStreams by streamsVm.userStreams.collectAsStateWithLifecycle()
    val watchedIds by streamsVm.watchedIds.collectAsStateWithLifecycle()
    val latestContentAt by streamsVm.latestContentAt.collectAsStateWithLifecycle()
    val latestContentKind by streamsVm.latestContentKind.collectAsStateWithLifecycle()
    val seenContentAt by streamsVm.seenContentAt.collectAsStateWithLifecycle()
    val newEpisodes by streamsVm.newEpisodes.collectAsStateWithLifecycle()
    val selectedServices by authVm.selectedServices.collectAsStateWithLifecycle()

    LaunchedEffect(Unit) { homeVm.loadAll() }

    // Popular-on-service rails track the live selection. Keyed on the selection
    // itself and awaited in this effect's coroutine (not viewModelScope) so
    // Compose cancels an in-flight fetch the moment the user toggles another
    // service — a stale older result can never overwrite a newer one. Also
    // covers sign-in hydrating services after Home has already mounted.
    LaunchedEffect(selectedServices, homeReady) { if (homeReady) homeVm.loadPopularByServices(selectedServices) }

    // Now & Next rails follow the same selection-tracking rules as the
    // Popular rails. Also keyed on newReleases so the rails build once the
    // home load's streaming_releases rows land (the 8s watchdog can flip
    // homeReady before they arrive).
    LaunchedEffect(selectedServices, homeReady, newReleases) {
        if (homeReady) homeVm.loadNowAndNext(selectedServices)
    }

    // Inline sponsored slot indices dismissed for this session.
    val dismissedAdSlots = remember { mutableStateMapOf<Int, Boolean>() }

    // Services editor sheet (opened from the top-bar services pill).
    var showServicesSheet by remember { mutableStateOf(false) }

    val scrollState = rememberScrollState()

    val scope = rememberCoroutineScope()
    var isRefreshing by remember { mutableStateOf(false) }
    val pullState = rememberPullToRefreshState()
    val statusBarTop = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()

    // Elevate the top bar once the feed has scrolled past a small threshold.
    // The 8.dp deadzone absorbs overscroll rubber-banding at the very top so
    // the container settles back to transparent instead of flickering.
    val elevateThresholdPx = with(LocalDensity.current) { 8.dp.toPx() }
    val isBarElevated by remember {
        derivedStateOf { scrollState.value > elevateThresholdPx }
    }

    val coachMark = CoachMarkManager.get()

    // BringIntoViewRequester for the Browse-by-genre section. Used by the
    // coach-mark tour so the scroll target resolves by composition identity
    // rather than a previously measured rect that may be stale or missing.
    val genreBringIntoViewRequester = remember { BringIntoViewRequester() }

    // Coach-mark scroll coordination: when the genre mark requests a scroll,
    // bring the Browse-by-genre section into view, then settle after 350ms so
    // onGloballyPositioned can re-report after the scroll.
    LaunchedEffect(coachMark.isShowing, coachMark.currentMark?.key) {
        if (!coachMark.isShowing) return@LaunchedEffect
        // Only service the HOME tour. The sheet tour runs while HomeScreen is
        // still composed underneath the ModalBottomSheet; without this guard
        // the unconditional markScrollSettled() below races the sheet's own
        // handler and nulls scrollRequestId before the sheet can scroll.
        if (!coachMark.activeTourIsHome) return@LaunchedEffect
        if (coachMark.scrollRequestId == "browseByGenre") {
            coachMark.clearScrollRequest()
            genreBringIntoViewRequester.bringIntoView()
            delay(350)
        }
        coachMark.markScrollSettled()
    }

    // Adaptive width class for tablet/split-screen windows. Used to stretch the
    // Home search bar, hero carousel and section rails edge-to-edge on tablets
    // while keeping phone gutters unchanged.
    val widthClass = rememberWidthClass()

    Box(modifier = modifier.fillMaxSize()) {
        PullToRefreshBox(
            isRefreshing = isRefreshing,
            onRefresh = {
                if (isRefreshing || coachMark.isShowing) return@PullToRefreshBox
                scope.launch {
                    isRefreshing = true
                    try {
                        homeVm.refreshFeed()
                        homeVm.loadPopularByServices(selectedServices)
                        homeVm.loadNowAndNext(selectedServices)
                    } finally {
                        isRefreshing = false
                    }
                }
            },
            state = pullState,
            modifier = Modifier.fillMaxSize(),
            indicator = {
                PullToRefreshDefaults.Indicator(
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .offset(y = statusBarTop + 56.dp),
                    isRefreshing = isRefreshing,
                    state = pullState,
                    containerColor = SurfaceContainer,
                    color = BrandOrange,
                )
            },
        ) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(scrollState),
    ) {
        // Reserve space for the pinned PageBar (status bar + 56dp bar height).
        Spacer(Modifier.statusBarsPadding().height(56.dp))

        // GUI-41: the "notifications got turned off" message used to live only
        // on Profile → Notifications, which nobody visits after a reinstall —
        // they would just stop getting alerts with no way to know why. Renders
        // nothing unless the account wants push and POST_NOTIFICATIONS has
        // never been asked for on this install.
        PushReauthBanner(
            modifier = Modifier.padding(
                horizontal = widthClass.homeHorizontalPadding,
                vertical = 8.dp,
            ),
        )

        // Search bar
        SearchBar(
            widthClass = widthClass,
            onClick = onOpenSearch,
            modifier = Modifier.onGloballyPositioned { coords ->
                coachMark.setMeasuredRect("search", coords.boundsInRoot())
            })

        // Hero carousel
        if (!homeReady) {
            Box(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
                ShimmerHero()
            }
        } else {
            val heroItems = remember(
                trending, onAir, bingeReady, providerByTmdb,
                heroGames, heroLiveCreators, heroCreatorUploads,
            ) {
                buildHeroRail(
                    trending = trending,
                    onAir = onAir,
                    bingeReady = bingeReady,
                    providerByTmdb = providerByTmdb,
                    games = heroGames,
                    liveCreators = heroLiveCreators,
                    creatorUploads = heroCreatorUploads,
                )
            }
            if (heroItems.isNotEmpty()) {
                HeroCarousel(
                    widthClass = widthClass,
                    items = heroItems,
                    onSelect = { item ->
                        val logger = WatchIntentLogger.get()
                        when (item) {
                            is HeroItem.Media -> {
                                logger.log(
                                    WatchIntentLogger.IntentEventType.CARD_TAPPED,
                                    titleId = item.result.id.toString(),
                                    platformId = item.platform?.name?.lowercase() ?: "tmdb",
                                    metadata = mapOf("section" to "hero_carousel"),
                                )
                                onOpenTitle(PendingTitleRoute(
                                    titleId = item.result.id.toString(),
                                    titleName = item.result.displayName,
                                    isTv = item.result.isTV,
                                ))
                            }
                            is HeroItem.Game -> {
                                logger.log(
                                    WatchIntentLogger.IntentEventType.CARD_TAPPED,
                                    titleId = item.game.id,
                                    platformId = item.game.broadcasts.firstOrNull()?.lowercase() ?: "",
                                    metadata = mapOf(
                                        "section" to "hero_carousel",
                                        "kind" to "sport",
                                        "state" to item.game.state,
                                    ),
                                )
                                onOpenGame(item.game)
                            }
                            is HeroItem.LiveCreator -> {
                                logger.log(
                                    WatchIntentLogger.IntentEventType.CARD_TAPPED,
                                    titleId = item.creator.titleId,
                                    platformId = item.creator.kind.sourceType,
                                    metadata = mapOf(
                                        "section" to "hero_carousel",
                                        "kind" to "live_creator",
                                    ),
                                )
                                onOpenTitle(PendingTitleRoute(
                                    titleId = item.creator.titleId,
                                    titleName = item.creator.displayName,
                                    posterUrl = item.creator.avatarUrl,
                                    isTv = false,
                                ))
                            }
                            is HeroItem.CreatorUpload -> {
                                logger.log(
                                    WatchIntentLogger.IntentEventType.CARD_TAPPED,
                                    titleId = item.upload.titleId,
                                    platformId = SourceKind.from(item.upload.titleId).sourceType,
                                    metadata = mapOf(
                                        "section" to "hero_carousel",
                                        "kind" to "creator_upload",
                                    ),
                                )
                                onOpenTitle(PendingTitleRoute(
                                    titleId = item.upload.titleId,
                                    titleName = item.upload.title ?: "",
                                    posterUrl = item.upload.thumbnailUrl ?: item.upload.posterUrl,
                                    isTv = false,
                                ))
                            }
                        }
                    },
                )
            }
        }

        // My Watch List
        if (!homeReady) {
            ShimmerSection("My Watch List", Modifier.padding(horizontal = widthClass.homeHorizontalPadding, vertical = 8.dp))
        } else {
            WatchListSection(
                streams = userStreams,
                watchedIds = watchedIds,
                latestContentAt = latestContentAt,
                latestContentKind = latestContentKind,
                seenContentAt = seenContentAt,
                isAuthenticated = authVm.isAuthenticated.value,
                onOpen = { stream ->
                    WatchIntentLogger.get().log(
                        WatchIntentLogger.IntentEventType.CARD_TAPPED,
                        titleId = stream.titleId,
                        platformId = stream.platform?.lowercase() ?: "tmdb",
                        metadata = mapOf("section" to "watch_list"),
                    )
                    onOpenTitle(PendingTitleRoute(
                        titleId = stream.titleId,
                        titleName = stream.title ?: stream.titleName,
                        posterUrl = stream.posterUrl,
                        isTv = stream.isTv ?: TitleId.isTv(stream.titleId) ?: true,
                    ))
                },
                onSeeAll = {
                    WatchIntentLogger.get().log(
                        WatchIntentLogger.IntentEventType.CARD_TAPPED,
                        metadata = mapOf("section" to "watch_list_see_all"),
                    )
                    onOpenWatchList()
                },
                onSignIn = { onOpenSearch() },
            )
        }

        // Today's Pick — daily spotlight from streaming_releases
        if (!homeReady) {
            ShimmerSection("Today's Pick", Modifier.padding(horizontal = widthClass.homeHorizontalPadding, vertical = 8.dp))
        } else if (todaysPick != null) {
            TodaysPickSpotlight(
                pick = todaysPick!!,
                selectedServices = selectedServices,
                onOpen = { row ->
                    WatchIntentLogger.get().log(
                        WatchIntentLogger.IntentEventType.CARD_TAPPED,
                        titleId = row.tmdbId.toString(),
                        metadata = mapOf("section" to "todays_pick"),
                    )
                    onOpenTitle(PendingTitleRoute(
                        titleId = row.tmdbId.toString(),
                        titleName = row.title,
                        posterUrl = row.posterUrl,
                        isTv = row.tmdbType == "tv",
                    ))
                },
            )
        }

        // New Episodes — what has actually landed on the shows you follow.
        // No shimmer placeholder on purpose: the section renders nothing when
        // there is nothing new, and a shimmer that resolves to an absent rail
        // reads as a rail that failed to load.
        NewEpisodesSection(
            episodes = newEpisodes,
            onOpen = { row ->
                WatchIntentLogger.get().log(
                    WatchIntentLogger.IntentEventType.CARD_TAPPED,
                    titleId = row.titleId,
                    platformId = row.platform?.lowercase() ?: "tmdb",
                    metadata = mapOf("section" to "new_episodes"),
                )
                onOpenTitle(PendingTitleRoute(
                    titleId = row.titleId,
                    titleName = newEpisodeShowName(row),
                    posterUrl = row.posterUrl,
                    isTv = TitleId.isTv(row.titleId) ?: true,
                ))
            },
            onSeeAll = {
                WatchIntentLogger.get().log(
                    WatchIntentLogger.IntentEventType.CARD_TAPPED,
                    metadata = mapOf("section" to "new_episodes_see_all"),
                )
                onOpenNewEpisodes()
            },
        )

        // Around the World — rotating daily country rail
        if (homeReady) {
            aroundTheWorldRail?.let { around ->
                AroundTheWorldSection(
                    subtitle = "Streaming in ${around.country.displayName} today · ${around.providerName}",
                    shows = around.shows.take(10),
                    onOpen = { r ->
                        WatchIntentLogger.get().log(
                            WatchIntentLogger.IntentEventType.CARD_TAPPED,
                            titleId = r.id.toString(),
                            metadata = mapOf("section" to "around_the_world"),
                        )
                        onOpenTitle(PendingTitleRoute(titleId = r.id.toString(), titleName = r.displayName, isTv = r.isTV))
                    },
                    onSeeAll = {
                        WatchIntentLogger.get().log(
                            WatchIntentLogger.IntentEventType.CARD_TAPPED,
                            metadata = mapOf("section" to "around_the_world_see_all"),
                        )
                        onOpenAroundTheWorld(around.country.regionCode)
                    },
                    modifier = Modifier.padding(horizontal = widthClass.homeHorizontalPadding, vertical = 8.dp),
                )
            }
        }

        // Coming to Streaming (upcoming movies)
        if (!homeReady) {
            ShimmerSection("Coming to Streaming", Modifier.padding(horizontal = widthClass.homeHorizontalPadding, vertical = 8.dp))
        } else if (upcoming.isNotEmpty()) {
            PosterSection(
                title = "Coming to Streaming",
                shows = upcoming.take(20),
                providerByTmdb = providerByTmdb,
                onOpen = { r ->
                    WatchIntentLogger.get().log(
                        WatchIntentLogger.IntentEventType.CARD_TAPPED,
                        titleId = r.id.toString(),
                        metadata = mapOf("section" to "coming_to_streaming"),
                    )
                    onOpenTitle(PendingTitleRoute(titleId = r.id.toString(), titleName = r.displayName, isTv = false, isComingToStreaming = true))
                },
                onSeeAll = {
                    WatchIntentLogger.get().log(
                        WatchIntentLogger.IntentEventType.CARD_TAPPED,
                        metadata = mapOf("section" to "coming_to_streaming_see_all"),
                    )
                    onSeeAllList(HomeListTarget(title = "Coming to Streaming", tag = "COMING SOON", shows = upcoming, providerByTmdb = providerByTmdb))
                },
            )
        }

        // New This Week (streaming releases from the last 7 days)
        if (!homeReady) {
            ShimmerSection("New This Week", Modifier.padding(horizontal = widthClass.homeHorizontalPadding, vertical = 8.dp))
        } else if (newReleases.isNotEmpty()) {
            PosterSection(
                title = "New This Week",
                shows = newReleases.take(20),
                providerByTmdb = providerByTmdb,
                badgeText = { "NEW" },
                onOpen = { r ->
                    WatchIntentLogger.get().log(
                        WatchIntentLogger.IntentEventType.CARD_TAPPED,
                        titleId = r.id.toString(),
                        metadata = mapOf("section" to "whats_new_today"),
                    )
                    onOpenTitle(PendingTitleRoute(titleId = r.id.toString(), titleName = r.displayName, isTv = r.isTV))
                },
                onSeeAll = {
                    WatchIntentLogger.get().log(
                        WatchIntentLogger.IntentEventType.CARD_TAPPED,
                        metadata = mapOf("section" to "whats_new_today_see_all"),
                    )
                    onSeeAllList(HomeListTarget(title = "New This Week", tag = "TODAY", shows = newReleases, providerByTmdb = providerByTmdb))
                },
            )
        }

        // Inline sponsored slot #0 — after What's New Today
        InlineAdSlot(
            slotIndex = 0,
            selectedServices = selectedServices,
            adSource = "home_inline",
            sectionKey = "home_inline_ad",
            dismissed = dismissedAdSlots,
        )

        // Personalised Top Picks pool — hoisted so both the Top Picks and
        // Everyone's Watching sections share it (Everyone's Watching excludes
        // any id already shown in Top Picks). Excludes watched titles and
        // boosts titles on the user's selected services above equally-rated
        // ones. Resolves the provider's catalogue id and tests set membership.
        val selected = selectedServices.map { it.lowercase() }
        fun onService(id: Int): Boolean {
            val catalogId = providerByTmdb[id]?.catalogId ?: return false
            return selected.contains(catalogId)
        }
        fun scoreFor(r: TMDBResult): Double =
            0.60 * ((r.voteAverage ?: 7.0) / 10.0) +
                (if (onService(r.id)) 0.20 else 0.0) +
                (if (preferredGenres.isNotEmpty() && (r.genreIds ?: emptyList()).any { it in preferredGenres }) 0.20 else 0.0)
        val topPicksAll = trending
            .filter { providerByTmdb[it.id] != null }
            .filter { !watchedIds.contains(it.id.toString()) }
            .sortedByDescending { scoreFor(it) }
        val topPickIds = topPicksAll.take(20).map { it.id }.toSet()

        // Top Picks for You (trending scored)
        if (!homeReady) {
            ShimmerSection("Top Picks for You", Modifier.padding(horizontal = widthClass.homeHorizontalPadding, vertical = 8.dp))
        } else if (trending.isNotEmpty()) {
            val topPicks = topPicksAll.take(20)
            PosterSection(
                title = "Top Picks for You",
                shows = topPicks,
                providerByTmdb = providerByTmdb,
                badgeAsMatchChip = true,
                badgeText = { r ->
                    val score = scoreFor(r)
                    "${(score.coerceIn(0.50, 0.99) * 100).toInt()}% Match"
                },
                onOpen = { r ->
                    WatchIntentLogger.get().log(
                        WatchIntentLogger.IntentEventType.CARD_TAPPED,
                        titleId = r.id.toString(),
                        metadata = mapOf("section" to "top_picks"),
                    )
                    onOpenTitle(PendingTitleRoute(titleId = r.id.toString(), titleName = r.displayName, isTv = r.isTV))
                },
                onSeeAll = {
                    WatchIntentLogger.get().log(
                        WatchIntentLogger.IntentEventType.CARD_TAPPED,
                        metadata = mapOf("section" to "top_picks_see_all"),
                    )
                    onSeeAllList(HomeListTarget(title = "Top Picks for You", tag = "TOP PICK", shows = topPicksAll, providerByTmdb = providerByTmdb))
                },
            )
        }

        // Creators/Podcasts for You
        if (!homeReady) {
            ShimmerSection("Creators/Podcasts for You", Modifier.padding(horizontal = widthClass.homeHorizontalPadding, vertical = 8.dp))
        } else {
            val hasFollowedCreators = userStreams.any { SourceKind.from(it.titleId).isNonTMDB }
            if (hasFollowedCreators) {
                val followedCreatorIds = userStreams
                    .map { it.titleId }
                    .filter { SourceKind.from(it).isNonTMDB }
                    .toSet()
                val creators = recommendedCreators.filter { it.titleId !in followedCreatorIds }
                if (creators.isEmpty()) {
                    EmptyStateRow(
                        title = "Creators/Podcasts for You",
                        message = "Follow more creators to get fresh recommendations.",
                    )
                } else {
                    CreatorsForYouSection(
                        creators = creators,
                        onSeeAll = { onSeeAllCreators(creators, followedCreatorIds.toList()) },
                        onOpen = { creator ->
                            WatchIntentLogger.get().log(
                                WatchIntentLogger.IntentEventType.CARD_TAPPED,
                                titleId = creator.titleId,
                                platformId = creator.sourceType,
                                metadata = mapOf("section" to "creators_for_you"),
                            )
                            onOpenTitle(PendingTitleRoute(
                                titleId = creator.titleId,
                                titleName = creator.displayName,
                                posterUrl = creator.imageUrl,
                                // Creators route to CreatorDetail via SourceKind; the
                                // tv/movie flag is unused for prefixed ids.
                                isTv = true,
                            ))
                        },
                    )
                }
            }
        }

        // Inline sponsored slot #1 — after Creators/Podcasts for You
        InlineAdSlot(
            slotIndex = 1,
            selectedServices = selectedServices,
            adSource = "home_inline",
            sectionKey = "home_inline_ad",
            dismissed = dismissedAdSlots,
        )

        // Everyone's Watching (ranked)
        if (!homeReady) {
            ShimmerSection("Everyone's Watching", Modifier.padding(horizontal = widthClass.homeHorizontalPadding, vertical = 8.dp))
        } else if (trending.isNotEmpty()) {
            // Build rank lookup from the de-duplicated trending array before
            // any filtering, so trueRanks reflects the real TMDB trending
            // position (1-based), not the post-exclusion display index.
            val rankLookup = trending.mapIndexed { idx, r -> r.id to (idx + 1) }.toMap()
            val rankedShows = trending.filter { providerByTmdb[it.id] != null }.filterNot { it.id in topPickIds }
            TrendingRankedSection(
                shows = rankedShows.take(20),
                providerByTmdb = providerByTmdb,
                trueRanks = rankedShows.mapNotNull { rankLookup[it.id] },
                onOpen = { r ->
                    WatchIntentLogger.get().log(
                        WatchIntentLogger.IntentEventType.CARD_TAPPED,
                        titleId = r.id.toString(),
                        metadata = mapOf("section" to "everyones_watching"),
                    )
                    onOpenTitle(PendingTitleRoute(titleId = r.id.toString(), titleName = r.displayName, isTv = r.isTV))
                },
                onSeeAll = {
                    WatchIntentLogger.get().log(
                        WatchIntentLogger.IntentEventType.CARD_TAPPED,
                        metadata = mapOf("section" to "everyones_watching_see_all"),
                    )
                    onSeeAllList(HomeListTarget(title = "Everyone's Watching", tag = "EVERYONES_WATCHING", shows = rankedShows, providerByTmdb = providerByTmdb))
                },
            )
        }

        // Inline sponsored slot #2 — after Everyone's Watching, before Leaving Soon
        InlineAdSlot(
            slotIndex = 2,
            selectedServices = selectedServices,
            adSource = "home_inline",
            sectionKey = "home_inline_ad",
            dismissed = dismissedAdSlots,
        )

        // Leaving Soon — server-backed rows from the expiring_titles table
        if (!homeReady) {
            ShimmerSection("Leaving Soon", Modifier.padding(horizontal = widthClass.homeHorizontalPadding, vertical = 8.dp))
        } else if (leavingSoon.isNotEmpty()) {
            PosterSection(
                title = "Leaving Soon",
                shows = leavingSoon.take(20),
                providerByTmdb = providerByTmdb,
                accentColor = BrandOrange,
                onOpen = { r ->
                    WatchIntentLogger.get().log(
                        WatchIntentLogger.IntentEventType.CARD_TAPPED,
                        titleId = r.id.toString(),
                        metadata = mapOf("section" to "leaving_soon"),
                    )
                    onOpenTitle(PendingTitleRoute(titleId = r.id.toString(), titleName = r.displayName, isTv = r.isTV))
                },
                onSeeAll = {
                    WatchIntentLogger.get().log(
                        WatchIntentLogger.IntentEventType.CARD_TAPPED,
                        metadata = mapOf("section" to "leaving_soon_see_all"),
                    )
                    onSeeAllList(HomeListTarget(title = "Leaving Soon", tag = "LEAVING SOON", shows = leavingSoon, providerByTmdb = providerByTmdb))
                },
            )
        }

        // Inline sponsored slot #3 — after Leaving Soon
        InlineAdSlot(
            slotIndex = 3,
            selectedServices = selectedServices,
            adSource = "home_inline",
            sectionKey = "home_inline_ad",
            dismissed = dismissedAdSlots,
        )

        // Popular on {service}
        val services = StreamingCatalog.ordered(selectedServices)
        if (!homeReady) {
            services.take(3).forEach { svc ->
                ShimmerSection("Popular on ${svc.name}", Modifier.padding(horizontal = widthClass.homeHorizontalPadding, vertical = 8.dp))
                ShimmerSection("Now & Next on ${svc.name}", Modifier.padding(horizontal = widthClass.homeHorizontalPadding, vertical = 8.dp))
            }
        } else {
            services.forEachIndexed { index, svc ->
                val results = popularByService[svc.id] ?: emptyList()
                if (results.isNotEmpty()) {
                    val providerId = HomeViewModel.get().providerIdFor(svc.id)
                    PopularOnServiceSection(
                        serviceName = svc.name,
                        accentColor = svc.glow,
                        shows = results.take(20),
                        onOpen = { r ->
                            WatchIntentLogger.get().log(
                                WatchIntentLogger.IntentEventType.CARD_TAPPED,
                                titleId = r.id.toString(),
                                metadata = mapOf("section" to "popular_on_${svc.id}"),
                            )
                            onOpenTitle(PendingTitleRoute(titleId = r.id.toString(), titleName = r.displayName, isTv = r.isTV))
                        },
                        onSeeAll = providerId?.let { pid ->
                            {
                                WatchIntentLogger.get().log(
                                    WatchIntentLogger.IntentEventType.CARD_TAPPED,
                                    metadata = mapOf("section" to "popular_on_${svc.id}_see_all"),
                                )
                                onSeeAllPopular(svc.id, pid)
                            }
                        },
                    )
                }
                val nowNext = nowNextByService[svc.id] ?: emptyList()
                if (nowNext.isNotEmpty()) {
                    NowAndNextSection(
                        serviceName = svc.name,
                        accentColor = svc.glow,
                        entries = nowNext,
                        onOpen = { entry ->
                            WatchIntentLogger.get().log(
                                WatchIntentLogger.IntentEventType.CARD_TAPPED,
                                titleId = entry.result.id.toString(),
                                metadata = mapOf("section" to "now_next_${svc.id}"),
                            )
                            onOpenTitle(PendingTitleRoute(
                                titleId = entry.result.id.toString(),
                                titleName = entry.result.displayName,
                                posterUrl = entry.posterUrl,
                                isTv = entry.result.isTV,
                            ))
                        },
                        onSeeAll = {
                            WatchIntentLogger.get().log(
                                WatchIntentLogger.IntentEventType.CARD_TAPPED,
                                metadata = mapOf("section" to "now_next_${svc.id}_see_all"),
                            )
                            onSeeAllList(HomeListTarget(
                                title = "Now & Next on ${svc.name}",
                                tag = "NOW & NEXT",
                                shows = nowNext.map { it.result },
                                providerByTmdb = providerByTmdb,
                            ))
                        },
                    )
                }
                // Dynamic per-service ad after every second service (index % 2 == 1)
                if (index % 2 == 1) {
                    InlineAdSlot(
                        slotIndex = 100 + index / 2,
                        selectedServices = selectedServices,
                        adSource = "home_inline",
                        sectionKey = "home_inline_ad",
                        dismissed = dismissedAdSlots,
                    )
                }
            }
        }

        // Inline sponsored slot #4 — after per-service ForEach, before Browsing genre
        InlineAdSlot(
            slotIndex = 4,
            selectedServices = selectedServices,
            adSource = "home_inline",
            sectionKey = "home_inline_ad",
            dismissed = dismissedAdSlots,
        )

        // Browse by genre (pill grid) — drives the Because you watch rail below.
        Box(
            modifier = Modifier
                .bringIntoViewRequester(genreBringIntoViewRequester)
                .onGloballyPositioned { coords ->
                    coachMark.setMeasuredRect("genre", coords.boundsInRoot())
                },
        ) {
            GenrePillGrid(
                selectedGenreId = selectedGenreId,
                onSelect = { pill -> HomeViewModel.get().loadGenre(pill.id, pill.label, pill.mediaType) },
            )
        }

        // Because You Watch (genre discovery)
        if (!homeReady) {
            ShimmerSection("Browsing $selectedGenreName", Modifier.padding(horizontal = widthClass.homeHorizontalPadding, vertical = 8.dp))
        } else if (genreShows.isNotEmpty()) {
            Box(
                modifier = Modifier.onGloballyPositioned { coords ->
                    coachMark.setMeasuredRect("because_you_watch", coords.boundsInRoot())
                },
            ) {
                PosterSection(
                    title = "Browsing $selectedGenreName",
                    shows = genreShows.filter { providerByTmdb[it.id] != null }.take(20),
                    providerByTmdb = providerByTmdb,
                    onOpen = { r ->
                        WatchIntentLogger.get().log(
                            WatchIntentLogger.IntentEventType.CARD_TAPPED,
                            titleId = r.id.toString(),
                            metadata = mapOf("section" to "because_you_watch", "genre" to selectedGenreName),
                        )
                        onOpenTitle(PendingTitleRoute(titleId = r.id.toString(), titleName = r.displayName, isTv = r.isTV))
                    },
                )
            }
        }

        // Inline sponsored slot #5 — after Because you watch Crime
        InlineAdSlot(
            slotIndex = 5,
            selectedServices = selectedServices,
            adSource = "home_inline",
            sectionKey = "home_inline_ad",
            dismissed = dismissedAdSlots,
        )

        // Top Rated
        if (!homeReady) {
            ShimmerSection("Top rated right now", Modifier.padding(horizontal = widthClass.homeHorizontalPadding, vertical = 8.dp))
        } else if (topRated.isNotEmpty()) {
            PosterSection(
                title = "Top rated right now",
                shows = topRated.filter { providerByTmdb[it.id] != null }.take(20),
                providerByTmdb = providerByTmdb,
                onOpen = { r ->
                    WatchIntentLogger.get().log(
                        WatchIntentLogger.IntentEventType.CARD_TAPPED,
                        titleId = r.id.toString(),
                        metadata = mapOf("section" to "top_rated"),
                    )
                    onOpenTitle(PendingTitleRoute(titleId = r.id.toString(), titleName = r.displayName, isTv = r.isTV))
                },
            )
        }

        // Inline sponsored slot #6 — after Top rated right now, before New seasons
        InlineAdSlot(
            slotIndex = 6,
            selectedServices = selectedServices,
            adSource = "home_inline",
            sectionKey = "home_inline_ad",
            dismissed = dismissedAdSlots,
        )

        // New seasons — shows you follow (on-air titles from the user's watch list)
        if (!homeReady) {
            ShimmerSection("New seasons — shows you follow", Modifier.padding(horizontal = widthClass.homeHorizontalPadding, vertical = 8.dp))
        } else {
            val savedIds = userStreams.mapNotNull { TitleId.tmdbId(it.titleId) }.toSet()
            val newSeasons = onAir.filter { it.id in savedIds }.take(8)
            if (newSeasons.isNotEmpty()) {
                PosterSection(
                    title = "New seasons — shows you follow",
                    shows = newSeasons,
                    providerByTmdb = providerByTmdb,
                    onOpen = { r ->
                        WatchIntentLogger.get().log(
                            WatchIntentLogger.IntentEventType.CARD_TAPPED,
                            titleId = r.id.toString(),
                            metadata = mapOf("section" to "new_seasons"),
                        )
                        onOpenTitle(PendingTitleRoute(titleId = r.id.toString(), titleName = r.displayName, isTv = true))
                    },
                )
            }
        }

        // Inline sponsored slot #7 — after New seasons
        InlineAdSlot(
            slotIndex = 7,
            selectedServices = selectedServices,
            adSource = "home_inline",
            sectionKey = "home_inline_ad",
            dismissed = dismissedAdSlots,
        )

        // Binge Worthy (ended shows)
        if (!homeReady) {
            ShimmerSection("Binge Worthy", Modifier.padding(horizontal = widthClass.homeHorizontalPadding, vertical = 8.dp))
        } else if (bingeReady.isNotEmpty()) {
            val bingeTitle = if (userStreams.isEmpty()) "Binge Worthy" else "Binge Ready 🎉"
            PosterSection(
                title = bingeTitle,
                shows = bingeReady.filter { providerByTmdb[it.id] != null }.take(20),
                providerByTmdb = providerByTmdb,
                onOpen = { r ->
                    WatchIntentLogger.get().log(
                        WatchIntentLogger.IntentEventType.CARD_TAPPED,
                        titleId = r.id.toString(),
                        metadata = mapOf("section" to "binge_ready"),
                    )
                    onOpenTitle(PendingTitleRoute(titleId = r.id.toString(), titleName = r.displayName, isTv = r.isTV))
                },
                onSeeAll = {
                    WatchIntentLogger.get().log(
                        WatchIntentLogger.IntentEventType.CARD_TAPPED,
                        metadata = mapOf("section" to "binge_ready_see_all"),
                    )
                    onSeeAllList(HomeListTarget(title = bingeTitle, tag = "BINGE", shows = bingeReady.filter { providerByTmdb[it.id] != null }, providerByTmdb = providerByTmdb))
                },
            )
        }

        // Inline sponsored slot #8 — after Binge Worthy
        InlineAdSlot(
            slotIndex = 8,
            selectedServices = selectedServices,
            adSource = "home_inline",
            sectionKey = "home_inline_ad",
            dismissed = dismissedAdSlots,
        )

        // Widget promo banner
        WidgetPromoBanner(
            onSetUp = {
                WatchIntentLogger.get().log(WatchIntentLogger.IntentEventType.WIDGET_SETUP_TAPPED)
                onOpenWidgetSetup()
            },
        )

        BottomSafeSpacer(withTabBar = true)
    }
        }

        // Pinned top bar — wordmark left, services pill right (mirrors iOS PageBar)
        GsTopBar(
            elevated = isBarElevated,
            modifier = Modifier.align(Alignment.TopStart),
        ) {
            val serviceIds = StreamingCatalog.ordered(selectedServices).map { it.id }
            if (serviceIds.isNotEmpty()) {
                ServicesPill(
                    serviceIds = serviceIds,
                    onTap = { showServicesSheet = true },
                    modifier = Modifier.onGloballyPositioned { coords ->
                        coachMark.setMeasuredRect("services", coords.boundsInRoot())
                    },
                )
            }
        }
    }

    if (showServicesSheet) {
        ServicesBottomSheet(
            selected = selectedServices,
            onToggle = { id ->
                val next = if (id in selectedServices) selectedServices - id else selectedServices + id
                authVm.setSelectedServices(next)
            },
            onDismiss = { showServicesSheet = false },
        )
    }
}

// ── Search Bar ──────────────────────────────────────────────────────────────

@Composable
private fun SearchBar(
    widthClass: GSWidthClass,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = widthClass.homeSearchHorizontalPadding)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() }
            .glassCard()
            .padding(horizontal = 14.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = Icons.Filled.Search,
            contentDescription = "Search",
            tint = TextTertiary,
            modifier = Modifier.size(18.dp),
        )
        Spacer(Modifier.width(10.dp))
        Text(
            text = "Search shows, creators, podcasts…",
            fontSize = 14.sp,
            color = TextTertiary,
        )
    }
}

// -- Hero Carousel -----------------------------------------------------------

/**
 * The home hero. Mixes live sports, live creators, new creator uploads and
 * trending media in one newest-first rail, mirroring iOS HomeHeroCarousel.
 * Every card is one large hit target with its own tinted CTA: orange for
 * shows and movies, blue for sport, brand colour for creators.
 */
@Composable
private fun HeroCarousel(
    widthClass: GSWidthClass,
    items: List<HeroItem>,
    onSelect: (HeroItem) -> Unit,
) {
    if (items.isEmpty()) return
    LazyRow(
        contentPadding = PaddingValues(horizontal = widthClass.homeHorizontalPadding),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        modifier = Modifier.padding(vertical = 8.dp),
    ) {
        items(items, key = { it.id }) { item ->
            HeroCard(
                item = item,
                width = if (widthClass == GSWidthClass.Expanded) 360.dp else 300.dp,
                onSelect = { onSelect(item) },
            )
        }
    }
}

private val HeroLiveRed = Color(0xFFE50914)
private val HeroSportsBlue = Color(0xFF3B82F6)

/** Accent that carries the card's meaning: what kind of thing this is. */
private fun heroAccent(item: HeroItem): Color = when (item) {
    is HeroItem.Media -> BrandOrange
    is HeroItem.Game -> HeroSportsBlue
    is HeroItem.LiveCreator -> heroSourceColor(item.creator.kind)
    is HeroItem.CreatorUpload -> heroSourceColor(SourceKind.from(item.upload.titleId))
}

/** ESPN gives team colours as bare hex with no leading #. */
private fun teamColor(hex: String?, fallback: Color): Color {
    val clean = hex?.removePrefix("#")?.trim()?.takeIf { it.length == 6 } ?: return fallback
    return runCatching { Color("FF$clean".toLong(16)) }.getOrDefault(fallback)
}

@Composable
private fun HeroCard(
    item: HeroItem,
    width: Dp,
    onSelect: () -> Unit,
) {
    val accent = heroAccent(item)
    Box(
        modifier = Modifier
            .width(width)
            .aspectRatio(1.7f)
            .clip(RoundedCornerShape(18.dp))
            .border(1.dp, accent.copy(alpha = 0.35f), RoundedCornerShape(18.dp))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onSelect() },
    ) {
        HeroBackdrop(item)

        // Scrim. Heavier at the foot than the media-only carousel had, because
        // these cards now carry three stacked lines over the artwork.
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        colors = listOf(
                            Color.Black.copy(alpha = 0.10f),
                            Color.Black.copy(alpha = 0.45f),
                            Color.Black.copy(alpha = 0.85f),
                        ),
                    ),
                ),
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(16.dp),
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                HeroTopBadges(item)
            }
            Spacer(Modifier.weight(1f))
            HeroBottom(item, accent)
        }
    }
}

@Composable
private fun HeroBackdrop(item: HeroItem) {
    when (item) {
        is HeroItem.Media -> RemoteImage(
            url = item.result.backdropUrl ?: item.result.posterUrl,
            contentDescription = item.result.displayName,
            modifier = Modifier.fillMaxSize(),
            cornerRadius = 18,
            placeholderText = item.result.displayName.take(2).uppercase(),
            placeholderFontSize = 28.sp,
        )

        is HeroItem.Game -> {
            // No artwork exists for a game, so the two teams' own colours carry
            // it, with their abbreviations set large and faint for depth.
            val away = teamColor(item.game.away.primaryHex, Color(0xFF19294F))
            val home = teamColor(item.game.home.primaryHex, Color(0xFF521926))
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        Brush.linearGradient(
                            colors = listOf(
                                away,
                                away.copy(alpha = 0.85f),
                                home.copy(alpha = 0.85f),
                                home,
                            ),
                        ),
                    ),
            ) {
                Row(
                    modifier = Modifier.fillMaxSize(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = item.game.away.abbreviation,
                        fontSize = 56.sp,
                        fontWeight = FontWeight.Black,
                        color = Color.White.copy(alpha = 0.10f),
                        maxLines = 1,
                    )
                    Spacer(Modifier.weight(1f))
                    Text(
                        text = item.game.home.abbreviation,
                        fontSize = 56.sp,
                        fontWeight = FontWeight.Black,
                        color = Color.White.copy(alpha = 0.10f),
                        maxLines = 1,
                    )
                }
            }
        }

        is HeroItem.LiveCreator -> RemoteImage(
            url = item.creator.avatarUrl,
            contentDescription = item.creator.displayName,
            modifier = Modifier.fillMaxSize(),
            cornerRadius = 18,
            placeholderText = item.creator.displayName.take(2).uppercase(),
            placeholderFontSize = 28.sp,
        )

        is HeroItem.CreatorUpload -> RemoteImage(
            url = item.upload.thumbnailUrl ?: item.upload.posterUrl,
            contentDescription = item.upload.title,
            modifier = Modifier.fillMaxSize(),
            cornerRadius = 18,
            placeholderText = (item.upload.title ?: "?").take(2).uppercase(),
            placeholderFontSize = 28.sp,
        )
    }
}

@Composable
private fun HeroTopBadges(item: HeroItem) {
    when (item) {
        is HeroItem.Media -> {
            HeroBadge("TRENDING", BrandOrange)
            item.platform?.let { HeroBadge(it.name, it.color) }
        }

        is HeroItem.Game -> {
            when (item.game.state) {
                "live" -> HeroLivePill()
                "post" -> HeroBadge("FINAL", Color.White.copy(alpha = 0.20f))
                else -> HeroBadge("UPCOMING", BrandOrange)
            }
            HeroBadge(item.game.sport.uppercase(), Color.White.copy(alpha = 0.18f))
        }

        is HeroItem.LiveCreator -> {
            HeroLivePill()
            HeroBadge(
                item.creator.kind.displayLabel.uppercase(),
                heroSourceColor(item.creator.kind),
            )
        }

        is HeroItem.CreatorUpload -> {
            val kind = SourceKind.from(item.upload.titleId)
            HeroBadge(kind.displayLabel.uppercase(), heroSourceColor(kind))
        }
    }
}

@Composable
private fun HeroBottom(item: HeroItem, accent: Color) {
    val title: String
    val cta: String
    when (item) {
        is HeroItem.Media -> {
            title = item.result.displayName
            cta = "Play"
        }
        is HeroItem.Game -> {
            title = "${item.game.away.shortName.ifEmpty { item.game.away.name }} vs " +
                item.game.home.shortName.ifEmpty { item.game.home.name }
            cta = when (item.game.state) {
                "live" -> "Watch Live"
                "post" -> "Watch Recap"
                else -> "View Game"
            }
        }
        is HeroItem.LiveCreator -> {
            title = item.creator.streamTitle ?: item.creator.displayName
            cta = "Watch live"
        }
        is HeroItem.CreatorUpload -> {
            title = item.upload.episodeTitle ?: item.upload.title ?: ""
            cta = "Watch"
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            text = title,
            fontSize = 20.sp,
            fontWeight = FontWeight.Bold,
            color = Color.White,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        HeroMetaRow(item)
        HeroCtaPill(cta, accent)
    }
}

@Composable
private fun HeroMetaRow(item: HeroItem) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        when (item) {
            is HeroItem.Media -> {
                HeroMeta(if (item.result.isTV) "Series" else "Movie")
                item.result.year?.let { HeroDot(); HeroMeta(it.toString()) }
                item.result.voteAverage?.takeIf { it > 0 }?.let {
                    HeroDot()
                    Text(
                        text = "\u2605 ${String.format("%.1f", it)}",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = BrandOrange,
                    )
                }
            }

            is HeroItem.Game -> {
                if (item.game.state != "pre") {
                    Text(
                        text = "${item.game.away.abbreviation} ${item.game.away.score}" +
                            " \u2013 ${item.game.home.score} ${item.game.home.abbreviation}",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Black,
                        color = Color.White,
                        maxLines = 1,
                    )
                    HeroDot()
                }
                HeroMeta(item.game.statusDetail, weight = FontWeight.SemiBold)
            }

            is HeroItem.LiveCreator -> {
                HeroMeta(item.creator.displayName, weight = FontWeight.SemiBold)
                item.creator.category?.takeIf { it.isNotEmpty() }?.let {
                    HeroDot(); HeroMeta(it)
                }
                item.creator.viewerCount?.takeIf { it > 0 }?.let {
                    HeroDot()
                    Text(
                        text = compactViewers(it),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White,
                    )
                }
            }

            is HeroItem.CreatorUpload -> {
                HeroMeta(item.upload.title ?: "", weight = FontWeight.SemiBold)
            }
        }
    }
}

private fun compactViewers(n: Int): String = when {
    n >= 1_000_000 -> String.format("%.1fM watching", n / 1_000_000.0)
    n >= 1_000 -> String.format("%.1fK watching", n / 1_000.0)
    else -> "$n watching"
}

@Composable
private fun HeroMeta(text: String, weight: FontWeight = FontWeight.Medium) {
    Text(
        text = text,
        fontSize = 12.sp,
        fontWeight = weight,
        color = Color.White.copy(alpha = 0.78f),
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
    )
}

@Composable
private fun HeroDot() {
    Text(
        text = "\u00B7",
        fontSize = 12.sp,
        fontWeight = FontWeight.Bold,
        color = Color.White.copy(alpha = 0.4f),
    )
}

@Composable
private fun HeroBadge(text: String, bg: Color) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(bg.copy(alpha = 0.9f))
            .padding(horizontal = 9.dp, vertical = 4.dp),
    ) {
        Text(
            text = text,
            fontSize = 10.sp,
            fontWeight = FontWeight.Black,
            color = Color.White,
            maxLines = 1,
        )
    }
}

@Composable
private fun HeroLivePill() {
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(HeroLiveRed)
            .padding(horizontal = 9.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Box(
            modifier = Modifier
                .size(6.dp)
                .clip(CircleShape)
                .background(Color.White),
        )
        Text(
            text = "LIVE",
            fontSize = 10.sp,
            fontWeight = FontWeight.Black,
            color = Color.White,
            maxLines = 1,
        )
    }
}

@Composable
private fun HeroCtaPill(label: String, tint: Color) {
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(Color.Black.copy(alpha = 0.42f))
            .border(1.5.dp, tint, RoundedCornerShape(50))
            .padding(horizontal = 14.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(
            imageVector = Icons.Filled.PlayArrow,
            contentDescription = null,
            tint = tint,
            modifier = Modifier.size(15.dp),
        )
        Text(
            text = label,
            fontSize = 13.sp,
            fontWeight = FontWeight.Bold,
            color = tint,
            maxLines = 1,
        )
    }
}

// ── Today's Pick Spotlight ─────────────────────────────────────────────────

@Composable
private fun TodaysPickSpotlight(
    pick: StreamingReleasesService.StreamingReleaseRow,
    selectedServices: Set<String>,
    onOpen: (StreamingReleasesService.StreamingReleaseRow) -> Unit,
) {
    val orange = BrandOrange
    val navySurface = Color(0xFF04090F)

    // Reuse the same selected-services contains-check as Top Picks
    // (lowercased with appletv/apple and hbo/max aliases).
    val isSubscribed = run {
        val key = pick.sourceName?.lowercase() ?: ""
        if (key.isEmpty()) false else selectedServices.any { s ->
            val sl = s.lowercase()
            key.contains(sl) ||
                (sl == "appletv" && key.contains("apple")) ||
                (sl == "hbo" && (key.contains("hbo") || key.contains("max")))
        }
    }

    // Service badge color from Platform.from(sourceName), falling back to neutral.
    val platform = Platform.from(pick.sourceName)
    val badgeColor = platform?.color ?: Color.White.copy(alpha = 0.25f)
    val badgeName = platform?.name ?: pick.sourceName
    val badgeTextColor = platform?.textColor ?: Color.White

    // CTA text: "Watch on <source>" when subscribed, "Get on <source>" when not, "Watch now" when null.
    val ctaText = if (!pick.sourceName.isNullOrEmpty()) {
        if (isSubscribed) "Watch on ${pick.sourceName}" else "Get on ${pick.sourceName}"
    } else {
        "Watch now"
    }

    // Date string: "Wednesday, Jul 22"
    val dateFormatter = remember {
        java.time.format.DateTimeFormatter.ofPattern("EEEE, MMM d")
    }
    val dateString = remember { java.time.LocalDate.now().format(dateFormatter) }

    // Poster URL: prefer posterUrl, fall back to building from posterPath via TMDB CDN.
    val posterUrl = pick.posterUrl ?: pick.posterPath?.let { path ->
        val clean = if (path.startsWith("/")) path else "/$path"
        "${com.rork.guidestreamtvandroid.AppConfig.TMDB_IMAGE_BASE}w500$clean"
    }

    // streaming_releases has no backdrop column — resolve a 16:9 backdrop
    // client-side from TMDB. Keyed on tmdbId so the fetch never re-runs on
    // recomposition or scroll; failures fall back to the poster treatment.
    val tmdb = remember { TMDBService.get() }
    var backdropUrl by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(pick.tmdbId) {
        backdropUrl = try {
            val detail = if (pick.tmdbType == "tv") tmdb.getTVDetail(pick.tmdbId) else tmdb.getMovieDetail(pick.tmdbId)
            detail?.backdropPath?.let { path ->
                val clean = if (path.startsWith("/")) path else "/$path"
                "${com.rork.guidestreamtvandroid.AppConfig.TMDB_IMAGE_BASE}w1280$clean"
            }
        } catch (_: Exception) { null }
    }

    Column(
        modifier = Modifier
            .padding(horizontal = 12.dp, vertical = 8.dp)
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(navySurface.copy(alpha = 0.95f))
            .border(1.dp, Color.White.copy(alpha = 0.10f), RoundedCornerShape(12.dp))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onOpen(pick) },
    ) {
        // Eyebrow row: flame + "TODAY'S PICK" + trailing date
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "\uD83D\uDD25",
                fontSize = 17.sp,
            )
            Spacer(Modifier.width(6.dp))
            Text(
                text = "TODAY'S PICK",
                fontSize = 15.sp,
                fontWeight = FontWeight.Black,
                color = orange,
                letterSpacing = 1.2.sp,
                maxLines = 1,
            )
            Spacer(Modifier.weight(1f))
            Text(
                text = dateString,
                fontSize = 15.sp,
                fontWeight = FontWeight.Medium,
                color = Color.White.copy(alpha = 0.5f),
                maxLines = 1,
                softWrap = false,
                overflow = TextOverflow.Ellipsis,
            )
        }

        // 16:9 backdrop
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(16f / 9f),
        ) {
            if (backdropUrl != null) {
                RemoteImage(
                    url = backdropUrl,
                    modifier = Modifier.fillMaxSize(),
                )
            } else {
                RemoteImage(
                    url = posterUrl,
                    modifier = Modifier
                        .fillMaxSize()
                        .blur(20.dp)
                        .alpha(0.55f),
                )
                RemoteImage(
                    url = posterUrl,
                    modifier = Modifier.fillMaxSize(),
                )
            }
            // Gradient overlay for readability
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        Brush.verticalGradient(
                            colors = listOf(
                                Color.Transparent,
                                Color.Black.copy(alpha = 0.65f),
                            ),
                        ),
                    ),
            )
        }

        // Title + meta + badge + CTA
        Column(
            modifier = Modifier.padding(16.dp),
        ) {
            Text(
                text = pick.title ?: "Untitled",
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.height(8.dp))

            // Meta: star + rating, optional "· Source Original"
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = "★",
                    fontSize = 11.sp,
                    color = orange,
                )
                Spacer(Modifier.width(4.dp))
                pick.voteAverage?.let { rating ->
                    Text(
                        text = String.format("%.1f", rating),
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White.copy(alpha = 0.7f),
                    )
                }
                if (pick.isOriginal == true && !pick.sourceName.isNullOrEmpty()) {
                    Text(
                        text = " · ${pick.sourceName} Original",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color.White.copy(alpha = 0.5f),
                    )
                }
            }

            // Service badge
            if (!pick.sourceName.isNullOrEmpty()) {
                Spacer(Modifier.height(10.dp))
                Row(
                    modifier = Modifier
                        .clip(RoundedCornerShape(50))
                        .background(badgeColor.copy(alpha = 0.15f))
                        .padding(horizontal = 10.dp, vertical = 5.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(
                        modifier = Modifier
                            .size(8.dp)
                            .clip(CircleShape)
                            .background(badgeColor),
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(
                        text = (badgeName ?: "").let { if (it.length > 12) it.take(12) else it },
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = badgeTextColor,
                    )
                }
            }

            // Full-width primary CTA
            Spacer(Modifier.height(14.dp))
            Text(
                text = ctaText,
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
                color = Color(0xFF080604),
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(10.dp))
                    .background(orange)
                    .clickable { onOpen(pick) }
                    .padding(vertical = 13.dp),
            )
        }
    }
}

// ── New Episodes Section ─────────────────────────────────────────────────────

/**
 * Home rail for `new_episodes`. Mirrors the iOS section of the same name.
 *
 * Android had no New Episodes surface at all until now — `Routes.NEW_EPISODES`
 * was declared and never referenced, and nothing on Home read
 * `StreamsViewModel.newEpisodes` — so a followed show could fire a push and
 * still appear nowhere in the app. See
 * `claude/lioness-s3e5-no-alert-no-badge-aug31-2026.md`.
 *
 * That flow is already filtered to rows still new for THIS viewer
 * (`isNewForViewer`, GUI-74), sorted newest-first and capped at 20, so the rail
 * only slices it. Renders nothing at all when there is nothing new.
 */
@Composable
private fun NewEpisodesSection(
    episodes: List<NewEpisodeRow>,
    onOpen: (NewEpisodeRow) -> Unit,
    onSeeAll: () -> Unit,
    modifier: Modifier = Modifier,
) {
    if (episodes.isEmpty()) return
    Column(modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(
                text = "New Episodes",
                fontSize = 18.sp,
                lineHeight = 22.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
            )
            Spacer(Modifier.weight(1f))
            Text(
                text = "See all",
                fontSize = 13.sp,
                lineHeight = 16.sp,
                fontWeight = FontWeight.SemiBold,
                color = BrandOrange,
                modifier = Modifier.clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) { onSeeAll() },
            )
        }
        Spacer(Modifier.height(10.dp))
        LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            items(episodes.take(12)) { row ->
                NewEpisodeCard(row = row, onClick = { onOpen(row) })
            }
        }
    }
}

// ── Watch List Section ───────────────────────────────────────────────────────

@Composable
private fun WatchListSection(
    streams: List<com.rork.guidestreamtvandroid.data.models.UserStream>,
    watchedIds: Set<String>,
    latestContentAt: Map<String, Long>,
    latestContentKind: Map<String, String>,
    seenContentAt: Map<String, Long>,
    isAuthenticated: Boolean,
    onOpen: (com.rork.guidestreamtvandroid.data.models.UserStream) -> Unit,
    onSeeAll: (() -> Unit)? = null,
    onSignIn: () -> Unit = {},
) {
    if (streams.isEmpty()) {
        if (isAuthenticated) {
            EmptyStateRow(
                title = "My Watch List",
                message = "Tap the + on any show to add it here.",
                onSeeAll = onSeeAll,
            )
        } else {
            // Guest with no items — invitation, not a sign-in wall.
            Column(Modifier.padding(horizontal = rememberWidthClass().homeHorizontalPadding, vertical = 8.dp)) {
                Row(verticalAlignment = Alignment.Bottom) {
                    Text(
                        text = "My Watch List",
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold,
                        color = TextPrimary,
                    )
                }
                Spacer(Modifier.height(10.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.Start,
                    verticalAlignment = Alignment.Top,
                ) {
                    Box(
                        modifier = Modifier
                            .size(52.dp)
                            .clip(RoundedCornerShape(12.dp))
                            .background(BrandOrange.copy(alpha = 0.14f)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            imageVector = Icons.Filled.Star,
                            contentDescription = null,
                            tint = BrandOrange,
                            modifier = Modifier.size(22.dp),
                        )
                    }
                    Spacer(Modifier.width(12.dp))
                    Column {
                        Text(
                            text = "Nothing here yet",
                            fontSize = 14.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = TextPrimary,
                        )
                        Spacer(Modifier.height(2.dp))
                        Text(
                            text = "Add a show and we'll tell you the moment a new episode lands on one of your services.",
                            fontSize = 12.sp,
                            color = TextSecondary,
                        )
                        Spacer(Modifier.height(4.dp))
                        Text(
                            text = "Browse shows",
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = BrandOrange,
                            modifier = Modifier.clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                            ) { onSeeAll?.invoke() },
                        )
                    }
                }
            }
        }
        return
    }
    // Sort newest-content-first, preserving incoming index as a tiebreaker.
    // Titles with a recency entry sort ahead of those without; ties fall back
    // to the original added_at-desc order.
    val indexByTitleId = remember(streams) {
        val m = HashMap<String, Int>()
        for ((i, s) in streams.withIndex()) {
            if (s.titleId !in m) m[s.titleId] = i
        }
        m
    }
    // Reuses the shared badge rules so the Home rail always agrees with the
    // full My Watch List screen — no extra query, every input is already in memory.
    val streamsVm = StreamsViewModel.get()
    val sortedStreams = remember(streams, latestContentAt) {
        streams.sortedWith(
            compareByDescending<com.rork.guidestreamtvandroid.data.models.UserStream> { stream ->
                latestContentAt.containsKey(stream.titleId)
            }.thenByDescending { stream ->
                latestContentAt[stream.titleId] ?: Long.MIN_VALUE
            }.thenBy { stream ->
                indexByTitleId[stream.titleId] ?: streams.size
            },
        )
    }
    Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(
                text = "My Watch List",
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
            )
            if (onSeeAll != null) {
                Spacer(Modifier.weight(1f))
                Text(
                    text = "See all",
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = BrandOrange,
                    modifier = Modifier
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) { onSeeAll() },
                )
            }
        }
        Spacer(Modifier.height(10.dp))
        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(sortedStreams.take(15)) { stream ->
                WatchListCard(
                    stream = stream,
                    isWatched = watchedIds.contains(stream.titleId),
                    badgeText = streamsVm.newBadgeText(
                        stream,
                        latestContentAt,
                        latestContentKind,
                        seenContentAt,
                    ),
                    onClick = { onOpen(stream) },
                )
            }
        }
        // Quiet sync footer for guests with items — not a sign-in wall.
        if (!isAuthenticated) {
            Row(
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.Start,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "${streams.size} saved on this device. ",
                    fontSize = 11.sp,
                    color = TextSecondary,
                )
                Text(
                    text = "Sign in",
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = BrandOrange,
                    modifier = Modifier.clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onSignIn() },
                )
                Text(
                    text = " to keep them across devices.",
                    fontSize = 11.sp,
                    color = TextSecondary,
                )
            }
        }
    }
}

@Composable
private fun WatchListCard(
    stream: com.rork.guidestreamtvandroid.data.models.UserStream,
    isWatched: Boolean = false,
    /** "NEW EPISODE" / "NEW UPLOAD", or null when the title should not badge. */
    badgeText: String? = null,
    onClick: () -> Unit,
) {
    Column(
        modifier = Modifier
            .width(164.dp)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() },
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(0.6667f)
                .clip(RoundedCornerShape(10.dp)),
        ) {
            RemoteImage(
                url = stream.posterUrl,
                contentDescription = stream.title ?: stream.titleName,
                modifier = Modifier.fillMaxSize(),
                cornerRadius = 10,
                placeholderText = (stream.title ?: stream.titleName ?: stream.titleId).take(2).uppercase(),
                placeholderFontSize = 20.sp,
            )
            // Platform color bar
            val platform = Platform.from(stream.platform)
            if (platform != null) {
                Box(
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .fillMaxWidth()
                        .height(3.dp)
                        .background(platform.color),
                )
            }
            // New-content badge, top-left so it never collides with the
            // BottomEnd watched eye or the bottom platform color bar.
            if (badgeText != null) {
                Box(
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .padding(8.dp)
                        .clip(RoundedCornerShape(6.dp))
                        .background(Color.Black)
                        .padding(horizontal = 8.dp, vertical = 4.dp),
                ) {
                    Text(
                        text = badgeText,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                        maxLines = 1,
                    )
                }
            }
            // Display-only watched badge — never mutates any saved title.
            if (isWatched) {
                Box(
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(4.dp)
                        .size(20.dp)
                        .clip(CircleShape)
                        .background(BrandBlue),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.Filled.Visibility,
                        contentDescription = "Watched",
                        tint = Color.White,
                        modifier = Modifier.size(12.dp),
                    )
                }
            }
        }
        Spacer(Modifier.height(6.dp))
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            // GUI-70: movie vs series at a glance. A saved row whose media
            // type never resolves (legacy row, creator, podcast, game) gets no
            // glyph rather than a guessed one.
            val savedIsTv = stream.isTv ?: TitleId.isTv(stream.titleId)
            if (savedIsTv != null) MediaTypeGlyph(isTV = savedIsTv, size = 11.dp)
            Text(
                text = stream.title ?: stream.titleName ?: "Untitled",
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
                color = TextPrimary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

// ── Generic Poster Section ───────────────────────────────────────────────────

@Composable
private fun PosterSection(
    title: String,
    shows: List<TMDBResult>,
    providerByTmdb: Map<Int, Platform>,
    onOpen: (TMDBResult) -> Unit,
    badgeText: ((TMDBResult) -> String?)? = null,
    accentColor: Color = BrandOrange,
    onSeeAll: (() -> Unit)? = null,
    badgeAsMatchChip: Boolean = false,
) {
    if (shows.isEmpty()) return
    Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(
                text = title,
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
            )
            Spacer(Modifier.width(6.dp))
            Box(
                modifier = Modifier
                    .size(6.dp)
                    .clip(RoundedCornerShape(3.dp))
                    .background(accentColor)
                    .align(Alignment.Bottom),
            )
            if (onSeeAll != null) {
                Spacer(Modifier.weight(1f))
                Text(
                    text = "See all",
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = accentColor,
                    modifier = Modifier
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) { onSeeAll() },
                )
            }
        }
        Spacer(Modifier.height(10.dp))
        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(shows) { r ->
                val badge = badgeText?.invoke(r)
                PosterCardWithBadge(
                    show = r,
                    platformColor = providerByTmdb[r.id]?.color,
                    badgeText = badge,
                    onClick = { onOpen(r) },
                    badgeAsMatchChip = badgeAsMatchChip,
                )
            }
        }
    }
}

@Composable
private fun PosterCardWithBadge(
    show: TMDBResult,
    platformColor: Color?,
    badgeText: String?,
    onClick: () -> Unit,
    badgeAsMatchChip: Boolean = false,
) {
    Column(
        modifier = Modifier
            .width(164.dp)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() },
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(0.6667f)
                .clip(RoundedCornerShape(10.dp)),
        ) {
            RemoteImage(
                url = show.posterUrl,
                contentDescription = show.displayName,
                modifier = Modifier.fillMaxSize(),
                cornerRadius = 10,
                placeholderText = show.displayName.take(2).uppercase(),
                placeholderFontSize = 20.sp,
            )
            if (platformColor != null) {
                Box(
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .fillMaxWidth()
                        .height(3.dp)
                        .background(platformColor),
                )
            }
            if (badgeAsMatchChip && badgeText != null) {
                Box(
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(5.dp)
                        .clip(RoundedCornerShape(5.dp))
                        .background(BrandBlue.copy(alpha = 0.9f))
                        .padding(horizontal = 5.dp, vertical = 3.dp),
                ) {
                    Text(
                        text = badgeText,
                        fontSize = 8.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                    )
                }
            }
        }
        Spacer(Modifier.height(6.dp))
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            // GUI-70: movie vs series at a glance.
            MediaTypeGlyph(isTV = show.isTV, size = 11.dp)
            Text(
                text = show.displayName,
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
                color = TextPrimary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        if (!badgeAsMatchChip) {
            if (badgeText != null) {
                Text(
                    text = badgeText,
                    fontSize = 10.sp,
                    color = TextSecondary,
                    fontWeight = FontWeight.Medium,
                )
            } else if (show.year != null) {
                Text(
                    text = show.year.toString(),
                    fontSize = 10.sp,
                    color = TextSecondary,
                )
            }
        }
    }
}

// ── Trending Ranked Section ──────────────────────────────────────────────────

@Composable
private fun TrendingRankedSection(
    shows: List<TMDBResult>,
    providerByTmdb: Map<Int, Platform>,
    trueRanks: List<Int> = emptyList(),
    onOpen: (TMDBResult) -> Unit,
    onSeeAll: (() -> Unit)? = null,
) {
    if (shows.isEmpty()) return
    Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(
                text = "Everyone's Watching",
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
            )
            if (onSeeAll != null) {
                Spacer(Modifier.weight(1f))
                Text(
                    text = "See all",
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = BrandOrange,
                    modifier = Modifier
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) { onSeeAll() },
                )
            }
        }
        Spacer(Modifier.height(10.dp))
        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            itemsIndexed(shows) { index, r ->
                PosterCardWithBadge(
                    show = r,
                    platformColor = providerByTmdb[r.id]?.color,
                    badgeText = "#${trueRanks.getOrElse(index) { index + 1 }}",
                    onClick = { onOpen(r) },
                )
            }
        }
    }
}

// ── Popular on Service Section ───────────────────────────────────────────────

@Composable
private fun PopularOnServiceSection(
    serviceName: String,
    accentColor: Color,
    shows: List<TMDBResult>,
    onOpen: (TMDBResult) -> Unit,
    onSeeAll: (() -> Unit)? = null,
) {
    if (shows.isEmpty()) return
    Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(
                text = "Popular on ",
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
            )
            Text(
                text = serviceName,
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = accentColor,
            )
            if (onSeeAll != null) {
                Spacer(Modifier.weight(1f))
                Text(
                    text = "See all",
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = accentColor,
                    modifier = Modifier
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) { onSeeAll() },
                )
            }
        }
        Spacer(Modifier.height(10.dp))
        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(shows) { r ->
                PosterCardWithBadge(
                    show = r,
                    platformColor = accentColor,
                    badgeText = null,
                    onClick = { onOpen(r) },
                )
            }
        }
    }
}

// ── Around the World Section ────────────────────────────────────────────────

@Composable
private fun AroundTheWorldSection(
    subtitle: String,
    shows: List<TMDBResult>,
    onOpen: (TMDBResult) -> Unit,
    onSeeAll: () -> Unit,
    modifier: Modifier = Modifier,
) {
    if (shows.isEmpty()) return
    Column(modifier) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(
                text = "Around the World",
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
            )
            Spacer(Modifier.width(6.dp))
            Box(
                modifier = Modifier
                    .size(6.dp)
                    .clip(RoundedCornerShape(3.dp))
                    .background(BrandOrange)
                    .align(Alignment.Bottom),
            )
            Spacer(Modifier.weight(1f))
            Text(
                text = "See all",
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = BrandOrange,
                modifier = Modifier
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onSeeAll() },
            )
        }
        Spacer(Modifier.height(2.dp))
        Text(
            text = subtitle,
            fontSize = 12.sp,
            color = TextSecondary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Spacer(Modifier.height(10.dp))
        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(shows) { r ->
                PosterCardWithBadge(
                    show = r,
                    platformColor = BrandOrange,
                    badgeText = null,
                    onClick = { onOpen(r) },
                )
            }
        }
    }
}

// ── Now & Next on Service Section ────────────────────────────────────────

/** Matches iOS's NEW pill green (#16A34A) so both rails read identically. */
private val NowNextPillGreen = Color(0xFF16A34A)

@Composable
private fun NowAndNextSection(
    serviceName: String,
    accentColor: Color,
    entries: List<NowNextEntry>,
    onOpen: (NowNextEntry) -> Unit,
    onSeeAll: (() -> Unit)? = null,
) {
    if (entries.isEmpty()) return
    Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(
                text = "Now & Next on ",
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
            )
            Text(
                text = serviceName,
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = accentColor,
            )
            if (onSeeAll != null) {
                Spacer(Modifier.weight(1f))
                Text(
                    text = "See all",
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = accentColor,
                    modifier = Modifier
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) { onSeeAll() },
                )
            }
        }
        Spacer(Modifier.height(10.dp))
        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(entries) { entry ->
                NowNextPosterCard(
                    entry = entry,
                    accentColor = accentColor,
                    onClick = { onOpen(entry) },
                )
            }
        }
    }
}

@Composable
private fun NowNextPosterCard(
    entry: NowNextEntry,
    accentColor: Color,
    onClick: () -> Unit,
) {
    Column(
        modifier = Modifier
            .width(164.dp)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() },
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(0.6667f)
                .clip(RoundedCornerShape(10.dp)),
        ) {
            RemoteImage(
                url = entry.posterUrl,
                contentDescription = entry.result.displayName,
                modifier = Modifier.fillMaxSize(),
                cornerRadius = 10,
                placeholderText = entry.result.displayName.take(2).uppercase(),
                placeholderFontSize = 20.sp,
            )
            Box(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .height(3.dp)
                    .background(accentColor),
            )
            // Pill overlay owned by this section — green NEW for fresh
            // arrivals, neutral dark date for upcoming, nothing for backfill.
            if (entry.isNow) {
                Box(
                    modifier = Modifier
                        .align(Alignment.BottomStart)
                        .padding(8.dp)
                        .clip(RoundedCornerShape(50))
                        .background(NowNextPillGreen)
                        .padding(horizontal = 8.dp, vertical = 4.dp),
                ) {
                    Text(
                        text = "NEW",
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                        maxLines = 1,
                    )
                }
            } else if (entry.dateText != null) {
                Box(
                    modifier = Modifier
                        .align(Alignment.BottomStart)
                        .padding(8.dp)
                        .clip(RoundedCornerShape(50))
                        .background(Color.Black.copy(alpha = 0.72f))
                        .padding(horizontal = 8.dp, vertical = 4.dp),
                ) {
                    Text(
                        text = entry.dateText,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White.copy(alpha = 0.9f),
                        maxLines = 1,
                    )
                }
            }
        }
        Spacer(Modifier.height(6.dp))
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            // GUI-70: movie vs series at a glance.
            MediaTypeGlyph(isTV = entry.result.isTV, size = 11.dp)
            Text(
                text = entry.result.displayName,
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
                color = TextPrimary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Text(
            text = entry.meta,
            fontSize = 10.sp,
            color = TextSecondary,
            fontWeight = FontWeight.Medium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

// ── Empty State ──────────────────────────────────────────────────────────────

@Composable
private fun EmptyStateRow(title: String, message: String, onSeeAll: (() -> Unit)? = null) {
    Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(
                text = title,
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
            )
            if (onSeeAll != null) {
                Spacer(Modifier.weight(1f))
                Text(
                    text = "See all",
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = BrandOrange,
                    modifier = Modifier
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) { onSeeAll() },
                )
            }
        }
        Spacer(Modifier.height(10.dp))
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .glassCard()
                .padding(vertical = 24.dp, horizontal = 12.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = message,
                fontSize = 13.sp,
                color = TextTertiary,
            )
        }
    }
}

// ── Creators/Podcasts for You ────────────────────────────────────────────────

@Composable
private fun CreatorsForYouSection(
    creators: List<RecommendedCreator>,
    onOpen: (RecommendedCreator) -> Unit,
    onSeeAll: (() -> Unit)? = null,
) {
    if (creators.isEmpty()) return
    Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(
                text = "Creators/Podcasts for You",
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
            )
            if (onSeeAll != null) {
                Spacer(Modifier.weight(1f))
                Text(
                    text = "See all",
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = BrandBlue,
                    modifier = Modifier
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) { onSeeAll() },
                )
            }
        }
        Spacer(Modifier.height(10.dp))
        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            items(creators, key = { it.titleId }) { creator ->
                CreatorAvatarCard(creator = creator, onClick = { onOpen(creator) })
            }
        }
    }
}

@Composable
private fun CreatorAvatarCard(
    creator: RecommendedCreator,
    onClick: () -> Unit,
) {
    Column(
        modifier = Modifier
            .width(164.dp)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() },
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(0.6667f)
                .clip(RoundedCornerShape(10.dp)),
        ) {
            RemoteImage(
                url = creator.imageUrl,
                contentDescription = creator.displayName,
                modifier = Modifier.fillMaxSize(),
                cornerRadius = 10,
                placeholderText = creator.displayName.take(2).uppercase(),
                placeholderFontSize = 20.sp,
            )
            val kind = SourceKind.from(creator.titleId)
            val sourceColor = when (kind) {
                SourceKind.YOUTUBE -> YouTubeRed
                SourceKind.PODCAST -> PodcastPurple
                SourceKind.TWITCH -> TwitchPurple
                SourceKind.KICK -> KickGreen
                else -> BrandOrange
            }
            Box(
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .padding(5.dp)
                    .clip(RoundedCornerShape(4.dp))
                    .background(sourceColor.copy(alpha = 0.9f))
                    .padding(horizontal = 6.dp, vertical = 2.dp),
            ) {
                Text(
                    text = kind.displayLabel.uppercase(),
                    fontSize = 8.sp,
                    fontWeight = FontWeight.Bold,
                    color = if (kind == SourceKind.KICK) Color.Black else Color.White,
                )
            }
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(5.dp)
                    .clip(RoundedCornerShape(5.dp))
                    .background(BrandBlue.copy(alpha = 0.9f))
                    .padding(horizontal = 5.dp, vertical = 3.dp),
            ) {
                Text(
                    text = "${creator.matchPercentage}% Match",
                    fontSize = 8.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                )
            }
        }
        Spacer(Modifier.height(6.dp))
        Text(
            text = creator.displayName,
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            color = TextPrimary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

// ── Browse by Genre (pill grid) ──────────────────────────────────────────────

private data class GenrePill(val id: Int, val label: String, val mediaType: String)

private val browseGenres: List<GenrePill> = listOf(
    GenrePill(80, "Crime & Thriller", "tv"),
    GenrePill(10765, "Sci-Fi", "tv"),
    GenrePill(35, "Comedy", "tv"),
    GenrePill(18, "Drama", "tv"),
    GenrePill(10759, "Action", "tv"),
    GenrePill(99, "Documentary", "tv"),
    GenrePill(10749, "Romance", "movie"),
    GenrePill(10769, "International", "international"),
    GenrePill(16, "Anime", "anime"),
)

@Composable
private fun GenrePillGrid(selectedGenreId: Int, onSelect: (GenrePill) -> Unit) {
    Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
        Text(
            text = "Browse by genre",
            fontSize = 18.sp,
            fontWeight = FontWeight.Bold,
            color = TextPrimary,
        )
        Spacer(Modifier.height(10.dp))
        browseGenres.chunked(2).forEach { pair ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                pair.forEach { pill ->
                    GenrePillButton(
                        pill = pill,
                        modifier = Modifier.weight(1f),
                        selected = pill.id == selectedGenreId,
                        onClick = { onSelect(pill) },
                    )
                }
                if (pair.size == 1) {
                    Spacer(Modifier.weight(1f))
                }
            }
            Spacer(Modifier.height(10.dp))
        }
    }
}

@Composable
private fun GenrePillButton(
    pill: GenrePill,
    modifier: Modifier = Modifier,
    selected: Boolean = false,
    onClick: () -> Unit,
) {
    Box(
        modifier = modifier
            .glassCard()
            .then(if (selected) Modifier.border(2.dp, BrandOrange, RoundedCornerShape(10.dp)) else Modifier)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() }
            .padding(vertical = 14.dp, horizontal = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = pill.label,
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            color = TextPrimary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

// ── Widget Promo Banner ──────────────────────────────────────────────────────

@Composable
private fun WidgetPromoBanner(onSetUp: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 8.dp)
            .glassCard()
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onSetUp() }
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = "Add a home-screen widget",
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
            )
            Spacer(Modifier.height(4.dp))
            Text(
                text = "Track what's leaving soon at a glance.",
                fontSize = 12.sp,
                color = TextSecondary,
            )
        }
        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(8.dp))
                .background(BrandOrange)
                .padding(horizontal = 14.dp, vertical = 8.dp),
        ) {
            Text(
                text = "Set Up",
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
            )
        }
    }
}


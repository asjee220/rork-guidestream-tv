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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.rork.guidestreamtvandroid.data.models.Platform
import com.rork.guidestreamtvandroid.data.models.SourceKind
import com.rork.guidestreamtvandroid.data.models.StreamingCatalog
import com.rork.guidestreamtvandroid.data.models.TMDBResult
import com.rork.guidestreamtvandroid.data.remote.RecommendedCreator
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.data.repository.StreamsViewModel
import com.rork.guidestreamtvandroid.data.repository.WatchIntentLogger
import com.rork.guidestreamtvandroid.ui.components.PosterCard
import com.rork.guidestreamtvandroid.ui.components.RemoteImage
import com.rork.guidestreamtvandroid.ui.components.ServicesPill
import com.rork.guidestreamtvandroid.ui.components.ShimmerHero
import com.rork.guidestreamtvandroid.ui.components.ShimmerSection
import com.rork.guidestreamtvandroid.ui.ads.PooledAdSource
import com.rork.guidestreamtvandroid.ui.ads.SponsoredSlot
import com.rork.guidestreamtvandroid.ui.components.glassCard
import com.rork.guidestreamtvandroid.ui.home.HomeViewModel
import com.rork.guidestreamtvandroid.ui.navigation.HomeListTarget
import com.rork.guidestreamtvandroid.ui.navigation.PendingTitleRoute
import com.rork.guidestreamtvandroid.ui.theme.BottomSafeSpacer
import com.rork.guidestreamtvandroid.ui.theme.BrandBlue
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.GlassFill
import com.rork.guidestreamtvandroid.ui.theme.GlassStroke
import com.rork.guidestreamtvandroid.ui.theme.LightBlue
import com.rork.guidestreamtvandroid.ui.theme.Navy
import com.rork.guidestreamtvandroid.ui.theme.NewsGreen
import com.rork.guidestreamtvandroid.ui.theme.OutlineVariant
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary
import com.rork.guidestreamtvandroid.ui.theme.BrandWordmark
import com.rork.guidestreamtvandroid.ui.theme.WordmarkSize

/**
 * Home feed — mirrors iOS HomeView.swift.
 * Search bar, hero carousel, watch list, trending, top rated, genre discovery,
 * platform rows, coming to streaming, what's new, top picks, leaving soon,
 * binge worthy, widget promo banner.
 */
@Composable
fun HomeScreen(
    onOpenTitle: (PendingTitleRoute) -> Unit = {},
    onOpenSearch: () -> Unit = {},
    onSeeAllPopular: (serviceId: String, providerId: Int) -> Unit = { _, _ -> },
    onSeeAllList: (HomeListTarget) -> Unit = {},
    onOpenWatchList: () -> Unit = {},
    onOpenWidgetSetup: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val homeVm = HomeViewModel.get()
    val streamsVm = StreamsViewModel.get()
    val authVm = AuthViewModel.get()

    val homeReady by homeVm.homeContentReady.collectAsStateWithLifecycle()
    val trending by homeVm.trending.collectAsStateWithLifecycle()
    val onAir by homeVm.onAir.collectAsStateWithLifecycle()
    val topRated by homeVm.topRated.collectAsStateWithLifecycle()
    val newReleases by homeVm.newReleases.collectAsStateWithLifecycle()
    val upcoming by homeVm.upcoming.collectAsStateWithLifecycle()
    val bingeReady by homeVm.bingeReady.collectAsStateWithLifecycle()
    val genreShows by homeVm.genreShows.collectAsStateWithLifecycle()
    val selectedGenreName by homeVm.selectedGenreName.collectAsStateWithLifecycle()
    val recommendedCreators by homeVm.recommendedCreators.collectAsStateWithLifecycle()
    val popularByService by homeVm.popularByService.collectAsStateWithLifecycle()
    val providerByTmdb by homeVm.providerByTmdb.collectAsStateWithLifecycle()
    val preferredGenres by homeVm.preferredGenres.collectAsStateWithLifecycle()
    val userStreams by streamsVm.userStreams.collectAsStateWithLifecycle()
    val watchedIds by streamsVm.watchedIds.collectAsStateWithLifecycle()
    val selectedServices by authVm.selectedServices.collectAsStateWithLifecycle()

    LaunchedEffect(Unit) { homeVm.loadAll() }

    // Inline sponsored slot indices dismissed for this session.
    val dismissedAdSlots = remember { mutableStateMapOf<Int, Boolean>() }

    // Services editor sheet (opened from the top-bar services pill).
    var showServicesSheet by remember { mutableStateOf(false) }

    val scrollState = rememberScrollState()

    Box(modifier = modifier.fillMaxSize()) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(scrollState),
    ) {
        // Reserve space for the pinned PageBar (status bar + 56dp bar height).
        Spacer(Modifier.statusBarsPadding().height(56.dp))

        // Search bar
        SearchBar(onClick = onOpenSearch)

        // Hero carousel
        if (!homeReady) {
            Box(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                ShimmerHero()
            }
        } else if (trending.isNotEmpty()) {
            HeroCarousel(
                items = trending.filter { providerByTmdb[it.id] != null }.take(15),
                providerByTmdb = providerByTmdb,
                onOpen = { result ->
                    val platform = providerByTmdb[result.id]
                    WatchIntentLogger.get().log(
                        WatchIntentLogger.IntentEventType.CARD_TAPPED,
                        titleId = result.id.toString(),
                        platformId = platform?.name?.lowercase() ?: "tmdb",
                        metadata = mapOf("section" to "hero_carousel"),
                    )
                    onOpenTitle(PendingTitleRoute(
                        titleId = result.id.toString(),
                        titleName = result.displayName,
                        isTv = result.isTV,
                    ))
                },
            )
        }

        // My Watch List
        if (!homeReady) {
            ShimmerSection("My Watch List", Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
        } else {
            WatchListSection(
                streams = userStreams,
                watchedIds = watchedIds,
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
                    ))
                },
                onSeeAll = {
                    WatchIntentLogger.get().log(
                        WatchIntentLogger.IntentEventType.CARD_TAPPED,
                        metadata = mapOf("section" to "watch_list_see_all"),
                    )
                    onOpenWatchList()
                },
            )
        }

        // Coming to Streaming (upcoming movies)
        if (!homeReady) {
            ShimmerSection("Coming to Streaming", Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
        } else if (upcoming.isNotEmpty()) {
            PosterSection(
                title = "Coming to Streaming",
                shows = upcoming.take(12),
                providerByTmdb = providerByTmdb,
                onOpen = { r ->
                    WatchIntentLogger.get().log(
                        WatchIntentLogger.IntentEventType.CARD_TAPPED,
                        titleId = r.id.toString(),
                        metadata = mapOf("section" to "coming_to_streaming"),
                    )
                    onOpenTitle(PendingTitleRoute(titleId = r.id.toString(), titleName = r.displayName, isTv = false))
                },
            )
        }

        // New This Week (streaming releases from the last 7 days)
        if (!homeReady) {
            ShimmerSection("New This Week", Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
        } else if (newReleases.isNotEmpty()) {
            PosterSection(
                title = "New This Week",
                shows = newReleases.take(12),
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
            dismissed = dismissedAdSlots,
        )

        // Top Picks for You (trending scored)
        if (!homeReady) {
            ShimmerSection("Top Picks for You", Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
        } else if (trending.isNotEmpty()) {
            // Personalised Top Picks: exclude watched titles and boost titles on
            // the user's selected services above equally-rated ones. Reuses the
            // app's owned-service normalisation (lowercase name compare with the
            // apple / hbo-max special cases).
            val selected = selectedServices.map { it.lowercase() }
            fun onService(id: Int): Boolean {
                val key = providerByTmdb[id]?.name?.lowercase() ?: return false
                return selected.any { s ->
                    key.contains(s) ||
                        (s == "appletv" && key.contains("apple")) ||
                        (s == "hbo" && (key.contains("hbo") || key.contains("max")))
                }
            }
            fun scoreFor(r: TMDBResult): Double =
                0.60 * ((r.voteAverage ?: 7.0) / 10.0) +
                    (if (onService(r.id)) 0.20 else 0.0) +
                    (if (preferredGenres.isNotEmpty() && (r.genreIds ?: emptyList()).any { it in preferredGenres }) 0.20 else 0.0)
            val topPicksAll = trending
                .filter { providerByTmdb[it.id] != null }
                .filter { !watchedIds.contains(it.id.toString()) }
                .sortedByDescending { scoreFor(it) }
            val topPicks = topPicksAll.take(12)
            PosterSection(
                title = "Top Picks for You",
                shows = topPicks,
                providerByTmdb = providerByTmdb,
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
            ShimmerSection("Creators/Podcasts for You", Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
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
                            ))
                        },
                    )
                }
            }
        }

        // Trending This Week (ranked)
        if (!homeReady) {
            ShimmerSection("Trending This Week", Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
        } else if (trending.isNotEmpty()) {
            TrendingRankedSection(
                shows = trending.filter { providerByTmdb[it.id] != null }.take(12),
                providerByTmdb = providerByTmdb,
                onOpen = { r ->
                    WatchIntentLogger.get().log(
                        WatchIntentLogger.IntentEventType.CARD_TAPPED,
                        titleId = r.id.toString(),
                        metadata = mapOf("section" to "trending_ranked"),
                    )
                    onOpenTitle(PendingTitleRoute(titleId = r.id.toString(), titleName = r.displayName, isTv = r.isTV))
                },
                onSeeAll = {
                    WatchIntentLogger.get().log(
                        WatchIntentLogger.IntentEventType.CARD_TAPPED,
                        metadata = mapOf("section" to "trending_ranked_see_all"),
                    )
                    onSeeAllList(HomeListTarget(title = "Trending This Week", tag = "TRENDING", shows = trending.filter { providerByTmdb[it.id] != null }, providerByTmdb = providerByTmdb))
                },
            )
        }

        // Leaving Soon (on-air — placeholder for real Watchmode data)
        if (!homeReady) {
            ShimmerSection("Leaving Soon", Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
        } else if (onAir.isNotEmpty()) {
            PosterSection(
                title = "Leaving Soon",
                shows = onAir.filter { providerByTmdb[it.id] != null }.take(12),
                providerByTmdb = providerByTmdb,
                accentColor = BrandOrange,
                onOpen = { r ->
                    WatchIntentLogger.get().log(
                        WatchIntentLogger.IntentEventType.CARD_TAPPED,
                        titleId = r.id.toString(),
                        metadata = mapOf("section" to "leaving_soon"),
                    )
                    onOpenTitle(PendingTitleRoute(titleId = r.id.toString(), titleName = r.displayName, isTv = true))
                },
                onSeeAll = {
                    WatchIntentLogger.get().log(
                        WatchIntentLogger.IntentEventType.CARD_TAPPED,
                        metadata = mapOf("section" to "leaving_soon_see_all"),
                    )
                    onSeeAllList(HomeListTarget(title = "Leaving Soon", tag = "LEAVING SOON", shows = onAir.filter { providerByTmdb[it.id] != null }, providerByTmdb = providerByTmdb))
                },
            )
        }

        // Inline sponsored slot #1 — after Leaving Soon
        InlineAdSlot(
            slotIndex = 1,
            selectedServices = selectedServices,
            dismissed = dismissedAdSlots,
        )

        // Popular on {service}
        val services = StreamingCatalog.ordered(selectedServices)
        if (!homeReady) {
            services.take(3).forEach { svc ->
                ShimmerSection("Popular on ${svc.name}", Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
            }
        } else {
            services.forEach { svc ->
                val results = popularByService[svc.id] ?: emptyList()
                if (results.isNotEmpty()) {
                    val providerId = HomeViewModel.get().providerIdFor(svc.id)
                    PopularOnServiceSection(
                        serviceName = svc.name,
                        accentColor = svc.glow,
                        shows = results.take(12),
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
            }
        }

        // Browse by genre (pill grid) — drives the Because you watch rail below.
        GenrePillGrid(
            onSelect = { pill -> HomeViewModel.get().loadGenre(pill.id, pill.label, pill.mediaType) },
        )

        // Because You Watch (genre discovery)
        if (!homeReady) {
            ShimmerSection("Because you watch $selectedGenreName", Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
        } else if (genreShows.isNotEmpty()) {
            PosterSection(
                title = "Because you watch $selectedGenreName",
                shows = genreShows.filter { providerByTmdb[it.id] != null }.take(12),
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

        // Inline sponsored slot #2 — after Because you watch Crime
        InlineAdSlot(
            slotIndex = 2,
            selectedServices = selectedServices,
            dismissed = dismissedAdSlots,
        )

        // Top Rated
        if (!homeReady) {
            ShimmerSection("Top rated right now", Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
        } else if (topRated.isNotEmpty()) {
            PosterSection(
                title = "Top rated right now",
                shows = topRated.filter { providerByTmdb[it.id] != null }.take(12),
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

        // New seasons — shows you follow (on-air titles from the user's watch list)
        if (!homeReady) {
            ShimmerSection("New seasons — shows you follow", Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
        } else {
            val savedIds = userStreams.mapNotNull { it.titleId.toIntOrNull() }.toSet()
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

        // Binge Worthy (ended shows)
        if (!homeReady) {
            ShimmerSection("Binge Worthy", Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
        } else if (bingeReady.isNotEmpty()) {
            val bingeTitle = if (userStreams.isEmpty()) "Binge Worthy" else "Binge Ready 🎉"
            PosterSection(
                title = bingeTitle,
                shows = bingeReady.filter { providerByTmdb[it.id] != null }.take(12),
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

        // Inline sponsored slot #3 — after Binge Worthy
        InlineAdSlot(
            slotIndex = 3,
            selectedServices = selectedServices,
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

        // Pinned top bar — wordmark left, services pill right (mirrors iOS PageBar)
        HomePageBar(
            selectedServiceIds = StreamingCatalog.ordered(selectedServices).map { it.id },
            onOpenServices = { showServicesSheet = true },
            modifier = Modifier.align(Alignment.TopStart),
        )
    }

    if (showServicesSheet) {
        ServicesEditorSheet(
            selected = selectedServices,
            onToggle = { id ->
                val next = if (id in selectedServices) selectedServices - id else selectedServices + id
                authVm.setSelectedServices(next)
            },
            onDismiss = { showServicesSheet = false },
        )
    }
}

// ── Page Bar (pinned top) ────────────────────────────────────────────────────

@Composable
private fun HomePageBar(
    selectedServiceIds: List<String>,
    onOpenServices: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .statusBarsPadding()
            .height(56.dp)
            .padding(horizontal = 20.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BrandWordmark(size = WordmarkSize.NAV)
        Spacer(Modifier.weight(1f))
        if (selectedServiceIds.isNotEmpty()) {
            ServicesPill(
                serviceIds = selectedServiceIds,
                onTap = onOpenServices,
            )
        }
    }
}

// ── Services Editor Sheet ────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ServicesEditorSheet(
    selected: Set<String>,
    onToggle: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Navy,
    ) {
        Column {
            Text(
                text = "My services",
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
                modifier = Modifier.padding(horizontal = 20.dp),
            )
            Spacer(Modifier.height(4.dp))
            Text(
                text = "${selected.size} selected · tap to add or remove",
                fontSize = 13.sp,
                color = TextSecondary,
                modifier = Modifier.padding(horizontal = 20.dp),
            )
            Spacer(Modifier.height(16.dp))
            LazyVerticalGrid(
                columns = GridCells.Fixed(3),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(420.dp)
                    .padding(horizontal = 20.dp)
                    .navigationBarsPadding(),
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalArrangement = Arrangement.spacedBy(22.dp),
            ) {
                items(StreamingCatalog.all, key = { it.id }) { svc ->
                    ServiceEditorTile(
                        service = svc,
                        isSelected = svc.id in selected,
                        onTap = { onToggle(svc.id) },
                    )
                }
            }
            Spacer(Modifier.height(12.dp))
        }
    }
}

@Composable
private fun ServiceEditorTile(
    service: com.rork.guidestreamtvandroid.data.models.StreamingService,
    isSelected: Boolean,
    onTap: () -> Unit,
) {
    val borderColor = if (isSelected) service.glow else OutlineVariant
    val borderWidth = if (isSelected) 2.dp else 1.dp
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .aspectRatio(0.85f)
            .clip(RoundedCornerShape(14.dp))
            .background(service.bg)
            .border(borderWidth, borderColor, RoundedCornerShape(14.dp))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onTap() },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        val display = service.display
        val label = when (display) {
            is com.rork.guidestreamtvandroid.data.models.StreamingService.Display.Text -> display.text
            is com.rork.guidestreamtvandroid.data.models.StreamingService.Display.SymbolText -> display.text
            is com.rork.guidestreamtvandroid.data.models.StreamingService.Display.Star -> service.name
        }
        val labelColor = when (display) {
            is com.rork.guidestreamtvandroid.data.models.StreamingService.Display.Text -> display.color
            is com.rork.guidestreamtvandroid.data.models.StreamingService.Display.SymbolText -> display.color
            is com.rork.guidestreamtvandroid.data.models.StreamingService.Display.Star -> display.color
        }
        Text(
            text = label,
            fontSize = 13.sp,
            fontWeight = FontWeight.Black,
            color = labelColor,
            textAlign = TextAlign.Center,
        )
    }
}

// ── Search Bar ──────────────────────────────────────────────────────────────

@Composable
private fun SearchBar(onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
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

// ── Hero Carousel ────────────────────────────────────────────────────────────

@Composable
private fun HeroCarousel(
    items: List<TMDBResult>,
    providerByTmdb: Map<Int, Platform>,
    onOpen: (TMDBResult) -> Unit,
) {
    if (items.isEmpty()) return
    LazyRow(
        contentPadding = PaddingValues(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.padding(vertical = 8.dp),
    ) {
        items(items.take(10)) { result ->
            val platform = providerByTmdb[result.id]
            val accent = platform?.color ?: BrandOrange
            Box(
                modifier = Modifier
                    .width(280.dp)
                    .aspectRatio(1.7f)
                    .clip(RoundedCornerShape(16.dp))
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onOpen(result) },
            ) {
                RemoteImage(
                    url = result.backdropUrl ?: result.posterUrl,
                    contentDescription = result.displayName,
                    modifier = Modifier.fillMaxSize(),
                    cornerRadius = 16,
                    placeholderText = result.displayName.take(2).uppercase(),
                    placeholderFontSize = 28.sp,
                )
                // Gradient overlay
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(
                            Brush.verticalGradient(
                                colors = listOf(
                                    Color.Transparent,
                                    Color.Black.copy(alpha = 0.3f),
                                    Color.Black.copy(alpha = 0.75f),
                                ),
                            ),
                        ),
                )
                // Platform badge
                if (platform != null) {
                    Box(
                        modifier = Modifier
                            .align(Alignment.TopStart)
                            .padding(10.dp)
                            .clip(RoundedCornerShape(6.dp))
                            .background(accent.copy(alpha = 0.85f))
                            .padding(horizontal = 8.dp, vertical = 3.dp),
                    ) {
                        Text(
                            text = platform.name,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White,
                        )
                    }
                }
                // Title
                Column(
                    modifier = Modifier
                        .align(Alignment.BottomStart)
                        .padding(14.dp),
                ) {
                    Text(
                        text = result.displayName,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                        color = TextPrimary,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    if (result.voteAverage != null) {
                        Text(
                            text = "★ ${String.format("%.1f", result.voteAverage)}",
                            fontSize = 12.sp,
                            color = BrandOrange,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                }
            }
        }
    }
}

// ── Watch List Section ───────────────────────────────────────────────────────

@Composable
private fun WatchListSection(
    streams: List<com.rork.guidestreamtvandroid.data.models.UserStream>,
    watchedIds: Set<String>,
    onOpen: (com.rork.guidestreamtvandroid.data.models.UserStream) -> Unit,
    onSeeAll: (() -> Unit)? = null,
) {
    if (streams.isEmpty()) {
        EmptyStateRow(
            title = "My Watch List",
            message = "Tap the + on any show to add it here.",
            onSeeAll = onSeeAll,
        )
        return
    }
    Column(Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) {
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
            items(streams.take(15)) { stream ->
                WatchListCard(
                    stream = stream,
                    isWatched = watchedIds.contains(stream.titleId),
                    onClick = { onOpen(stream) },
                )
            }
        }
    }
}

@Composable
private fun WatchListCard(
    stream: com.rork.guidestreamtvandroid.data.models.UserStream,
    isWatched: Boolean = false,
    onClick: () -> Unit,
) {
    Column(
        modifier = Modifier
            .width(120.dp)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() },
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(0.67f)
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
) {
    if (shows.isEmpty()) return
    Column(Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) {
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
) {
    Column(
        modifier = Modifier
            .width(150.dp)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() },
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(0.67f)
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
        }
        Spacer(Modifier.height(6.dp))
        Text(
            text = show.displayName,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            color = TextPrimary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
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

// ── Trending Ranked Section ──────────────────────────────────────────────────

@Composable
private fun TrendingRankedSection(
    shows: List<TMDBResult>,
    providerByTmdb: Map<Int, Platform>,
    onOpen: (TMDBResult) -> Unit,
    onSeeAll: (() -> Unit)? = null,
) {
    if (shows.isEmpty()) return
    Column(Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(
                text = "Trending This Week",
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
                    badgeText = "#${index + 1}",
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
    Column(Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) {
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

// ── Empty State ──────────────────────────────────────────────────────────────

@Composable
private fun EmptyStateRow(title: String, message: String, onSeeAll: (() -> Unit)? = null) {
    Column(Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) {
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
                .padding(vertical = 24.dp, horizontal = 16.dp),
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
) {
    if (creators.isEmpty()) return
    Column(Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) {
        Text(
            text = "Creators/Podcasts for You",
            fontSize = 18.sp,
            fontWeight = FontWeight.Bold,
            color = TextPrimary,
        )
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
            .width(110.dp)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() },
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            modifier = Modifier
                .size(96.dp)
                .clip(CircleShape),
        ) {
            RemoteImage(
                url = creator.imageUrl,
                contentDescription = creator.displayName,
                modifier = Modifier.fillMaxSize(),
                cornerRadius = 48,
                placeholderText = creator.displayName.take(2).uppercase(),
                placeholderFontSize = 24.sp,
            )
        }
        Spacer(Modifier.height(6.dp))
        Text(
            text = creator.displayName,
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            color = TextPrimary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
        )
        Text(
            text = creator.category,
            fontSize = 10.sp,
            color = TextSecondary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
        )
        Text(
            text = "${creator.matchPercentage}% Match",
            fontSize = 10.sp,
            color = TextSecondary,
            fontWeight = FontWeight.Medium,
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
)

@Composable
private fun GenrePillGrid(onSelect: (GenrePill) -> Unit) {
    Column(Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) {
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
    onClick: () -> Unit,
) {
    Box(
        modifier = modifier
            .glassCard()
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
            .padding(horizontal = 20.dp, vertical = 8.dp)
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

// ── Inline Sponsored Slot ───────────────────────────────────────────

/**
 * Rotating pool of the eight affiliate offers, matching the iOS inline ad pool
 * and the detail-sheet sponsored cards (headline, subtitle, service id).
 */
private val inlineAdPool: List<Triple<String, String, String>> = listOf(
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
 * Compact inline sponsored slot inserted between home feed rows — mirrors iOS
 * inlineAdSlot. Hidden once its index is dismissed for the session. Even slots
 * prefer AdMob (Rakuten backfill); odd slots render the Rakuten card directly.
 */
@Composable
private fun InlineAdSlot(
    slotIndex: Int,
    selectedServices: Set<String>,
    dismissed: MutableMap<Int, Boolean>,
) {
    if (dismissed[slotIndex] == true) return

    // Rotate through the pool, preferring a service the user doesn't already own.
    val unowned = inlineAdPool.filter { it.first !in selectedServices }
    val pool = if (unowned.isEmpty()) inlineAdPool else unowned
    val offer = pool[slotIndex % pool.size]
    val service = StreamingCatalog.service(offer.first)

    Box(Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) {
        SponsoredSlot(
            preferredSource = if (slotIndex % 2 == 0) PooledAdSource.ADMOB_FIRST else PooledAdSource.RAKUTEN_FIRST,
            service = service,
            serviceId = offer.first,
            headline = offer.second,
            subtitle = offer.third,
            onDismiss = { dismissed[slotIndex] = true },
        )
    }
}

package com.rork.guidestreamtvandroid.ui.screens

import androidx.activity.compose.BackHandler
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items as gridItems
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.outlined.NotificationsNone
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rork.guidestreamtvandroid.data.models.Platform
import com.rork.guidestreamtvandroid.data.models.SourceKind
import com.rork.guidestreamtvandroid.data.models.StreamingCatalog
import com.rork.guidestreamtvandroid.data.models.TitleId
import com.rork.guidestreamtvandroid.data.models.UserStream
import com.rork.guidestreamtvandroid.data.remote.ExpiringTitlesService
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.data.repository.ReleaseReminderService
import com.rork.guidestreamtvandroid.data.repository.StreamsViewModel
import com.rork.guidestreamtvandroid.ui.components.RemoteImage
import com.rork.guidestreamtvandroid.ui.navigation.PendingTitleRoute
import com.rork.guidestreamtvandroid.ui.theme.BrandBlue
import com.rork.guidestreamtvandroid.ui.theme.Navy
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.pulltorefresh.PullToRefreshDefaults
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.SurfaceContainer
import com.rork.guidestreamtvandroid.ui.theme.systemBottomInset
import kotlinx.coroutines.launch

/**
 * The three categories the saved list is split into. SHOWS and MOVIES are
 * both TMDB entities separated by media type; CREATORS is every non-TMDB
 * entity — YouTube, podcasts, Twitch, Kick. Mirrors iOS WatchListTab.
 */
private enum class WatchListTab(
    val label: String,
    val icon: ImageVector,
    val emptyTitle: String,
    val emptyBody: String,
) {
    SHOWS(
        "Shows",
        Icons.Filled.Tv,
        "No shows saved yet",
        "Tap the + on any series to keep it here.",
    ),
    MOVIES(
        "Movies",
        Icons.Filled.Movie,
        "No movies saved yet",
        "Tap the + on any movie to keep it here.",
    ),
    CREATORS(
        "Creators",
        Icons.Filled.People,
        "No creators saved yet",
        "Follow a YouTube channel, podcast or streamer to see it here.",
    );

    companion object {
        /**
         * Which tab a saved row belongs to. Every non-TMDB id is a creator;
         * TMDB rows split on is_tv, falling back to the id's own prefix and
         * only then to "show" — the same precedence the departure-reminder
         * code uses, so a saved movie is never quietly filed as a series.
         */
        fun of(stream: UserStream): WatchListTab {
            if (SourceKind.from(stream.titleId).isNonTMDB) return CREATORS
            val isTv = stream.isTv ?: TitleId.isTv(stream.titleId) ?: true
            return if (isTv) SHOWS else MOVIES
        }
    }
}

/**
 * How the Creators tab orders its rows. RECENT_UPLOAD is the default and
 * matches the phone and TV watch lists — newest content first; ALPHABETICAL
 * is the opt-in added for GUI-94.
 */
private enum class WatchListSort(val label: String) {
    RECENT_UPLOAD("Recent upload"),
    ALPHABETICAL("A\u2013Z"),
    ;

    val next: WatchListSort
        get() = if (this == RECENT_UPLOAD) ALPHABETICAL else RECENT_UPLOAD
}

/**
 * Full "My Watch List" destination reached from the home feed's Watch List
 * "See all" link. Android-native mirror of iOS WatchListBottomSheet: a back
 * arrow, title, and a two-column poster grid of every saved title with a
 * watched badge and an inline remove control. No take limit. Live status and
 * content-source hydration remain iOS-only and are intentionally out of scope.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WatchListScreen(
    onBack: () -> Unit,
    onOpenTitle: (PendingTitleRoute) -> Unit,
    modifier: Modifier = Modifier,
) {
    BackHandler { onBack() }

    val streamsVm = StreamsViewModel.get()
    val userStreams by streamsVm.userStreams.collectAsStateWithLifecycle()
    val watchedIds by streamsVm.watchedIds.collectAsStateWithLifecycle()
    val latestContentAt by streamsVm.latestContentAt.collectAsStateWithLifecycle()
    val latestContentKind by streamsVm.latestContentKind.collectAsStateWithLifecycle()
    val seenContentAt by streamsVm.seenContentAt.collectAsStateWithLifecycle()

    val authVm = AuthViewModel.get()
    val selectedServices by authVm.selectedServices.collectAsStateWithLifecycle()
    val reminders = ReleaseReminderService.get()
    val departureReminded by reminders.departureRemindedTitleIds.collectAsStateWithLifecycle()

    // Watch-list filters — both default off, and both operate only on data
    // already in hand (selected services + the expiring-titles cache the
    // Home rail already fetched).
    var filterOnMyServices by remember { mutableStateOf(false) }
    var filterLeavingSoon by remember { mutableStateOf(false) }

    // Which category tab is showing. Seeded once from the data so a user
    // whose list happens to be all movies does not land on an empty Shows
    // tab; after that it follows their taps only.
    var selectedTab by remember { mutableStateOf(WatchListTab.SHOWS) }
    // Sort applied to the Creators tab only; the other tabs keep the list's
    // existing order.
    var creatorSort by remember { mutableStateOf(WatchListSort.RECENT_UPLOAD) }
    var didSeedTab by remember { mutableStateOf(false) }

    // Counted before any filter chip applies, so the empty-state copy can
    // tell "this category is empty" apart from "your filters emptied it".
    val tabCounts = userStreams.groupingBy { WatchListTab.of(it) }.eachCount()

    androidx.compose.runtime.LaunchedEffect(userStreams.size) {
        if (!didSeedTab && userStreams.isNotEmpty()) {
            didSeedTab = true
            if ((tabCounts[selectedTab] ?: 0) == 0) {
                WatchListTab.values().firstOrNull { (tabCounts[it] ?: 0) > 0 }
                    ?.let { selectedTab = it }
            }
        }
    }

    // Expiring rows keyed by tmdb id — first row wins (soonest leaving date)
    // when a title is leaving multiple services. Read straight from the
    // service cache; never a new network call, never a write.
    val expiryByTmdbId: Map<Int, ExpiringTitlesService.ExpiringTitleRow> = buildMap {
        for (row in ExpiringTitlesService.get().cachedRows()) {
            if (!containsKey(row.tmdbId)) put(row.tmdbId, row)
        }
    }

    val isOnMyServices: (UserStream) -> Boolean = { stream ->
        val platform = stream.platform
        if (platform.isNullOrEmpty()) {
            false
        } else {
            val n = platform.lowercase().filter { it.isLetterOrDigit() }
            StreamingCatalog.ordered(selectedServices).any { svc ->
                val s = svc.name.lowercase().filter { it.isLetterOrDigit() }
                s.isNotEmpty() && (n.contains(s) || s.contains(n))
            }
        }
    }

    // The tab scopes the list first; the chips then filter within it. Both
    // filters on intersect; neither on leaves the tab's order untouched.
    val inTabRaw = userStreams.filter { WatchListTab.of(it) == selectedTab }
    // Creators-only sort. Titles with no title_recency row sink below those
    // that have one, alphabetical among themselves, so an unknown upload date
    // never reads as a fresh one.
    val inTab = if (selectedTab != WatchListTab.CREATORS) {
        inTabRaw
    } else when (creatorSort) {
        WatchListSort.ALPHABETICAL ->
            inTabRaw.sortedBy { (it.title ?: it.titleId).lowercase() }
        WatchListSort.RECENT_UPLOAD ->
            inTabRaw.sortedWith(
                compareByDescending<UserStream> { latestContentAt[it.titleId] ?: Long.MIN_VALUE }
                    .thenBy { (it.title ?: it.titleId).lowercase() }
            )
    }
    val filteredStreams = if (!filterOnMyServices && !filterLeavingSoon) {
        inTab
    } else {
        inTab.filter { stream ->
            val onServicesOk = !filterOnMyServices || isOnMyServices(stream)
            val leavingOk = !filterLeavingSoon ||
                (TitleId.tmdbId(stream.titleId)?.let { expiryByTmdbId.containsKey(it) } == true)
            onServicesOk && leavingOk
        }
    }

    // Refresh departure-reminder state for every saved title matched
    // against the expiring cache.
    val expiryReminderKeys = userStreams.mapNotNull { stream ->
        val id = TitleId.tmdbId(stream.titleId)
        if (id != null && expiryByTmdbId.containsKey(id)) id.toString() else null
    }
    androidx.compose.runtime.LaunchedEffect(expiryReminderKeys) {
        expiryReminderKeys.forEach {
            reminders.refreshReminded(it, ReleaseReminderService.REMINDER_KIND_DEPARTURE)
        }
    }

    // Fetch watchlist_seen so the new-content badges reflect server state on
    // launch. Runs alongside the existing recency load in refreshAll.
    androidx.compose.runtime.LaunchedEffect(userStreams.size) {
        if (userStreams.isNotEmpty()) streamsVm.fetchWatchlistSeen()
    }

    val scope = rememberCoroutineScope()
    var isRefreshing by remember { mutableStateOf(false) }
    val pullState = rememberPullToRefreshState()

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(Navy),
    ) {
        // statusBarsPadding keeps the back-arrow tap target below the system
        // status bar — without it the status bar consumes the touch.
        Spacer(Modifier.statusBarsPadding().height(12.dp))

        // Top bar — back chevron + title (same treatment as PopularOnServiceCategoriesScreen)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
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
                    modifier = Modifier.size(24.dp),
                )
            }
            Spacer(Modifier.width(4.dp))
            Text(
                text = "My Watch List",
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
            )
        }

        Spacer(Modifier.height(8.dp))

        // Category tabs, then the existing filter chips beneath them. The
        // chips still apply, and now apply within whichever tab is selected.
        if (userStreams.isNotEmpty()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                WatchListTab.values().forEach { tab ->
                    WatchListTabChip(
                        tab = tab,
                        isOn = selectedTab == tab,
                        onSelect = { selectedTab = tab },
                        modifier = Modifier.weight(1f),
                    )
                }
            }

            Spacer(Modifier.height(8.dp))
        }

        // Watch-list filters — shown only when there are saved titles.
        if (userStreams.isNotEmpty()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                WatchListFilterChip(
                    label = "On my services",
                    isOn = filterOnMyServices,
                    onToggle = { filterOnMyServices = !filterOnMyServices },
                )
                WatchListFilterChip(
                    label = "Leaving soon",
                    isOn = filterLeavingSoon,
                    onToggle = { filterLeavingSoon = !filterLeavingSoon },
                )
                if (selectedTab == WatchListTab.CREATORS) {
                    Spacer(Modifier.weight(1f))
                    WatchListSortChip(
                        label = creatorSort.label,
                        onToggle = { creatorSort = creatorSort.next },
                    )
                }
            }
        }

        PullToRefreshBox(
            isRefreshing = isRefreshing,
            onRefresh = {
                if (isRefreshing) return@PullToRefreshBox
                scope.launch {
                    isRefreshing = true
                    try {
                        streamsVm.refreshAllNow()
                    } finally {
                        isRefreshing = false
                    }
                }
            },
            state = pullState,
            modifier = Modifier.fillMaxSize(),
            indicator = {
                PullToRefreshDefaults.Indicator(
                    modifier = Modifier.align(Alignment.TopCenter),
                    isRefreshing = isRefreshing,
                    state = pullState,
                    containerColor = SurfaceContainer,
                    color = BrandOrange,
                )
            },
        ) {
        if (userStreams.isEmpty()) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 36.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Text(
                    text = "Your watch list is empty",
                    fontSize = 17.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                    textAlign = TextAlign.Center,
                )
                Spacer(Modifier.height(8.dp))
                Text(
                    text = "Tap the + on any show, movie, or creator to save it here. We'll keep them ready for tonight.",
                    fontSize = 13.sp,
                    color = TextSecondary,
                    textAlign = TextAlign.Center,
                )
            }
        } else if (filteredStreams.isEmpty()) {
            // An empty category and a category the filters emptied need
            // different copy — "try turning a filter off" is useless advice
            // when no filter is on.
            val tabIsEmpty = (tabCounts[selectedTab] ?: 0) == 0
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 36.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Icon(
                    imageVector = if (tabIsEmpty) selectedTab.icon else Icons.Filled.Close,
                    contentDescription = null,
                    tint = Color.White.copy(alpha = 0.35f),
                    modifier = Modifier.size(34.dp),
                )
                Spacer(Modifier.height(10.dp))
                Text(
                    text = if (tabIsEmpty) selectedTab.emptyTitle else "No titles match these filters",
                    fontSize = 17.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                    textAlign = TextAlign.Center,
                )
                Spacer(Modifier.height(8.dp))
                Text(
                    text = if (tabIsEmpty) selectedTab.emptyBody else "Try turning a filter off.",
                    fontSize = 13.sp,
                    color = TextSecondary,
                    textAlign = TextAlign.Center,
                )
            }
        } else {
            LazyVerticalGrid(
                columns = GridCells.Fixed(2),
                contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 12.dp, bottom = systemBottomInset() + 24.dp),
                horizontalArrangement = Arrangement.spacedBy(14.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
                modifier = Modifier.fillMaxSize(),
            ) {
                gridItems(filteredStreams, key = { it.titleId }) { stream ->
                    val tmdbKey = TitleId.tmdbId(stream.titleId)
                    WatchListGridCell(
                        stream = stream,
                        isWatched = watchedIds.contains(stream.titleId),
                        badgeText = streamsVm.newBadgeText(stream, latestContentAt, latestContentKind, seenContentAt),
                        expiryText = tmdbKey?.let { expiryByTmdbId[it] }?.let { expiryBadgeText(it) },
                        isDepartureReminded = tmdbKey != null &&
                            departureReminded.contains(tmdbKey.toString()),
                        onToggleDepartureReminder = if (tmdbKey != null &&
                            expiryByTmdbId.containsKey(tmdbKey)
                        ) {
                            {
                                reminders.toggleReminder(
                                    titleId = tmdbKey.toString(),
                                    tmdbId = tmdbKey,
                                    source = "watchlist_leaving",
                                    reminderKind = ReleaseReminderService.REMINDER_KIND_DEPARTURE,
                                    mediaType = if (stream.isTv ?: TitleId.isTv(stream.titleId) ?: true) "tv" else "movie",
                                )
                            }
                        } else {
                            null
                        },
                        onClick = {
                            onOpenTitle(
                                PendingTitleRoute(
                                    titleId = stream.titleId,
                                    titleName = stream.title ?: stream.titleName,
                                    posterUrl = stream.posterUrl,
                                    isTv = stream.isTv ?: TitleId.isTv(stream.titleId) ?: true,
                                ),
                            )
                        },
                        onRemove = { streamsVm.removeFromMyStreams(stream.titleId) },
                    )
                }
            }
        }
        }
    }
}

@Composable
private fun WatchListGridCell(
    stream: UserStream,
    isWatched: Boolean,
    badgeText: String?,
    expiryText: String?,
    isDepartureReminded: Boolean,
    onToggleDepartureReminder: (() -> Unit)?,
    onClick: () -> Unit,
    onRemove: () -> Unit,
) {
    val platform = Platform.from(stream.platform)
    val platformMeta = run {
        val p = stream.platform
        if (!p.isNullOrEmpty() && p.uppercase() != "STREAM" && p.lowercase() != "streaming") {
            p.replaceFirstChar { it.uppercase() }
        } else {
            "Watch list"
        }
    }
    Column(
        modifier = Modifier
            .fillMaxWidth()
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
                placeholderFontSize = 22.sp,
            )
            if (platform != null) {
                Box(
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .fillMaxWidth()
                        .height(3.dp)
                        .background(platform.color),
                )
            }
            // New-content badge — top-leading corner, solid black rounded
            // badge with white bold uppercase text. Shows "NEW EPISODE" for
            // shows and "NEW UPLOAD" for creators.
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
                    )
                }
            }
            // Inline remove control — top-right.
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(6.dp)
                    .size(26.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.55f))
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onRemove() },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Filled.Close,
                    contentDescription = "Remove from watch list",
                    tint = Color.White,
                    modifier = Modifier.size(15.dp),
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
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            color = TextPrimary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            text = platformMeta,
            fontSize = 11.sp,
            color = TextTertiary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        // Expiry badge + departure-reminder bell for saved titles matched
        // against the expiring-titles cache.
        if (expiryText != null) {
            Spacer(Modifier.height(4.dp))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text(
                    text = expiryText,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    color = BrandOrange,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false),
                )
                if (onToggleDepartureReminder != null) {
                    Box(
                        modifier = Modifier
                            .size(26.dp)
                            .clip(CircleShape)
                            .background(
                                if (isDepartureReminded) BrandOrange.copy(alpha = 0.22f)
                                else Color(0xFF1B2739)
                            )
                            .border(
                                width = 1.dp,
                                color = if (isDepartureReminded) BrandOrange.copy(alpha = 0.5f)
                                else Color(0xFF2E3E58),
                                shape = CircleShape,
                            )
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                            ) { onToggleDepartureReminder() },
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            imageVector = if (isDepartureReminded) Icons.Filled.Notifications
                            else Icons.Outlined.NotificationsNone,
                            contentDescription = "Leaving soon reminder",
                            tint = if (isDepartureReminded) BrandOrange else TextSecondary,
                            modifier = Modifier.size(14.dp),
                        )
                    }
                }
            }
        }
    }
}

/**
 * Formats a matched expiring-titles row into badge text carrying the leaving
 * date and service name.
 */
private fun expiryBadgeText(row: ExpiringTitlesService.ExpiringTitleRow): String {
    val dateText = row.leavingDate
        ?.let { runCatching { java.time.LocalDate.parse(it) }.getOrNull() }
        ?.let { java.time.format.DateTimeFormatter.ofPattern("MMM d", java.util.Locale.US).format(it) }
    return buildString {
        append("Leaving ")
        append(dateText ?: "soon")
        if (!row.serviceName.isNullOrEmpty()) {
            append(" · ")
            append(row.serviceName)
        }
    }
}

/**
 * One of the three category tabs. Shares the filter chip's capsule and depth
 * tokens so the two bars read as one control stack, and takes an equal third
 * of the row so the tabs sit on a steady grid.
 */
@Composable
private fun WatchListTabChip(
    tab: WatchListTab,
    isOn: Boolean,
    onSelect: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(16.dp))
            .background(if (isOn) Color(0xFF2E3E58) else Color(0xFF1B2739))
            .border(
                width = 1.dp,
                color = if (isOn) BrandOrange else Color.White.copy(alpha = 0.10f),
                shape = RoundedCornerShape(16.dp),
            )
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onSelect() }
            .padding(horizontal = 8.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = tab.icon,
            contentDescription = null,
            tint = if (isOn) Color.White else TextSecondary,
            modifier = Modifier.size(15.dp),
        )
        Spacer(Modifier.width(5.dp))
        Text(
            text = tab.label,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            color = if (isOn) Color.White else TextSecondary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/**
 * Small capsule toggle used by the watch-list filter bar. New sheet surface
 * uses the literal depth tokens (#1B2739 fill, #2E3E58 raised) rather than
 * theme aliases.
 */
@Composable
private fun WatchListSortChip(
    label: String,
    onToggle: () -> Unit,
) {
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(16.dp))
            .background(Color(0xFF1B2739))
            .border(
                width = 1.dp,
                color = Color.White.copy(alpha = 0.10f),
                shape = RoundedCornerShape(16.dp),
            )
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onToggle() }
            .padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = "Sort: $label",
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            color = Color.White.copy(alpha = 0.85f),
        )
    }
}

@Composable
private fun WatchListFilterChip(
    label: String,
    isOn: Boolean,
    onToggle: () -> Unit,
) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(16.dp))
            .background(if (isOn) Color(0xFF2E3E58) else Color(0xFF1B2739))
            .border(
                width = 1.dp,
                color = if (isOn) BrandOrange else Color.White.copy(alpha = 0.10f),
                shape = RoundedCornerShape(16.dp),
            )
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onToggle() }
            .padding(horizontal = 14.dp, vertical = 8.dp),
    ) {
        Text(
            text = label,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            color = if (isOn) Color.White else TextSecondary,
        )
    }
}

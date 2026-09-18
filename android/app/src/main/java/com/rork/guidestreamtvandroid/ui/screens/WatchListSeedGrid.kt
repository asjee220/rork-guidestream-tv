package com.rork.guidestreamtvandroid.ui.screens

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.animateFloatAsState
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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items as rowItems
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rork.guidestreamtvandroid.data.models.SourceKind
import com.rork.guidestreamtvandroid.data.models.TMDBResult
import com.rork.guidestreamtvandroid.data.remote.SupabaseManager
import com.rork.guidestreamtvandroid.data.remote.TMDBService
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.data.repository.PushTokenManager
import com.rork.guidestreamtvandroid.data.repository.StreamsViewModel
import com.rork.guidestreamtvandroid.data.repository.WatchIntentLogger
import com.rork.guidestreamtvandroid.ui.components.RemoteImage
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.systemBottomInset
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Which seed pool the grid draws from. Mirrors the watchlist's category
 * tabs and iOS `WatchListSeedCategory`.
 */
enum class WatchListSeedCategory { SHOWS, MOVIES, CREATORS }

/**
 * Per-device flags for the seed surface. Conveniences, never server state:
 * a reinstall simply shows the grid again. Mirrors iOS `WatchListSeedPrefs`.
 */
object WatchListSeedPrefs {
    private const val DISMISSED_KEY = "gs.watchlistSeedDismissed"
    private const val PUSH_ASKED_KEY = "gs.pushAskedOnFirstSave"

    fun isDismissed(context: Context): Boolean =
        context.getSharedPreferences("gs_prefs", Context.MODE_PRIVATE)
            .getBoolean(DISMISSED_KEY, false)

    fun setDismissed(context: Context, value: Boolean) {
        context.getSharedPreferences("gs_prefs", Context.MODE_PRIVATE)
            .edit().putBoolean(DISMISSED_KEY, value).apply()
    }

    fun pushAsked(context: Context): Boolean =
        context.getSharedPreferences("gs_prefs", Context.MODE_PRIVATE)
            .getBoolean(PUSH_ASKED_KEY, false)

    fun setPushAsked(context: Context) {
        context.getSharedPreferences("gs_prefs", Context.MODE_PRIVATE)
            .edit().putBoolean(PUSH_ASKED_KEY, true).apply()
    }
}

/**
 * Saves before Home counts as personalized (Recommended for You, Top Picks genre and
 * New Episodes all key off user_streams). Counted across every category. Nothing on Home
 * is gated on it — Today's Pick is a daily rotation shown regardless — so the copy
 * promises personalization, never an unlock.
 */
private const val NUDGE_THRESHOLD = 3
private const val COLUMNS = 3
private const val SEED_COUNT = 12

private data class SeedItem(
    val titleId: String,
    val title: String,
    val posterUrl: String?,
    val platform: String?,
    val isTv: Boolean?,
)

@Serializable
private data class SeedCreatorRow(
    @SerialName("title_id") val titleId: String = "",
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("image_url") val imageUrl: String? = null,
    @SerialName("source_type") val sourceType: String? = null,
    val category: String? = null,
)

/**
 * The empty watchlist's first-run surface. Replaces the onboarding
 * "Watching now" and "Follow creators" steps: a tappable grid of seeds for
 * whichever category tab is selected, saved one tap at a time straight into
 * `user_streams`. Never a gate — dismissible, and gone for good once the
 * user says so. Android-native mirror of iOS `WatchListSeedGrid`.
 */
@Composable
fun WatchListSeedGrid(
    category: WatchListSeedCategory,
    /** Fired from the "Done" button once the nudge threshold is met. */
    onDone: () -> Unit,
    /** Fired from the ✕. The caller decides what replaces the grid. */
    onDismiss: () -> Unit,
    /** Fired on every save or un-save the user makes from this grid. */
    onInteraction: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val streamsVm = StreamsViewModel.get()
    val userStreams by streamsVm.userStreams.collectAsStateWithLifecycle()
    val savedIds = userStreams.map { it.titleId }.toSet()
    val savedCount = userStreams.size
    val remaining = (NUDGE_THRESHOLD - savedCount).coerceAtLeast(0)

    var railIndex by remember(category) { mutableStateOf(0) }
    var seeds by remember { mutableStateOf<List<SeedItem>>(emptyList()) }
    var isLoading by remember { mutableStateOf(true) }

    LaunchedEffect(category, railIndex) {
        isLoading = true
        seeds = withContext(Dispatchers.IO) { loadSeeds(category, railIndex) }
        isLoading = false
    }

    // The first save is the one moment a notification has an obvious payoff,
    // so the system prompt fires here — once per install, and only while the
    // permission is still undetermined.
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        AuthViewModel.get().setNotificationPreferences(granted, false)
        if (granted) PushTokenManager.get().registerIfPermitted()
    }
    fun maybeRequestPush() {
        if (WatchListSeedPrefs.pushAsked(context)) return
        WatchListSeedPrefs.setPushAsked(context)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            AuthViewModel.get().setNotificationPreferences(true, false)
            PushTokenManager.get().registerIfPermitted()
            return
        }
        val granted = ContextCompat.checkSelfPermission(
            context, Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
    }

    fun toggle(seed: SeedItem) {
        onInteraction()
        if (seed.titleId in savedIds) {
            streamsVm.removeFromMyStreams(seed.titleId)
            WatchIntentLogger.get().log(
                WatchIntentLogger.IntentEventType.WATCHLIST_REMOVED,
                titleId = seed.titleId,
                platformId = seed.platform,
                metadata = mapOf("source" to "watchlist_seed"),
            )
        } else {
            streamsVm.addToMyStreams(
                titleId = seed.titleId,
                title = seed.title,
                posterUrl = seed.posterUrl,
                platform = seed.platform,
                isTv = seed.isTv,
            )
            WatchIntentLogger.get().log(
                WatchIntentLogger.IntentEventType.WATCHLIST_ADDED,
                titleId = seed.titleId,
                platformId = seed.platform,
                metadata = mapOf("source" to "watchlist_seed", "category" to category.name.lowercase()),
            )
            maybeRequestPush()
        }
    }

    val round = category == WatchListSeedCategory.CREATORS
    val rails = railLabels(category)

    LazyVerticalGrid(
        columns = GridCells.Fixed(COLUMNS),
        contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 4.dp, bottom = systemBottomInset() + 110.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
        modifier = modifier.fillMaxSize(),
    ) {
        item(span = { GridItemSpan(COLUMNS) }) {
            Column {
                SeedHeader(
                    subtitle = subtitleFor(category),
                    onDismiss = {
                        WatchListSeedPrefs.setDismissed(context, true)
                        onDismiss()
                    },
                )
                Spacer(Modifier.height(12.dp))
                SeedNudge(savedCount = savedCount, remaining = remaining)
                Spacer(Modifier.height(14.dp))
                LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    rowItems(rails.indices.toList()) { index ->
                        RailPill(
                            label = rails[index],
                            isOn = railIndex == index,
                            onTap = { railIndex = index },
                        )
                    }
                }
                Spacer(Modifier.height(2.dp))
            }
        }
        if (isLoading && seeds.isEmpty()) {
            items(SEED_COUNT) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(if (round) 1f else 0.667f)
                        .clip(if (round) CircleShape else RoundedCornerShape(12.dp))
                        .background(Color.White.copy(alpha = 0.08f)),
                )
            }
        } else {
            items(seeds, key = { it.titleId }) { seed ->
                SeedTile(
                    seed = seed,
                    isSaved = seed.titleId in savedIds,
                    round = round,
                    onTap = { toggle(seed) },
                )
            }
        }
        if (remaining == 0) {
            item(span = { GridItemSpan(COLUMNS) }) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 6.dp)
                        .height(50.dp)
                        .clip(RoundedCornerShape(14.dp))
                        .background(
                            Brush.verticalGradient(listOf(BrandOrange, BrandOrange.copy(alpha = 0.85f))),
                        )
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) { onDone() },
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = "Done — take me Home",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                    )
                }
            }
        }
    }
}

// ── Data ──────────────────────────────────────────────────────────

private fun railLabels(category: WatchListSeedCategory): List<String> = when (category) {
    WatchListSeedCategory.SHOWS -> listOf("Trending", "New this week", "Popular")
    WatchListSeedCategory.MOVIES -> listOf("Trending", "In theaters", "Coming soon")
    WatchListSeedCategory.CREATORS -> listOf("Top creators", "Podcasts", "Streamers")
}

private fun subtitleFor(category: WatchListSeedCategory): String = when (category) {
    WatchListSeedCategory.SHOWS -> "Save a few shows you'd actually watch. Everything else gets smarter from here."
    WatchListSeedCategory.MOVIES -> "Pick movies you've been meaning to see. We'll tell you when they land on a service you have."
    WatchListSeedCategory.CREATORS -> "Follow creators and podcasts so new drops show up next to your shows."
}

private suspend fun loadSeeds(category: WatchListSeedCategory, railIndex: Int): List<SeedItem> {
    val tmdb = TMDBService.get()
    val items: List<SeedItem> = when (category) {
        WatchListSeedCategory.SHOWS -> {
            val results: List<TMDBResult> = when (railIndex) {
                1 -> tmdb.getOnTheAir()
                2 -> tmdb.getPopularTV()
                else -> tmdb.getTrendingTV()
            }
            results.map { it.toSeed(isTv = true) }
        }
        WatchListSeedCategory.MOVIES -> {
            val results: List<TMDBResult> = when (railIndex) {
                1 -> tmdb.getNowPlayingMovies()
                2 -> tmdb.getUpcomingMovies()
                else -> tmdb.getTrendingMovies()
            }
            results.map { it.toSeed(isTv = false) }
        }
        WatchListSeedCategory.CREATORS -> {
            // The same query the retired onboarding step used: creator kinds
            // only, ordered by reach, live-search discoveries excluded.
            val rows = try {
                SupabaseManager.client.postgrest
                    .from("content_sources")
                    .select {
                        filter {
                            isIn("source_type", SourceKind.creatorSourceTypes)
                            exact("discovered_at", null)
                        }
                        order("subscriber_count", Order.DESCENDING, nullsFirst = false)
                        limit(60)
                    }
                    .decodeList<SeedCreatorRow>()
                    .filter { it.titleId.isNotBlank() && !it.displayName.isNullOrBlank() }
            } catch (_: Exception) {
                emptyList()
            }
            val filtered = when (railIndex) {
                1 -> rows.filter {
                    it.sourceType == "podcast" ||
                        (it.sourceType == "youtube" && it.category?.contains("podcast", ignoreCase = true) == true)
                }
                2 -> rows.filter { it.sourceType == "twitch" || it.sourceType == "kick" }
                else -> rows
            }
            filtered.map {
                SeedItem(
                    titleId = it.titleId,
                    title = it.displayName ?: "",
                    posterUrl = it.imageUrl,
                    platform = it.sourceType,
                    isTv = null,
                )
            }
        }
    }
    return items.filter { !it.posterUrl.isNullOrEmpty() }.take(SEED_COUNT)
}

private fun TMDBResult.toSeed(isTv: Boolean) = SeedItem(
    titleId = id.toString(),
    title = displayName,
    posterUrl = posterUrl,
    platform = null,
    isTv = isTv,
)

// ── Pieces ────────────────────────────────────────────────────────

@Composable
private fun SeedHeader(subtitle: String, onDismiss: () -> Unit) {
    Row(verticalAlignment = Alignment.Top) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = "Start your watchlist",
                fontSize = 17.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
            )
            Spacer(Modifier.height(4.dp))
            Text(
                text = subtitle,
                fontSize = 13.sp,
                color = TextSecondary,
                lineHeight = 18.sp,
            )
        }
        Spacer(Modifier.size(12.dp))
        Box(
            modifier = Modifier
                .size(30.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.08f))
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) { onDismiss() },
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Filled.Close,
                contentDescription = "Dismiss suggestions",
                tint = TextSecondary,
                modifier = Modifier.size(14.dp),
            )
        }
    }
}

@Composable
private fun SeedNudge(savedCount: Int, remaining: Int) {
    val done = remaining == 0
    val good = Color(0xFF3DD68C)
    val fraction by animateFloatAsState(
        targetValue = (savedCount.toFloat() / NUDGE_THRESHOLD).coerceIn(0f, 1f),
        label = "seedNudge",
    )
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(
            text = when {
                done -> "Your Home is personalized"
                remaining == 1 -> "1 more to personalize your Home"
                else -> "$remaining more to personalize your Home"
            },
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            color = if (done) good else TextSecondary,
            maxLines = 1,
        )
        Spacer(Modifier.size(10.dp))
        Box(
            modifier = Modifier
                .weight(1f)
                .height(4.dp)
                .clip(RoundedCornerShape(2.dp))
                .background(Color.White.copy(alpha = 0.10f)),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth(fraction)
                    .height(4.dp)
                    .background(if (done) good else BrandOrange),
            )
        }
    }
}

@Composable
private fun RailPill(label: String, isOn: Boolean, onTap: () -> Unit) {
    Text(
        text = label,
        fontSize = 11.sp,
        fontWeight = FontWeight.Bold,
        color = if (isOn) Color.White else TextSecondary,
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(if (isOn) BrandOrange else Color.White.copy(alpha = 0.08f))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onTap() }
            .padding(horizontal = 10.dp, vertical = 5.dp),
    )
}

@Composable
private fun SeedTile(
    seed: SeedItem,
    isSaved: Boolean,
    round: Boolean,
    onTap: () -> Unit,
) {
    val shape = if (round) CircleShape else RoundedCornerShape(12.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onTap() },
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(if (round) 1f else 0.667f)
                .clip(shape)
                .then(if (isSaved) Modifier.border(3.dp, BrandOrange, shape) else Modifier),
        ) {
            RemoteImage(
                url = seed.posterUrl,
                contentDescription = seed.title,
                modifier = Modifier.fillMaxSize(),
                cornerRadius = if (round) 100 else 12,
                placeholderText = seed.title.take(2).uppercase(),
                placeholderFontSize = 18.sp,
            )
            if (!round) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(
                            Brush.verticalGradient(
                                0.5f to Color.Transparent,
                                1f to Color.Black.copy(alpha = 0.75f),
                            ),
                        ),
                )
                Text(
                    text = seed.title,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier
                        .align(Alignment.BottomStart)
                        .padding(8.dp),
                )
            }
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(if (round) 2.dp else 6.dp)
                    .size(26.dp)
                    .clip(CircleShape)
                    .background(if (isSaved) BrandOrange else Color.Black.copy(alpha = 0.45f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = if (isSaved) Icons.Filled.Bookmark else Icons.Outlined.BookmarkBorder,
                    contentDescription = if (isSaved) "Remove ${seed.title}" else "Save ${seed.title}",
                    tint = Color.White,
                    modifier = Modifier.size(13.dp),
                )
            }
        }
        if (round) {
            Spacer(Modifier.height(6.dp))
            Text(
                text = seed.title,
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
                color = if (isSaved) TextPrimary else TextSecondary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center,
            )
        }
    }
}

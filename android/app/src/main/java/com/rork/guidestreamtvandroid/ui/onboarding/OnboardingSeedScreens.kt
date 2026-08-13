package com.rork.guidestreamtvandroid.ui.onboarding

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.togetherWith
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
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
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowForward
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.PlayArrow

import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.guidestreamtvandroid.data.models.StreamingCatalog
import com.rork.guidestreamtvandroid.data.models.TMDBResult
import com.rork.guidestreamtvandroid.data.remote.SupabaseManager
import com.rork.guidestreamtvandroid.data.remote.TMDBService
import com.rork.guidestreamtvandroid.ui.components.RemoteImage
import com.rork.guidestreamtvandroid.ui.theme.BrandBlue
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.Navy
import com.rork.guidestreamtvandroid.ui.theme.SurfaceDark
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * A show or creator the user picks during onboarding, committed to the
 * watch list once the step completes. Mirrors the iOS seed-onboarding flow.
 */
data class StreamSeed(
    val titleId: String,
    val title: String?,
    val posterUrl: String?,
    val platform: String?,
)

// ── Watching now (pick shows) ─────────────────────────────────────

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun WatchingNowScreen(
    selectedServices: Set<String>,
    onContinue: (List<StreamSeed>) -> Unit,
    onSkip: () -> Unit,
    onBack: () -> Unit = {},
    onSkipAll: () -> Unit = {},
    currentStep: Int = 2,
    totalSteps: Int = 4,
) {
    val tmdb = remember { TMDBService.get() }
    var shows by remember { mutableStateOf<List<TMDBResult>>(emptyList()) }
    var isLoading by remember { mutableStateOf(true) }
    val selectedIds = remember { mutableStateListOf<Int>() }
    var activeService by remember { mutableStateOf("") }

    LaunchedEffect(Unit) {
        val combined = (tmdb.getTrendingTV() + tmdb.getPopularTV())
            .distinctBy { it.id }
            .filter { it.posterUrl != null }
            .take(30)
        shows = combined
        isLoading = false
    }

    val filteredShows = remember(shows, activeService) {
        if (activeService.isEmpty()) shows
        else shows.filter { activeService.equals("trending", ignoreCase = true) || true }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        OnboardingHeader(currentStep = currentStep, totalSteps = totalSteps, onBack = onBack, onSkipAll = onSkipAll)

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
                .padding(top = 12.dp, bottom = 8.dp),
        ) {
            Text(
                text = "What are you watching right now?",
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
            )
            Text(
                text = "We found top shows across your services — tap every one you follow.",
                fontSize = 14.sp,
                color = TextSecondary,
            )
        }

        // Promises — quiet inline line, no chrome (E1)
        PromisesLine(modifier = Modifier.padding(horizontal = 24.dp).padding(bottom = 12.dp))

        // Filter rubric + service chips (E2, E5, C4)
        Column(
            modifier = Modifier.fillMaxWidth().padding(bottom = 12.dp),
        ) {
            Text(
                text = "FILTER BY SERVICE",
                fontSize = 10.sp,
                fontWeight = FontWeight.SemiBold,
                letterSpacing = 1.1.sp,
                color = Color.White.copy(alpha = 0.35f),
                modifier = Modifier.padding(horizontal = 24.dp).padding(bottom = 6.dp),
            )
            androidx.compose.foundation.lazy.LazyRow(
                contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 24.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                item {
                    FilterChip(
                        label = "All",
                        isSelected = activeService.isEmpty(),
                        onClick = { activeService = "" },
                    )
                }
                items(selectedServices.sorted().toList()) { serviceId ->
                    val svc = StreamingCatalog.service(serviceId)
                    FilterChip(
                        label = svc?.name ?: serviceId,
                        isSelected = activeService == serviceId,
                        onClick = { activeService = serviceId },
                    )
                }
            }
        }

        Box(modifier = Modifier.weight(1f)) {
            if (isLoading) {
                CircularProgressIndicator(
                    modifier = Modifier.align(Alignment.Center).size(28.dp),
                    color = BrandOrange,
                    strokeWidth = 2.dp,
                )
            } else {
                LazyVerticalGrid(
                    columns = GridCells.Fixed(3),
                    modifier = Modifier.fillMaxSize().padding(horizontal = 20.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    items(filteredShows, key = { it.id }) { show ->
                        PosterPickTile(
                            title = show.displayName,
                            posterUrl = show.posterUrl,
                            isSelected = show.id in selectedIds,
                            onTap = {
                                if (show.id in selectedIds) selectedIds.remove(show.id)
                                else selectedIds.add(show.id)
                            },
                        )
                    }
                }
            }
        }

        OnboardingBottomBar(
            primaryText = "Add to My List",
            skipText = "Skip",
            enabled = selectedIds.isNotEmpty(),
            onPrimary = {
                val seeds = shows.filter { it.id in selectedIds }.map {
                    StreamSeed(
                        titleId = it.id.toString(),
                        title = it.displayName,
                        posterUrl = it.posterUrl,
                        platform = null,
                    )
                }
                onContinue(seeds)
            },
            onSkip = onSkip,
        )
    }
}

// ── Follow creators + podcasts ───────────────────────────────────

@Serializable
private data class OnboardingCreatorRow(
    @SerialName("title_id") val titleId: String = "",
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("image_url") val imageUrl: String? = null,
    @SerialName("source_type") val sourceType: String? = null,
    val category: String? = null,
)

private enum class CreatorLane { CREATORS, PODCASTS }
private enum class CreatorSubFilter(override val label: String) : SubFilter { ALL("All"), YOUTUBE("YouTube"), STREAMERS("Streamers") }
private enum class PodcastSubFilter(override val label: String) : SubFilter { ALL("All"), VIDEO("Video"), AUDIO("Audio") }

private interface SubFilter { val label: String }

@Composable
fun FollowCreatorsOnboardingScreen(
    onContinue: (List<StreamSeed>) -> Unit,
    onSkip: () -> Unit,
    onBack: () -> Unit = {},
    onSkipAll: () -> Unit = {},
    currentStep: Int = 3,
    totalSteps: Int = 4,
) {
    var creators by remember { mutableStateOf<List<OnboardingCreatorRow>>(emptyList()) }
    var podcasts by remember { mutableStateOf<List<OnboardingCreatorRow>>(emptyList()) }
    var isLoading by remember { mutableStateOf(true) }
    val selectedIds = remember { mutableStateListOf<String>() }
    var lane by remember { mutableStateOf(CreatorLane.CREATORS) }
    var creatorSub by remember { mutableStateOf(CreatorSubFilter.ALL) }
    var podcastSub by remember { mutableStateOf(PodcastSubFilter.ALL) }

    LaunchedEffect(Unit) {
        val allContent = try {
            SupabaseManager.client.postgrest
                .from("content_sources")
                .select { limit(60) }
                .decodeList<OnboardingCreatorRow>()
                .filter { it.titleId.isNotBlank() && !it.displayName.isNullOrBlank() }
        } catch (_: Exception) {
            emptyList()
        }
        creators = allContent.filter { it.sourceType == "youtube" || it.sourceType == "twitch" || it.sourceType == "kick" }
        podcasts = allContent.filter { it.sourceType == "podcast" || (it.sourceType == "youtube" && it.category?.contains("podcast", ignoreCase = true) == true) }
        if (creators.isEmpty() && podcasts.isNotEmpty()) lane = CreatorLane.PODCASTS
        isLoading = false
    }

    val displayList = when (lane) {
        CreatorLane.CREATORS -> when (creatorSub) {
            CreatorSubFilter.ALL -> creators
            CreatorSubFilter.YOUTUBE -> creators.filter { it.sourceType == "youtube" }
            CreatorSubFilter.STREAMERS -> creators.filter { it.sourceType == "twitch" || it.sourceType == "kick" }
        }
        CreatorLane.PODCASTS -> when (podcastSub) {
            PodcastSubFilter.ALL -> podcasts
            PodcastSubFilter.VIDEO -> podcasts.filter { it.sourceType == "youtube" }
            PodcastSubFilter.AUDIO -> podcasts.filter { it.sourceType == "podcast" }
        }
    }

    val titleText = when (lane) {
        CreatorLane.CREATORS -> "Now add your creators"
        CreatorLane.PODCASTS -> "…and your podcasts"
    }
    val subtitleText = when (lane) {
        CreatorLane.CREATORS -> "Follow the channels you already watch — new uploads land on your home feed, right next to your shows."
        CreatorLane.PODCASTS -> "Video or audio, we track new episodes the moment they drop."
    }

    Column(modifier = Modifier.fillMaxSize()) {
        OnboardingHeader(currentStep = currentStep, totalSteps = totalSteps, onBack = onBack, onSkipAll = onSkipAll)

        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(top = 12.dp, bottom = 8.dp),
        ) {
            Text(text = titleText, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
            Text(text = subtitleText, fontSize = 14.sp, color = TextSecondary)
        }

        // Segmented control (F3)
        if (creators.isNotEmpty() && podcasts.isNotEmpty()) {
            SegmentedControl(
                options = listOf("Creators", "Podcasts"),
                selectedIndex = if (lane == CreatorLane.CREATORS) 0 else 1,
                onSelect = { idx -> lane = if (idx == 0) CreatorLane.CREATORS else CreatorLane.PODCASTS },
                modifier = Modifier.padding(horizontal = 24.dp).padding(bottom = 10.dp),
            )
        }

        // Sub-filter chips (F4)
        val subFilters: List<SubFilter> = if (lane == CreatorLane.CREATORS) {
            CreatorSubFilter.entries.filter { f ->
                f == CreatorSubFilter.ALL || when (f) {
                    CreatorSubFilter.YOUTUBE -> creators.any { it.sourceType == "youtube" }
                    CreatorSubFilter.STREAMERS -> creators.any { it.sourceType == "twitch" || it.sourceType == "kick" }
                    CreatorSubFilter.ALL -> true
                }
            }
        } else {
            PodcastSubFilter.entries.filter { f ->
                f == PodcastSubFilter.ALL || when (f) {
                    PodcastSubFilter.VIDEO -> podcasts.any { it.sourceType == "youtube" }
                    PodcastSubFilter.AUDIO -> podcasts.any { it.sourceType == "podcast" }
                    PodcastSubFilter.ALL -> true
                }
            }
        }
        if (subFilters.size >= 2) {
            androidx.compose.foundation.lazy.LazyRow(
                contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 24.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.padding(bottom = 10.dp),
            ) {
                items(subFilters) { filter ->
                    val isSelected = if (lane == CreatorLane.CREATORS) creatorSub == filter else podcastSub == filter
                    FilterChip(
                        label = filter.label,
                        isSelected = isSelected,
                        onClick = {
                            if (lane == CreatorLane.CREATORS) creatorSub = filter as CreatorSubFilter
                            else podcastSub = filter as PodcastSubFilter
                        },
                    )
                }
            }
        }

        Box(modifier = Modifier.weight(1f)) {
            when {
                isLoading -> CircularProgressIndicator(
                    modifier = Modifier.align(Alignment.Center).size(28.dp),
                    color = BrandOrange,
                    strokeWidth = 2.dp,
                )
                displayList.isEmpty() -> Text(
                    text = "Nothing here yet — check back soon.",
                    fontSize = 14.sp, color = TextSecondary,
                    modifier = Modifier.align(Alignment.Center),
                )
                else -> LazyVerticalGrid(
                    columns = GridCells.Fixed(3),
                    modifier = Modifier.fillMaxSize().padding(horizontal = 20.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    items(displayList, key = { it.titleId }) { item ->
                        val isPodcast = lane == CreatorLane.PODCASTS
                        CreatorPickTile(
                            name = item.displayName ?: "",
                            imageUrl = item.imageUrl,
                            isSelected = item.titleId in selectedIds,
                            isPodcast = isPodcast,
                            sourceType = item.sourceType,
                            onTap = {
                                if (item.titleId in selectedIds) selectedIds.remove(item.titleId)
                                else selectedIds.add(item.titleId)
                            },
                        )
                    }
                }
            }
        }

        OnboardingBottomBar(
            primaryText = "Add to My List",
            skipText = "Skip for now",
            enabled = selectedIds.isNotEmpty(),
            onPrimary = {
                val allItems = creators + podcasts
                val seeds = allItems.filter { it.titleId in selectedIds }.map {
                    StreamSeed(
                        titleId = it.titleId,
                        title = it.displayName,
                        posterUrl = it.imageUrl,
                        platform = it.sourceType,
                    )
                }
                onContinue(seeds)
            },
            onSkip = onSkip,
        )
    }
}

// ── Shared tiles + bottom bar ─────────────────────────────────────

@Composable
private fun PromisesLine(modifier: Modifier = Modifier) {
    val items = listOf("Lands in My Watch List", "Instant episode alerts", "One-tap deep links")
    Row(modifier = modifier, verticalAlignment = Alignment.CenterVertically) {
        items.forEachIndexed { i, item ->
            if (i > 0) {
                Text(
                    text = "  ·  ",
                    fontSize = 11.5.sp,
                    color = Color.White.copy(alpha = 0.18f),
                )
            }
            Icon(
                imageVector = Icons.Filled.Check,
                contentDescription = null,
                tint = BrandOrange,
                modifier = Modifier.size(10.dp),
            )
            Text(
                text = " $item",
                fontSize = 11.5.sp,
                color = Color.White.copy(alpha = 0.55f),
            )
        }
    }
}

@Composable
private fun FilterChip(
    label: String,
    isSelected: Boolean,
    onClick: () -> Unit,
) {
    Text(
        text = label,
        fontSize = 12.sp,
        fontWeight = FontWeight.SemiBold,
        color = if (isSelected) Color.White else TextSecondary,
        modifier = Modifier
            .clip(RoundedCornerShape(9.dp))
            .background(if (isSelected) Color.White.copy(alpha = 0.10f) else Color.White.copy(alpha = 0.04f))
            .border(1.dp, if (isSelected) Color.White else Color.Transparent, RoundedCornerShape(9.dp))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() }
            .padding(horizontal = 12.dp, vertical = 7.dp),
    )
}

@Composable
private fun SegmentedControl(
    options: List<String>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(Color.White.copy(alpha = 0.07f))
            .padding(3.dp),
    ) {
        options.forEachIndexed { i, label ->
            Text(
                text = label,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                color = if (i == selectedIndex) Color.White else TextSecondary,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .weight(1f)
                    .height(38.dp)
                    .wrapContentHeight(Alignment.CenterVertically)
                    .clip(RoundedCornerShape(10.dp))
                    .background(if (i == selectedIndex) Color.White.copy(alpha = 0.10f) else Color.Transparent)
                    .border(1.dp, if (i == selectedIndex) Color.White else Color.Transparent, RoundedCornerShape(10.dp))
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onSelect(i) },
            )
        }
    }
}

@Composable
private fun PosterPickTile(
    title: String,
    posterUrl: String?,
    isSelected: Boolean,
    onTap: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onTap() },
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(0.66f)
                .clip(RoundedCornerShape(10.dp))
                .then(
                    if (isSelected) Modifier.border(2.dp, BrandOrange, RoundedCornerShape(10.dp))
                    else Modifier,
                ),
        ) {
            RemoteImage(
                url = posterUrl,
                contentDescription = title,
                modifier = Modifier.fillMaxSize(),
                cornerRadius = 10,
                placeholderText = title,
            )
            if (isSelected) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(BrandOrange.copy(alpha = 0.15f)),
                )
                SelectedBadge(modifier = Modifier.align(Alignment.TopEnd).padding(5.dp))
            }
        }
        Spacer(Modifier.height(4.dp))
        Text(
            text = title,
            fontSize = 9.sp,
            fontWeight = FontWeight.SemiBold,
            color = if (isSelected) TextPrimary else Color.White.copy(alpha = 0.55f),
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun CreatorPickTile(
    name: String,
    imageUrl: String?,
    isSelected: Boolean,
    isPodcast: Boolean,
    sourceType: String?,
    onTap: () -> Unit,
) {
    val avatarShape = if (isPodcast) RoundedCornerShape(13.dp) else CircleShape
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
                .fillMaxWidth(0.82f)
                .aspectRatio(1f),
        ) {
            Box(
                modifier = Modifier
                    .matchParentSize()
                    .clip(avatarShape)
                    .background(Color.White.copy(alpha = 0.06f))
                    .then(
                        if (isSelected) Modifier.border(2.5.dp, BrandOrange, avatarShape)
                        else Modifier,
                    ),
            ) {
                RemoteImage(
                    url = imageUrl,
                    contentDescription = name,
                    modifier = Modifier.fillMaxSize(),
                    cornerRadius = if (isPodcast) 13 else 100,
                    placeholderText = name.take(2).uppercase(),
                    placeholderFontSize = 18.sp,
                )
            }
            // Video/Audio badge (G2) — only for podcasts
            if (isPodcast) {
                val isAudio = sourceType == "podcast"
                Row(
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .offset(x = (-4).dp, y = (-4).dp)
                        .clip(RoundedCornerShape(50.dp))
                        .background(Navy)
                        .border(0.5.dp, Color.White.copy(alpha = 0.3f), RoundedCornerShape(50.dp))
                        .padding(horizontal = 4.dp, vertical = 2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        imageVector = if (isAudio) Icons.Filled.MusicNote else Icons.Filled.PlayArrow,
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier.size(7.dp),
                    )
                    Text(
                        text = if (isAudio) " Audio" else " Video",
                        fontSize = 7.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                    )
                }
            }
            // Selection check (F5)
            if (isSelected) {
                SelectedBadge(modifier = Modifier.align(Alignment.TopEnd))
            }
        }
        Spacer(Modifier.height(6.dp))
        Text(
            text = name,
            fontSize = 11.sp,
            color = if (isSelected) TextPrimary else TextSecondary,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun SelectedBadge(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .size(22.dp)
            .clip(CircleShape)
            .background(BrandOrange),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = Icons.Filled.Check,
            contentDescription = "Selected",
            tint = Color.White,
            modifier = Modifier.size(14.dp),
        )
    }
}

@Composable
private fun OnboardingBottomBar(
    primaryText: String,
    onPrimary: () -> Unit,
    onSkip: () -> Unit,
    skipText: String = "Skip for now",
    enabled: Boolean = true,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(SurfaceDark)
            .drawBehind {
                drawRect(
                    color = Color.White.copy(alpha = 0.10f),
                    topLeft = Offset.Zero,
                    size = Size(width = size.width, height = 1f),
                )
            }
            .padding(horizontal = 20.dp)
            .padding(top = 12.dp, bottom = 28.dp)
            .navigationBarsPadding(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(52.dp)
                .clip(RoundedCornerShape(50.dp))
                .background(
                    if (enabled) Brush.verticalGradient(
                        colors = listOf(BrandOrange, BrandOrange.copy(alpha = 0.85f)),
                    ) else SolidColor(Color.White.copy(alpha = 0.10f))
                )
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    enabled = enabled,
                ) { onPrimary() },
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = primaryText,
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
                color = if (enabled) Color.White else Color.White.copy(alpha = 0.35f),
            )
            Spacer(Modifier.width(8.dp))
            Icon(
                imageVector = Icons.Filled.ArrowForward,
                contentDescription = null,
                tint = if (enabled) Color.White else Color.White.copy(alpha = 0.35f),
                modifier = Modifier.size(16.dp),
            )
        }
        Spacer(Modifier.height(10.dp))
        Text(
            text = skipText,
            fontSize = 14.sp,
            color = TextSecondary,
            modifier = Modifier
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) { onSkip() }
                .padding(8.dp),
        )
    }
}

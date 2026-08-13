package com.rork.guidestreamtvandroid.ui.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowForward
import androidx.compose.material.icons.filled.Check
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.guidestreamtvandroid.data.models.TMDBResult
import com.rork.guidestreamtvandroid.data.remote.SupabaseManager
import com.rork.guidestreamtvandroid.data.remote.TMDBService
import com.rork.guidestreamtvandroid.ui.components.RemoteImage
import com.rork.guidestreamtvandroid.ui.theme.BrandBlue
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
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

    LaunchedEffect(Unit) {
        val combined = (tmdb.getTrendingTV() + tmdb.getPopularTV())
            .distinctBy { it.id }
            .filter { it.posterUrl != null }
            .take(30)
        shows = combined
        isLoading = false
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

        // Value strip (folded from SeedPromptScreen)
        FlowRow(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            valuePill("Lands in My Watch List")
            valuePill("Instant episode alerts")
            valuePill("One-tap deep links")
        }

        Box(modifier = Modifier.weight(1f)) {
            if (isLoading) {
                CircularProgressIndicator(
                    modifier = Modifier
                        .align(Alignment.Center)
                        .size(28.dp),
                    color = BrandOrange,
                    strokeWidth = 2.dp,
                )
            } else {
                LazyVerticalGrid(
                    columns = GridCells.Fixed(3),
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 20.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    items(shows, key = { it.id }) { show ->
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
            primaryText = if (selectedIds.isEmpty()) "Continue" else "Add ${selectedIds.size} & continue",
            skipText = "Skip",
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

// ── Follow creators ───────────────────────────────────────────────

@Serializable
private data class OnboardingCreatorRow(
    @SerialName("title_id") val titleId: String = "",
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("image_url") val imageUrl: String? = null,
    @SerialName("source_type") val sourceType: String? = null,
    val category: String? = null,
)

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
    var isLoading by remember { mutableStateOf(true) }
    val selectedIds = remember { mutableStateListOf<String>() }

    LaunchedEffect(Unit) {
        creators = try {
            SupabaseManager.client.postgrest
                .from("content_sources")
                .select {
                    filter { eq("source_type", "youtube") }
                    limit(30)
                }
                .decodeList<OnboardingCreatorRow>()
                .filter { it.titleId.isNotBlank() && !it.displayName.isNullOrBlank() }
        } catch (_: Exception) {
            emptyList()
        }
        isLoading = false
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
                text = "Follow creators",
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
            )
            Text(
                text = "Get notified when they post something new",
                fontSize = 14.sp,
                color = TextSecondary,
            )
        }

        Box(modifier = Modifier.weight(1f)) {
            when {
                isLoading -> CircularProgressIndicator(
                    modifier = Modifier
                        .align(Alignment.Center)
                        .size(28.dp),
                    color = BrandOrange,
                    strokeWidth = 2.dp,
                )
                creators.isEmpty() -> Text(
                    text = "No creators to show right now.",
                    fontSize = 14.sp,
                    color = TextSecondary,
                    modifier = Modifier.align(Alignment.Center),
                )
                else -> LazyVerticalGrid(
                    columns = GridCells.Fixed(3),
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 20.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    items(creators, key = { it.titleId }) { creator ->
                        CreatorPickTile(
                            name = creator.displayName ?: "",
                            imageUrl = creator.imageUrl,
                            isSelected = creator.titleId in selectedIds,
                            onTap = {
                                if (creator.titleId in selectedIds) selectedIds.remove(creator.titleId)
                                else selectedIds.add(creator.titleId)
                            },
                        )
                    }
                }
            }
        }

        OnboardingBottomBar(
            primaryText = if (selectedIds.isEmpty()) "Finish" else "Follow ${selectedIds.size} & finish",
            onPrimary = {
                val seeds = creators.filter { it.titleId in selectedIds }.map {
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
                .clip(RoundedCornerShape(12.dp))
                .then(
                    if (isSelected) Modifier.border(2.5.dp, BrandOrange, RoundedCornerShape(12.dp))
                    else Modifier,
                ),
        ) {
            RemoteImage(
                url = posterUrl,
                contentDescription = title,
                modifier = Modifier.fillMaxSize(),
                cornerRadius = 12,
                placeholderText = title,
            )
            if (isSelected) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color.Black.copy(alpha = 0.35f)),
                )
                SelectedBadge(modifier = Modifier.align(Alignment.TopEnd).padding(6.dp))
            }
        }
        Spacer(Modifier.height(6.dp))
        Text(
            text = title,
            fontSize = 11.sp,
            color = if (isSelected) TextPrimary else TextSecondary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun CreatorPickTile(
    name: String,
    imageUrl: String?,
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
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth(0.82f)
                .aspectRatio(1f)
                .clip(CircleShape)
                .then(
                    if (isSelected) Modifier.border(2.5.dp, BrandOrange, CircleShape)
                    else Modifier,
                ),
        ) {
            RemoteImage(
                url = imageUrl,
                contentDescription = name,
                modifier = Modifier.fillMaxSize(),
                cornerRadius = 100,
                placeholderText = name.take(2).uppercase(),
                placeholderFontSize = 18.sp,
            )
            if (isSelected) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .clip(CircleShape)
                        .background(Color.Black.copy(alpha = 0.35f)),
                )
                SelectedBadge(modifier = Modifier.align(Alignment.TopEnd))
            }
        }
        Spacer(Modifier.height(6.dp))
        Text(
            text = name,
            fontSize = 11.sp,
            color = if (isSelected) TextPrimary else TextSecondary,
            maxLines = 1,
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
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp)
            .padding(top = 8.dp, bottom = 28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(56.dp)
                .clip(RoundedCornerShape(50.dp))
                .background(
                    Brush.verticalGradient(
                        colors = listOf(BrandOrange, BrandOrange.copy(alpha = 0.85f)),
                    ),
                )
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) { onPrimary() },
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = primaryText,
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
            )
            Spacer(Modifier.width(8.dp))
            Icon(
                imageVector = Icons.Filled.ArrowForward,
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier.size(16.dp),
            )
        }
        Spacer(Modifier.height(12.dp))
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

@Composable
private fun valuePill(text: String) {
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(13.dp))
            .background(Color.White.copy(alpha = 0.05f))
            .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(13.dp))
            .padding(horizontal = 10.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(
            imageVector = Icons.Filled.Check,
            contentDescription = null,
            tint = BrandOrange,
            modifier = Modifier.size(10.dp),
        )
        Text(
            text = text,
            fontSize = 10.5.sp,
            color = Color.White.copy(alpha = 0.55f),
        )
    }
}

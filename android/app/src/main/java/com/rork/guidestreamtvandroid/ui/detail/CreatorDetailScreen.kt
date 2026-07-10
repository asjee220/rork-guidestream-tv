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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.PlayArrow
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
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.rork.guidestreamtvandroid.data.models.ContentSource
import com.rork.guidestreamtvandroid.data.models.NewEpisodeRow
import com.rork.guidestreamtvandroid.data.remote.SupabaseManager
import com.rork.guidestreamtvandroid.data.repository.StreamsViewModel
import com.rork.guidestreamtvandroid.data.repository.WatchIntentLogger
import com.rork.guidestreamtvandroid.ui.components.RemoteImage
import com.rork.guidestreamtvandroid.ui.components.glassCard
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.GlassFill
import com.rork.guidestreamtvandroid.ui.theme.GlassStroke
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Creator detail view model — mirrors iOS CreatorDetailView.swift state.
 * Loads content_sources row + recent uploads from new_episodes.
 */
class CreatorDetailViewModel : ViewModel() {

    private val _source = MutableStateFlow<ContentSource?>(null)
    val source: StateFlow<ContentSource?> = _source.asStateFlow()

    private val _episodes = MutableStateFlow<List<NewEpisodeRow>>(emptyList())
    val episodes: StateFlow<List<NewEpisodeRow>> = _episodes.asStateFlow()

    private val _isLoading = MutableStateFlow(true)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    companion object {
        @Volatile private var instance: CreatorDetailViewModel? = null
        fun get(): CreatorDetailViewModel = instance ?: synchronized(this) {
            instance ?: CreatorDetailViewModel().also { instance = it }
        }
    }

    fun load(titleId: String) {
        _isLoading.value = true
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val rows = SupabaseManager.client.postgrest
                    .from("content_sources")
                    .select {
                        filter { eq("title_id", titleId) }
                        limit(1)
                    }
                    .decodeList<ContentSource>()
                _source.value = rows.firstOrNull()

                val epRows = SupabaseManager.client.postgrest
                    .from("new_episodes")
                    .select {
                        filter { eq("title_id", titleId) }
                        limit(30)
                    }
                    .decodeList<NewEpisodeRow>()
                _episodes.value = epRows.sortedByDescending { it.releasedAt ?: "" }
            } catch (_: Exception) {
                // Keep defaults
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun reset() {
        _source.value = null
        _episodes.value = emptyList()
        _isLoading.value = true
    }
}

/**
 * Creator detail screen — mirrors iOS CreatorDetailView.swift.
 * Hero header, follow/unfollow, episode list, play (open YouTube/Twitch/web).
 */
@Composable
fun CreatorDetailScreen(
    titleId: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val vm = CreatorDetailViewModel.get()
    val streamsVm = StreamsViewModel.get()
    val context = LocalContext.current

    val source by vm.source.collectAsStateWithLifecycle()
    val episodes by vm.episodes.collectAsStateWithLifecycle()
    val isLoading by vm.isLoading.collectAsStateWithLifecycle()
    val userStreams by streamsVm.userStreams.collectAsStateWithLifecycle()

    val isFollowed = userStreams.any { it.titleId == titleId }
    val sourceType = source?.sourceType ?: titleId.substringBefore(":", "youtube")

    LaunchedEffect(titleId) {
        vm.load(titleId)
    }

    Box(modifier = modifier.fillMaxSize()) {
        if (isLoading) {
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
                    .verticalScroll(rememberScrollState()),
            ) {
                // Hero header
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(1.8f),
                ) {
                    RemoteImage(
                        url = source?.imageUrl,
                        contentDescription = source?.displayName,
                        modifier = Modifier.fillMaxSize(),
                        cornerRadius = 0,
                        placeholderText = (source?.displayName ?: titleId).take(2).uppercase(),
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
                                        Color.Black.copy(alpha = 0.7f),
                                    ),
                                ),
                            ),
                    )
                    // Back button
                    Box(
                        modifier = Modifier
                            .align(Alignment.TopStart)
                            .statusBarsPadding()
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
                    // Title
                    Column(
                        modifier = Modifier
                            .align(Alignment.BottomStart)
                            .padding(16.dp),
                    ) {
                        Text(
                            text = source?.displayName ?: titleId,
                            fontSize = 24.sp,
                            fontWeight = FontWeight.Bold,
                            color = TextPrimary,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                        if (source?.category != null) {
                            Text(
                                text = "${sourceType.uppercase()} · ${source?.category}",
                                fontSize = 13.sp,
                                color = TextSecondary,
                            )
                        }
                    }
                }

                // Follow button
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                ) {
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(12.dp))
                            .background(if (isFollowed) GlassFill else BrandOrange)
                            .border(
                                1.dp,
                                if (isFollowed) GlassStroke else BrandOrange,
                                RoundedCornerShape(12.dp),
                            )
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                            ) {
                                if (isFollowed) {
                                    streamsVm.removeFromMyStreams(titleId)
                                    WatchIntentLogger.get().log(
                                        WatchIntentLogger.IntentEventType.WATCHLIST_REMOVED,
                                        titleId = titleId,
                                        platformId = sourceType,
                                    )
                                } else {
                                    streamsVm.addToMyStreams(
                                        titleId = titleId,
                                        title = source?.displayName,
                                        posterUrl = source?.imageUrl,
                                        platform = sourceType,
                                    )
                                    WatchIntentLogger.get().log(
                                        WatchIntentLogger.IntentEventType.WATCHLIST_ADDED,
                                        titleId = titleId,
                                        platformId = sourceType,
                                    )
                                }
                            }
                            .padding(vertical = 14.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            text = if (isFollowed) "Following" else "Follow",
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Bold,
                            color = if (isFollowed) TextPrimary else Color.White,
                        )
                    }
                }

                // Description
                if (!source?.description.isNullOrBlank()) {
                    Text(
                        text = source?.description ?: "",
                        fontSize = 14.sp,
                        color = TextSecondary,
                        lineHeight = 20.sp,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                    )
                }

                // Episodes
                if (episodes.isNotEmpty()) {
                    Spacer(Modifier.height(16.dp))
                    Text(
                        text = "Recent Episodes",
                        fontSize = 17.sp,
                        fontWeight = FontWeight.Bold,
                        color = TextPrimary,
                        modifier = Modifier.padding(horizontal = 16.dp),
                    )
                    Spacer(Modifier.height(8.dp))
                    episodes.forEach { ep ->
                        EpisodeRow(
                            episode = ep,
                            onPlay = {
                                val url = ep.deepLinkUrl ?: ep.thumbnailUrl
                                if (!url.isNullOrBlank()) {
                                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                                }
                                WatchIntentLogger.get().log(
                                    WatchIntentLogger.IntentEventType.TRAILER_WATCHED,
                                    titleId = titleId,
                                    platformId = sourceType,
                                )
                            },
                        )
                    }
                }

                Spacer(Modifier.height(40.dp))
            }
        }
    }
}

@Composable
private fun EpisodeRow(
    episode: NewEpisodeRow,
    onPlay: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp)
            .glassCard(10)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onPlay() }
            .padding(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(72.dp)
                .aspectRatio(1.6f)
                .clip(RoundedCornerShape(6.dp)),
        ) {
            RemoteImage(
                url = episode.thumbnailUrl ?: episode.posterUrl,
                contentDescription = episode.episodeTitle,
                modifier = Modifier.fillMaxSize(),
                cornerRadius = 6,
                placeholderText = "▶",
                placeholderFontSize = 18.sp,
            )
        }
        Spacer(Modifier.width(10.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = episode.episodeTitle ?: episode.title ?: "New episode",
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                color = TextPrimary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            if (episode.releasedAt != null) {
                Text(
                    text = episode.releasedAt!!.take(10),
                    fontSize = 12.sp,
                    color = TextTertiary,
                )
            }
        }
        Icon(
            imageVector = Icons.Filled.PlayArrow,
            contentDescription = "Play",
            tint = BrandOrange,
            modifier = Modifier.size(24.dp),
        )
    }
}

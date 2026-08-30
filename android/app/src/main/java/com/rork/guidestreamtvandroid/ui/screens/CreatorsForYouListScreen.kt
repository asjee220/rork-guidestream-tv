package com.rork.guidestreamtvandroid.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
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
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items as gridItems
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.guidestreamtvandroid.data.models.SourceKind
import com.rork.guidestreamtvandroid.data.remote.RecommendedCreator
import com.rork.guidestreamtvandroid.data.remote.RecommendedCreatorsService
import com.rork.guidestreamtvandroid.ui.ads.InlineAdSlot
import com.rork.guidestreamtvandroid.ui.components.RemoteImage
import com.rork.guidestreamtvandroid.ui.theme.BrandBlue
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.KickGreen
import com.rork.guidestreamtvandroid.ui.theme.Navy
import com.rork.guidestreamtvandroid.ui.theme.PodcastPurple
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TwitchPurple
import com.rork.guidestreamtvandroid.ui.theme.YouTubeRed
import com.rork.guidestreamtvandroid.ui.theme.systemBottomInset

/**
 * Full-screen browse behind the "Creators/Podcasts for You" rail's See all
 * link. GUI-5: the rail was the only recommendation rail on Home without one,
 * on either platform. iOS got `CreatorsForYouListView`; this is its Android
 * twin, and it follows [HomeListScreen]'s shape — back-arrow row, large title,
 * two-column grid, an inline ad after every sixth card — so all the See-all
 * destinations stay consistent.
 *
 * Seeded with the rail's own recommendations so the screen never blanks while
 * the deeper fetch is in flight, then replaced by a call that asks the
 * recommender for [RecommendedCreatorsService.DEEP_LIMIT] instead of the
 * rail's 12. The rail's list is filtered on the caller's side, so what arrives
 * here is already free of creators the user follows.
 */
@Composable
fun CreatorsForYouListScreen(
    initialCreators: List<RecommendedCreator>,
    followedIds: List<String>,
    onBack: () -> Unit,
    onOpenCreator: (RecommendedCreator) -> Unit,
    modifier: Modifier = Modifier,
) {
    BackHandler { onBack() }

    var creators by remember(initialCreators) { mutableStateOf(initialCreators) }
    var isLoadingDeeper by remember(followedIds) { mutableStateOf(followedIds.isNotEmpty()) }

    // Only ever replaces the seed when the deeper call actually returns more,
    // so a failed or short fetch can never shrink what is already on screen.
    LaunchedEffect(followedIds) {
        if (followedIds.isEmpty()) return@LaunchedEffect
        val deeper = RecommendedCreatorsService.recommend(
            followedIds = followedIds,
            limit = RecommendedCreatorsService.DEEP_LIMIT,
        ).filter { it.titleId !in followedIds }
        if (deeper.size > creators.size) creators = deeper
        isLoadingDeeper = false
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(Navy),
    ) {
        // statusBarsPadding keeps the back-arrow tap target below the system
        // status bar — without it the status bar consumes the touch.
        Spacer(Modifier.statusBarsPadding().height(12.dp))

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
        }

        Text(
            text = "Creators/Podcasts for You",
            fontSize = 28.sp,
            fontWeight = FontWeight.Bold,
            color = TextPrimary,
            modifier = Modifier.padding(horizontal = 20.dp),
        )

        Spacer(Modifier.height(8.dp))

        if (creators.isEmpty()) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = if (isLoadingDeeper) "Finding creators…" else "Nothing here yet",
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = TextSecondary,
                )
            }
        } else {
            val dismissedAdSlots = remember { mutableStateMapOf<Int, Boolean>() }
            LazyVerticalGrid(
                columns = GridCells.Fixed(2),
                contentPadding = PaddingValues(
                    start = 20.dp,
                    end = 20.dp,
                    top = 12.dp,
                    bottom = systemBottomInset() + 24.dp,
                ),
                horizontalArrangement = Arrangement.spacedBy(14.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
                modifier = Modifier.fillMaxSize(),
            ) {
                creators.chunked(6).forEachIndexed { chunkIdx, chunk ->
                    gridItems(chunk, key = { it.titleId }) { creator ->
                        CreatorGridCell(
                            creator = creator,
                            onClick = { onOpenCreator(creator) },
                        )
                    }
                    if (chunk.size >= 6) {
                        item(span = { GridItemSpan(maxLineSpan) }) {
                            InlineAdSlot(
                                slotIndex = chunkIdx,
                                selectedServices = emptySet(),
                                adSource = "list_inline",
                                sectionKey = "list_inline_ad",
                                dismissed = dismissedAdSlots,
                            )
                        }
                    }
                }

                if (isLoadingDeeper) {
                    item(span = { GridItemSpan(maxLineSpan) }) {
                        Box(
                            modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            CircularProgressIndicator(
                                color = TextPrimary,
                                modifier = Modifier.size(22.dp),
                            )
                        }
                    }
                }
            }
        }
    }
}

/**
 * Grid-sized twin of the rail's `CreatorAvatarCard` — same poster proportions,
 * platform badge and match chip, sized to the column instead of a fixed 164dp.
 */
@Composable
private fun CreatorGridCell(
    creator: RecommendedCreator,
    onClick: () -> Unit,
) {
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
                .aspectRatio(0.6667f)
                .clip(RoundedCornerShape(10.dp)),
        ) {
            RemoteImage(
                url = creator.imageUrl,
                contentDescription = creator.displayName,
                modifier = Modifier.fillMaxSize(),
                cornerRadius = 10,
                placeholderText = creator.displayName.take(2).uppercase(),
                placeholderFontSize = 22.sp,
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
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            color = TextPrimary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

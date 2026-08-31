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
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rork.guidestreamtvandroid.data.models.TitleId
import com.rork.guidestreamtvandroid.data.repository.StreamsViewModel
import com.rork.guidestreamtvandroid.ui.ads.InlineAdSlot
import com.rork.guidestreamtvandroid.ui.components.NewEpisodeListRow
import com.rork.guidestreamtvandroid.ui.components.newEpisodeShowName
import com.rork.guidestreamtvandroid.ui.navigation.PendingTitleRoute
import com.rork.guidestreamtvandroid.ui.theme.Navy
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.systemBottomInset

/**
 * Full-screen "New Episodes" list, reached from the Home rail's See all.
 * Mirrors iOS NewEpisodesListView: back-arrow row, large heading, one row per
 * episode. Reads `StreamsViewModel.newEpisodes` directly rather than taking a
 * snapshot, so opening an episode and coming back reflects any refresh that
 * happened underneath.
 *
 * That flow is already filtered to rows still new for THIS viewer
 * (`isNewForViewer`, GUI-74), sorted newest-first and capped at 20, so this
 * screen deliberately does no filtering or sorting of its own — a second
 * opinion here is how the rail and the list start disagreeing.
 */
@Composable
fun NewEpisodesScreen(
    onBack: () -> Unit,
    onOpenTitle: (PendingTitleRoute) -> Unit,
    modifier: Modifier = Modifier,
) {
    BackHandler { onBack() }

    val streamsVm = StreamsViewModel.get()
    val episodes by streamsVm.newEpisodes.collectAsStateWithLifecycle()

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
            text = "New Episodes",
            fontSize = 28.sp,
            lineHeight = 34.sp,
            fontWeight = FontWeight.Bold,
            color = TextPrimary,
            modifier = Modifier.padding(horizontal = 20.dp),
        )

        Spacer(Modifier.height(8.dp))

        if (episodes.isEmpty()) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = "Nothing new right now",
                    fontSize = 15.sp,
                    lineHeight = 19.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = TextSecondary,
                )
            }
        } else {
            val dismissedAdSlots = remember { mutableStateMapOf<Int, Boolean>() }
            LazyColumn(
                contentPadding = PaddingValues(
                    start = 20.dp,
                    end = 20.dp,
                    top = 12.dp,
                    bottom = systemBottomInset() + 24.dp,
                ),
                verticalArrangement = Arrangement.spacedBy(16.dp),
                modifier = Modifier.fillMaxSize(),
            ) {
                episodes.chunked(6).forEachIndexed { chunkIdx, chunk ->
                    items(chunk, key = { "${it.titleId}-${it.season}-${it.episode}-${it.episodeId ?: it.id}" }) { row ->
                        NewEpisodeListRow(
                            row = row,
                            onClick = {
                                onOpenTitle(
                                    PendingTitleRoute(
                                        titleId = row.titleId,
                                        titleName = newEpisodeShowName(row),
                                        posterUrl = row.posterUrl,
                                        isTv = TitleId.isTv(row.titleId) ?: true,
                                    ),
                                )
                            },
                        )
                    }
                    // Same cadence as HomeListScreen: one slot after each full
                    // run of six, never after a short trailing chunk.
                    if (chunk.size >= 6) {
                        item {
                            InlineAdSlot(
                                slotIndex = chunkIdx,
                                selectedServices = emptySet(),
                                adSource = "list_inline",
                                sectionKey = "new_episodes_inline_ad",
                                dismissed = dismissedAdSlots,
                            )
                        }
                    }
                }
            }
        }
    }
}

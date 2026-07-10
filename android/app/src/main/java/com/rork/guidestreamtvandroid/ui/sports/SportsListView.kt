package com.rork.guidestreamtvandroid.ui.sports

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
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.guidestreamtvandroid.data.models.SportsGame
import com.rork.guidestreamtvandroid.ui.theme.GlassFill
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary

/** Which see-all section is showing — drives the title. */
enum class SportsSection(val title: String) {
    LIVE("Live Now"),
    UPCOMING("Upcoming"),
    FINAL("Final"),
}

/**
 * Full-screen "See all" list for each Sports section. Mirrors iOS
 * SportsListView.swift — reuses the same compact game rows and opens the
 * shared watch sheet on tap.
 */
@Composable
fun SportsListView(
    games: List<SportsGame>,
    section: SportsSection,
    sportFilter: String,
    onBack: () -> Unit,
    onOpenGame: (SportsGame) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .background(Color(red = 0x04, green = 0x09, blue = 0x0F)),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(GlassFill)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onBack() },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = "Back",
                    tint = TextPrimary,
                    modifier = Modifier.size(22.dp),
                )
            }
            Spacer(Modifier.width(12.dp))
            Text(
                text = if (sportFilter == "All") section.title else "${section.title} · $sportFilter",
                fontSize = 22.sp,
                fontWeight = FontWeight.Black,
                color = TextPrimary,
            )
        }

        if (games.isEmpty()) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(
                    text = "No ${section.title.lowercase()} games${if (sportFilter == "All") "" else " for $sportFilter"}.",
                    fontSize = 14.sp,
                    color = TextTertiary,
                )
            }
        } else {
            LazyColumn(
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                items(games, key = { it.id }) { game ->
                    when (section) {
                        SportsSection.LIVE -> LiveGameRow(game) { onOpenGame(game) }
                        SportsSection.UPCOMING -> UpcomingGameRow(game) { onOpenGame(game) }
                        SportsSection.FINAL -> FinalGameRow(game) { onOpenGame(game) }
                    }
                }
            }
        }
    }
}

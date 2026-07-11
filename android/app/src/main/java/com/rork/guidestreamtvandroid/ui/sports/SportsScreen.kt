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
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.SportsBasketball
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rork.guidestreamtvandroid.data.models.SportsGame
import com.rork.guidestreamtvandroid.data.models.StreamingCatalog
import com.rork.guidestreamtvandroid.data.models.StreamingService
import com.rork.guidestreamtvandroid.data.repository.AuthViewModel
import com.rork.guidestreamtvandroid.data.repository.TeamFavoritesService
import com.rork.guidestreamtvandroid.data.repository.WatchIntentLogger
import com.rork.guidestreamtvandroid.ui.components.ServicesPill
import com.rork.guidestreamtvandroid.ui.theme.BrandBlue
import com.rork.guidestreamtvandroid.ui.theme.BottomSafeSpacer
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.BrandWordmark
import com.rork.guidestreamtvandroid.ui.theme.Hairline
import com.rork.guidestreamtvandroid.ui.theme.Navy
import com.rork.guidestreamtvandroid.ui.theme.OutlineVariant
import com.rork.guidestreamtvandroid.ui.theme.SurfaceContainer
import com.rork.guidestreamtvandroid.ui.theme.SurfaceElevated
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.WordmarkSize

private val sportOptions = listOf("All", "NBA", "NBA Summer", "NFL", "Soccer", "MLB", "UFC")
private val LiveRed = Color(0xFFE50914)

/**
 * Sports screen — mirrors iOS SportsView.swift.
 * Pinned header (wordmark + services pill), sport pills, My Teams from real
 * favorites, and Live Now / Upcoming / Final sections with See all.
 */
@Composable
fun SportsScreen(
    onOpenGameDetail: (SportsGame) -> Unit,
    modifier: Modifier = Modifier,
) {
    val vm = SportsViewModel.get()
    val games by vm.games.collectAsStateWithLifecycle()
    val isLoading by vm.isLoading.collectAsStateWithLifecycle()
    val selectedSport by vm.selectedSport.collectAsStateWithLifecycle()

    val authVm = AuthViewModel.get()
    val selectedServices by authVm.selectedServices.collectAsStateWithLifecycle()

    val favorites = TeamFavoritesService.get()
    val favRows by favorites.rows.collectAsStateWithLifecycle()

    var isEditingTeams by remember { mutableStateOf(false) }
    var watchGame by remember { mutableStateOf<SportsGame?>(null) }
    var seeAll by remember { mutableStateOf<SportsSection?>(null) }
    var showServices by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { vm.fetchGames() }

    val activeSport = selectedSport ?: "All"
    val filtered = remember(games, activeSport) {
        if (activeSport == "All") games else games.filter { it.sport == activeSport }
    }
    val live = remember(filtered) { filtered.filter { it.state == "live" } }
    val upcoming = remember(filtered) { filtered.filter { it.state == "pre" } }
    val finals = remember(filtered) { filtered.filter { it.state == "post" } }

    // Build My Teams chips from persisted favorites, matched to loaded games.
    val teamChips = remember(favRows, games) {
        favRows.values.mapNotNull { row ->
            val game = findGameForFavorite(games, row.teamUid, row.teamAbbr)
            TeamChip(
                uid = row.teamUid,
                abbrev = row.teamAbbr ?: (row.teamName ?: row.teamUid).take(3).uppercase(),
                name = row.teamName ?: row.teamAbbr ?: "",
                colorHex = colorHexForFavorite(game, row.teamUid),
                statusLabel = teamStatusLabel(game),
                isLive = game?.state == "live",
            )
        }
    }

    Column(modifier = modifier.fillMaxSize()) {
        // Pinned header: wordmark + services pill
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .height(56.dp)
                .padding(horizontal = 20.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            BrandWordmark(size = WordmarkSize.NAV)
            Spacer(Modifier.weight(1f))
            if (isLoading && games.isNotEmpty()) {
                CircularProgressIndicator(color = BrandOrange, modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                Spacer(Modifier.width(10.dp))
            }
            val serviceIds = StreamingCatalog.ordered(selectedServices).map { it.id }
            if (serviceIds.isNotEmpty()) {
                ServicesPill(serviceIds = serviceIds, onTap = { showServices = true })
            }
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // Sport pills
            item {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(sportOptions) { sport ->
                        SportChip(sport, sport == activeSport) {
                            vm.setSport(if (sport == "All") null else sport)
                        }
                    }
                }
            }

            // My Teams
            if (teamChips.isNotEmpty()) {
                item {
                    MyTeamsSection(
                        chips = teamChips,
                        isEditing = isEditingTeams,
                        onToggleEdit = { isEditingTeams = !isEditingTeams },
                        onChipTap = { chip ->
                            findGameForFavorite(games, chip.uid, chip.abbrev)?.let { watchGame = it }
                        },
                        onRemove = { chip ->
                            favorites.toggle(
                                SportsGame.TeamSummary(
                                    name = chip.name,
                                    abbreviation = chip.abbrev,
                                    uid = chip.uid,
                                    displayName = chip.name,
                                    shortName = chip.name,
                                ),
                                league = favRows[chip.uid]?.league,
                                sport = favRows[chip.uid]?.sport,
                            )
                        },
                    )
                }
                item {
                    Box(Modifier.fillMaxWidth().height(1.dp).background(Hairline))
                }
            } else {
                item { NoFavoritesPrompt() }
            }

            // Content
            if (isLoading && games.isEmpty()) {
                items(3) { LoadingCard() }
            } else if (filtered.isEmpty()) {
                item { EmptyState(activeSport) }
            } else {
                if (live.isNotEmpty()) {
                    item { SectionHeader("Live Now", live.size) { seeAll = SportsSection.LIVE } }
                    items(live.take(4), key = { "live-${it.id}" }) { game ->
                        LiveGameRow(game) { openCard(game, watchGameSetter = { watchGame = it }) }
                    }
                }
                if (upcoming.isNotEmpty()) {
                    item { SectionHeader("Upcoming", upcoming.size) { seeAll = SportsSection.UPCOMING } }
                    items(upcoming.take(8), key = { "up-${it.id}" }) { game ->
                        UpcomingGameRow(game) { openCard(game, watchGameSetter = { watchGame = it }) }
                    }
                }
                if (finals.isNotEmpty()) {
                    item { SectionHeader("Final", finals.size) { seeAll = SportsSection.FINAL } }
                    items(finals.take(6), key = { "fin-${it.id}" }) { game ->
                        FinalGameRow(game) { openCard(game, watchGameSetter = { watchGame = it }) }
                    }
                }
            }

            item { BottomSafeSpacer(withTabBar = true) }
        }
    }

    // Watch sheet
    watchGame?.let { game ->
        SportsWatchSheet(
            game = game,
            onDismiss = { watchGame = null },
            onOpenGameDetail = { g ->
                watchGame = null
                onOpenGameDetail(g)
            },
            onOpenSchedule = {
                watchGame = null
                seeAll = SportsSection.UPCOMING
            },
        )
    }

    // Services editor sheet
    if (showServices) {
        ServicesEditorSheet(
            selected = selectedServices,
            onToggle = { id ->
                val next = if (id in selectedServices) selectedServices - id else selectedServices + id
                authVm.setSelectedServices(next)
            },
            onDismiss = { showServices = false },
        )
    }

    // See all overlay
    seeAll?.let { section ->
        val list = when (section) {
            SportsSection.LIVE -> live
            SportsSection.UPCOMING -> upcoming
            SportsSection.FINAL -> finals
        }
        Box(Modifier.fillMaxSize()) {
            SportsListView(
                games = list,
                section = section,
                sportFilter = activeSport,
                onBack = { seeAll = null },
                onOpenGame = { game -> watchGame = game },
            )
        }
    }
}

private fun openCard(game: SportsGame, watchGameSetter: (SportsGame) -> Unit) {
    WatchIntentLogger.get().log(
        WatchIntentLogger.IntentEventType.CARD_TAPPED,
        titleId = "${game.away.abbreviation}-${game.home.abbreviation}-${game.sport}",
        metadata = mapOf("section" to "sports", "sport" to game.sport),
    )
    watchGameSetter(game)
}

// MARK: - Pills

@Composable
private fun SportChip(label: String, selected: Boolean, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .clip(CircleShape)
            .then(if (selected) Modifier.background(BrandOrange) else Modifier)
            .border(1.dp, if (selected) Color.Transparent else Color.White.copy(alpha = 0.15f), CircleShape)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() }
            .padding(horizontal = 14.dp, vertical = 7.dp),
    ) {
        Text(
            text = label,
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold,
            color = if (selected) Color.White else Color.White.copy(alpha = 0.5f),
        )
    }
}

// MARK: - My Teams

data class TeamChip(
    val uid: String,
    val abbrev: String,
    val name: String,
    val colorHex: String?,
    val statusLabel: String,
    val isLive: Boolean,
)

@Composable
private fun MyTeamsSection(
    chips: List<TeamChip>,
    isEditing: Boolean,
    onToggleEdit: () -> Unit,
    onChipTap: (TeamChip) -> Unit,
    onRemove: (TeamChip) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("My Teams", fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Color.White)
            Spacer(Modifier.weight(1f))
            Text(
                text = if (isEditing) "Done" else "Edit",
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium,
                color = BrandBlue,
                modifier = Modifier
                    .clip(CircleShape)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onToggleEdit() }
                    .padding(horizontal = 8.dp, vertical = 4.dp),
            )
        }
        LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            items(chips, key = { it.uid }) { chip ->
                Box {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(3.dp),
                        modifier = Modifier
                            .clip(RoundedCornerShape(12.dp))
                            .background(SurfaceContainer)
                            .border(
                                1.dp,
                                if (chip.isLive) LiveRed.copy(alpha = 0.35f) else OutlineVariant,
                                RoundedCornerShape(12.dp),
                            )
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                            ) { onChipTap(chip) }
                            .padding(8.dp)
                            .width(64.dp),
                    ) {
                        Box(
                            modifier = Modifier
                                .size(26.dp)
                                .clip(RoundedCornerShape(7.dp))
                                .background(hexToColor(chip.colorHex, Color.White.copy(alpha = 0.15f))),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(chip.abbrev.take(3), fontSize = 8.sp, fontWeight = FontWeight.Black, color = Color.White)
                        }
                        Text(chip.name, fontSize = 9.sp, fontWeight = FontWeight.SemiBold, color = Color.White.copy(alpha = 0.6f), maxLines = 1)
                        Text(
                            chip.statusLabel,
                            fontSize = 8.sp,
                            fontWeight = FontWeight.Bold,
                            color = if (chip.isLive) LiveRed else BrandOrange,
                            maxLines = 1,
                        )
                    }
                    if (isEditing) {
                        Box(
                            modifier = Modifier
                                .align(Alignment.TopEnd)
                                .size(22.dp)
                                .clip(CircleShape)
                                .background(LiveRed)
                                .clickable(
                                    interactionSource = remember { MutableInteractionSource() },
                                    indication = null,
                                ) { onRemove(chip) },
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(Icons.Filled.Close, contentDescription = "Remove", tint = Color.White, modifier = Modifier.size(12.dp))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun NoFavoritesPrompt() {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("My Teams", fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Color.White)
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.padding(vertical = 8.dp),
        ) {
            Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = BrandOrange.copy(alpha = 0.7f), modifier = Modifier.size(14.dp))
            Text(
                "Tap the star on any game to favorite a team and see it here.",
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium,
                color = Color.White.copy(alpha = 0.45f),
                maxLines = 2,
            )
        }
    }
}

// MARK: - Section header

@Composable
private fun SectionHeader(title: String, count: Int, onSeeAll: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(title, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Color.White)
        Spacer(Modifier.width(8.dp))
        Box(
            modifier = Modifier
                .clip(CircleShape)
                .background(SurfaceContainer)
                .padding(horizontal = 7.dp, vertical = 2.dp),
        ) {
            Text("$count", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Color.White.copy(alpha = 0.5f))
        }
        Spacer(Modifier.weight(1f))
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .clip(CircleShape)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) { onSeeAll() }
                .padding(horizontal = 4.dp, vertical = 2.dp),
        ) {
            Text("See all", fontSize = 13.sp, fontWeight = FontWeight.Medium, color = BrandBlue)
            Spacer(Modifier.width(4.dp))
            Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = null, tint = BrandBlue, modifier = Modifier.size(12.dp))
        }
    }
}

// MARK: - Game rows (shared with SportsListView)

@Composable
fun LiveGameRow(game: SportsGame, onClick: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(SurfaceContainer)
            .border(1.dp, OutlineVariant, RoundedCornerShape(16.dp))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() }
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(6.dp).clip(CircleShape).background(LiveRed))
            Spacer(Modifier.width(5.dp))
            Text("LIVE", fontSize = 9.sp, fontWeight = FontWeight.Black, color = LiveRed)
            Spacer(Modifier.width(6.dp))
            Text("${game.sport} · ${game.statusDetail}", fontSize = 9.sp, fontWeight = FontWeight.SemiBold, color = Color.White.copy(alpha = 0.5f), maxLines = 1)
            Spacer(Modifier.weight(1f))
            Box(
                modifier = Modifier.clip(CircleShape).background(BrandOrange).padding(horizontal = 14.dp, vertical = 7.dp),
            ) {
                Text("Watch ▶", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Color.White)
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            LiveTeamBlock(game.away, Modifier.weight(1f), Alignment.Start)
            Text("VS", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Color.White.copy(alpha = 0.2f))
            LiveTeamBlock(game.home, Modifier.weight(1f), Alignment.End)
        }
        BroadcastsRow(game.broadcasts)
    }
}

@Composable
private fun LiveTeamBlock(team: SportsGame.TeamSummary, modifier: Modifier, align: Alignment.Horizontal) {
    Column(
        modifier = modifier,
        horizontalAlignment = align,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Box(
            modifier = Modifier
                .size(38.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(hexToColor(team.primaryHex)),
            contentAlignment = Alignment.Center,
        ) {
            Text(team.abbreviation, fontSize = 9.sp, fontWeight = FontWeight.Black, color = Color.White)
        }
        Text(team.shortName.ifEmpty { team.abbreviation }, fontSize = 10.sp, fontWeight = FontWeight.SemiBold, color = Color.White.copy(alpha = 0.6f), maxLines = 1)
        Text(team.score.ifEmpty { "0" }, fontSize = 24.sp, fontWeight = FontWeight.Black, color = if (team.isWinner) Color.White else Color.White.copy(alpha = 0.55f))
    }
}

@Composable
fun UpcomingGameRow(game: SportsGame, onClick: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(SurfaceContainer)
            .border(1.dp, OutlineVariant, RoundedCornerShape(16.dp))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() }
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            TeamBadge(game.away)
            Text("vs", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Color.White.copy(alpha = 0.3f))
            TeamBadge(game.home)
            Column(Modifier.weight(1f)) {
                Text("${game.away.shortName.ifEmpty { game.away.abbreviation }} vs ${game.home.shortName.ifEmpty { game.home.abbreviation }}", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = Color.White, maxLines = 1)
                Text("${game.sport} · ${game.statusDetail}", fontSize = 10.sp, color = Color.White.copy(alpha = 0.4f), maxLines = 1)
            }
            Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = Color.White.copy(alpha = 0.35f), modifier = Modifier.size(16.dp))
        }
        BroadcastsRow(game.broadcasts)
    }
}

@Composable
private fun TeamBadge(team: SportsGame.TeamSummary) {
    Box(
        modifier = Modifier
            .size(30.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(hexToColor(team.primaryHex)),
        contentAlignment = Alignment.Center,
    ) {
        Text(team.abbreviation, fontSize = 7.sp, fontWeight = FontWeight.Black, color = Color.White)
    }
}

@Composable
fun FinalGameRow(game: SportsGame, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(SurfaceElevated)
            .border(1.dp, OutlineVariant, RoundedCornerShape(14.dp))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() }
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.width(110.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            FinalScoreLine(game.away)
            FinalScoreLine(game.home)
        }
        Box(Modifier.width(1.dp).height(36.dp).background(Hairline))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(game.statusDetail.ifEmpty { "Final" }, fontSize = 10.sp, fontWeight = FontWeight.Bold, color = Color.White.copy(alpha = 0.55f))
            Text(game.sport, fontSize = 9.sp, fontWeight = FontWeight.SemiBold, color = Color.White.copy(alpha = 0.35f))
        }
        Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = Color.White.copy(alpha = 0.3f), modifier = Modifier.size(16.dp))
    }
}

@Composable
private fun FinalScoreLine(team: SportsGame.TeamSummary) {
    val color = if (team.isWinner) Color.White else Color.White.copy(alpha = 0.5f)
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(team.abbreviation, fontSize = 11.sp, fontWeight = FontWeight.Bold, color = color)
        Spacer(Modifier.weight(1f))
        Text(team.score.ifEmpty { "0" }, fontSize = 14.sp, fontWeight = FontWeight.Black, color = color)
    }
}

@Composable
private fun BroadcastsRow(broadcasts: List<String>) {
    if (broadcasts.isEmpty()) return
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("ON:", fontSize = 9.sp, fontWeight = FontWeight.Bold, color = Color.White.copy(alpha = 0.35f))
        broadcasts.take(4).forEach { name ->
            Box(
                modifier = Modifier.clip(RoundedCornerShape(5.dp)).background(broadcastColor(name)).padding(horizontal = 8.dp, vertical = 3.dp),
            ) {
                Text(name, fontSize = 9.sp, fontWeight = FontWeight.Black, color = Color.White)
            }
        }
    }
}

// MARK: - States

@Composable
private fun LoadingCard() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(120.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(SurfaceContainer)
            .border(1.dp, OutlineVariant, RoundedCornerShape(16.dp)),
    )
}

@Composable
private fun EmptyState(sport: String) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(vertical = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(Icons.Filled.SportsBasketball, contentDescription = null, tint = Color.White.copy(alpha = 0.3f), modifier = Modifier.size(28.dp))
        Text(
            text = if (sport == "All") "No games today." else "No $sport games today.",
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium,
            color = Color.White.copy(alpha = 0.5f),
        )
    }
}

// MARK: - Helpers

private fun findGameForFavorite(games: List<SportsGame>, uid: String, abbr: String?): SportsGame? {
    fun matches(g: SportsGame): Boolean {
        if (g.away.uid == uid || g.home.uid == uid) return true
        if (abbr != null) return g.away.abbreviation == abbr || g.home.abbreviation == abbr
        return false
    }
    games.firstOrNull { it.state == "live" && matches(it) }?.let { return it }
    games.filter { it.state == "pre" && matches(it) }.minByOrNull { it.startTime ?: "" }?.let { return it }
    games.filter { it.state == "post" && matches(it) }.maxByOrNull { it.startTime ?: "" }?.let { return it }
    return null
}

private fun colorHexForFavorite(game: SportsGame?, uid: String): String? {
    if (game == null) return null
    if (game.away.uid == uid) return game.away.primaryHex
    if (game.home.uid == uid) return game.home.primaryHex
    return null
}

// MARK: - Services editor sheet

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
    service: StreamingService,
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
            is StreamingService.Display.Text -> display.text
            is StreamingService.Display.SymbolText -> display.text
            is StreamingService.Display.Star -> service.name
        }
        val labelColor = when (display) {
            is StreamingService.Display.Text -> display.color
            is StreamingService.Display.SymbolText -> display.color
            is StreamingService.Display.Star -> display.color
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

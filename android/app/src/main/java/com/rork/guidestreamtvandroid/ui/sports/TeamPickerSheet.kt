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
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.filled.Search
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
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rork.guidestreamtvandroid.data.models.SportsGame
import com.rork.guidestreamtvandroid.data.remote.SportsTeamCatalogService
import com.rork.guidestreamtvandroid.data.repository.TeamFavoritesService
import com.rork.guidestreamtvandroid.ui.components.GsSheetDragHandle
import com.rork.guidestreamtvandroid.ui.theme.BrandBlue
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.Hairline
import com.rork.guidestreamtvandroid.ui.theme.OutlineVariant
import com.rork.guidestreamtvandroid.ui.theme.SheetLevel
import com.rork.guidestreamtvandroid.ui.theme.SheetSurfaceBase
import com.rork.guidestreamtvandroid.ui.theme.SurfaceContainer
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.sheetTopInset
import kotlinx.coroutines.launch

/**
 * Presentation source for [TeamPickerSheet]. First-run gets onboarding copy and
 * a "Not right now" escape; the edit entry point gets neutral copy and Done.
 */
enum class TeamPickerMode { ONBOARDING, EDIT }

/**
 * Favorite-team picker — mirrors iOS TeamPickerSheet.swift. Shown automatically
 * the first time a user opens the Sports tab, and on demand from
 * "My Teams -> Edit".
 *
 * Reads the full league rosters from SportsTeamCatalogService and writes through
 * TeamFavoritesService, so a team favorited here is identical to one starred on
 * a game card and is picked up by sports_poll_and_notify for starting-soon /
 * going-live / final-score pushes.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TeamPickerSheet(
    mode: TeamPickerMode,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()

    val catalog = remember { SportsTeamCatalogService.get() }
    val favorites = remember { TeamFavoritesService.get() }
    val teams by catalog.teams.collectAsStateWithLifecycle()
    val isLoading by catalog.isLoading.collectAsStateWithLifecycle()
    val favRows by favorites.rows.collectAsStateWithLifecycle()

    var selectedSport by remember { mutableStateOf<String?>(null) }
    var query by remember { mutableStateOf("") }
    var isSaving by remember { mutableStateOf(false) }
    var seeded by remember { mutableStateOf(false) }

    /** Teams picked in this session, keyed by uid. */
    val selected = remember { mutableStateMapOf<String, SportsTeamCatalogService.SportsTeamRow>() }

    LaunchedEffect(Unit) {
        catalog.load()
        favorites.load()
    }

    // Pre-tick whatever is already favorited so the edit entry point is a true
    // editor rather than an additive-only picker. Runs once, after the
    // catalogue arrives.
    LaunchedEffect(teams, favRows) {
        if (seeded || teams.isEmpty()) return@LaunchedEffect
        teams.filter { favRows.containsKey(it.teamUid) }.forEach { selected[it.teamUid] = it }
        seeded = true
    }

    val sports = remember(teams) { teams.map { it.sport }.distinct() }
    val activeSport = selectedSport ?: sports.firstOrNull()
    val visibleTeams = remember(teams, activeSport, query) {
        val pool = teams.filter { it.sport == activeSport }
        val q = query.trim().lowercase()
        if (q.isEmpty()) pool else pool.filter { it.searchHaystack.contains(q) }
    }
    // Selection in catalogue order so the strip doesn't reshuffle on each tap.
    val orderedSelection = remember(teams, selected.size) {
        teams.filter { selected.containsKey(it.teamUid) }
    }

    val ctaEnabled = mode == TeamPickerMode.EDIT || selected.isNotEmpty()
    val ctaLabel = when {
        mode == TeamPickerMode.EDIT -> "Done"
        selected.isEmpty() -> "Continue"
        selected.size == 1 -> "Follow 1 team"
        else -> "Follow ${selected.size} teams"
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = SheetSurfaceBase,
        scrimColor = Color.Black.copy(alpha = 0.60f),
        tonalElevation = 0.dp,
        dragHandle = { GsSheetDragHandle(level = SheetLevel.Base) },
        contentWindowInsets = { sheetTopInset() },
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .fillMaxHeight(0.88f),
        ) {
            // Header
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 20.dp, end = 20.dp, top = 6.dp, bottom = 12.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text(
                    "SPORTS",
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 1.4.sp,
                    color = BrandOrange,
                )
                Text(
                    if (mode == TeamPickerMode.ONBOARDING) "Pick your teams" else "Your teams",
                    fontSize = 21.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                )
                Text(
                    if (mode == TeamPickerMode.ONBOARDING) {
                        "We'll ping you before kickoff, when they go live, and with the final score \u2014 and pin them to the top of Sports."
                    } else {
                        "Add or remove teams. Changes save when you tap Done."
                    },
                    fontSize = 12.5.sp,
                    color = Color.White.copy(alpha = 0.5f),
                    lineHeight = 18.sp,
                )
            }

            // Sport pills
            LazyRow(
                horizontalArrangement = Arrangement.spacedBy(7.dp),
                contentPadding = PaddingValues(horizontal = 20.dp),
                modifier = Modifier.padding(bottom = 11.dp),
            ) {
                items(sports, key = { it }) { sport ->
                    val isActive = sport == activeSport
                    Box(
                        modifier = Modifier
                            .clip(CircleShape)
                            .then(if (isActive) Modifier.background(BrandOrange) else Modifier)
                            .border(
                                1.dp,
                                if (isActive) Color.Transparent else Color.White.copy(alpha = 0.15f),
                                CircleShape,
                            )
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                            ) { selectedSport = sport }
                            .padding(horizontal = 14.dp, vertical = 7.dp),
                    ) {
                        Text(
                            sport,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold,
                            color = if (isActive) Color.White else Color.White.copy(alpha = 0.5f),
                        )
                    }
                }
            }

            // Search
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier
                    .padding(horizontal = 20.dp)
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(12.dp))
                    .background(Color.White.copy(alpha = 0.06f))
                    .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(12.dp))
                    .padding(horizontal = 12.dp, vertical = 9.dp),
            ) {
                Icon(
                    Icons.Filled.Search,
                    contentDescription = null,
                    tint = Color.White.copy(alpha = 0.45f),
                    modifier = Modifier.size(15.dp),
                )
                Box(Modifier.weight(1f)) {
                    if (query.isEmpty()) {
                        Text(
                            "Search teams",
                            fontSize = 13.sp,
                            color = Color.White.copy(alpha = 0.35f),
                        )
                    }
                    BasicTextField(
                        value = query,
                        onValueChange = { query = it },
                        singleLine = true,
                        cursorBrush = SolidColor(BrandOrange),
                        textStyle = TextStyle(color = Color.White, fontSize = 13.sp),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                if (query.isNotEmpty()) {
                    Icon(
                        Icons.Filled.Close,
                        contentDescription = "Clear search",
                        tint = Color.White.copy(alpha = 0.4f),
                        modifier = Modifier
                            .size(15.dp)
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                            ) { query = "" },
                    )
                }
            }

            Spacer(Modifier.height(12.dp))

            // Grid / states
            Box(Modifier.weight(1f)) {
                when {
                    teams.isEmpty() && isLoading -> {
                        LazyVerticalGrid(
                            columns = GridCells.Adaptive(96.dp),
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            verticalArrangement = Arrangement.spacedBy(10.dp),
                            contentPadding = PaddingValues(horizontal = 20.dp),
                        ) {
                            items(12) {
                                Box(
                                    Modifier
                                        .height(92.dp)
                                        .clip(RoundedCornerShape(14.dp))
                                        .background(Color.White.copy(alpha = 0.045f)),
                                )
                            }
                        }
                    }

                    teams.isEmpty() -> {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(10.dp),
                            modifier = Modifier.fillMaxWidth().padding(top = 48.dp),
                        ) {
                            Icon(
                                Icons.Filled.CloudOff,
                                contentDescription = null,
                                tint = Color.White.copy(alpha = 0.3f),
                                modifier = Modifier.size(26.dp),
                            )
                            Text(
                                "Couldn't load teams right now.",
                                fontSize = 13.sp,
                                fontWeight = FontWeight.Medium,
                                color = Color.White.copy(alpha = 0.5f),
                            )
                            Text(
                                "Try again",
                                fontSize = 13.sp,
                                fontWeight = FontWeight.Bold,
                                color = BrandBlue,
                                modifier = Modifier.clickable(
                                    interactionSource = remember { MutableInteractionSource() },
                                    indication = null,
                                ) { scope.launch { catalog.load(force = true) } },
                            )
                        }
                    }

                    visibleTeams.isEmpty() -> {
                        Text(
                            "No teams match that search.",
                            fontSize = 12.5.sp,
                            fontWeight = FontWeight.Medium,
                            color = Color.White.copy(alpha = 0.35f),
                            textAlign = TextAlign.Center,
                            modifier = Modifier.fillMaxWidth().padding(top = 34.dp),
                        )
                    }

                    else -> {
                        LazyVerticalGrid(
                            columns = GridCells.Adaptive(96.dp),
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            verticalArrangement = Arrangement.spacedBy(10.dp),
                            contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = 16.dp),
                        ) {
                            items(visibleTeams, key = { it.teamUid }) { team ->
                                TeamTile(
                                    team = team,
                                    isSelected = selected.containsKey(team.teamUid),
                                    onToggle = {
                                        if (selected.containsKey(team.teamUid)) {
                                            selected.remove(team.teamUid)
                                        } else {
                                            selected[team.teamUid] = team
                                        }
                                    },
                                )
                            }
                        }
                    }
                }
            }

            // Footer
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Hairline.copy(alpha = 0.0f))
                    .padding(top = 12.dp, bottom = 20.dp),
            ) {
                Box(Modifier.fillMaxWidth().height(1.dp).background(Hairline))
                Spacer(Modifier.height(12.dp))

                if (orderedSelection.isNotEmpty()) {
                    LazyRow(
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        contentPadding = PaddingValues(horizontal = 20.dp),
                        modifier = Modifier.padding(bottom = 10.dp),
                    ) {
                        items(orderedSelection, key = { it.teamUid }) { team ->
                            SelectedChip(team) { selected.remove(team.teamUid) }
                        }
                    }
                }

                Box(
                    modifier = Modifier
                        .padding(horizontal = 20.dp)
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(14.dp))
                        .background(if (ctaEnabled) BrandOrange else Color.White.copy(alpha = 0.10f))
                        .clickable(
                            enabled = ctaEnabled && !isSaving,
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                        ) {
                            scope.launch {
                                isSaving = true
                                try {
                                    commitSelection(favorites, favRows.keys, selected.values.toList())
                                } finally {
                                    isSaving = false
                                    onDismiss()
                                }
                            }
                        }
                        .padding(vertical = 14.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    if (isSaving) {
                        CircularProgressIndicator(
                            color = Color.White,
                            strokeWidth = 2.dp,
                            modifier = Modifier.size(18.dp),
                        )
                    } else {
                        Text(
                            ctaLabel,
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Bold,
                            color = if (ctaEnabled) Color.White else Color.White.copy(alpha = 0.35f),
                        )
                    }
                }

                if (mode == TeamPickerMode.ONBOARDING) {
                    Text(
                        "Not right now",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color.White.copy(alpha = 0.42f),
                        textAlign = TextAlign.Center,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                            ) { onDismiss() }
                            .padding(vertical = 11.dp),
                    )
                }
            }
        }
    }
}

/**
 * Diffs the session selection against persisted favorites and applies only what
 * actually changed, so re-opening the sheet and tapping Done writes nothing.
 */
private suspend fun commitSelection(
    favorites: TeamFavoritesService,
    before: Set<String>,
    selection: List<SportsTeamCatalogService.SportsTeamRow>,
) {
    val after = selection.map { it.teamUid }.toSet()

    val additions = selection
        .filter { it.teamUid !in before }
        .map { row ->
            TeamFavoritesService.FavoriteRow(
                teamUid = row.teamUid,
                teamAbbr = row.teamAbbr,
                teamName = row.displayLabel,
                league = row.league,
                sport = row.sport,
                teamId = row.teamId,
            )
        }
    if (additions.isNotEmpty()) favorites.addMany(additions)

    val removals = before.filter { it !in after }
    if (removals.isNotEmpty()) favorites.removeMany(removals)
}

@Composable
private fun TeamTile(
    team: SportsTeamCatalogService.SportsTeamRow,
    isSelected: Boolean,
    onToggle: () -> Unit,
) {
    Box {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterVertically),
            modifier = Modifier
                .fillMaxWidth()
                .height(92.dp)
                .clip(RoundedCornerShape(14.dp))
                .background(
                    if (isSelected) BrandOrange.copy(alpha = 0.10f) else Color.White.copy(alpha = 0.045f),
                )
                .border(
                    1.dp,
                    if (isSelected) BrandOrange else OutlineVariant,
                    RoundedCornerShape(14.dp),
                )
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) { onToggle() }
                .padding(horizontal = 4.dp),
        ) {
            TeamLogo(
                team = team.asTeamSummary(),
                size = 46.dp,
                cornerRadius = 11.dp,
                inset = 5.dp,
                abbreviationFontSize = 11.sp,
            )
            Text(
                team.displayLabel,
                fontSize = 10.sp,
                fontWeight = FontWeight.SemiBold,
                color = if (isSelected) Color.White else Color.White.copy(alpha = 0.72f),
                textAlign = TextAlign.Center,
                maxLines = 2,
                lineHeight = 12.sp,
            )
        }
        if (isSelected) {
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(5.dp)
                    .size(17.dp)
                    .clip(CircleShape)
                    .background(BrandOrange),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Filled.Check,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(11.dp),
                )
            }
        }
    }
}

@Composable
private fun SelectedChip(
    team: SportsTeamCatalogService.SportsTeamRow,
    onRemove: () -> Unit,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        modifier = Modifier
            .clip(CircleShape)
            .background(SurfaceContainer)
            .border(1.dp, OutlineVariant, CircleShape)
            .padding(start = 5.dp, end = 9.dp, top = 4.dp, bottom = 4.dp),
    ) {
        TeamLogo(
            team = team.asTeamSummary(),
            size = 16.dp,
            cornerRadius = 4.dp,
            inset = 1.dp,
            abbreviationFontSize = 5.sp,
        )
        Text(
            team.teamAbbr ?: team.displayLabel,
            fontSize = 10.5.sp,
            fontWeight = FontWeight.SemiBold,
            color = Color.White,
        )
        Icon(
            Icons.Filled.Close,
            contentDescription = "Remove",
            tint = TextSecondary,
            modifier = Modifier
                .size(11.dp)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) { onRemove() },
        )
    }
}

/**
 * Bridges a catalogue row into the [SportsGame.TeamSummary] shape [TeamLogo]
 * already renders, so picker crests are visually identical to game-card crests.
 */
private fun SportsTeamCatalogService.SportsTeamRow.asTeamSummary(): SportsGame.TeamSummary =
    SportsGame.TeamSummary(
        name = teamName,
        abbreviation = teamAbbr ?: teamName.take(3).uppercase(),
        logoUrl = logoUrl,
        uid = teamUid,
        displayName = teamName,
        shortName = displayLabel,
        primaryHex = color,
    )

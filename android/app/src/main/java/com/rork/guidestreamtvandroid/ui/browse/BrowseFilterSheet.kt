package com.rork.guidestreamtvandroid.ui.browse

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.guidestreamtvandroid.data.models.BrowseCatalog
import com.rork.guidestreamtvandroid.data.models.BrowseFilters
import com.rork.guidestreamtvandroid.data.models.BrowseMediaType
import com.rork.guidestreamtvandroid.data.remote.TMDBService
import com.rork.guidestreamtvandroid.ui.components.GsSheetDragHandle
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.Navy
import com.rork.guidestreamtvandroid.ui.theme.SheetLevel
import com.rork.guidestreamtvandroid.ui.theme.SheetSurfaceBase
import com.rork.guidestreamtvandroid.ui.theme.sheetTopInset
import kotlinx.coroutines.delay

/**
 * Release-year windows offered in the sheet. Mirrors iOS `YearPreset`.
 *
 * Presets rather than a dual-thumb range slider: the underlying model takes any
 * IntRange, so a slider can replace this later without touching the query layer.
 */
private enum class YearPreset(val label: String) {
    ANY("Any"),
    LAST_2("Last 2 years"),
    LAST_5("Last 5 years"),
    DECADE_2010("2010s"),
    DECADE_2000("2000s"),
    BEFORE_2000("Before 2000");

    val range: IntRange?
        get() {
            val now = BrowseCatalog.yearBounds.last
            return when (this) {
                ANY -> null
                LAST_2 -> (now - 1)..now
                LAST_5 -> (now - 4)..now
                DECADE_2010 -> 2010..2019
                DECADE_2000 -> 2000..2009
                BEFORE_2000 -> BrowseCatalog.yearBounds.first..1999
            }
        }

    companion object {
        fun matching(range: IntRange?): YearPreset =
            entries.firstOrNull { it.range == range } ?: ANY
    }
}

/**
 * Grouped filter sheet for Search & Browse. Mirrors iOS `BrowseFilterSheet`.
 *
 * The primary button states the outcome — "Show 214 titles" — and recounts as
 * the draft changes. Nothing is applied until the button is pressed.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BrowseFilterSheet(
    filters: BrowseFilters,
    onApply: (BrowseFilters) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var draft by remember { mutableStateOf(filters) }
    var previewCount by remember { mutableStateOf<Int?>(null) }
    var isCounting by remember { mutableStateOf(true) }

    // Debounced so tapping through chips does not fire a request per tap.
    LaunchedEffect(draft) {
        isCounting = true
        delay(250)
        previewCount = TMDBService.get().discoverBrowse(draft, page = 1).totalResults
        isCounting = false
    }

    val hasResults = (previewCount ?: 1) > 0

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = SheetSurfaceBase,
        scrimColor = Color.Black.copy(alpha = 0.60f),
        tonalElevation = 0.dp,
        dragHandle = { GsSheetDragHandle(level = SheetLevel.Base) },
        contentWindowInsets = { sheetTopInset() },
    ) {
        Column(modifier = Modifier.fillMaxWidth().fillMaxHeight(0.92f)) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "Filters",
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    text = "Reset",
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = BrandOrange,
                    modifier = Modifier.clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) {
                        draft = BrowseFilters(
                            genreIds = draft.genreIds,
                            providerIds = draft.providerIds,
                        )
                    },
                )
            }

            Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 18.dp),
                verticalArrangement = Arrangement.spacedBy(22.dp),
            ) {
                // Type
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    GroupLabel("Type")
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(10.dp))
                            .background(Color.White.copy(alpha = 0.07f))
                            .padding(3.dp)
                            .alpha(if (draft.lockingGenre == null) 1f else 0.55f),
                        horizontalArrangement = Arrangement.spacedBy(3.dp),
                    ) {
                        BrowseMediaType.entries.forEach { type ->
                            val on = draft.resolvedMediaType == type
                            Text(
                                text = type.label,
                                fontSize = 13.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = if (on) Navy else Color.White.copy(alpha = 0.6f),
                                textAlign = TextAlign.Center,
                                modifier = Modifier
                                    .weight(1f)
                                    .clip(RoundedCornerShape(8.dp))
                                    .background(if (on) BrandOrange else Color.Transparent)
                                    .clickable(
                                        interactionSource = remember { MutableInteractionSource() },
                                        indication = null,
                                    ) {
                                        if (draft.lockingGenre == null) {
                                            draft = draft.copy(mediaType = type)
                                        }
                                    }
                                    .padding(vertical = 8.dp),
                            )
                        }
                    }
                    // Horror is film-only in TMDB and Anime is TV-only, so
                    // picking either pins Type instead of quietly returning an
                    // empty grid.
                    draft.lockingGenre?.lockReason?.let {
                        Text(it, fontSize = 12.sp, color = Color.White.copy(alpha = 0.45f))
                    }
                }

                // Genre
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    GroupLabel("Genre")
                    ChipRows(
                        items = BrowseCatalog.genres.map { it.id to it.displayName },
                        isOn = { draft.genreIds.contains(it) },
                        onTap = { id ->
                            draft = if (draft.genreIds.contains(id)) {
                                // Never leave the grid genre-less; it is the subject.
                                if (draft.genreIds.size > 1) {
                                    draft.copy(genreIds = draft.genreIds - id)
                                } else {
                                    draft
                                }
                            } else {
                                draft.copy(genreIds = draft.genreIds + id)
                            }
                        },
                    )
                }

                // Services
                Column {
                    GroupLabel("Where I can watch")
                    Spacer(modifier = Modifier.height(4.dp))
                    ToggleRow(
                        title = "Only my services",
                        detail = draft.providerIds.size.takeIf { it > 0 }?.let { "$it connected" },
                        checked = draft.onlyMyServices,
                        onChange = { draft = draft.copy(onlyMyServices = it) },
                        showDivider = true,
                    )
                    ToggleRow(
                        title = "Include free with ads",
                        detail = null,
                        checked = draft.includeFreeWithAds,
                        onChange = { draft = draft.copy(includeFreeWithAds = it) },
                        showDivider = false,
                    )
                }

                // Year
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    GroupLabel("Release year")
                    ChipRows(
                        items = YearPreset.entries.map { it.name to it.label },
                        isOn = { YearPreset.matching(draft.yearRange).name == it },
                        onTap = { name ->
                            draft = draft.copy(yearRange = YearPreset.valueOf(name).range)
                        },
                    )
                }

                // Rating
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    GroupLabel("Minimum rating")
                    val options = listOf("any" to "Any") +
                        BrowseCatalog.ratingOptions.map { it.toString() to "★ ${it.toInt()}+" }
                    ChipRows(
                        items = options,
                        isOn = { key ->
                            if (key == "any") draft.minRating == null
                            else draft.minRating == key.toDoubleOrNull()
                        },
                        onTap = { key ->
                            draft = draft.copy(
                                minRating = if (key == "any") null else key.toDoubleOrNull()
                            )
                        },
                    )
                }

                Spacer(modifier = Modifier.height(4.dp))
            }

            Text(
                text = when {
                    isCounting || previewCount == null -> "Counting…"
                    previewCount == 0 -> "No titles match"
                    else -> "Show $previewCount titles"
                },
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
                color = if (hasResults) Navy else Color.White.copy(alpha = 0.35f),
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 18.dp, vertical = 6.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(if (hasResults) BrandOrange else Color.White.copy(alpha = 0.10f))
                    .clickable(
                        enabled = hasResults,
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) {
                        onApply(draft)
                        onDismiss()
                    }
                    .padding(vertical = 15.dp),
            )
            Spacer(modifier = Modifier.height(24.dp))
        }
    }
}

@Composable
private fun GroupLabel(text: String) {
    Text(
        text = text.uppercase(),
        fontSize = 11.sp,
        fontWeight = FontWeight.Bold,
        letterSpacing = 1.2.sp,
        color = Color.White.copy(alpha = 0.42f),
    )
}

/**
 * Two-per-row wrapping chips. A fixed wrap rather than a flow layout keeps the
 * sheet height predictable across font-scale settings.
 */
@Composable
private fun ChipRows(
    items: List<Pair<String, String>>,
    isOn: (String) -> Boolean,
    onTap: (String) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        items.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { (key, label) ->
                    val on = isOn(key)
                    Text(
                        text = label,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = if (on) Navy else Color.White.copy(alpha = 0.8f),
                        textAlign = TextAlign.Center,
                        maxLines = 1,
                        modifier = Modifier
                            .weight(1f)
                            .clip(CircleShape)
                            .background(if (on) BrandOrange else Color.White.copy(alpha = 0.07f))
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                            ) { onTap(key) }
                            .padding(horizontal = 14.dp, vertical = 9.dp),
                    )
                }
                if (row.size == 1) Box(modifier = Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun ToggleRow(
    title: String,
    detail: String?,
    checked: Boolean,
    onChange: (Boolean) -> Unit,
    showDivider: Boolean,
) {
    Column {
        Row(
            modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(modifier = Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
                Text(title, fontSize = 14.sp, color = Color.White)
                if (detail != null) {
                    Text(
                        text = " · $detail",
                        fontSize = 12.sp,
                        color = Color.White.copy(alpha = 0.4f),
                    )
                }
            }
            Switch(
                checked = checked,
                onCheckedChange = onChange,
                colors = SwitchDefaults.colors(
                    checkedThumbColor = Color.White,
                    checkedTrackColor = BrandOrange,
                ),
            )
        }
        if (showDivider) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(1.dp)
                    .background(Color.White.copy(alpha = 0.07f))
            )
        }
    }
}

package com.rork.guidestreamtvandroid.ui.components

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
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.guidestreamtvandroid.data.models.StreamingCatalog
import com.rork.guidestreamtvandroid.data.models.StreamingService
import com.rork.guidestreamtvandroid.data.models.selectionAccent
import com.rork.guidestreamtvandroid.data.models.selectionGlyphColor
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.OutlineVariant
import com.rork.guidestreamtvandroid.ui.theme.SheetLevel
import com.rork.guidestreamtvandroid.ui.theme.SheetSurfaceBase
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.sheetTopInset

/**
 * Shared "My services" editor sheet used by both the Home and Sports top-bar
 * services pills. Hybrid layout: "Most popular" tile grid + "All services · A–Z"
 * toggle-row list, both filtered by the search field.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ServicesBottomSheet(
    selected: Set<String>,
    onToggle: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var serviceQuery by remember { mutableStateOf("") }
    val filteredPopular = remember(serviceQuery) {
        if (serviceQuery.isBlank()) StreamingCatalog.popular
        else StreamingCatalog.popular.filter { it.name.contains(serviceQuery, ignoreCase = true) }
    }
    val filteredAll = remember(serviceQuery) {
        if (serviceQuery.isBlank()) StreamingCatalog.alphabetical
        else StreamingCatalog.alphabetical.filter { it.name.contains(serviceQuery, ignoreCase = true) }
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
                .fillMaxHeight(0.92f),
        ) {
            GsSheetHeader(
                title = "My services",
                subtitle = "${selected.size} selected · tap to add or remove",
            )
            Spacer(Modifier.height(6.dp))
            ServiceSearchField(
                query = serviceQuery,
                onQueryChange = { serviceQuery = it },
                modifier = Modifier.padding(horizontal = 12.dp),
            )
            Spacer(Modifier.height(12.dp))

            if (filteredPopular.isEmpty() && filteredAll.isEmpty()) {
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp)
                        .navigationBarsPadding(),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("No services match", fontSize = 14.sp, color = TextSecondary)
                }
            } else {
                LazyVerticalGrid(
                    columns = GridCells.Fixed(3),
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp)
                        .navigationBarsPadding(),
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                    verticalArrangement = Arrangement.spacedBy(0.dp),
                ) {
                    // Most popular section
                    if (filteredPopular.isNotEmpty()) {
                        item(span = { GridItemSpan(maxLineSpan) }) {
                            Text(
                                text = "Most popular",
                                fontSize = 13.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = TextSecondary,
                                modifier = Modifier.padding(bottom = 12.dp),
                            )
                        }
                        items(filteredPopular, key = { "popular_${it.id}" }) { svc ->
                            ServiceEditorTile(
                                service = svc,
                                isSelected = svc.id in selected,
                                onTap = { onToggle(svc.id) },
                            )
                        }
                        item(span = { GridItemSpan(maxLineSpan) }) {
                            Spacer(Modifier.height(16.dp))
                        }
                    }

                    // All services · A–Z section
                    if (filteredAll.isNotEmpty()) {
                        item(span = { GridItemSpan(maxLineSpan) }) {
                            Text(
                                text = "All services · A–Z",
                                fontSize = 13.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = TextSecondary,
                                modifier = Modifier.padding(bottom = 12.dp),
                            )
                        }
                        itemsIndexed(
                            filteredAll,
                            key = { _, svc -> "all_${svc.id}" },
                            span = { _, _ -> GridItemSpan(maxLineSpan) },
                        ) { idx, svc ->
                            val rowPosition = when {
                                filteredAll.size == 1 -> ServiceRowPosition.Only
                                idx == 0 -> ServiceRowPosition.First
                                idx == filteredAll.lastIndex -> ServiceRowPosition.Last
                                else -> ServiceRowPosition.Middle
                            }
                            ServiceToggleRowItem(
                                service = svc,
                                isSelected = svc.id in selected,
                                onTap = { onToggle(svc.id) },
                                position = rowPosition,
                            )
                        }
                    }
                }
            }
            Spacer(Modifier.height(12.dp))
        }
    }
}

/** Placement of an A–Z toggle row within its contiguous bordered group. */
private enum class ServiceRowPosition { First, Middle, Last, Only }

@Composable
private fun ServiceToggleRowItem(
    service: StreamingService,
    isSelected: Boolean,
    onTap: () -> Unit,
    position: ServiceRowPosition = ServiceRowPosition.Middle,
) {
    val roundedTop = position == ServiceRowPosition.First || position == ServiceRowPosition.Only
    val roundedBottom = position == ServiceRowPosition.Last || position == ServiceRowPosition.Only
    val shape = RoundedCornerShape(
        topStart = if (roundedTop) 14.dp else 0.dp,
        topEnd = if (roundedTop) 14.dp else 0.dp,
        bottomEnd = if (roundedBottom) 14.dp else 0.dp,
        bottomStart = if (roundedBottom) 14.dp else 0.dp,
    )
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Color.White.copy(alpha = 0.04f))
            .drawBehind {
                // Contiguous group chrome matching the onboarding A–Z list:
                // side hairlines on every row, cap hairlines + 14dp corners
                // only on the first/last row, and a soft divider between rows
                // instead of a hard border edge.
                val stroke = 1.dp.toPx()
                val radius = 14.dp.toPx()
                val outline = Color.White.copy(alpha = 0.08f)
                val topInset = if (roundedTop) radius else 0f
                val bottomInset = if (roundedBottom) radius else 0f
                val arcRadius = radius - stroke / 2f
                drawLine(
                    outline,
                    Offset(stroke / 2f, topInset),
                    Offset(stroke / 2f, size.height - bottomInset),
                    stroke,
                )
                drawLine(
                    outline,
                    Offset(size.width - stroke / 2f, topInset),
                    Offset(size.width - stroke / 2f, size.height - bottomInset),
                    stroke,
                )
                if (roundedTop) {
                    drawLine(outline, Offset(radius, stroke / 2f), Offset(size.width - radius, stroke / 2f), stroke)
                    drawArc(outline, 180f, 90f, false, Offset(stroke / 2f, stroke / 2f), Size(arcRadius * 2, arcRadius * 2), style = Stroke(stroke))
                    drawArc(outline, 270f, 90f, false, Offset(size.width - radius - arcRadius, stroke / 2f), Size(arcRadius * 2, arcRadius * 2), style = Stroke(stroke))
                }
                if (roundedBottom) {
                    drawLine(outline, Offset(radius, size.height - stroke / 2f), Offset(size.width - radius, size.height - stroke / 2f), stroke)
                    drawArc(outline, 90f, 90f, false, Offset(stroke / 2f, size.height - radius - arcRadius), Size(arcRadius * 2, arcRadius * 2), style = Stroke(stroke))
                    drawArc(outline, 0f, 90f, false, Offset(size.width - radius - arcRadius, size.height - radius - arcRadius), Size(arcRadius * 2, arcRadius * 2), style = Stroke(stroke))
                } else {
                    drawRect(
                        Color.White.copy(alpha = 0.06f),
                        topLeft = Offset(0f, size.height - stroke),
                        size = Size(size.width, stroke),
                    )
                }
            }
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onTap() }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ServiceMiniIcon(service = service, size = 36.dp)
        Spacer(Modifier.width(12.dp))
        Text(
            text = service.name,
            fontSize = 15.sp,
            color = Color.White,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        VisualSwitch(checked = isSelected)
    }
}

@Composable
private fun ServiceMiniIcon(service: StreamingService, size: Dp) {
    Box(
        modifier = Modifier
            .size(size)
            .clip(RoundedCornerShape(10.dp))
            .background(service.bg),
        contentAlignment = Alignment.Center,
    ) {
        val display = service.display
        val textSize = (size.value * 0.3f).sp
        when (display) {
            is StreamingService.Display.Text -> {
                Text(
                    text = display.text,
                    fontSize = textSize,
                    fontWeight = display.weight,
                    color = display.color,
                    textAlign = TextAlign.Center,
                    maxLines = 2,
                )
            }
            is StreamingService.Display.SymbolText -> {
                Text(
                    text = display.text,
                    fontSize = textSize,
                    fontWeight = FontWeight.Black,
                    color = display.color,
                )
            }
            is StreamingService.Display.Star -> {
                Text("\u2605", fontSize = (size.value * 0.5f).sp, color = display.color)
            }
        }
    }
}

@Composable
private fun VisualSwitch(checked: Boolean) {
    Box(
        modifier = Modifier
            .size(width = 44.dp, height = 26.dp)
            .clip(RoundedCornerShape(50.dp))
            .background(if (checked) BrandOrange else Color.White.copy(alpha = 0.15f)),
        contentAlignment = if (checked) Alignment.CenterEnd else Alignment.CenterStart,
    ) {
        Box(
            modifier = Modifier
                .padding(2.dp)
                .size(22.dp)
                .clip(CircleShape)
                .background(Color.White),
        )
    }
}

@Composable
private fun ServiceEditorTile(
    service: StreamingService,
    isSelected: Boolean,
    onTap: () -> Unit,
) {
    val accent = service.selectionAccent
    val borderColor = if (isSelected) accent else OutlineVariant
    val borderWidth = if (isSelected) 3.dp else 1.dp
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(1f),
        ) {
            val tileShape = RoundedCornerShape(18.dp)
            val shadowModifier = if (isSelected) {
                Modifier.shadow(
                    elevation = 12.dp,
                    shape = tileShape,
                    ambientColor = accent.copy(alpha = 0.55f),
                    spotColor = accent.copy(alpha = 0.55f),
                )
            } else {
                Modifier
            }
            Box(
                modifier = Modifier
                    .matchParentSize()
                    .then(shadowModifier)
                    .clip(tileShape)
                    .background(service.bg)
                    .border(borderWidth, borderColor, tileShape)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onTap() },
                contentAlignment = Alignment.Center,
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
                    maxLines = 2,
                )
            }
            if (isSelected) {
                Box(
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .offset(x = 6.dp, y = (-6).dp)
                        .size(22.dp)
                        .clip(CircleShape)
                        .background(accent),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.Filled.Check,
                        contentDescription = "Selected",
                        tint = service.selectionGlyphColor,
                        modifier = Modifier.size(13.dp),
                    )
                }
            }
        }
        Spacer(Modifier.height(8.dp))
        Text(
            text = service.name,
            fontSize = 12.sp,
            fontWeight = FontWeight.Medium,
            color = TextSecondary,
            maxLines = 1,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun ServiceSearchField(
    query: String,
    onQueryChange: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var isFocused by remember { mutableStateOf(false) }
    BasicTextField(
        value = query,
        onValueChange = onQueryChange,
        singleLine = true,
        textStyle = TextStyle(color = Color.White, fontSize = 15.sp),
        cursorBrush = SolidColor(BrandOrange),
        modifier = modifier
            .fillMaxWidth()
            .height(44.dp)
            .clip(RoundedCornerShape(50.dp))
            .background(Color.White.copy(alpha = 0.05f))
            .border(
                1.dp,
                if (isFocused) BrandOrange else Color.White.copy(alpha = 0.10f),
                RoundedCornerShape(50.dp),
            )
            .onFocusChanged { isFocused = it.isFocused },
        decorationBox = { innerTextField ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(44.dp)
                    .padding(horizontal = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    imageVector = Icons.Filled.Search,
                    contentDescription = null,
                    tint = TextSecondary,
                    modifier = Modifier.size(16.dp),
                )
                Spacer(Modifier.width(8.dp))
                Box(modifier = Modifier.weight(1f)) {
                    if (query.isEmpty()) {
                        Text(
                            text = "Search all services",
                            fontSize = 15.sp,
                            color = TextSecondary,
                        )
                    }
                    innerTextField()
                }
            }
        },
    )
}

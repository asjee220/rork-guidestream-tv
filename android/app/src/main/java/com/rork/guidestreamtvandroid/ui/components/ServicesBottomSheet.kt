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
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
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
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.guidestreamtvandroid.data.models.StreamingCatalog
import com.rork.guidestreamtvandroid.data.models.StreamingService
import com.rork.guidestreamtvandroid.data.models.selectionAccent
import com.rork.guidestreamtvandroid.data.models.selectionGlyphColor
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.OutlineVariant
import com.rork.guidestreamtvandroid.ui.theme.SurfaceDark
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.sheetTopInset

/**
 * Shared "My services" editor sheet used by both the Home and Sports top-bar
 * services pills. Header, search field, and the 3-column tile grid with the
 * selection accent border/badge/glow. Selection changes flow straight through
 * [onToggle] so each caller keeps its existing persistence path
 * (AuthViewModel.setSelectedServices) and ordering untouched.
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
    val filteredServices = remember(serviceQuery) {
        if (serviceQuery.isBlank()) StreamingCatalog.all
        else StreamingCatalog.all.filter { it.name.contains(serviceQuery, ignoreCase = true) }
    }
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = SurfaceDark,
        dragHandle = { GsSheetDragHandle() },
        contentWindowInsets = { sheetTopInset() },
    ) {
        Column {
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
            if (filteredServices.isEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(420.dp)
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
                        .fillMaxWidth()
                        .height(420.dp)
                        .padding(horizontal = 12.dp)
                        .navigationBarsPadding(),
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                    verticalArrangement = Arrangement.spacedBy(22.dp),
                ) {
                    items(filteredServices, key = { it.id }) { svc ->
                        ServiceEditorTile(
                            service = svc,
                            isSelected = svc.id in selected,
                            onTap = { onToggle(svc.id) },
                        )
                    }
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
    val accent = service.selectionAccent
    val borderColor = if (isSelected) accent else OutlineVariant
    val borderWidth = if (isSelected) 3.dp else 1.dp
    // Outer column is deliberately never clipped so the selection badge can
    // overhang the tile's top-right corner without being cut off.
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(1f),
        ) {
            val tileShape = RoundedCornerShape(18.dp)
            val shadowModifier = if (isSelected) {
                // Glow is decorative only (colored shadows need API 28); the
                // 3.dp accent border + badge carry selection on older devices.
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
                            text = "Search services",
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

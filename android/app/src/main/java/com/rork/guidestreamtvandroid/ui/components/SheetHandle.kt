package com.rork.guidestreamtvandroid.ui.components

import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.rork.guidestreamtvandroid.ui.theme.SheetLevel

/**
 * Shared drag handle for all Material3 [ModalBottomSheet] call sites.
 * Mirrors iOS `sheetSurface()` handle: a 36×4 white-45% capsule
 * with 12dp vertical padding, followed by a 1.5dp white-28% top hairline.
 * High-contrast variants (60% handle, 40% hairline) activate automatically
 * when the system high-contrast text setting is enabled.
 */
@Composable
fun GsSheetDragHandle(
    level: SheetLevel = SheetLevel.Base,
) {
    val context = LocalContext.current
    val isHighContrast = remember {
        Settings.Secure.getInt(
            context.contentResolver,
            "high_text_contrast_enabled",
            0,
        ) == 1
    }
    val handleAlpha = if (isHighContrast) 0.60f else 0.45f
    val hairlineAlpha = if (isHighContrast) 0.40f else 0.28f

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            modifier = Modifier
                .padding(top = 12.dp, bottom = 12.dp)
                .width(36.dp)
                .height(4.dp)
                .clip(RoundedCornerShape(2.dp))
                .background(Color.White.copy(alpha = handleAlpha)),
        )
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(1.5.dp)
                .background(Color.White.copy(alpha = hairlineAlpha)),
        )
    }
}

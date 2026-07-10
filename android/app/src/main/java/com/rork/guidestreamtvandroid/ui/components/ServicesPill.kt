package com.rork.guidestreamtvandroid.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.guidestreamtvandroid.data.models.StreamingCatalog
import com.rork.guidestreamtvandroid.data.models.StreamingService
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.Navy

/**
 * Orange-outlined pill that sits to the right of the GuideStream TV wordmark
 * in the top bar on Home. Shows the user's first three selected services as
 * overlapping mini-icons with a small counter badge. Tapping opens the
 * services editor sheet. Mirrors iOS ServicesPill.swift.
 */
@Composable
fun ServicesPill(
    serviceIds: List<String>,
    onTap: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val topServices = serviceIds.mapNotNull { StreamingCatalog.service(it) }.take(3)
    val iconDiameter = 22.dp
    val stride = 13.dp

    Box(modifier = modifier) {
        Row(
            modifier = Modifier
                .clip(CircleShape)
                .background(BrandOrange.copy(alpha = 0.10f))
                .border(1.4.dp, BrandOrange, CircleShape)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                ) { onTap() }
                .padding(start = 6.dp, end = 10.dp, top = 5.dp, bottom = 5.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            // Overlapping stacked mini-icons
            val stackWidth = stride * (maxOf(topServices.size, 1) - 1) + iconDiameter
            Box(
                modifier = Modifier.width(stackWidth),
                contentAlignment = Alignment.CenterStart,
            ) {
                topServices.forEachIndexed { index, service ->
                    ServiceMiniIcon(
                        service = service,
                        size = iconDiameter,
                        modifier = Modifier.offset(x = stride * index),
                    )
                }
            }
            Icon(
                imageVector = Icons.Filled.KeyboardArrowDown,
                contentDescription = null,
                tint = BrandOrange.copy(alpha = 0.75f),
                modifier = Modifier.size(14.dp),
            )
        }

        // Counter badge, top-right
        Box(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .offset(x = 6.dp, y = (-7).dp)
                .clip(CircleShape)
                .background(BrandOrange)
                .border(1.5.dp, Navy, CircleShape)
                .padding(horizontal = 5.dp, vertical = 1.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = serviceIds.size.toString(),
                fontSize = 9.sp,
                fontWeight = FontWeight.Black,
                color = Color.White,
            )
        }
    }
}

@Composable
private fun ServiceMiniIcon(
    service: StreamingService,
    size: androidx.compose.ui.unit.Dp,
    modifier: Modifier = Modifier,
) {
    val fg = if (service.bg.luminance() > 0.5f) Color.Black else Color.White
    val initial = service.name.trim().firstOrNull()?.uppercase() ?: "?"
    Box(
        modifier = modifier
            .size(size)
            .clip(CircleShape)
            .background(service.bg)
            .border(1.5.dp, Navy, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = initial,
            fontSize = 11.sp,
            fontWeight = FontWeight.Black,
            color = fg,
            textAlign = TextAlign.Center,
        )
    }
}

package com.rork.guidestreamtvandroid.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import coil3.request.crossfade

/**
 * Remote image with fallback — mirrors iOS RemoteImage.swift.
 * Loads from URL via Coil 3, shows a branded placeholder while loading
 * or when the URL is null.
 */
@Composable
fun RemoteImage(
    url: String?,
    contentDescription: String? = null,
    modifier: Modifier = Modifier,
    cornerRadius: Int = 8,
    placeholderText: String? = null,
    placeholderFontSize: TextUnit = 11.sp,
) {
    val shape = remember(cornerRadius) { RoundedCornerShape(cornerRadius.dp) }
    Box(
        modifier = modifier
            .clip(shape)
            .background(Color(red = 0x12, green = 0x1B, blue = 0x2A)),
        contentAlignment = Alignment.Center,
    ) {
        if (url != null && url.isNotEmpty()) {
            AsyncImage(
                model = url,
                contentDescription = contentDescription,
                modifier = Modifier.fillMaxSize(),
                clipToBounds = true,
            )
        } else if (placeholderText != null) {
            Text(
                text = placeholderText,
                fontSize = placeholderFontSize,
                fontWeight = FontWeight.SemiBold,
                color = Color.White.copy(alpha = 0.3f),
                textAlign = TextAlign.Center,
            )
        }
    }
}

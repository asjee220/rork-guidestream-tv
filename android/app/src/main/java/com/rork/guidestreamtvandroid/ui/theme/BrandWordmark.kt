package com.rork.guidestreamtvandroid.ui.theme

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.BaselineShift
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

enum class WordmarkSize(val baseSize: Int, val tvSize: Int, val weight: FontWeight) {
    LARGE(36, 20, FontWeight.Black),
    NAV(20, 12, FontWeight.Black),
    SMALL(13, 8, FontWeight.Bold),
}

/**
 * "GuideStream TV" wordmark.
 * Guide (white) + Stream (orange) + TV (light-blue, superscript).
 * Mirrors iOS BrandWordmark.swift.
 */
@Composable
fun BrandWordmark(
    size: WordmarkSize = WordmarkSize.NAV,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.Bottom,
    ) {
        Text(
            text = buildAnnotatedString {
                withStyle(SpanStyle(color = TextPrimary)) { append("Guide") }
                withStyle(SpanStyle(color = BrandOrange)) { append("Stream") }
                withStyle(
                    SpanStyle(
                        color = LightBlue,
                        fontSize = size.tvSize.sp,
                        fontWeight = FontWeight.Bold,
                        baselineShift = BaselineShift(0.3f),
                    )
                ) { append("TV") }
            },
            fontSize = size.baseSize.sp,
            fontWeight = size.weight,
            modifier = Modifier.padding(start = 0.dp),
        )
    }
}

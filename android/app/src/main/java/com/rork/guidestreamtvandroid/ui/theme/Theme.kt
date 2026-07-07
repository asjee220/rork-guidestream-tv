package com.rork.guidestreamtvandroid.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val GuideStreamColorScheme = darkColorScheme(
    primary = BrandOrange,
    onPrimary = Color.White,
    secondary = BrandBlue,
    onSecondary = Color.White,
    tertiary = NewsGreen,
    onTertiary = Color.Black,
    background = Navy,
    onBackground = TextPrimary,
    surface = SurfaceDark,
    onSurface = TextPrimary,
    surfaceVariant = SurfaceElevated,
    onSurfaceVariant = TextSecondary,
    outline = Hairline,
    outlineVariant = GlassStroke,
)

@Composable
fun AppTheme(
    darkTheme: Boolean = true,
    content: @Composable () -> Unit
) {
    MaterialTheme(
        colorScheme = GuideStreamColorScheme,
        typography = AppTypography,
        content = content
    )
}

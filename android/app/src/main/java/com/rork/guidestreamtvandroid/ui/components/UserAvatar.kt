package com.rork.guidestreamtvandroid.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Flight
import androidx.compose.material.icons.filled.LocalMovies
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.NightsStay
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange

/**
 * What `users.avatar_url` can hold, and how this client reads it.
 *
 * The column is one text field carrying two different things, and the prefix
 * is what tells them apart:
 *
 *   "https://…/storage/v1/object/public/avatars/<uid>/<file>"  an upload
 *   "preset:popcorn"                                           a built-in
 *   null / empty                                               initials
 *
 * Presets exist because tvOS has no file picker and no photo library, so an
 * Apple TV viewer could otherwise never change their avatar. They are drawn
 * from an icon and a gradient rather than shipped as image assets, so the same
 * eight choices render on all three platforms without adding a binary to any
 * of them. The ids are the contract between platforms — change one here and it
 * must change in the iOS UserAvatar.swift and the tvOS copy in the same commit.
 */
data class AvatarPreset(
    val id: String,
    val icon: ImageVector,
    val colors: List<Color>,
) {
    /** The value written to `users.avatar_url` for this preset. */
    val storageValue: String get() = "preset:$id"

    companion object {
        val all: List<AvatarPreset> = listOf(
            AvatarPreset("popcorn", Icons.Filled.LocalMovies, listOf(Color(0xFFF5821F), Color(0xFFC2410C))),
            AvatarPreset("film", Icons.Filled.Movie, listOf(Color(0xFF6366F1), Color(0xFF3730A3))),
            AvatarPreset("tv", Icons.Filled.Tv, listOf(Color(0xFF0EA5E9), Color(0xFF0C4A6E))),
            AvatarPreset("star", Icons.Filled.Star, listOf(Color(0xFFFACC15), Color(0xFFA16207))),
            AvatarPreset("bolt", Icons.Filled.Bolt, listOf(Color(0xFFA855F7), Color(0xFF6B21A8))),
            AvatarPreset("heart", Icons.Filled.Favorite, listOf(Color(0xFFEC4899), Color(0xFF9D174D))),
            AvatarPreset("moon", Icons.Filled.NightsStay, listOf(Color(0xFF38BDF8), Color(0xFF1E3A8A))),
            AvatarPreset("rocket", Icons.Filled.Flight, listOf(Color(0xFF22C55E), Color(0xFF14532D))),
        )

        fun named(id: String): AvatarPreset? = all.firstOrNull { it.id == id }
    }
}

/** A parsed `users.avatar_url`. */
sealed interface ParsedAvatar {
    data class Uploaded(val url: String) : ParsedAvatar
    data class Preset(val preset: AvatarPreset) : ParsedAvatar
}

/**
 * Parses the stored column value. Anything unrecognised — empty, malformed, or
 * a preset id this build does not know — reads as null so an older client falls
 * back to initials rather than rendering a broken image.
 */
fun parseAvatarUrl(raw: String?): ParsedAvatar? {
    val value = raw?.trim().orEmpty()
    if (value.isEmpty()) return null
    if (value.startsWith("preset:")) {
        return AvatarPreset.named(value.removePrefix("preset:"))?.let { ParsedAvatar.Preset(it) }
    }
    if (!value.startsWith("http://") && !value.startsWith("https://")) return null
    return ParsedAvatar.Uploaded(value)
}

/**
 * The account avatar: an uploaded photo, a preset, or the initials monogram.
 *
 * One composable at every size — the profile header draws it at 88dp and the
 * home top bar at 30dp, which is what "a smaller version of the avatar in the
 * profile section" means literally rather than by approximation.
 */
@Composable
fun UserAvatar(
    initials: String,
    avatarUrl: String?,
    size: Dp,
    modifier: Modifier = Modifier,
) {
    val parsed = parseAvatarUrl(avatarUrl)
    Box(
        modifier = modifier
            .size(size)
            .clip(CircleShape)
            .then(
                if (parsed == null) {
                    Modifier.background(BrandOrange.copy(alpha = 0.2f))
                } else {
                    Modifier
                }
            )
            .border(2.dp, BrandOrange, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        when (parsed) {
            is ParsedAvatar.Uploaded -> RemoteImage(
                url = parsed.url,
                contentDescription = "Profile picture",
                modifier = Modifier.fillMaxSize(),
                cornerRadius = (size.value / 2).toInt(),
                placeholderText = initials,
                placeholderFontSize = (size.value * 0.36f).sp,
            )

            is ParsedAvatar.Preset -> Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Brush.linearGradient(parsed.preset.colors)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = parsed.preset.icon,
                    contentDescription = parsed.preset.id,
                    tint = Color.White,
                    modifier = Modifier.size(size * 0.5f),
                )
            }

            null -> Text(
                text = initials,
                fontSize = (size.value * 0.36f).sp,
                fontWeight = FontWeight.Black,
                color = BrandOrange,
            )
        }
    }
}

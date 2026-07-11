package com.rork.guidestreamtvandroid.ui.theme

import androidx.compose.ui.graphics.Color

// Brand color tokens — matched from iOS Theme.swift
val Navy = Color(red = 0x04, green = 0x09, blue = 0x0F)
val BrandOrange = Color(red = 0xF5, green = 0x82, blue = 0x1F)
val BrandBlue = Color(red = 0x1A, green = 0x6F, blue = 0xE8)
val NewsGreen = Color(red = 0x00, green = 0x9E, blue = 0x8A)
val LightBlue = Color(red = 0x5B, green = 0xB0, blue = 0xFF)

// Text tiers
val TextPrimary = Color.White
val TextSecondary = Color.White.copy(alpha = 0.55f)
val TextTertiary = Color.White.copy(alpha = 0.35f)

// Surfaces
val SurfaceDark = Color(red = 0x0B, green = 0x12, blue = 0x1C)
val SurfaceElevated = Color(red = 0x12, green = 0x1B, blue = 0x2A)
// Canonical Material 3 tonal tokens — opaque surface + hairline outline.
val SurfaceContainer = Color(0xFF142033)
val OutlineVariant = Color.White.copy(alpha = 0.13f)
// Legacy names kept as aliases so all existing call sites inherit the tonal treatment.
val GlassFill = SurfaceContainer
val GlassStroke = OutlineVariant
val Hairline = Color.White.copy(alpha = 0.08f)

// Platform brand colors
val NetflixRed = Color(red = 0xE5, green = 0x09, blue = 0x14)
val HboPurple = Color(red = 0x5A, green = 0x1F, blue = 0xCB)
val AppleTVBlack = Color(red = 0x10, green = 0x10, blue = 0x10)
val HuluGreen = Color(red = 0x1C, green = 0xE7, blue = 0x83)
val PrimeBlue = Color(red = 0x00, green = 0xA8, blue = 0xE1)
val DisneyBlue = Color(red = 0x11, green = 0x3C, blue = 0xCF)
val ParamountBlue = Color(red = 0x00, green = 0x64, blue = 0xFF)
val CrunchyrollOrange = Color(red = 0xF4, green = 0x7B, blue = 0x20)
val YouTubeRed = Color(red = 0xFF, green = 0x00, blue = 0x00)
val TwitchPurple = Color(red = 0x91, green = 0x46, blue = 0xFF)
val KickGreen = Color(red = 0x53, green = 0xFC, blue = 0x18)
val PodcastPurple = Color(red = 0x7C, green = 0x3A, blue = 0xED)
val TmdbPurple = Color(red = 0x6A, green = 0x3F, blue = 0xE0)

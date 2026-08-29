package com.rork.guidestreamtvandroid.ui.ads

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import com.google.android.gms.ads.AdListener
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.AdSize
import com.google.android.gms.ads.AdView
import com.google.android.gms.ads.LoadAdError
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.GlassFill
import com.rork.guidestreamtvandroid.ui.theme.GlassStroke
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary

/**
 * Native ad card — mirrors iOS NativeAdCardView.
 * Renders an AdMob banner ad inside a glass card with an "Ad" badge.
 * When [feedStyle] is true the card fills the inline chip its caller draws:
 * no surface of its own, a muted "Ad" attribution chip, and the banner
 * filling the remaining height. The default (false) path is unchanged so the
 * Reels carousel keeps its existing card.
 */
@Composable
fun NativeAdCard(
    modifier: Modifier = Modifier,
    compact: Boolean = false,
    feedStyle: Boolean = false,
    onAdLoaded: () -> Unit = {},
    onAdFailedToLoad: () -> Unit = {},
) {
    if (feedStyle) {
        Column(
            modifier = modifier
                .fillMaxSize()
                // End inset clears the caller's close control.
                .padding(start = 12.dp, end = 44.dp, top = 10.dp, bottom = 10.dp),
        ) {
            // Attribution — the same muted chip the affiliate presentation uses.
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(3.dp))
                    .background(Color.White.copy(alpha = 0.12f))
                    .padding(horizontal = 5.dp, vertical = 1.dp),
            ) {
                Text(
                    text = "Ad",
                    fontSize = 10.sp,
                    // Pinned so the app's 24.sp body line height does not eat
                    // the 50dp the banner needs below it.
                    lineHeight = 12.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color.White.copy(alpha = 0.62f),
                )
            }
            Spacer(Modifier.height(6.dp))
            // Banner ad — same ad unit resolution as the standard card.
            BannerAd(
                adUnitId = AdUnitResolver.native(LocalContext.current),
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f),
                onAdLoaded = onAdLoaded,
                onAdFailedToLoad = onAdFailedToLoad,
            )
        }
    } else {
        Column(
            modifier = modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(14.dp))
                .background(GlassFill)
                .border(1.dp, GlassStroke, RoundedCornerShape(14.dp))
                .padding(if (compact) 8.dp else 12.dp),
        ) {
            // "Ad" badge
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(4.dp))
                        .background(BrandOrange.copy(alpha = 0.2f))
                        .padding(horizontal = 6.dp, vertical = 2.dp),
                ) {
                    Text(
                        text = "Ad",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        color = BrandOrange,
                    )
                }
                Spacer(Modifier.weight(1f))
            }
            Spacer(Modifier.height(8.dp))
            // Banner ad
            BannerAd(
                adUnitId = AdUnitResolver.native(LocalContext.current),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(if (compact) 50.dp else 100.dp),
                onAdLoaded = onAdLoaded,
                onAdFailedToLoad = onAdFailedToLoad,
            )
        }
    }
}

/**
 * Compose wrapper for an AdMob banner AdView.
 *
 * Waits for [AdManager.sdkInitialized] before creating the AdView: requesting
 * an ad before MobileAds.initialize completes fails, and because the failure
 * arrives asynchronously it used to mark the slot as "no fill" and swap in the
 * fallback permanently. Every request is also issued exactly once — the old
 * update block re-requested on each recomposition, which threw away in-flight
 * loads and could spam the ad unit.
 */
@Composable
fun BannerAd(
    adUnitId: String,
    modifier: Modifier = Modifier,
    onAdLoaded: () -> Unit = {},
    onAdFailedToLoad: () -> Unit = {},
) {
    val adManager = AdManager.get()
    val sdkReady by adManager.sdkInitialized.collectAsState()

    // Nothing to show until the SDK is up; the slot stays collapsed rather
    // than reporting a spurious failure.
    if (!sdkReady) return

    AndroidView(
        modifier = modifier,
        factory = { context ->
            AdView(context).apply {
                setAdSize(AdSize.BANNER)
                this.adUnitId = adUnitId
                adListener = object : AdListener() {
                    override fun onAdLoaded() {
                        adManager.recordNativeLoaded()
                        onAdLoaded()
                    }

                    override fun onAdFailedToLoad(error: LoadAdError) {
                        adManager.recordNativeError(
                            "[${error.code}] ${error.message}",
                        )
                        onAdFailedToLoad()
                    }
                }
                adManager.recordNativeAttempt()
                loadAd(AdRequest.Builder().build())
            }
        },
    )
}


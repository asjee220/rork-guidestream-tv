package com.rork.guidestreamtvandroid.ui.ads

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.ui.viewinterop.AndroidView
import com.google.android.gms.ads.AdListener
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.AdSize
import com.google.android.gms.ads.AdView
import com.google.android.gms.ads.LoadAdError
import com.rork.guidestreamtvandroid.AppConfig
import com.rork.guidestreamtvandroid.ui.theme.BrandOrange
import com.rork.guidestreamtvandroid.ui.theme.GlassFill
import com.rork.guidestreamtvandroid.ui.theme.GlassStroke
import com.rork.guidestreamtvandroid.ui.theme.TextPrimary
import com.rork.guidestreamtvandroid.ui.theme.TextSecondary
import com.rork.guidestreamtvandroid.ui.theme.TextTertiary

/**
 * Native ad card — mirrors iOS NativeAdCardView.
 * Renders an AdMob banner ad inside a glass card with an "Ad" badge.
 */
@Composable
fun NativeAdCard(
    modifier: Modifier = Modifier,
    onAdLoaded: () -> Unit = {},
    onAdFailedToLoad: () -> Unit = {},
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(GlassFill)
            .border(1.dp, GlassStroke, RoundedCornerShape(14.dp))
            .padding(12.dp),
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
            adUnitId = AppConfig.ADMOB_NATIVE_AD_UNIT_ID,
            modifier = Modifier
                .fillMaxWidth()
                .height(100.dp),
            onAdLoaded = onAdLoaded,
            onAdFailedToLoad = onAdFailedToLoad,
        )
    }
}

/**
 * Compose wrapper for AdMob banner AdView.
 */
@Composable
fun BannerAd(
    adUnitId: String,
    modifier: Modifier = Modifier,
    onAdLoaded: () -> Unit = {},
    onAdFailedToLoad: () -> Unit = {},
) {
    var adLoaded by remember { mutableStateOf(false) }
    AndroidView(
        modifier = modifier,
        factory = { context ->
            AdView(context).apply {
                setAdSize(AdSize.BANNER)
                this.adUnitId = adUnitId
                adListener = object : AdListener() {
                    override fun onAdLoaded() {
                        adLoaded = true
                        onAdLoaded()
                    }

                    override fun onAdFailedToLoad(error: LoadAdError) {
                        onAdFailedToLoad()
                    }
                }
                loadAd(AdRequest.Builder().build())
            }
        },
        update = { adView ->
            if (!adLoaded) {
                adView.loadAd(AdRequest.Builder().build())
            }
        },
    )
}


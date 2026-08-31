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
import android.graphics.drawable.Drawable
import android.view.ViewGroup
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.core.graphics.drawable.toBitmap
import com.google.android.gms.ads.AdListener
import com.google.android.gms.ads.AdLoader
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdOptions
import com.google.android.gms.ads.nativead.NativeAdView
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
        // GUI-85: a real native ad, laid out by us. This used to be an "Ad"
        // pill above an AdView banner, which is why the chip carried no
        // headline and no advertiser -- a banner has no separable assets, so
        // there was nothing to lay out and the 50dp creative could never fill
        // the caller's 96dp box.
        NativeAdChip(
            adUnitId = AdUnitResolver.native(LocalContext.current),
            modifier = modifier,
            onAdLoaded = onAdLoaded,
            onAdFailedToLoad = onAdFailedToLoad,
        )
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
            // Still an AdView, so it resolves the BANNER slot. Before GUI-85
            // both paths asked for the "native" slot, which is why that slot
            // had to hold a Banner unit.
            BannerAd(
                adUnitId = AdUnitResolver.banner(LocalContext.current),
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


// ── Native chip (GUI-85) ─────────────────────────────────────────────────────

/**
 * The 96dp feed chip, rendered from a real AdMob **native advanced** ad.
 *
 * Why this exists: the chip used to draw an "Ad" pill above an `AdView` at
 * `AdSize.BANNER`. A banner ad is a single opaque creative with no separable
 * assets, so there was no headline and no advertiser to lay out, and a 50dp
 * banner could not fill the caller's 96dp box. iOS has always loaded a native
 * ad and laid out its assets itself, which is the whole reason the two
 * platforms looked nothing alike.
 *
 * Layout is deliberately identical to `RakutenAffiliatePresentation`'s feed
 * branch — same 96dp flush square, same 14sp/17sp three-line headline, same
 * 11sp advertiser line, same muted attribution chip — so a slot looks the same
 * whether AdMob fills it or the affiliate fallback does.
 *
 * Mechanics worth knowing before editing:
 *  * AdMob requires the ad's assets to be displayed inside a [NativeAdView]
 *    with the asset views registered on it. The whole chip is drawn by one
 *    [ComposeView] registered as `headlineView`, which both satisfies that and
 *    makes the entire card the click target — matching iOS, where the card is
 *    one tap target with no CTA pill.
 *  * `setNativeAd` makes the NativeAdView add its own AdChoices overlay, so
 *    the policy requirement is met without drawing one.
 *  * `bodyView` and `callToActionView` are deliberately NOT registered. The
 *    chip draws neither, and registering an asset view that is never shown is
 *    a policy risk (see claude/ad-chip-v2-aug2026.md).
 */
@Composable
private fun NativeAdChip(
    adUnitId: String,
    modifier: Modifier = Modifier,
    onAdLoaded: () -> Unit = {},
    onAdFailedToLoad: () -> Unit = {},
) {
    val context = LocalContext.current
    val adManager = AdManager.get()
    val sdkReady by adManager.sdkInitialized.collectAsState()
    var nativeAd by remember { mutableStateOf<NativeAd?>(null) }

    // Keyed on sdkReady as well as the unit: requesting before
    // MobileAds.initialize completes fails asynchronously, and that failure
    // used to mark the slot as no-fill permanently.
    DisposableEffect(adUnitId, sdkReady) {
        if (sdkReady) {
            adManager.recordNativeAttempt()
            AdLoader.Builder(context, adUnitId)
                .forNativeAd { ad ->
                    nativeAd?.destroy()
                    nativeAd = ad
                    adManager.recordNativeLoaded()
                    onAdLoaded()
                }
                .withAdListener(object : AdListener() {
                    override fun onAdFailedToLoad(error: LoadAdError) {
                        adManager.recordNativeError("[${error.code}] ${error.message}")
                        onAdFailedToLoad()
                    }
                })
                .withNativeAdOptions(
                    NativeAdOptions.Builder()
                        // Bottom-trailing, where the reference layout puts its
                        // "···" and where iOS puts AdChoices.
                        .setAdChoicesPlacement(NativeAdOptions.ADCHOICES_BOTTOM_RIGHT)
                        .build(),
                )
                .build()
                .loadAd(AdRequest.Builder().build())
        }
        onDispose {
            // A NativeAd holds native resources; leaking one leaks the ad.
            nativeAd?.destroy()
            nativeAd = null
        }
    }

    val ad = nativeAd ?: return

    AndroidView(
        modifier = modifier.fillMaxSize(),
        factory = { ctx ->
            NativeAdView(ctx).apply {
                val content = ComposeView(ctx).apply {
                    setViewCompositionStrategy(
                        ViewCompositionStrategy.DisposeOnViewTreeLifecycleDestroyed,
                    )
                }
                addView(
                    content,
                    ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT,
                    ),
                )
                headlineView = content
            }
        },
        update = { view ->
            (view.getChildAt(0) as? ComposeView)?.setContent { NativeChipContent(ad) }
            // Must come after the asset views are registered.
            view.setNativeAd(ad)
        },
    )
}

/** Drawable -> ImageBitmap, guarding the zero-intrinsic-size case. */
@Composable
private fun rememberDrawableBitmap(drawable: Drawable?) = remember(drawable) {
    val w = drawable?.intrinsicWidth ?: 0
    val h = drawable?.intrinsicHeight ?: 0
    if (drawable == null || w <= 0 || h <= 0) null
    else runCatching { drawable.toBitmap().asImageBitmap() }.getOrNull()
}

@Composable
private fun NativeChipContent(ad: NativeAd) {
    // `icon` is the square asset; `images` is the landscape creative. The chip
    // is a 96dp square, so the icon is preferred and the first image is the
    // fallback for fills that omit it.
    val creative = rememberDrawableBitmap(
        ad.icon?.drawable ?: ad.images.firstOrNull()?.drawable,
    )
    val headline = ad.headline?.takeIf { it.isNotBlank() } ?: "Sponsored"
    // Native fills often omit `advertiser`; `store` is the usual stand-in.
    val advertiser = ad.advertiser?.takeIf { it.isNotBlank() }
        ?: ad.store?.takeIf { it.isNotBlank() }

    Row(
        modifier = Modifier.fillMaxSize(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Creative — flush to the start edge, full height, square corners. The
        // caller's clip rounds the two corners that meet the card's edge.
        Box(
            modifier = Modifier
                .fillMaxHeight()
                .width(96.dp)
                .background(Color.White.copy(alpha = 0.06f)),
            contentAlignment = Alignment.Center,
        ) {
            if (creative != null) {
                Image(
                    bitmap = creative,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
            } else {
                Text(
                    text = headline.take(3).uppercase(),
                    fontSize = 19.sp,
                    lineHeight = 23.sp,
                    fontWeight = FontWeight.Black,
                    color = Color.White,
                )
            }
        }
        Spacer(Modifier.width(12.dp))
        Column(
            modifier = Modifier
                .weight(1f)
                // End inset clears the caller's close control so a three-line
                // headline never runs underneath it.
                .padding(end = 44.dp, top = 12.dp, bottom = 12.dp),
        ) {
            Text(
                text = headline,
                fontSize = 14.sp,
                // Every Text pins its own lineHeight: AppTypography.bodyLarge
                // carries 24.sp, and inheriting it overflows the 96dp box.
                lineHeight = 17.sp,
                fontWeight = FontWeight.SemiBold,
                color = TextPrimary,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.height(5.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (advertiser != null) {
                    Text(
                        text = advertiser,
                        fontSize = 11.sp,
                        lineHeight = 14.sp,
                        color = Color.White.copy(alpha = 0.52f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false),
                    )
                    Spacer(Modifier.width(5.dp))
                }
                // Required attribution, right after the advertiser name.
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(3.dp))
                        .background(Color.White.copy(alpha = 0.12f))
                        .padding(horizontal = 5.dp, vertical = 1.dp),
                ) {
                    Text(
                        text = "Ad",
                        fontSize = 10.sp,
                        lineHeight = 12.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color.White.copy(alpha = 0.62f),
                    )
                }
            }
        }
    }
}

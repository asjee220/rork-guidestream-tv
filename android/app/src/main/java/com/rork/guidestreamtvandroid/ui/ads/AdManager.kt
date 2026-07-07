package com.rork.guidestreamtvandroid.ui.ads

import android.app.Activity
import android.content.Context
import com.google.android.gms.ads.AdError
import com.google.android.gms.ads.AdListener
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.FullScreenContentCallback
import com.google.android.gms.ads.LoadAdError
import com.google.android.gms.ads.MobileAds
import com.google.android.gms.ads.interstitial.InterstitialAd
import com.google.android.gms.ads.interstitial.InterstitialAdLoadCallback
import com.rork.guidestreamtvandroid.AppConfig
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * AdMob manager — mirrors iOS AdManager.swift.
 * Initializes the Mobile Ads SDK, loads native ads, and manages
 * interstitial ad cadence (every 5 swipes in Reels).
 */
class AdManager private constructor() {

    private var interstitialAd: InterstitialAd? = null

    private val _interstitialReady = MutableStateFlow(false)
    val interstitialReady: StateFlow<Boolean> = _interstitialReady.asStateFlow()

    private val _interstitialSwipeCount = MutableStateFlow(0)
    val interstitialSwipeCount: StateFlow<Int> = _interstitialSwipeCount.asStateFlow()

    companion object {
        private const val INTERSTITIAL_INTERVAL = 5

        @Volatile private var instance: AdManager? = null
        fun get(): AdManager = instance ?: synchronized(this) {
            instance ?: AdManager().also { instance = it }
        }
    }

    /** Initialize the Mobile Ads SDK. Call from Application.onCreate(). */
    fun initialize(context: Context) {
        MobileAds.initialize(context) { }
    }

    /** Preload an interstitial ad. Call after init. */
    fun preloadInterstitial(context: Context) {
        val adRequest = AdRequest.Builder().build()
        InterstitialAd.load(
            context,
            AppConfig.ADMOB_INTERSTITIAL_AD_UNIT_ID,
            adRequest,
            object : InterstitialAdLoadCallback() {
                override fun onAdLoaded(ad: InterstitialAd) {
                    interstitialAd = ad
                    _interstitialReady.value = true
                    ad.fullScreenContentCallback = object : FullScreenContentCallback() {
                        override fun onAdDismissedFullScreenContent() {
                            interstitialAd = null
                            _interstitialReady.value = false
                            preloadInterstitial(context)
                        }
                        override fun onAdFailedToShowFullScreenContent(p0: AdError) {
                            interstitialAd = null
                            _interstitialReady.value = false
                            preloadInterstitial(context)
                        }
                    }
                }
                override fun onAdFailedToLoad(error: LoadAdError) {
                    interstitialAd = null
                    _interstitialReady.value = false
                }
            },
        )
    }

    /** Show interstitial if ready and the cadence interval is met. */
    fun maybeShowInterstitial(activity: Activity) {
        _interstitialSwipeCount.value += 1
        if (_interstitialSwipeCount.value % INTERSTITIAL_INTERVAL == 0 && interstitialAd != null) {
            interstitialAd?.show(activity)
        }
    }

    /** Build a standard AdRequest. */
    fun buildAdRequest(): AdRequest = AdRequest.Builder().build()
}

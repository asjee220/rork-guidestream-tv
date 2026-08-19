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
import com.google.android.ump.ConsentInformation
import com.google.android.ump.ConsentRequestParameters
import com.google.android.ump.UserMessagingPlatform
import com.rork.guidestreamtvandroid.AppConfig
import com.rork.guidestreamtvandroid.data.remote.RemoteConfigService
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

    // MARK: UMP consent gating

    private var consentInformation: ConsentInformation? = null
    private var consentGathered = false
    private var adsInitialized = false

    private val _privacyOptionsRequired = MutableStateFlow(false)

    /** True when UMP requires a privacy options entry point (EEA/UK). */
    val privacyOptionsRequired: StateFlow<Boolean> = _privacyOptionsRequired.asStateFlow()

    /**
     * Requests UMP consent (EEA/UK users see the Google consent form), then
     * initializes + preloads the ad SDK only when consent allows ad requests.
     * Safe to call more than once — an already-satisfied form is never
     * re-presented — and a finishing activity skips the form and falls
     * straight through to the canRequestAds check. On any consent error the
     * same canRequestAds check still runs.
     */
    fun gatherConsentThenInitialize(activity: Activity) {
        val consentInfo = UserMessagingPlatform.getConsentInformation(activity)
        consentInformation = consentInfo
        refreshPrivacyOptionsRequirement(consentInfo)

        if (!consentGathered && !activity.isFinishing && !activity.isDestroyed) {
            consentGathered = true
            val parameters = ConsentRequestParameters.Builder()
                .setTagForUnderAgeOfConsent(false)
                .build()
            consentInfo.requestConsentInfoUpdate(
                activity,
                parameters,
                {
                    // Consent info updated — show the form if the GDPR message
                    // requires one, then re-check the privacy options status.
                    UserMessagingPlatform.loadAndShowConsentFormIfRequired(activity) { _ ->
                        refreshPrivacyOptionsRequirement(consentInfo)
                        maybeInitializeAndPreload(activity)
                    }
                },
                { _ ->
                    // Consent info failed — still honor the canRequestAds check.
                    maybeInitializeAndPreload(activity)
                },
            )
        } else {
            maybeInitializeAndPreload(activity)
        }
    }

    /** Shows the UMP privacy options form and refreshes the requirement flag on dismiss. */
    fun showPrivacyOptions(activity: Activity) {
        val consentInfo = consentInformation ?: return
        if (activity.isFinishing || activity.isDestroyed) return
        UserMessagingPlatform.showPrivacyOptionsForm(activity) { _ ->
            refreshPrivacyOptionsRequirement(consentInfo)
        }
    }

    private fun maybeInitializeAndPreload(context: Context) {
        val consentInfo = consentInformation ?: return
        if (adsInitialized || !consentInfo.canRequestAds()) return
        adsInitialized = true
        initialize(context)
        preloadInterstitial(context)
    }

    private fun refreshPrivacyOptionsRequirement(consentInfo: ConsentInformation) {
        _privacyOptionsRequired.value =
            consentInfo.privacyOptionsRequirementStatus ==
                ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED
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
            RemoteConfigService.adUnit("interstitial") ?: AppConfig.ADMOB_INTERSTITIAL_AD_UNIT_ID,
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

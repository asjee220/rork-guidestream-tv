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

    // MARK: Diagnostics

    private val _sdkInitialized = MutableStateFlow(false)

    /** True once MobileAds.initialize has completed. Gates all ad requests. */
    val sdkInitialized: StateFlow<Boolean> = _sdkInitialized.asStateFlow()

    private val _consentStatusText = MutableStateFlow("Not requested")
    private val _canRequestAds = MutableStateFlow(false)
    private val _lastNativeError = MutableStateFlow<String?>(null)
    private val _lastInterstitialError = MutableStateFlow<String?>(null)
    private val _nativeLoadAttempts = MutableStateFlow(0)
    private val _nativeAdsReceived = MutableStateFlow(0)

    /** Records that a banner/native request was issued. */
    fun recordNativeAttempt() {
        _nativeLoadAttempts.value += 1
    }

    /** Records a successful banner/native fill. */
    fun recordNativeLoaded() {
        _nativeAdsReceived.value += 1
        _lastNativeError.value = null
    }

    /** Records a banner/native load failure with its AdMob error text. */
    fun recordNativeError(message: String) {
        _lastNativeError.value = message
    }

    /**
     * Immutable snapshot of the whole ad stack, rendered by the Ad Diagnostics
     * screen so a Play testing build can explain why slots are empty.
     */
    data class Diagnostics(
        val sdkInitialized: Boolean,
        val consentStatus: String,
        val canRequestAds: Boolean,
        val privacyOptionsRequired: Boolean,
        val manifestAppId: String,
        val nativeAdUnitId: String,
        val interstitialAdUnitId: String,
        val remoteUnitRejected: String?,
        val nativeLoadAttempts: Int,
        val nativeAdsReceived: Int,
        val interstitialReady: Boolean,
        val lastNativeError: String?,
        val lastInterstitialError: String?,
    ) {
        /** Plain-English verdict naming the current blocker. */
        val summary: String
            get() = when {
                remoteUnitRejected != null ->
                    "Remote config supplied an ad unit from a different AdMob app. " +
                        "Falling back to the bundled unit. $remoteUnitRejected"
                !canRequestAds ->
                    "Consent does not permit ad requests yet, so the ad SDK has not started."
                !sdkInitialized ->
                    "Ad SDK has not finished initializing. Tap Retry."
                lastNativeError != null ->
                    "SDK is running but the last ad request failed: $lastNativeError"
                nativeAdsReceived == 0 && nativeLoadAttempts > 0 ->
                    "Requests are going out but AdMob returned no ads yet — normal for a new ad unit."
                nativeLoadAttempts == 0 ->
                    "SDK is running but no ad request has been made yet."
                else ->
                    "Ad stack is healthy — $nativeAdsReceived ad(s) filled this session."
            }

        /** Multi-line report for the Copy button. */
        val plainText: String
            get() = buildString {
                appendLine("Ad Diagnostics (Android)")
                appendLine("------------------------")
                appendLine("Summary: $summary")
                appendLine()
                appendLine("SDK initialized: $sdkInitialized")
                appendLine("Consent status: $consentStatus")
                appendLine("Can request ads: $canRequestAds")
                appendLine("Privacy options required: $privacyOptionsRequired")
                appendLine()
                appendLine("Manifest app id: $manifestAppId")
                appendLine("Native unit: $nativeAdUnitId")
                appendLine("Interstitial unit: $interstitialAdUnitId")
                appendLine("Remote unit rejected: ${remoteUnitRejected ?: "no"}")
                appendLine()
                appendLine("Load attempts: $nativeLoadAttempts")
                appendLine("Ads received: $nativeAdsReceived")
                appendLine("Interstitial ready: $interstitialReady")
                appendLine("Last native error: ${lastNativeError ?: "none"}")
                appendLine("Last interstitial error: ${lastInterstitialError ?: "none"}")
            }
    }

    /** Builds a live diagnostics snapshot. */
    fun diagnostics(context: Context): Diagnostics = Diagnostics(
        sdkInitialized = _sdkInitialized.value,
        consentStatus = _consentStatusText.value,
        canRequestAds = _canRequestAds.value,
        privacyOptionsRequired = _privacyOptionsRequired.value,
        manifestAppId = AdUnitResolver.appId(context) ?: "(missing)",
        nativeAdUnitId = AdUnitResolver.native(context),
        interstitialAdUnitId = AdUnitResolver.interstitial(context),
        remoteUnitRejected = AdUnitResolver.lastRejectionReason,
        nativeLoadAttempts = _nativeLoadAttempts.value,
        nativeAdsReceived = _nativeAdsReceived.value,
        interstitialReady = _interstitialReady.value,
        lastNativeError = _lastNativeError.value,
        lastInterstitialError = _lastInterstitialError.value,
    )

    /**
     * Clears cached errors and re-runs the consent/init chain, or re-requests
     * ads when the SDK is already up. Backs the "Retry" diagnostics button.
     */
    fun retryFromDiagnostics(activity: Activity) {
        _lastNativeError.value = null
        _lastInterstitialError.value = null
        if (_sdkInitialized.value) {
            preloadInterstitial(activity)
        } else {
            gatherConsentThenInitialize(activity)
        }
    }

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
        _consentStatusText.value = describeConsent(consentInfo)
        _canRequestAds.value = consentInfo.canRequestAds()
        // Not latching `adsInitialized` on the consent-denied path means a
        // later retry can still bring ads up, instead of the process staying
        // permanently ad-free after one transient consent failure.
        if (adsInitialized || !consentInfo.canRequestAds()) return
        adsInitialized = true
        initialize(context)
        preloadInterstitial(context)
    }

    private fun describeConsent(consentInfo: ConsentInformation): String =
        when (consentInfo.consentStatus) {
            ConsentInformation.ConsentStatus.NOT_REQUIRED -> "Not required"
            ConsentInformation.ConsentStatus.REQUIRED -> "Required (form pending)"
            ConsentInformation.ConsentStatus.OBTAINED -> "Obtained"
            else -> "Unknown"
        }

    private fun refreshPrivacyOptionsRequirement(consentInfo: ConsentInformation) {
        _privacyOptionsRequired.value =
            consentInfo.privacyOptionsRequirementStatus ==
                ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED
    }

    /** Initialize the Mobile Ads SDK. Call from Application.onCreate(). */
    fun initialize(context: Context) {
        MobileAds.initialize(context) {
            _sdkInitialized.value = true
        }
    }

    /** Preload an interstitial ad. Call after init. */
    fun preloadInterstitial(context: Context) {
        val adRequest = AdRequest.Builder().build()
        InterstitialAd.load(
            context,
            AdUnitResolver.interstitial(context),
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
                    _lastInterstitialError.value = error.message
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

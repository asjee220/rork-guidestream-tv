package com.rork.guidestreamtvandroid.ui.reels

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.webkit.ConsoleMessage
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInteropFilter
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.rork.guidestreamtvandroid.BuildConfig

/**
 * Inline YouTube trailer player for Reels.
 *
 * The IFrame Player API validates the embedding page's real origin and
 * referrer against the `origin` playerVar. YouTube's newer enforcement
 * (error 153 — blocked/missing referrer) rejects embeds hosted on origins it
 * does not recognise, which includes `appassets.androidplatform.net`: the
 * page loads and the API comes up, but the video itself never plays.
 *
 * The document is therefore loaded with [PlayerBaseUrl] as its base URL so the
 * WebView reports a genuine third-party https origin and sends a matching
 * `Referer` on the embed request. `youtube.com` does NOT work as the base URL
 * either — an embed claiming to be referred by youtube itself is rejected with
 * error 152 — so the app's real domain is used and the page's `origin`
 * playerVar is kept identical to it.
 *
 * Config (video id / mute / autoplay) is injected into the static asset
 * (`assets/yt_player.html`) via placeholder replacement because a data-loaded
 * document has no query string. This is YouTube-ToS compliant and never uses
 * ExoPlayer/media3, which cannot play YouTube and would require ToS-violating
 * stream extraction.
 *
 * The WebView never consumes touch ([pointerInteropFilter] returns false),
 * mirroring the iOS `allowsHitTesting(false)` on the player layer so the
 * VerticalPager swipe and every overlay tap keep working.
 */
@OptIn(ExperimentalComposeUiApi::class)
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun YouTubeReelPlayer(
    videoId: String,
    isMuted: Boolean,
    isPlaying: Boolean,
    onPlayerError: (Int) -> Unit,
    onPlayerReady: () -> Unit,
    onEnded: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val currentOnPlayerError by rememberUpdatedState(onPlayerError)
    val currentOnPlayerReady by rememberUpdatedState(onPlayerReady)
    val currentOnEnded by rememberUpdatedState(onEnded)
    val mainHandler = remember { Handler(Looper.getMainLooper()) }

    // Remembered holder tracking the last values pushed into the WebView so the
    // update block only reloads when the videoId actually changes and only
    // evaluates mute/playback JS when those values actually change.
    val holder = remember { PlayerStateHolder() }

    val lifecycleOwner = LocalLifecycleOwner.current

    AndroidView(
        modifier = modifier.pointerInteropFilter { false },
        factory = { ctx ->
            if (BuildConfig.DEBUG) {
                WebView.setWebContentsDebuggingEnabled(true)
            }

            WebView(ctx).apply {
                @Suppress("DEPRECATION")
                settings.apply {
                    javaScriptEnabled = true
                    // Mandatory: without this Android blocks autoplay and the
                    // embed stays frozen on a black frame.
                    mediaPlaybackRequiresUserGesture = false
                    domStorageEnabled = true
                    // Android's default WebView UA carries the "; wv" token,
                    // which YouTube penalises. Strip it from the real default
                    // rather than fabricating a UA from scratch.
                    userAgentString = userAgentString.replace("; wv", "")
                    loadWithOverviewMode = true
                    useWideViewPort = true
                }
                // The embed is a third-party frame relative to the base URL;
                // with the default policy its cookies are dropped and playback
                // never starts, leaving a permanently black player.
                android.webkit.CookieManager.getInstance()
                    .setAcceptThirdPartyCookies(this, true)
                webViewClient = object : WebViewClient() {
                    override fun onPageStarted(
                        view: WebView,
                        url: String?,
                        favicon: android.graphics.Bitmap?,
                    ) {
                        Log.w("GSReels", "page started: $url")
                    }

                    override fun onPageFinished(view: WebView, url: String?) {
                        Log.w("GSReels", "page finished: $url")
                    }

                    override fun onReceivedError(
                        view: WebView,
                        request: WebResourceRequest,
                        error: android.webkit.WebResourceError,
                    ) {
                        // Sub-resource failures matter here too: a blocked
                        // iframe_api or embed request is exactly the failure
                        // mode being diagnosed on the cloud emulator.
                        Log.w(
                            "GSReels",
                            "resource error ${error.errorCode} '${error.description}' " +
                                "main=${request.isForMainFrame} url=${request.url}",
                        )
                    }

                    override fun onReceivedHttpError(
                        view: WebView,
                        request: WebResourceRequest,
                        errorResponse: WebResourceResponse,
                    ) {
                        Log.w(
                            "GSReels",
                            "http ${errorResponse.statusCode} " +
                                "main=${request.isForMainFrame} url=${request.url}",
                        )
                    }
                }
                // Required for HTML5 <video> to render inside a WebView; the
                // console hook surfaces IFrame API errors that are otherwise
                // invisible on device.
                webChromeClient = object : WebChromeClient() {
                    override fun onConsoleMessage(consoleMessage: ConsoleMessage): Boolean {
                        Log.w(
                            "GSReels",
                            "console: ${consoleMessage.message()} " +
                                "[${consoleMessage.sourceId()}:${consoleMessage.lineNumber()}]",
                        )
                        return true
                    }
                }
                setBackgroundColor(android.graphics.Color.BLACK)
                isVerticalScrollBarEnabled = false
                isHorizontalScrollBarEnabled = false
                overScrollMode = WebView.OVER_SCROLL_NEVER
                addJavascriptInterface(
                    object {
                        @JavascriptInterface
                        fun onReady() {
                            Log.w("GSReels", "player ready")
                            mainHandler.post { currentOnPlayerReady() }
                        }

                        @JavascriptInterface
                        fun onEnded() {
                            mainHandler.post { currentOnEnded() }
                        }

                        @JavascriptInterface
                        fun onPlayerState(state: Int) {
                            Log.w("GSReels", "state: $state")
                        }

                        /**
                         * Player errors. Negative codes are synthetic and come
                         * from the player page itself rather than YouTube:
                         * -1 pre-ready JS error, -2 readiness timeout,
                         * -3 the IFrame API script failed to load.
                         */
                        @JavascriptInterface
                        fun onPlayerError(code: Int) {
                            val label = when (code) {
                                -1 -> "pre-ready JS error"
                                -2 -> "readiness timeout"
                                -3 -> "iframe API load failed"
                                else -> "youtube error"
                            }
                            Log.w("GSReels", "error code: $code ($label)")
                            mainHandler.post { currentOnPlayerError(code) }
                        }
                    },
                    "GSBridge",
                )
                holder.webViewRef = this
            }
        },
        update = { webView ->
            if (holder.lastVideoId != videoId) {
                holder.lastVideoId = videoId
                holder.lastMuted = isMuted
                holder.lastPlaying = isPlaying
                // autoplay mirrors the pager's play state: reloading a paused
                // reel must not silently start playing again.
                val html = buildPlayerHtml(
                    context = webView.context,
                    videoId = videoId,
                    isMuted = isMuted,
                    autoplay = isPlaying,
                )
                Log.w("GSReels", "loading player for video $videoId (origin=$PlayerBaseUrl)")
                webView.loadDataWithBaseURL(
                    PlayerBaseUrl,
                    html,
                    "text/html",
                    "utf-8",
                    null,
                )
            } else {
                if (holder.lastMuted != isMuted) {
                    holder.lastMuted = isMuted
                    val js = if (isMuted) "player.mute();" else "player.unMute();"
                    webView.evaluateJavascript("try{$js}catch(e){}", null)
                }
                if (holder.lastPlaying != isPlaying) {
                    holder.lastPlaying = isPlaying
                    val js = if (isPlaying) "player.playVideo();" else "player.pauseVideo();"
                    webView.evaluateJavascript("try{$js}catch(e){}", null)
                }
            }
        },
        onRelease = { webView ->
            webView.stopLoading()
            webView.loadUrl("about:blank")
            webView.removeAllViews()
            webView.destroy()
            holder.webViewRef = null
        },
    )

    // Deterministic teardown: swiping a reel away kills its audio and never
    // leaves a second player alive.
    DisposableEffect(Unit) {
        onDispose {
            holder.lastVideoId = null
        }
    }

    // Backgrounding must never leave trailer audio playing.
    val currentIsPlaying by rememberUpdatedState(isPlaying)
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_PAUSE -> {
                    holder.webViewRef?.let { wv ->
                        wv.evaluateJavascript("try{player.pauseVideo();}catch(e){}", null)
                        wv.onPause()
                    }
                }
                Lifecycle.Event.ON_RESUME -> {
                    holder.webViewRef?.let { wv ->
                        wv.onResume()
                        if (currentIsPlaying) {
                            wv.evaluateJavascript("try{player.playVideo();}catch(e){}", null)
                        }
                    }
                }
                else -> Unit
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }
}

/**
 * Origin the player page is served from. Must stay byte-identical to the
 * `PLAYER_ORIGIN` constant in `assets/yt_player.html`: YouTube compares the
 * embed's referrer against the `origin` playerVar and fails with 152/153 on
 * any mismatch.
 */
private const val PlayerBaseUrl = "https://guidestream.tv"

/**
 * Reads the static player page from assets and injects the per-reel config.
 * The video id is sanitised to the YouTube id alphabet so a malformed key can
 * never break out of the JS string literal.
 */
private fun buildPlayerHtml(
    context: Context,
    videoId: String,
    isMuted: Boolean,
    autoplay: Boolean,
): String {
    val template = context.assets.open("yt_player.html").bufferedReader().use { it.readText() }
    val safeId = videoId.filter { it.isLetterOrDigit() || it == '-' || it == '_' }
    return template
        .replace("__VIDEO_ID__", safeId)
        .replace("__MUTE__", if (isMuted) "1" else "0")
        .replace("__AUTOPLAY__", if (autoplay) "1" else "0")
}

/** Holds the last-pushed state so recompositions don't reload/restart the WebView. */
private class PlayerStateHolder {
    var lastVideoId: String? = null
    var lastMuted: Boolean = true
    var lastPlaying: Boolean = true
    var webViewRef: WebView? = null
}

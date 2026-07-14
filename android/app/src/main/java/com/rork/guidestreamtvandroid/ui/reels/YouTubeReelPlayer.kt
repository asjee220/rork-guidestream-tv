package com.rork.guidestreamtvandroid.ui.reels

import android.annotation.SuppressLint
import android.net.Uri
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
import androidx.webkit.WebViewAssetLoader
import com.rork.guidestreamtvandroid.BuildConfig

/**
 * Inline YouTube trailer player for Reels.
 *
 * The IFrame Player API validates the embedding page's real origin and
 * referrer against the `origin` playerVar. iOS' `WKWebView.loadHTMLString`
 * grants a base-URL document that origin, but Android's
 * `loadDataWithBaseURL` gives the document an opaque origin with no valid
 * referrer, so YouTube rejects the embed with error 150 on every video.
 *
 * The fix serves the player HTML from a genuine, servable https origin via
 * AndroidX [WebViewAssetLoader] (`https://appassets.androidplatform.net`), so
 * the document has a real origin and referrer that match the `origin`
 * playerVar. The player page is a static asset (`assets/yt_player.html`) that
 * reads its video id and mute flag from the query string. This is
 * YouTube-ToS compliant and never uses ExoPlayer/media3, which cannot play
 * YouTube and would require ToS-violating stream extraction.
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
            // Serve the player HTML from a real https origin so the IFrame API
            // sees a valid origin + referrer matching the `origin` playerVar.
            val assetLoader = WebViewAssetLoader.Builder()
                .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(ctx))
                .build()

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
                }
                // Delegate asset requests to the loader so the player page is
                // served from https://appassets.androidplatform.net with a real
                // origin instead of an opaque loadDataWithBaseURL origin.
                webViewClient = object : WebViewClient() {
                    override fun shouldInterceptRequest(
                        view: WebView,
                        request: WebResourceRequest,
                    ): WebResourceResponse? {
                        return assetLoader.shouldInterceptRequest(request.url)
                    }
                }
                // Required for HTML5 <video> to render inside a WebView; the
                // console hook surfaces IFrame API errors that are otherwise
                // invisible on device.
                webChromeClient = object : WebChromeClient() {
                    override fun onConsoleMessage(consoleMessage: ConsoleMessage): Boolean {
                        Log.d(
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
                            Log.d("GSReels", "player ready")
                            mainHandler.post { currentOnPlayerReady() }
                        }

                        @JavascriptInterface
                        fun onEnded() {
                            mainHandler.post { currentOnEnded() }
                        }

                        @JavascriptInterface
                        fun onPlayerState(state: Int) {
                            Log.d("GSReels", "state: $state")
                        }

                        @JavascriptInterface
                        fun onPlayerError(code: Int) {
                            Log.d("GSReels", "error code: $code")
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
                val muteFlag = if (isMuted) "1" else "0"
                val url = Uri.parse("https://appassets.androidplatform.net/assets/yt_player.html")
                    .buildUpon()
                    .appendQueryParameter("v", videoId)
                    .appendQueryParameter("mute", muteFlag)
                    .build()
                    .toString()
                webView.loadUrl(url)
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

/** Holds the last-pushed state so recompositions don't reload/restart the WebView. */
private class PlayerStateHolder {
    var lastVideoId: String? = null
    var lastMuted: Boolean = true
    var lastPlaying: Boolean = true
    var webViewRef: WebView? = null
}

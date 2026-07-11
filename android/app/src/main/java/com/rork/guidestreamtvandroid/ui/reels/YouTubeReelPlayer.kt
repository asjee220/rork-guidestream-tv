package com.rork.guidestreamtvandroid.ui.reels

import android.annotation.SuppressLint
import android.os.Handler
import android.os.Looper
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebView
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

/**
 * Inline YouTube trailer player for Reels.
 *
 * Mirrors the shipping iOS phone implementation: it embeds the official YouTube
 * IFrame Player API inside a plain [WebView] loaded from a youtube.com base URL
 * (so the IFrame API treats the page as same-origin and does not raise embed
 * error 150/153). This is YouTube-ToS compliant and requires no Gradle
 * dependency. It never uses ExoPlayer/media3, which cannot play YouTube and
 * would require ToS-violating stream extraction.
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
    onEmbedError: () -> Unit,
    onEnded: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val currentOnEmbedError by rememberUpdatedState(onEmbedError)
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
            WebView(ctx).apply {
                @Suppress("DEPRECATION")
                settings.apply {
                    javaScriptEnabled = true
                    // Mandatory: without this Android blocks autoplay and the
                    // embed stays frozen on a black frame.
                    mediaPlaybackRequiresUserGesture = false
                    domStorageEnabled = true
                }
                // Required for HTML5 <video> to render inside a WebView.
                webChromeClient = WebChromeClient()
                setBackgroundColor(android.graphics.Color.BLACK)
                isVerticalScrollBarEnabled = false
                isHorizontalScrollBarEnabled = false
                overScrollMode = WebView.OVER_SCROLL_NEVER
                addJavascriptInterface(
                    object {
                        @JavascriptInterface
                        fun onReady() {
                            // No-op hook; playback is driven by player vars.
                        }

                        @JavascriptInterface
                        fun onEnded() {
                            mainHandler.post { currentOnEnded() }
                        }

                        @JavascriptInterface
                        fun onEmbedError() {
                            mainHandler.post { currentOnEmbedError() }
                        }
                    },
                    "GSBridge",
                )
            }
        },
        update = { webView ->
            if (holder.lastVideoId != videoId) {
                holder.lastVideoId = videoId
                holder.lastMuted = isMuted
                holder.lastPlaying = isPlaying
                webView.loadDataWithBaseURL(
                    "https://www.youtube.com",
                    buildEmbedHtml(videoId, isMuted),
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

/**
 * Builds the IFrame Player API HTML. Player vars match the iOS playerVars
 * exactly so behaviour is identical across platforms.
 */
private fun buildEmbedHtml(videoId: String, isMuted: Boolean): String {
    val muteFlag = if (isMuted) 1 else 0
    return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
            * { margin: 0; padding: 0; }
            html, body { background: #000; width: 100%; height: 100%; overflow: hidden; }
            #player { width: 100%; height: 100%; }
        </style>
        </head>
        <body>
        <div id="player"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
            var player;
            function onYouTubeIframeAPIReady() {
                player = new YT.Player('player', {
                    videoId: '$videoId',
                    playerVars: {
                        playsinline: 1,
                        autoplay: 1,
                        mute: $muteFlag,
                        controls: 0,
                        rel: 0,
                        modestbranding: 1,
                        showinfo: 0,
                        iv_load_policy: 3,
                        fs: 0,
                        disablekb: 1,
                        loop: 1,
                        playlist: '$videoId',
                        enablejsapi: 1,
                        origin: 'https://www.youtube.com'
                    },
                    events: {
                        'onReady': function(e) {
                            try {
                                e.target.playVideo();
                                if ($muteFlag === 1) { e.target.mute(); } else { e.target.unMute(); }
                            } catch (err) {}
                            if (window.GSBridge && GSBridge.onReady) { GSBridge.onReady(); }
                        },
                        'onStateChange': function(e) {
                            if (e.data === 0) {
                                if (window.GSBridge && GSBridge.onEnded) { GSBridge.onEnded(); }
                            }
                        },
                        'onError': function(e) {
                            if (window.GSBridge && GSBridge.onEmbedError) { GSBridge.onEmbedError(); }
                        }
                    }
                });
            }
        </script>
        </body>
        </html>
    """.trimIndent()
}

package com.rork.guidestreamtvandroid.ui.reels

import android.util.Log
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
import com.pierfrancescosoffritti.androidyoutubeplayer.core.player.PlayerConstants
import com.pierfrancescosoffritti.androidyoutubeplayer.core.player.YouTubePlayer
import com.pierfrancescosoffritti.androidyoutubeplayer.core.player.listeners.AbstractYouTubePlayerListener
import com.pierfrancescosoffritti.androidyoutubeplayer.core.player.options.IFramePlayerOptions
import com.pierfrancescosoffritti.androidyoutubeplayer.core.player.views.YouTubePlayerView

/**
 * Inline YouTube trailer player for Reels.
 *
 * Uses the proven open-source android-youtube-player library (v13.0.0), which
 * wraps the official YouTube IFrame API in a WebView. Version 13.0.0 fixes the
 * error 152 "missing HTTP referrer" problem by deriving the embed origin from
 * the app's package name, and it correctly handles third-party cookies and WebView
 * UA cleanup that a raw WebView does not. This is YouTube-ToS compliant and never
 * uses ExoPlayer/media3 stream extraction.
 *
 * The view never consumes touch ([pointerInteropFilter] returns false),
 * mirroring the iOS `allowsHitTesting(false)` on the player layer so the
 * VerticalPager swipe and every overlay tap keep working.
 */
@OptIn(ExperimentalComposeUiApi::class)
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
    val lifecycleOwner = LocalLifecycleOwner.current

    // State holder so the update block can nudge play/pause/mute without
    // recreating the player or the listener.
    val holder = remember { PlayerHolder() }

    AndroidView(
        modifier = modifier.pointerInteropFilter { false },
        factory = { ctx ->
            Log.w("GSReels", "creating player for video $videoId")
            val options = IFramePlayerOptions.Builder(ctx)
                .autoplay(1)
                .mute(1)
                .controls(0)
                .rel(0)
                .ivLoadPolicy(3)
                .build()

            YouTubePlayerView(ctx).apply {
                enableAutomaticInitialization = false
                initialize(object : AbstractYouTubePlayerListener() {
                    override fun onReady(youTubePlayer: YouTubePlayer) {
                        holder.player = youTubePlayer
                        holder.lastVideoId = videoId
                        holder.lastMuted = isMuted
                        holder.lastPlaying = isPlaying
                        youTubePlayer.cueVideo(videoId, 0f)
                        if (isPlaying) youTubePlayer.play()
                        if (isMuted) youTubePlayer.mute() else youTubePlayer.unMute()
                        currentOnPlayerReady()
                    }

                    override fun onStateChange(
                        youTubePlayer: YouTubePlayer,
                        state: PlayerConstants.PlayerState,
                    ) {
                        if (state == PlayerConstants.PlayerState.ENDED) {
                            currentOnEnded()
                        }
                    }

                    override fun onError(
                        youTubePlayer: YouTubePlayer,
                        error: PlayerConstants.PlayerError,
                    ) {
                        Log.w("GSReels", "player error $error for video $videoId")
                        // REQUEST_MISSING_HTTP_REFERER is a transient init error that
                        // the library recovers from automatically; mapping it to the
                        // Kotlin error handler would cause false fallback cascades.
                        if (error != PlayerConstants.PlayerError.REQUEST_MISSING_HTTP_REFERER) {
                            currentOnPlayerError(error.ordinal)
                        }
                    }
                }, true, options)
                holder.view = this
            }
        },
        update = { view ->
            // The library requires lifecycle observation on the view itself.
            lifecycleOwner.lifecycle.addObserver(view)

            holder.player?.let { player ->
                if (holder.lastVideoId != videoId) {
                    holder.lastVideoId = videoId
                    player.cueVideo(videoId, 0f)
                }
                if (holder.lastMuted != isMuted) {
                    holder.lastMuted = isMuted
                    if (isMuted) player.mute() else player.unMute()
                }
                if (holder.lastPlaying != isPlaying) {
                    holder.lastPlaying = isPlaying
                    if (isPlaying) player.play() else player.pause()
                }
            }
        },
        onRelease = { view ->
            lifecycleOwner.lifecycle.removeObserver(view)
            view.release()
            holder.player = null
            holder.view = null
        },
    )

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_PAUSE -> {
                    holder.player?.pause()
                    holder.view?.let { view ->
                        lifecycleOwner.lifecycle.removeObserver(view)
                    }
                }
                Lifecycle.Event.ON_RESUME -> {
                    holder.view?.let { view ->
                        lifecycleOwner.lifecycle.addObserver(view)
                    }
                    if (isPlaying) holder.player?.play()
                }
                else -> Unit
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }
}

private class PlayerHolder {
    var player: YouTubePlayer? = null
    var view: YouTubePlayerView? = null
    var lastVideoId: String? = null
    var lastMuted: Boolean = true
    var lastPlaying: Boolean = true
}

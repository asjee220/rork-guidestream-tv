package com.rork.guidestreamtvandroid.data.local

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import java.util.Locale

/**
 * Live speech-to-text for the Ask Stream sheet — mirrors iOS
 * SpeechInputService.swift. Wraps [SpeechRecognizer] with partial results so
 * the text field fills in as the user talks. SpeechRecognizer must be created
 * and driven on the main thread, so every operation is posted to the main
 * looper. The recognizer is destroyed on [stop] and never leaked across sheet
 * opens.
 */
object SpeechInputService {

    private var recognizer: SpeechRecognizer? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * Session-end callback for the CURRENT start invocation. Nulled once
     * fired (so onEnd runs at most once per session — onError can follow
     * onPartialResults and onResults can be followed by further callbacks)
     * and nulled by [stop] so an explicit user-initiated stop never fires it.
     */
    private var currentOnEnd: ((Boolean) -> Unit)? = null

    /** True when the device has an on-device/Google recognition service. */
    fun isAvailable(context: Context): Boolean =
        SpeechRecognizer.isRecognitionAvailable(context.applicationContext)

    /**
     * Starts listening and streams both partial and final transcriptions
     * through [onPartial]. RECORD_AUDIO permission must already be granted
     * by the caller.
     *
     * Unlike iOS's SFSpeechRecognizer, Android's SpeechRecognizer ends its
     * own session after a silence timeout, so [onEnd] reports session end:
     * it fires exactly once per start with `startedOk = true` for a normal
     * finish (results delivered or a recoverable error such as a silence
     * timeout) and `startedOk = false` when recognition could not run at all
     * (no service, recognizer creation failure, startListening throwing, or
     * ERROR_INSUFFICIENT_PERMISSIONS) so the caller can hide the mic.
     * RecognitionListener callbacks arrive on the main thread, so [onEnd]
     * may set Compose state directly.
     */
    fun start(context: Context, onPartial: (String) -> Unit, onEnd: (Boolean) -> Unit) {
        val appContext = context.applicationContext
        if (!isAvailable(appContext)) {
            onEnd(false)
            return
        }
        mainHandler.post {
            destroyRecognizer()
            // Fresh session: arm its end callback (also resets the at-most-once guard).
            currentOnEnd = onEnd
            val r: SpeechRecognizer? = SpeechRecognizer.createSpeechRecognizer(appContext)
            if (r == null) {
                fireEnd(false)
                return@post
            }
            recognizer = r
            r.setRecognitionListener(object : RecognitionListener {
                override fun onPartialResults(partialResults: Bundle?) = deliver(partialResults, onPartial)
                override fun onResults(results: Bundle?) {
                    deliver(results, onPartial)
                    fireEnd(true)
                }
                override fun onError(error: Int) {
                    // Keep whatever text arrived; report the session as over.
                    fireEnd(error != SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS)
                }
                override fun onReadyForSpeech(params: Bundle?) {}
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {}
                override fun onEvent(eventType: Int, params: Bundle?) {}
            })
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
                )
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault().toLanguageTag())
            }
            try {
                r.startListening(intent)
            } catch (_: Exception) {
                destroyRecognizer()
                fireEnd(false)
            }
        }
    }

    /**
     * Cancels and destroys the active recognizer, if any. Safe to call twice.
     * Marks the current session consumed so a user-initiated stop never fires
     * [currentOnEnd] — the caller resets its own state in that path.
     */
    fun stop() {
        mainHandler.post {
            currentOnEnd = null
            destroyRecognizer()
        }
    }

    /** Invokes the current session's end callback at most once. */
    private fun fireEnd(startedOk: Boolean) {
        val cb = currentOnEnd ?: return
        currentOnEnd = null
        cb(startedOk)
    }

    private fun destroyRecognizer() {
        recognizer?.let {
            try { it.cancel() } catch (_: Exception) { }
            try { it.destroy() } catch (_: Exception) { }
        }
        recognizer = null
    }

    private fun deliver(bundle: Bundle?, onPartial: (String) -> Unit) {
        val text = bundle
            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            ?.firstOrNull()
        if (!text.isNullOrBlank()) onPartial(text)
    }
}

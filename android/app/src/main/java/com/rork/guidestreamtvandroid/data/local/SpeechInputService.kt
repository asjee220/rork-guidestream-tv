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

    /** True when the device has an on-device/Google recognition service. */
    fun isAvailable(context: Context): Boolean =
        SpeechRecognizer.isRecognitionAvailable(context.applicationContext)

    /**
     * Starts listening and streams both partial and final transcriptions
     * through [onPartial]. Returns whether recognition could be started.
     * RECORD_AUDIO permission must already be granted by the caller.
     */
    fun start(context: Context, onPartial: (String) -> Unit): Boolean {
        val appContext = context.applicationContext
        if (!isAvailable(appContext)) return false
        mainHandler.post {
            destroyRecognizer()
            val r = SpeechRecognizer.createSpeechRecognizer(appContext)
            recognizer = r
            r.setRecognitionListener(object : RecognitionListener {
                override fun onPartialResults(partialResults: Bundle?) = deliver(partialResults, onPartial)
                override fun onResults(results: Bundle?) = deliver(results, onPartial)
                override fun onError(error: Int) { /* keep whatever text arrived */ }
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
            }
        }
        return true
    }

    /** Cancels and destroys the active recognizer, if any. Safe to call twice. */
    fun stop() {
        mainHandler.post { destroyRecognizer() }
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

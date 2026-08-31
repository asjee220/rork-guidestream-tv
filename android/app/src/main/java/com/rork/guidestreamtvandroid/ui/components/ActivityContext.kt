package com.rork.guidestreamtvandroid.ui.components

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper

/**
 * The Activity hosting this Context, or null if there is none.
 *
 * Compose's `LocalContext` is usually the Activity, which is why a plain
 * `context as? Activity` cast looks fine and works everywhere it is tested.
 * It stops being the Activity inside a Compose `Dialog`: the dialog wraps the
 * activity in a themed `ContextWrapper`, the cast silently yields null, and
 * whatever depended on the Activity quietly stops happening. That is exactly
 * how GUI-84 happened — Trailers & Clips could not rotate when it was opened
 * from the coming-soon sheet, because that route hosts the player in a Dialog.
 *
 * Walk the wrapper chain instead of casting.
 */
internal fun Context.findActivity(): Activity? {
    var current: Context? = this
    while (current is ContextWrapper) {
        if (current is Activity) return current
        current = current.baseContext
    }
    return null
}

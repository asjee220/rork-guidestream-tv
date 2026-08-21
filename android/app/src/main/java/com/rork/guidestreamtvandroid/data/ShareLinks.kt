package com.rork.guidestreamtvandroid.data

import android.content.Context
import android.content.Intent
import android.net.Uri

/**
 * Single source of truth for every share affordance so all surfaces produce
 * the same `https://guidestream.tv/w/{segment}/{id}?t={title}` deep link —
 * mirrors iOS ShareService.swift.
 */
object ShareLinks {

    enum class Kind(val segment: String) {
        MOVIE("movie"),
        TV("tv"),
        CREATOR("c"),
        GAME("g"),
    }

    /** Canonical share URL. A blank title falls back to the id. */
    fun url(kind: Kind, id: String, title: String): String {
        val effectiveTitle = title.trim().ifEmpty { id }
        return "https://guidestream.tv/w/${kind.segment}/${Uri.encode(id)}?t=${Uri.encode(effectiveTitle)}"
    }

    /** Message shared alongside the URL. */
    fun message(title: String): String = "Watch $title on GuideStream TV"

    /**
     * Fires the system share chooser with the share message + URL. Silently
     * ignores failure (e.g. no share target on the device).
     */
    fun share(context: Context, kind: Kind, id: String, title: String) {
        try {
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_SUBJECT, title)
                putExtra(Intent.EXTRA_TEXT, "${message(title)}\n${url(kind, id, title)}")
            }
            context.startActivity(Intent.createChooser(intent, "Share"))
        } catch (_: Exception) {
            // No share target available — never crash.
        }
    }
}

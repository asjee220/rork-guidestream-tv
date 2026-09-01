package com.rork.guidestreamtvandroid.data.remote

import android.os.Build
import com.rork.guidestreamtvandroid.BuildConfig
import com.rork.guidestreamtvandroid.SupabaseConfig
import com.rork.guidestreamtvandroid.data.local.DeviceIdentity
import io.ktor.client.HttpClient
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.contentType
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

/**
 * Client for the `support_request` edge function (GUI-87).
 *
 * Contact Support used to hand off to a mail app with the device details
 * pasted into the body. This posts the same fields to the function that
 * already backs the website form, so the request lands in `support_requests`
 * with channel = "app" and is picked up by the existing support triage, and
 * the customer never leaves GuideStream.
 *
 * The function is deployed with verify_jwt=false, so the anon key is enough
 * and guests can write in too. Row-level security on `support_requests`
 * denies every client insert - the function writes with the service role -
 * so this path is the only one an app can use.
 */
object SupportRequestService {

    private val client: HttpClient by lazy { HttpClient() }

    /** The device model as a person would recognise it, e.g. "Pixel 8 Pro". */
    private val deviceModel: String
        get() {
            val manufacturer = Build.MANUFACTURER.orEmpty()
            val model = Build.MODEL.orEmpty()
            return if (model.startsWith(manufacturer, ignoreCase = true)) {
                model
            } else {
                "$manufacturer $model".trim()
            }
        }

    /**
     * Submits a support request. Returns true only on a 2xx from the function;
     * every failure (validation, network, server) returns false so the form
     * can keep the customer's text on screen and let them retry.
     */
    suspend fun submit(
        name: String,
        email: String,
        topic: String,
        message: String,
    ): Boolean {
        return try {
            val deviceId = runCatching { DeviceIdentity.get().deviceId }.getOrNull()
            val body = buildJsonObject {
                put("name", JsonPrimitive(name))
                put("email", JsonPrimitive(email))
                put("topic", JsonPrimitive(topic))
                put("message", JsonPrimitive(message))
                put("channel", JsonPrimitive("app"))
                put("subject", JsonPrimitive("GuideStream TV — $topic"))
                put("app_version", JsonPrimitive(BuildConfig.VERSION_NAME))
                put("build", JsonPrimitive(BuildConfig.VERSION_CODE.toString()))
                put("device_model", JsonPrimitive(deviceModel))
                put("os_version", JsonPrimitive("Android ${Build.VERSION.RELEASE}"))
                if (deviceId != null) put("device_id", JsonPrimitive(deviceId))
            }
            val url = "${SupabaseConfig.URL.trim()}/functions/v1/support_request"
            val response: HttpResponse = client.post(url) {
                contentType(ContentType.Application.Json)
                header(HttpHeaders.ContentType, "application/json")
                header("apikey", SupabaseConfig.ANON_KEY)
                header(HttpHeaders.Authorization, "Bearer ${SupabaseConfig.ANON_KEY}")
                setBody(body.toString())
            }
            response.status.value in 200..299
        } catch (_: Exception) {
            false
        }
    }
}

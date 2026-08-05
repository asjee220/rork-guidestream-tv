package com.rork.guidestreamtvandroid.data.remote

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.util.Log
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.rork.guidestreamtvandroid.AppConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.security.MessageDigest
import java.util.UUID

/**
 * Native "Sign in with Google" via the Android Credential Manager.
 *
 * Replaces the Custom Tab / browser redirect with the system account sheet.
 * Returns a Google ID token plus the raw nonce that was used to mint it —
 * the caller hands both to Supabase `signInWith(IDToken)`, which verifies
 * that the nonce embedded in the token matches.
 *
 * Nonce handling follows Google's requirement: the *hashed* nonce goes to
 * Credential Manager, the *raw* nonce goes to Supabase.
 */
object GoogleCredentialSignIn {

    private const val TAG = "GoogleCredentialSignIn"

    /** Successful credential retrieval. */
    data class Token(val idToken: String, val rawNonce: String)

    /** The user dismissed the account sheet. Not an error worth surfacing. */
    class CancelledException : Exception("Google sign-in cancelled")

    /**
     * No usable credential on this device (no Google account, no Play
     * Services, or Credential Manager unavailable). The caller should fall
     * back to the browser OAuth flow.
     */
    class UnavailableException(cause: Throwable?) :
        Exception("Google credentials unavailable", cause)

    /**
     * Credential Manager must present a system sheet, so it needs the hosting
     * Activity — an application context throws. Compose's `LocalContext` is
     * normally the Activity already, but it can be a themed wrapper, so walk
     * the wrapper chain to be safe.
     */
    private fun Context.findActivity(): Activity? {
        var current: Context? = this
        while (current is ContextWrapper) {
            if (current is Activity) return current
            current = current.baseContext
        }
        return null
    }

    /** SHA-256 of [raw], hex-encoded — the form Google expects for the nonce. */
    private fun hashNonce(raw: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(raw.toByteArray())
        return digest.fold("") { acc, byte -> acc + "%02x".format(byte) }
    }

    /**
     * Requests a Google ID token using the system account sheet.
     *
     * Tries the filtered flow first so returning users get a one-tap sheet
     * listing only accounts already authorized for this app. If none exist,
     * retries with the explicit "Sign in with Google" flow, which shows every
     * Google account on the device.
     *
     * @param context should be an Activity context so the sheet can be shown.
     * @throws CancelledException if the user dismissed the sheet.
     * @throws UnavailableException if no credential could be obtained at all.
     */
    suspend fun requestIdToken(context: Context): Token {
        val activity = context.findActivity()
            ?: throw UnavailableException(IllegalStateException("No Activity context"))
        val rawNonce = UUID.randomUUID().toString()
        val hashedNonce = hashNonce(rawNonce)
        val credentialManager = CredentialManager.create(activity)

        val filteredOption = GetGoogleIdOption.Builder()
            .setServerClientId(AppConfig.GOOGLE_WEB_CLIENT_ID)
            .setFilterByAuthorizedAccounts(true)
            .setAutoSelectEnabled(true)
            .setNonce(hashedNonce)
            .build()

        val idToken = try {
            fetchToken(credentialManager, activity, filteredOption)
        } catch (e: NoCredentialException) {
            // No previously-authorized account — show the full picker instead.
            Log.i(TAG, "No authorized account; falling back to explicit picker")
            val explicitOption = GetSignInWithGoogleOption
                .Builder(serverClientId = AppConfig.GOOGLE_WEB_CLIENT_ID)
                .setNonce(hashedNonce)
                .build()
            try {
                fetchToken(credentialManager, activity, explicitOption)
            } catch (e2: GetCredentialCancellationException) {
                throw CancelledException()
            } catch (e2: NoCredentialException) {
                throw UnavailableException(e2)
            } catch (e2: GetCredentialException) {
                throw UnavailableException(e2)
            }
        } catch (e: GetCredentialCancellationException) {
            throw CancelledException()
        } catch (e: GetCredentialException) {
            throw UnavailableException(e)
        }

        return Token(idToken = idToken, rawNonce = rawNonce)
    }

    private suspend fun fetchToken(
        credentialManager: CredentialManager,
        context: Context,
        option: androidx.credentials.CredentialOption,
    ): String {
        val request = GetCredentialRequest.Builder()
            .addCredentialOption(option)
            .build()
        // The sheet is UI — drive it from the main thread even though callers
        // run this service on an IO dispatcher.
        val response = withContext(Dispatchers.Main) {
            credentialManager.getCredential(request = request, context = context)
        }
        val credential = response.credential
        if (
            credential is CustomCredential &&
            credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL
        ) {
            return GoogleIdTokenCredential.createFrom(credential.data).idToken
        }
        throw UnavailableException(null)
    }
}

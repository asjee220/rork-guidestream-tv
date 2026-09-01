import java.util.Properties

// Upload signing material. Never committed (see android/.gitignore).
//   Local  : android/keystore.properties
//   CI     : RELEASE_STORE_FILE / RELEASE_STORE_PASSWORD / RELEASE_KEY_ALIAS / RELEASE_KEY_PASSWORD
// When none is present the release build is left UNSIGNED on purpose, so a
// debug-signed artifact can never be produced and rejected by Play.
val keystorePropsFile = rootProject.file("keystore.properties")
val keystoreProps = Properties().apply {
    if (keystorePropsFile.exists()) keystorePropsFile.inputStream().use { load(it) }
}
fun signingValue(key: String, env: String): String? =
    keystoreProps.getProperty(key)?.takeIf { it.isNotBlank() }
        ?: System.getenv(env)?.takeIf { it.isNotBlank() }

val releaseStoreFile = signingValue("storeFile", "RELEASE_STORE_FILE")
val releaseStorePassword = signingValue("storePassword", "RELEASE_STORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "RELEASE_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "RELEASE_KEY_PASSWORD")
val hasReleaseSigning = releaseStoreFile != null && releaseStorePassword != null &&
    releaseKeyAlias != null && releaseKeyPassword != null

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.google.services)
}

android {
    namespace = "com.rork.guidestreamtvandroid"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.rork.guidestreamtvandroid"
        minSdk = 24
        targetSdk = 36
        // Play requires a strictly increasing versionCode, and every bundle
        // RorkMax has published used the build's Unix epoch seconds — the live
        // 1.0.20 bundle is 1787520409 (Aug 23 2026 21:26 UTC). A small ordinal
        // like 21 or 22 is therefore far BELOW what Play already has and is
        // rejected on upload. Keep the epoch convention: when bumping, use
        // `date +%s` at the time of the build.
        versionCode = 1788196440
        versionName = "1.0.25"

        // Production AdMob app id, committed as the default — the same shape as
        // iOS Info.plist's GADApplicationIdentifier. An env-var-only path is not
        // safe here: Android Studio launched from Finder inherits no shell
        // environment, so every release bundle since 1.0.21 silently shipped
        // Google's test app id. ANDROID_ADMOB_APP_ID still overrides for CI, and
        // the debug build type below pins Google's test ids.
        manifestPlaceholders["ANDROID_ADMOB_APP_ID"] = System.getenv("ANDROID_ADMOB_APP_ID")
            ?: "ca-app-pub-6595855555549220~6152605646"

        // Bundled ad units — the last-resort fallback when the Supabase
        // `ads_android` remote-config row is missing or carries units from a
        // different AdMob app (AdUnitResolver validates the publisher prefix
        // against the manifest app id at runtime). Committed as the real units;
        // the env vars still override for CI.
        //
        // GUI-85: the feed chip now loads a real NATIVE ADVANCED ad, so this
        // must be a Native unit. It was a Banner id, which is why the chip
        // could only ever render a bare AdView creative with no headline and
        // no advertiser. The banner unit lives on in ADMOB_BANNER_AD_UNIT_ID
        // for the Reels carousel card, which still uses an AdView.
        buildConfigField(
            "String",
            "ADMOB_NATIVE_AD_UNIT_ID",
            "\"${System.getenv("ANDROID_ADMOB_NATIVE_AD_UNIT_ID")
                ?: "ca-app-pub-6595855555549220/8358142755"}\"",
        )
        buildConfigField(
            "String",
            "ADMOB_BANNER_AD_UNIT_ID",
            "\"${System.getenv("ANDROID_ADMOB_BANNER_AD_UNIT_ID")
                ?: "ca-app-pub-6595855555549220/8484572161"}\"",
        )
        buildConfigField(
            "String",
            "ADMOB_INTERSTITIAL_AD_UNIT_ID",
            "\"${System.getenv("ANDROID_ADMOB_INTERSTITIAL_AD_UNIT_ID")
                ?: "ca-app-pub-6595855555549220/7171490491"}\"",
        )
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = rootProject.file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        debug {
            // Never request the live units from a debug build — developer and
            // emulator traffic on a real unit risks an invalid-traffic flag.
            // Google's Android test ids (the previous defaults were the iOS test
            // app id and a Native advanced unit, neither of which can fill an
            // AdView banner).
            manifestPlaceholders["ANDROID_ADMOB_APP_ID"] =
                "ca-app-pub-3940256099942544~3347511713"
            // Google's NATIVE ADVANCED test unit. This was the debug fallback
            // before 2026-08-31 and it never filled -- because the code was
            // requesting a banner. Now that the chip loads a native ad it is
            // the right id again, and it is how the chip layout gets verified
            // on an emulator without touching a live unit.
            buildConfigField(
                "String",
                "ADMOB_NATIVE_AD_UNIT_ID",
                "\"ca-app-pub-3940256099942544/2247696110\"",
            )
            buildConfigField(
                "String",
                "ADMOB_BANNER_AD_UNIT_ID",
                "\"ca-app-pub-3940256099942544/6300978111\"",
            )
            buildConfigField(
                "String",
                "ADMOB_INTERSTITIAL_AD_UNIT_ID",
                "\"ca-app-pub-3940256099942544/1033173712\"",
            )
        }
        release {
            isMinifyEnabled = false
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "No upload keystore found - release build will be UNSIGNED. " +
                        "Provide android/keystore.properties or the RELEASE_* env vars."
                )
                null
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.material.icons.extended)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.ktor.client.core)
    implementation(libs.ktor.client.android)
    implementation(libs.ktor.client.content.negotiation)
    implementation(libs.ktor.serialization.json)
    implementation(libs.coil.compose)
    implementation(libs.coil.network.okhttp)
    implementation(libs.koin.androidx.compose)
    implementation(libs.supabase.auth)
    implementation(libs.supabase.postgrest)
    implementation(libs.androidx.datastore.preferences)
    implementation(libs.play.services.ads)
    implementation(libs.user.messaging.platform)
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.messaging)
    implementation(libs.androidx.glance.appwidget)
    implementation(libs.androidx.glance.material3)
    implementation(libs.media3.exoplayer)
    implementation(libs.media3.ui)
    implementation(libs.play.services.auth)
    implementation(libs.androidx.credentials)
    implementation(libs.androidx.credentials.play.services.auth)
    implementation(libs.googleid)
    implementation(libs.androidx.webkit)
    implementation(libs.androidx.browser)
    implementation(libs.android.youtube.player)
    debugImplementation(libs.androidx.ui.tooling)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

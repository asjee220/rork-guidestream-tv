# ProGuard / R8 rules for GuideStream TV Android - release builds only.
# R8 minification enabled 2026-09-27 to clear Play's DEX code optimization warning.
# Most libraries ship their own consumer rules; these cover the gaps.

# Keep line numbers so Play crash reports deobfuscate with mapping.txt.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
-keepattributes Signature,InnerClasses,EnclosingMethod,*Annotation*
-keepattributes RuntimeVisibleAnnotations,AnnotationDefault

# kotlinx.serialization - keep generated serializers and companions for app models.
-keep,includedescriptorclasses class com.rork.guidestreamtvandroid.**$$serializer { *; }
-keepclassmembers class com.rork.guidestreamtvandroid.** {
*** Companion;
}
-keepclasseswithmembers class com.rork.guidestreamtvandroid.** {
kotlinx.serialization.KSerializer serializer(...);
}

# WebView JavaScript bridges (YouTube player and in-app web views).
-keepclassmembers class * {
@android.webkit.JavascriptInterface <methods>;
}

# Optional JVM-only dependencies of Ktor / Supabase that are absent on Android.
-dontwarn org.slf4j.**
-dontwarn java.lang.management.**
-dontwarn io.ktor.util.debug.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

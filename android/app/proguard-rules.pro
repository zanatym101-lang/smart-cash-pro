# Flutter & Flutter Plugins Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}

# Drift & SQLite
-keep class * extends com.example.drift.** { *; }
-keep class net.sqlcipher.** { *; }
-keep class io.requery.android.database.sqlite.** { *; }
-keep class androidx.sqlite.** { *; }
-keep class com.smartcashpro.app.data.sqlite.** { *; }
-dontwarn net.sqlcipher.**

# Google Mobile Ads SDK
-keep public class com.google.android.gms.ads.** {
   public *;
}
-keep public class com.google.ads.** {
   public *;
}
-keep class com.google.android.gms.internal.ads.** { *; }
-dontwarn com.google.android.gms.ads.**

# Firebase Auth, Firestore, and Core
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-keep class io.flutter.plugins.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Cryptography & Security
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**

# Local Auth & Biometrics
-keep class androidx.biometric.** { *; }
-dontwarn androidx.biometric.**

# Desugaring & Reflection
-dontwarn java.lang.invoke.**
-dontwarn javax.annotation.**

# Flutter Play Core / Deferred Components
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

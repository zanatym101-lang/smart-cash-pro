import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val storeFileProp = keystoreProperties.getProperty("storeFile").orEmpty().trim()
val storePasswordProp =
    keystoreProperties.getProperty("storePassword").orEmpty().trim()
val keyAliasProp = keystoreProperties.getProperty("keyAlias").orEmpty().trim()
val keyPasswordProp =
    keystoreProperties.getProperty("keyPassword").orEmpty().trim()
val storeFileRef =
    if (storeFileProp.isNotBlank()) rootProject.file(storeFileProp) else null
val storeFileFallback =
    if (storeFileProp.isNotBlank()) rootProject.file("app/$storeFileProp") else null
val resolvedStoreFile = when {
    storeFileRef?.exists() == true -> storeFileRef
    storeFileFallback?.exists() == true -> storeFileFallback
    else -> null
}
val hasReleaseSigning =
    resolvedStoreFile != null &&
        storePasswordProp.isNotBlank() &&
        keyAliasProp.isNotBlank() &&
        keyPasswordProp.isNotBlank()

android {
    namespace = "com.smartcashpro.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.smartcashpro.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                storeFile = resolvedStoreFile
                storePassword = storePasswordProp
                keyAlias = keyAliasProp
                keyPassword = keyPasswordProp
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

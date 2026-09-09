plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.handypick.mimasu"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.handypick.mimasu"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    defaultConfig {
        // minSdk 24 is what the extension ecosystem targets, and desugaring
        // below relies on it.
        multiDexEnabled = true
    }
}

// Libraries an extension expects the HOST to provide at runtime.
//
// Extensions build against extensions-lib as `compileOnly`, so none of this is
// inside their APK (INSTRUCTIONS.md 5.1, 5.2). The exact set below was read out
// of a real extension's classes.dex — see docs/phase-0-findings.md 4. Removing
// any of these turns into a NoClassDefFoundError the moment a source class
// loads, not at build time.
dependencies {
    // Confirmed referenced by a real extension.
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.okhttp3:okhttp-dnsoverhttps:4.12.0")
    implementation("com.squareup.okio:okio:3.9.1")
    implementation("org.jsoup:jsoup:1.18.1")
    implementation("androidx.preference:preference-ktx:1.2.1")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")

    // A lib-1.4 extension still returns rx.Observable, so RxJava 1 has to be
    // on the classpath even though nothing of ours uses it.
    implementation("io.reactivex:rxjava:1.3.8")
}

flutter {
    source = "../.."
}

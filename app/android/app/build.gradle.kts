plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.onepe.onepe_pos"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    // The Nexgo SDK (in-device printer) still references the legacy Apache HTTP classes.
    useLibrary("org.apache.http.legacy")

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.onepe.onepe_pos"
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
            // The Nexgo SDK references optional libraries (Firebase, Gson, CleverTap…) it doesn't ship;
            // R8 fails on them and could strip the printer classes, so release builds aren't shrunk.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Nexgo terminal SDK (N82 / N86 built-in printer), from the OnePe Android printer plugin.
    implementation(files("libs/ps-n86Release-v2.1.10.aar"))
}

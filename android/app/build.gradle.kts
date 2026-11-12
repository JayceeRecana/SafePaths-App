plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.safepaths.safepaths_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    dependencies {
        coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.safepaths.safepaths_app"
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

    flavorDimensions += "environment"
    productFlavors {
        create("production") {
            dimension = "environment"
            manifestPlaceholders["appLabel"] = "SafePaths"
            manifestPlaceholders["appIcon"] = "@mipmap/launcher_icon"
        }
        create("fieldtest") {
            dimension = "environment"
            applicationIdSuffix = ".test"
            versionNameSuffix = "-fieldtest"
            manifestPlaceholders["appLabel"] = "SafePaths Test"
            manifestPlaceholders["appIcon"] = "@drawable/fieldtest_icon"
        }
    }
}

// Never let the Google Services plugin fall back to the production JSON for tests.
tasks.configureEach {
    if (name.contains("Fieldtest") && name.endsWith("GoogleServices")) {
        doFirst {
            check(file("src/fieldtest/google-services.json").exists()) {
                "Missing src/fieldtest/google-services.json. Register com.safepaths.safepaths_app.test in a separate Firebase project."
            }
        }
    }
}

flutter {
    source = "../.."
}

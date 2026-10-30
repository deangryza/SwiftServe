import java.util.Base64

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// A demo override must prevent native production auto-init before Dart selects
// demo FirebaseOptions. Normal builds keep the standard FirebaseInitProvider.
val localFirebaseEmulator = (project.findProperty("dart-defines")?.toString()?.split(",") ?: emptyList())
    .mapNotNull { runCatching { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }.getOrNull() }
    .any { it.startsWith("LOCAL_FIREBASE_EMULATOR_HOST=") && it.substringAfter("=").isNotBlank() }

android {
    namespace = "com.example.my_app"
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
        applicationId = "com.example.my_app"
        manifestPlaceholders["firebaseInitProviderEnabled"] = (!localFirebaseEmulator).toString()
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
}

flutter {
    source = "../.."
}

// Debug builds forward each connected device's port 5000 to this computer, so
// the app's default API_BASE_URL (http://127.0.0.1:5000) reaches the local
// backend with a plain `flutter run`, over USB or wireless debugging.
val adbPath = provider { android.adbExecutable.absolutePath }
val forwardLocalApi by tasks.registering {
    doLast {
        val adb = adbPath.get()
        val devices = try {
            ProcessBuilder(adb, "devices").start().inputStream.bufferedReader()
                .readLines()
                .drop(1)
                .map { it.split("\t") }
                .filter { it.size == 2 && it[1] == "device" }
                .map { it[0] }
        } catch (error: Exception) {
            logger.warn("Skipping adb reverse: ${error.message}")
            emptyList()
        }
        devices.forEach { device ->
            val exitCode = ProcessBuilder(adb, "-s", device, "reverse", "tcp:5000", "tcp:5000")
                .start()
                .waitFor()
            if (exitCode == 0) {
                logger.lifecycle("Forwarded port 5000 to the local backend on $device")
            } else {
                logger.warn("adb reverse failed on $device")
            }
        }
    }
}
tasks.matching { it.name == "preDebugBuild" }.configureEach {
    dependsOn(forwardLocalApi)
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.telima.telima"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // Clé de signature unique de Telima : TOUTES les versions doivent être signées avec elle,
    // sinon Android refuse d'installer la mise à jour par-dessus l'application existante.
    // Conservez android/app/telima-signing.jks en lieu sûr (sauvegarde).
    signingConfigs {
        create("telima") {
            storeFile = file("telima-signing.jks")
            storePassword = System.getenv("TELIMA_STORE_PASSWORD") ?: "android"
            keyAlias = System.getenv("TELIMA_KEY_ALIAS") ?: "androiddebugkey"
            keyPassword = System.getenv("TELIMA_KEY_PASSWORD") ?: "android"
        }
    }

    defaultConfig {
        applicationId = "app.telima.telima"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("telima")
        }
        debug {
            signingConfig = signingConfigs.getByName("telima")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.aether.aether_gui"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.aether.aether_gui"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 29 // aether 2.4.0 needs Android 10+
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // aether ships as libaether.so; extracted to nativeLibraryDir so it can be exec'd.
    packaging {
        jniLibs {
            useLegacyPackaging = true
            keepDebugSymbols += listOf("**/libaether.so", "**/liblyrebird.so", "**/libpsiphon.so")
            // Flutter's target-platform filters its engine but not manually supplied jniLibs.
            // Exclude those extra helpers only for debug; release still emits all split ABIs.
            if (gradle.startParameter.taskNames.any { it.contains("Debug", ignoreCase = true) }) {
                excludes += listOf("**/armeabi-v7a/*.so", "**/x86_64/*.so")
            }
        }
    }

    // Release key from android/key.properties (gitignored); without it release falls back to the debug key.
    val keyProps = rootProject.file("key.properties").takeIf { it.exists() }
        ?.let { f -> Properties().apply { f.inputStream().use { load(it) } } }
    signingConfigs {
        if (keyProps != null) create("release") {
            storeFile = rootProject.file(keyProps.getProperty("storeFile")) // relative to android/
            storePassword = keyProps.getProperty("storePassword")
            keyAlias = keyProps.getProperty("keyAlias")
            keyPassword = keyProps.getProperty("keyPassword")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (keyProps != null) "release" else "debug")
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

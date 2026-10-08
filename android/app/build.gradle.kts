plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Google OAuth (AppAuth, PKCE) returns to the reversed client ID of the Android OAuth client:
//   GOOGLE_OAUTH_CLIENT_ID = <prefix>.apps.googleusercontent.com
//   redirect scheme        = com.googleusercontent.apps.<prefix>
// The app computes the same scheme in Dart (AppConfig.googleRedirectScheme) from the same client ID,
// so the manifest placeholder and the redirect URI can never drift apart. Local builds pass the
// client ID as an environment variable or as a Gradle property.
val googleClientId: String =
    (System.getenv("GOOGLE_OAUTH_CLIENT_ID") ?: (findProperty("GOOGLE_OAUTH_CLIENT_ID") as? String) ?: "")
        .trim()
val googleClientSuffix = ".apps.googleusercontent.com"
val googleRedirectScheme: String =
    if (googleClientId.endsWith(googleClientSuffix)) {
        "com.googleusercontent.apps." + googleClientId.removeSuffix(googleClientSuffix)
    } else {
        // Unconfigured build: AppAuth cannot complete sign-in, and the app reports that as a friendly error.
        "com.voxelops.oauth.unconfigured"
    }

// Release signing is optional: when the keystore variables are present (CI secrets) the
// release APK is signed with the stable release key, otherwise the debug key is used.
val releaseKeystorePath: String? =
    System.getenv("ANDROID_KEYSTORE_PATH")?.takeIf { it.isNotBlank() }

android {
    namespace = "com.voxelops.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.voxelops.app"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders += mapOf("appAuthRedirectScheme" to googleRedirectScheme)
    }

    signingConfigs {
        if (releaseKeystorePath != null) {
            create("release") {
                storeFile = file(releaseKeystorePath)
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (releaseKeystorePath != null) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
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

// Android Lint is not part of the release gate (flutter analyze and the test suite are).
// Lint analysis of third-party Flutter plugins can crash on some runners, so its tasks are disabled.
tasks.matching { it.name.lowercase().contains("lint") }.configureEach {
    enabled = false
}

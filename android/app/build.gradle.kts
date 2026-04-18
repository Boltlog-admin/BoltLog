plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // Match the Firebase Android client config in google-services.json
    // This ensures Google Sign-In credentials are accepted for this app.
    namespace = "com.example.boltlog"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications (Java 8+ APIs on older minSdk)
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Application ID must match the Firebase Android client package_name
        // configured in android/app/google-services.json
        applicationId = "com.example.boltlog"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion  // Android 5.0+ for broad device compatibility
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

    packaging {
        resources {
            excludes += listOf(
                "META-INF/INDEX.LIST",
                "META-INF/DEPENDENCIES",
                "META-INF/versions/**/OSGI-INF/MANIFEST.MF"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // Include all jar files from the libs folder, excluding problematic ones
    // Many JARs in libs are build tools or conflict with dependencies
    val libsDir = file("libs")
    if (libsDir.exists()) {
        implementation(fileTree(libsDir) {
            include("*.jar")
            exclude(
                "bundletool-*.jar",                    // Build tool
                "proto-google-common-protos-*.jar",    // Conflicts with Firebase
                "guava-*-jre.jar",                     // Conflicts with guava-android
                "grpc-*.jar",                          // Conflicts with dependency versions
                "javax.inject-*.jar",                  // Already provided by dependencies
                "kotlin-gradle-plugin-*.jar",          // Build tool, not runtime
                "annotations-*.jar",                   // Conflicts with dependency versions
                "netty-*.jar",                         // Conflicts with dependency versions, causes META-INF issues
                "bcprov-*.jar",                        // Causes META-INF conflicts
                "bcutil-*.jar"                         // Causes META-INF conflicts
            )
        })
    }

    // FirebaseUI for authentication
    implementation("com.firebaseui:firebase-ui-auth:9.0.0")

    // Activity Result API support
    implementation("androidx.activity:activity-ktx:1.8.2")

    // Required only if Facebook login support is required
    // Find the latest Facebook SDK releases here: https://goo.gl/Ce5L94
    // implementation("com.facebook.android:facebook-android-sdk:8.x")
}

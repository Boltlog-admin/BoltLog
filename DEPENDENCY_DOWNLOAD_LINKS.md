# Manual Dependency Download Links

## 🔧 Build Tools & Core Dependencies

### 1. Gradle Wrapper
**Version:** 8.14  
**Download Link:**  
[Gradle 8.14 All Distribution](https://services.gradle.org/distributions/gradle-8.14-all.zip)

**Installation:**
- Extract to: `%USERPROFILE%\.gradle\wrapper\dists\gradle-8.14-all\`
- Or let Gradle download it automatically (recommended)

---

### 2. Android Build Tools
**Version:** 8.11.1 (as specified in settings.gradle.kts)

**Android Gradle Plugin:**
- [Maven Central](https://repo1.maven.org/maven2/com/android/tools/build/gradle/8.11.1/)
- [Direct JAR Download](https://repo1.maven.org/maven2/com/android/tools/build/gradle/8.11.1/gradle-8.11.1.jar)

**Android Build Tools:**
- Download via Android SDK Manager (recommended)
- Or via [Maven Repository](https://repo1.maven.org/maven2/com/android/tools/build/builder/8.11.1/)

---

### 3. Kotlin Plugin
**Version:** 2.2.20  
**Download Link:**  
[Kotlin Gradle Plugin 2.2.20](https://repo1.maven.org/maven2/org/jetbrains/kotlin/kotlin-gradle-plugin/2.2.20/)

---

## 🔥 Firebase & Google Services

### 4. Google Services Plugin
**Version:** 4.3.15  
**Download Link:**  
[Google Services Plugin 4.3.15](https://repo1.maven.org/maven2/com/google/gms/google-services/4.3.15/)

**Firebase SDKs** (downloaded automatically via FlutterFire, but direct links):
- [Firebase Core Android SDK](https://firebase.google.com/download/android)
- [Firebase Auth Documentation](https://firebase.google.com/docs/auth/android/start)
- [Cloud Firestore Quickstart](https://firebase.google.com/docs/firestore/quickstart)
- [Firebase Messaging Android Client](https://firebase.google.com/docs/cloud-messaging/android/client)

---

## 📦 Flutter Packages (pubspec.yaml)

These are managed via `flutter pub get`, but here are the package pages:

### Core Dependencies:
- **[cupertino_icons](https://pub.dev/packages/cupertino_icons)**
- **[firebase_core](https://pub.dev/packages/firebase_core)**
- **[firebase_auth](https://pub.dev/packages/firebase_auth)**
- **[cloud_firestore](https://pub.dev/packages/cloud_firestore)**
- **[google_fonts](https://pub.dev/packages/google_fonts)**
- **[flutter_svg](https://pub.dev/packages/flutter_svg)**
- **[google_maps_flutter](https://pub.dev/packages/google_maps_flutter)**
- **[geolocator](https://pub.dev/packages/geolocator)**
- **[geocoding](https://pub.dev/packages/geocoding)**
- **[firebase_messaging](https://pub.dev/packages/firebase_messaging)**
- **[image_picker](https://pub.dev/packages/image_picker)**

### Dev Dependencies:
- **[flutter_lints](https://pub.dev/packages/flutter_lints)**
- **[flutter_launcher_icons](https://pub.dev/packages/flutter_launcher_icons)**

---

## 🗺️ Google Maps SDK

**Google Maps SDK for Android:**
- Download via Android SDK Manager (recommended)
- Or [Maven Repository](https://repo1.maven.org/maven2/com/google/android/gms/play-services-maps/)

**Note:** Requires Google Play Services on device/emulator

---

## 📥 Quick Download Script

Run this PowerShell command to download Gradle wrapper manually:

```powershell
$gradleVersion = "8.14"
$gradleUrl = "https://services.gradle.org/distributions/gradle-$gradleVersion-all.zip"
$gradleHome = "$env:USERPROFILE\.gradle\wrapper\dists\gradle-$gradleVersion-all"
New-Item -ItemType Directory -Force -Path $gradleHome | Out-Null
Invoke-WebRequest -Uri $gradleUrl -OutFile "$gradleHome\gradle-$gradleVersion-all.zip"
```

---

## ⚠️ Important Notes

1. **Flutter Packages:** Best downloaded via `flutter pub get` (handles version resolution)
2. **Gradle Dependencies:** Usually auto-downloaded, but can be pre-downloaded via `gradlew --refresh-dependencies`
3. **Android SDK Components:** Use Android SDK Manager for proper installation
4. **Firebase:** FlutterFire handles native SDK downloads automatically

---

## 🚀 Recommended Approach

Instead of manual downloads, use these commands:

```powershell
# 1. Download Flutter packages
flutter pub get

# 2. Pre-download Gradle dependencies
cd android
.\gradlew.bat --refresh-dependencies --no-daemon
cd ..

# 3. This will download everything needed
```

Manual downloads are mainly useful for:
- Offline builds
- Troubleshooting network issues
- Pre-caching for multiple projects

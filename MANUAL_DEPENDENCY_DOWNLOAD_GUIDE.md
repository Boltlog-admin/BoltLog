# Manual Dependency Download Guide

This guide explains which dependencies can be pre-downloaded to speed up your Flutter build process.

## 📦 Dependency Categories

### ✅ **CAN BE PRE-DOWNLOADED MANUALLY**

#### 1. **Flutter/Dart Packages** (pubspec.yaml)
**Status:** ✅ Can pre-download  
**Command:** `flutter pub get`  
**Location:** `~/.pub-cache/` (Windows: `%APPDATA%\Pub\Cache\`)

**Your dependencies:**
- `firebase_core: ^4.0.0`
- `firebase_auth: ^6.1.3`
- `cloud_firestore: ^6.0.0`
- `google_fonts: ^7.0.0`
- `flutter_svg: ^2.0.10+1`
- `google_maps_flutter: ^2.8.0`
- `geolocator: ^14.0.2`
- `geocoding: ^4.0.0`
- `firebase_messaging: ^16.1.0`
- `image_picker: ^1.1.2`
- `cupertino_icons: ^1.0.8`

**How to pre-download:**
```powershell
flutter pub get
```

---

#### 2. **Gradle Wrapper**
**Status:** ✅ Can pre-download  
**Version:** 8.14  
**Location:** `%USERPROFILE%\.gradle\wrapper\dists\gradle-8.14-all\`

**How to pre-download:**
```powershell
# Manual download
$gradleUrl = "https://services.gradle.org/distributions/gradle-8.14-all.zip"
$gradleHome = "$env:USERPROFILE\.gradle\wrapper\dists\gradle-8.14-all"
New-Item -ItemType Directory -Force -Path $gradleHome
Invoke-WebRequest -Uri $gradleUrl -OutFile "$gradleHome\gradle-8.14-all.zip"

# Or trigger via Gradle
cd android
.\gradlew.bat --version
```

---

#### 3. **Android Gradle Plugins & Build Tools**
**Status:** ✅ Can pre-download  
**Location:** `%USERPROFILE%\.gradle\caches\` and `%USERPROFILE%\.android\build-cache\`

**Your plugins:**
- `com.android.application:8.11.1`
- `com.google.gms.google-services:4.3.15`
- `org.jetbrains.kotlin.android:2.2.20`
- `com.android.tools.build:gradle:8.11.1`
- `com.android.tools.build:builder:8.11.1`
- `com.android.tools.build:apkzlib:8.11.1`

**How to pre-download:**
```powershell
cd android
.\gradlew.bat --refresh-dependencies --no-daemon
# This downloads all Android build tools and dependencies
```

---

#### 4. **Google Fonts** (Partial)
**Status:** ⚠️ Partially pre-downloadable  
**Note:** Google Fonts are downloaded at runtime, but you can:
- Pre-cache by running the app once
- Manually download fonts from [Google Fonts](https://fonts.google.com/)
- The `google_fonts` package handles this automatically

---

### ⚠️ **AUTOMATICALLY DOWNLOADED DURING BUILD** (Cannot easily pre-download)

#### 1. **Firebase Native SDKs**
**Status:** ⚠️ Auto-downloaded  
**Why:** FlutterFire automatically downloads native Android/iOS SDKs during build  
**Location:** Downloaded by Gradle during build process

**Includes:**
- Firebase Core Android SDK
- Firebase Auth Android SDK
- Cloud Firestore Android SDK
- Firebase Messaging Android SDK

**Note:** These are large (~100-200MB total) and take time to download on first build.

---

#### 2. **Google Maps SDK**
**Status:** ⚠️ Auto-downloaded  
**Why:** `google_maps_flutter` downloads native Android SDK during build  
**Size:** ~50-100MB

---

#### 3. **Plugin Native Dependencies**
**Status:** ⚠️ Auto-downloaded  
**Your plugins that download native code:**
- `geolocator` - Android location services
- `geocoding` - Android geocoding services
- `image_picker` - Android image picker native code
- `firebase_messaging` - FCM native SDK

---

#### 4. **Android SDK Components**
**Status:** ⚠️ Requires Android Studio/SDK Manager  
**Components needed:**
- Android SDK Platform (compileSdk version)
- Android Build Tools
- Android Support Libraries
- Google Play Services

**How to pre-install:**
```powershell
# If you have Android Studio installed:
# Open Android Studio > SDK Manager > Install:
# - Android SDK Platform (latest)
# - Android SDK Build-Tools
# - Google Play Services
```

---

## 🚀 Quick Pre-Download Script

Run the provided script to pre-download what's possible:

```powershell
.\pre_download_dependencies.ps1
```

This script will:
1. ✅ Download all Flutter packages (`flutter pub get`)
2. ✅ Download Gradle wrapper
3. ✅ Pre-download Android Gradle dependencies
4. ℹ️ Provide info on what still needs to download during build

---

## ⏱️ Expected Time Savings

**Before pre-download:**
- First build: 10-15 minutes
- Subsequent builds: 5-8 minutes

**After pre-download:**
- First build: 5-8 minutes (saves 5-7 minutes)
- Subsequent builds: 2-4 minutes (saves 3-4 minutes)

**What still takes time:**
- Native SDK downloads (Firebase, Google Maps) - ~2-3 minutes
- Compilation - ~2-3 minutes
- APK packaging - ~1 minute

---

## 📋 Manual Download Checklist

- [ ] Run `flutter pub get` to download Dart packages
- [ ] Run `cd android && .\gradlew.bat --version` to download Gradle
- [ ] Run `cd android && .\gradlew.bat --refresh-dependencies` to download Android tools
- [ ] Install Android SDK components via Android Studio (if available)
- [ ] Run `flutter build apk --release` (will still download native SDKs, but faster)

---

## 🔍 Where Dependencies Are Stored

| Type | Location |
|------|----------|
| Flutter packages | `%APPDATA%\Pub\Cache\` |
| Gradle wrapper | `%USERPROFILE%\.gradle\wrapper\dists\` |
| Gradle dependencies | `%USERPROFILE%\.gradle\caches\` |
| Android SDK | `%LOCALAPPDATA%\Android\Sdk\` (if Android Studio installed) |
| Build cache | `%USERPROFILE%\.gradle\caches\` |

---

## 💡 Tips

1. **First build is always slowest** - Native SDKs are large and must be downloaded
2. **Use Gradle daemon** - Already enabled in your `gradle.properties`
3. **Enable build cache** - Already enabled in your `gradle.properties`
4. **Subsequent builds are faster** - Dependencies are cached
5. **Network speed matters** - Firebase/Google SDKs are large downloads

---

## 🎯 Summary

**Best approach:**
1. Run `flutter pub get` ✅
2. Run `cd android && .\gradlew.bat --refresh-dependencies` ✅
3. Accept that native SDKs will download during first build ⚠️
4. Subsequent builds will be much faster! 🚀

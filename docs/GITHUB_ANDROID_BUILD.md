# Build Android APK on GitHub

The workflow **[Build Android APK](.github/workflows/build-android.yml)** runs on:

- **Push** / **PR** to `main` or `master` when `lib/`, `android/`, or `pubspec*` change  
- **Manual run**: **Actions** → **Build Android APK** → **Run workflow**

## Download the APK

1. Open the repository on GitHub → **Actions**
2. Open the latest **Build Android APK** run (green check)
3. Scroll to **Artifacts**
4. Download **boltlog-apk** (zip containing `app-release.apk`)

Artifacts are kept for **90 days**.

## Local build (optional)

If your machine fails with Gradle cache errors, rely on this workflow or run:

```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk` (ignored by git).

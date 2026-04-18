# Android APK & iOS builds on GitHub

Binaries are **not** stored in git. They are built in **GitHub Actions** and kept as **Artifacts** on each run.

## When builds run automatically

| Event | Android | iOS |
|--------|---------|-----|
| **Push to `main` / `master`** | Yes — every push | Yes — every push |
| **Pull request** | If `lib/`, `android/`, `assets/`, `pubspec*`, etc. change | Same (plus `ios/`) |
| **Manual** | Actions → **Build Android APK** → **Run workflow** | Actions → **Build iOS archive** → **Run workflow** |

So merging to `main` always produces fresh **boltlog-apk** and **boltlog-ios-archive** artifacts (when the workflows succeed).

## Get the APK (Android)

1. Open the repo on **GitHub** → **Actions**
2. Open workflow **Build Android APK**
3. Open the latest **green** run (or **Run workflow** to start one)
4. Scroll to **Artifacts** → download **`boltlog-apk`** (contains `app-release.apk`)

## Get the iOS archive

1. **Actions** → **Build iOS archive**
2. Latest successful run → **Artifacts** → **`boltlog-ios-archive`**

The CI build uses **`flutter build ipa --release --no-codesign`**. You still need **signing** (Apple Developer) to install on devices or submit to the App Store — use Xcode or Transporter with your certificates/profiles.

## Firestore rules deploy

See **`docs/FIREBASE_CI.md`** — separate workflow **Deploy Firestore rules**.

## Workflows don’t start?

See **`docs/TROUBLESHOOTING_GITHUB_ACTIONS.md`** (enable Actions in Settings, forks, etc.).

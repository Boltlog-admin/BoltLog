# Firebase Storage Image Upload – Analysis Report

**Date:** February 19, 2025  
**Project:** Boltlog Flutter App  
**Issue:** Persistent image upload failures

---

## Executive Summary

This report traces the Firebase Storage image upload flow across three screens, reviews configuration and rules, and lists likely causes of upload failures with concrete fixes.

---

## 1. Upload Flow Trace

### 1.1 Signup Screen (`signup_screen.dart`)

**Flow:**
1. User creates account via `createUserWithEmailAndPassword`
2. `getIdToken(true)` + 2-second delay before uploads
3. Images compressed via `ImageService.compressImage()`
4. `StorageService.putDataWithRetry()` for car book, driver license, and selfie
5. Paths: `drivers/{userId}/car_book.jpg`, `driver_license.jpg`, `selfie.jpg`

**Data source:** Uses `Uint8List` from `image.readAsBytes()` and saves to temp dir. Uses bytes for upload (avoids file path issues).

### 1.2 Driver Completion Screen (`driver_completion_screen.dart`)

**Flow:**
1. User already logged in (`FirebaseAuth.instance.currentUser`)
2. `getIdToken(true)` + 2-second delay
3. Uses `_carBookImageBytes` / `_driverLicenseImageBytes` / `_selfieImageBytes` (or reads from file)
4. `StorageService.putDataWithRetry()` with compressed bytes
5. Same paths as signup

**Data source:** Uses `Uint8List` from `image.readAsBytes()` and temp file. Uses bytes for upload.

### 1.3 Driver Account Edit Screen (`driver_account_edit_screen.dart`)

**Flow:**
1. User already logged in
2. `getIdToken(true)` only (no delay)
3. Uses `StorageService.putFileWithRetry()` with `File(image.path)`
4. Same paths as above

**Data source:** Uses `File(image.path)` directly. This is the main risk area.

---

## 2. Configuration Review

### 2.1 `storage_service.dart`

- Uses `FirebaseStorage.instance` (default bucket)
- Retries on permission/403/unauthorized/unauthenticated/unknown
- Up to 3 attempts with `getIdToken(true)` between retries
- Two methods: `putDataWithRetry` (bytes) and `putFileWithRetry` (file)

### 2.2 `storage.rules`

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /{allPaths=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

- Syntax is correct
- Allows any authenticated user to read/write
- Must be deployed to Firebase (see Section 5)

### 2.3 `firebase_options.dart`

- `storageBucket: 'boltlog.firebasestorage.app'` for all platforms
- `projectId: 'boltlog'`
- Android app ID: `1:28158895372:android:7da1f25f88abc96b719529` (com.boltlog.app)

### 2.4 `google-services.json`

- `storage_bucket: "boltlog.firebasestorage.app"`
- `project_id: "boltlog"`
- Client for `com.boltlog.app` present

### 2.5 `main.dart`

- `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`
- No explicit Storage init; Storage uses default app
- Firestore, Messaging, Crashlytics initialized

---

## 3. Root Causes Identified

### 3.1 HIGH: `driver_account_edit_screen` – File path on Android

**Issue:** Uses `File(image.path)` with `putFileWithRetry`. On Android 10+, `image_picker` often returns `content://` URIs. `File` does not support `content://` URIs, so `putFile()` can fail with file-not-found or similar errors.

**Evidence:** Flutter/Dart issues and docs note that `File` does not support `content://` URIs.

**Fix:** Use `image.readAsBytes()` and `putDataWithRetry` instead of `putFileWithRetry`, same pattern as signup and driver completion screens.

---

### 3.2 HIGH: Storage rules not deployed

**Issue:** Rules in `storage.rules` must be deployed to Firebase. If not deployed, the default rules (often deny-all) apply, causing `storage/unauthorized` or `storage/unauthenticated`.

**Fix:** Deploy rules via Firebase CLI or Console (see Section 5).

---

### 3.3 MEDIUM: Auth token propagation timing (signup)

**Issue:** Right after `createUserWithEmailAndPassword`, the new user’s token may not be fully propagated to Storage. A 2-second delay may be insufficient on slow networks or busy servers.

**Fix:** Increase delay or use a more robust wait (e.g., retry with backoff, or wait for auth state).

---

### 3.4 MEDIUM: No explicit Storage bucket

**Issue:** `FirebaseStorage.instance` uses the default bucket. If `storageBucket` is missing or wrong in config, you can get `storage/no-default-bucket` or `storage/bucket-not-found`.

**Status:** `firebase_options.dart` and `google-services.json` both set `boltlog.firebasestorage.app`. Likely OK, but worth verifying in Firebase Console.

---

### 3.5 LOW: `driver_account_edit_screen` – No bytes fallback

**Issue:** Unlike signup and driver completion, this screen does not store bytes and relies on `File`. If the file path is invalid, there is no fallback.

**Fix:** Align with signup/driver completion: read bytes immediately and use `putDataWithRetry`.

---

### 3.6 LOW: Error visibility

**Issue:** Errors are logged and shown in SnackBars, but `FirebaseException.code` is not always surfaced. This makes it harder to distinguish `storage/unauthenticated` vs `storage/unauthorized` vs network issues.

**Fix:** Log and optionally display `FirebaseException.code` and `message`.

---

## 4. Step-by-Step Fixes

### Fix 1: Align `driver_account_edit_screen` with bytes-based upload

**Goal:** Avoid `content://` and path issues by using bytes and `putDataWithRetry`.

1. Add `Uint8List?` fields for each image type.
2. In `_showImageSourceDialog`, after picking an image:
   - Call `image.readAsBytes()`
   - Save bytes to temp file
   - Store bytes in state
   - Pass both file and bytes to `onImageSelected`.
3. In `_saveChanges`, for each new image:
   - Use stored bytes (or read from file if bytes missing)
   - Compress with `ImageService.compressImage()`
   - Call `StorageService.putDataWithRetry()` instead of `putFileWithRetry()`.

---

### Fix 2: Deploy Storage rules

**Option A – Firebase CLI:**
```powershell
firebase login
firebase deploy --only storage
```

**Option B – Firebase Console:**
1. Open [Firebase Console Storage Rules](https://console.firebase.google.com/project/boltlog/storage/boltlog.firebasestorage.app/rules)
2. Paste contents of `storage.rules`
3. Click **Publish**

---

### Fix 3: Improve auth timing on signup

In `signup_screen.dart`, before uploads:

```dart
// Replace the current 2-second delay with:
await userCredential.user?.getIdToken(true);
// Wait for auth to propagate (increase if needed)
await Future.delayed(const Duration(seconds: 3));
```

Or add a retry loop that waits and retries until upload succeeds or max attempts reached.

---

### Fix 4: Add structured error logging

In `StorageService` and/or screens, when catching upload errors:

```dart
} on FirebaseException catch (e) {
  debugPrint('Storage error: code=${e.code}, message=${e.message}');
  // Optionally: FirebaseCrashlytics.instance.recordError(e, stackTrace);
  rethrow;
}
```

Use this to confirm whether failures are `storage/unauthenticated`, `storage/unauthorized`, or something else.

---

### Fix 5: Verify bucket and project in Firebase Console

1. Firebase Console → Project Settings → General
2. Confirm default Storage bucket is `boltlog.firebasestorage.app`
3. Storage → Rules tab: confirm rules match `storage.rules` and are published

---

## 5. Verification Steps

### 5.1 Rules deployment

1. Firebase Console → Storage → Rules
2. Confirm rules match `storage.rules`
3. Check “Last published” timestamp

### 5.2 Signup flow (Driver)

1. Create a new driver account with all three images
2. Watch debug console for:
   - `Car book image uploaded successfully`
   - `Driver license image uploaded successfully`
   - `Selfie image uploaded successfully`
3. If errors appear, note `FirebaseException.code` and `message`

### 5.3 Driver completion flow

1. Log in as a passenger, switch to driver, complete profile with images
2. Confirm uploads succeed and profile is saved

### 5.4 Driver account edit flow

1. Log in as driver, open Edit Account
2. Change one or more images
3. Save and confirm uploads succeed

### 5.5 Firebase Console

1. Storage → Files
2. Confirm `drivers/{userId}/` folders and files appear after successful uploads

---

## 6. Summary Table

| Cause                         | Severity | Screen(s) affected | Fix priority |
|------------------------------|----------|--------------------|--------------|
| File path / content://       | HIGH     | driver_account_edit| 1            |
| Rules not deployed           | HIGH     | All                | 1            |
| Auth token timing            | MEDIUM   | signup             | 2            |
| Bucket/config mismatch       | MEDIUM   | All                | 2            |
| No bytes fallback            | LOW      | driver_account_edit| 3            |
| Error visibility             | LOW      | All                | 3            |

---

## 7. Recommended Implementation Order

1. Deploy Storage rules (Fix 2)
2. Update `driver_account_edit_screen` to use bytes (Fix 1)
3. Add error logging (Fix 4)
4. Test all three flows
5. If signup still fails, apply auth timing fix (Fix 3)
6. Verify bucket and project config (Fix 5)

---

## 8. References

- [Firebase Storage Flutter – Handle errors](https://firebase.google.com/docs/storage/flutter/handle-errors)
- [Firebase Storage Flutter – Upload files](https://firebase.google.com/docs/storage/flutter/upload-files)
- [Firebase Storage security rules](https://firebase.google.com/docs/storage/security)
- [Flutter content:// URI issue](https://github.com/flutter/flutter/issues/147037)

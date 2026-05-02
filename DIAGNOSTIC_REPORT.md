# Boltlog App – Diagnostic Report

**Generated:** February 2025  
**Purpose:** Verify configuration and identify potential issues

---

## 1. Firebase Configuration

| Item | Status | Details |
|------|--------|---------|
| **Project ID** | OK | `boltlog` |
| **Storage Bucket** | OK | `boltlog.firebasestorage.app` (matches firebase_options.dart & google-services.json) |
| **Android App ID** | OK | `1:28158895372:android:7da1f25f88abc96b719529` |
| **Package Name** | OK | `com.boltlog.app` (matches build.gradle.kts & google-services.json) |
| **google-services.json** | OK | Present, first client uses `com.boltlog.app` |

---

## 2. Storage Rules

| Check | Status |
|-------|--------|
| **drivers/{pathKey}/{fileName}** | OK – `canAccess(pathKey)` checks email or uid_ |
| **senders/{pathKey}/{fileName}** | OK – `canAccess(pathKey)` |
| **sanitizeEmail** | Matches app: `split('@').join('_at_').split('.').join('_')` |
| **Deployed** | Confirm with `npx firebase-tools deploy --only storage` |

**Path format:** `drivers/{emailKey}/car_book.jpg` e.g. `drivers/admin_at_boltlog_org/car_book.jpg`

---

## 3. Image Upload Flow

| Component | Status |
|-----------|--------|
| **StorageService** | 2s initial delay + 6 retries for getDownloadURL |
| **Bucket fallback** | Tries default → boltlog.firebasestorage.app → boltlog.appspot.com |
| **putFile fallback** | Uses temp file if putData fails |
| **Parallel uploads** | Signup & driver completion upload 3 images in parallel |
| **Path key** | Uses `storagePathKey(email, uid)` – email-based for sorting |

---

## 4. Known Issues (Flutter Analyze)

- **215 issues** – mostly warnings (unused imports, unnecessary casts, dead code)
- **No critical errors** – app should build and run
- Consider cleaning: `ecocash_service.dart`, `payment_service.dart`, `ride_service.dart`, `routing_service.dart`, `wallet_service.dart`

---

## 5. Image Upload Troubleshooting

If "no object exists at the desired reference" persists:

1. **Check Firebase Console → Storage → Files**  
   - Confirm bucket is `boltlog.firebasestorage.app`  
   - Check if any files appear after upload (upload may succeed but getDownloadURL fail)

2. **Run with debug logging:**
   ```cmd
   flutter run
   ```
   Look for: `StorageService getDownloadURL attempt X/6 failed (propagation), retrying...`

3. **Verify rules deployed:**
   ```cmd
   npx firebase-tools deploy --only storage
   ```

4. **Test with permissive rules (temporary):**  
   In Firebase Console → Storage → Rules, temporarily use:
   ```
   allow read, write: if request.auth != null;
   ```
   If uploads work, the issue is likely pathKey/email matching in the current rules.

5. **Email casing:**  
   Firebase Auth typically stores emails in lowercase. If the app receives mixed-case email, the pathKey might not match. Consider adding `.toLowerCase()` to `sanitizeEmailForStorage` and a matching rule (Firebase rules may not support toLowerCase – verify).

---

## 6. Quick Health Check Commands

```cmd
# Verify dependencies
flutter pub get

# Static analysis
flutter analyze

# Build APK
flutter build apk

# Deploy storage rules
npx firebase-tools deploy --only storage

# Deploy Firestore rules
npx firebase-tools deploy --only firestore
```

---

## 7. Summary

| Area | Status |
|------|--------|
| Firebase config | OK |
| Storage rules | OK (deploy to confirm) |
| Upload flow | OK (retries + parallel) |
| Code quality | 215 warnings, no blocking errors |
| APK build | Working |

**Recommendation:** If image uploads still fail, run `flutter run` and capture the full error + `StorageService` logs when the failure occurs. Check Firebase Console → Storage to see if files are created even when the app reports failure.

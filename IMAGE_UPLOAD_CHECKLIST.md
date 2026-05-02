# Image Upload Failure – Checklist

Use this checklist to track down why image uploads fail.

---

## 1. Firebase Console

| Check | Where | Action |
|-------|-------|--------|
| **Storage enabled** | Firebase Console → Storage | Storage must be enabled and a bucket must exist |
| **Rules published** | Storage → Rules tab | Rules must be saved and published (not just edited) |
| **Bucket name** | Storage → Files | Should be `boltlog.firebasestorage.app` |
| **Billing** | Project Settings → Usage and billing | Some regions may require Blaze plan |

---

## 2. Storage Rules

Rules must allow:

- `request.auth != null` (user signed in)
- `request.auth.uid == userId` (path matches user)
- `request.resource.size < 10MB`
- `request.resource.contentType` is `image/*` or null

**Path:** `drivers/{userId}/{fileName}`  
**Example:** `drivers/abc123xyz/car_book.jpg`

---

## 3. Auth State

| Flow | When upload happens | Auth source |
|------|---------------------|-------------|
| **Email signup (Driver)** | Right after `createUserWithEmailAndPassword` | New user, token may need time |
| **Google Sign-In (Driver)** | On DriverCompletionScreen after sign-in | Google credential |
| **Account edit** | When editing profile | Existing session |

**Checks:**

- User must be signed in before upload
- `FirebaseAuth.instance.currentUser` must not be null
- Token refresh (`getIdToken(true)`) runs before upload

---

## 4. App Configuration

| Item | Expected | Location |
|------|----------|----------|
| **storageBucket** | `boltlog.firebasestorage.app` | `firebase_options.dart` |
| **applicationId** | `com.boltlog.app` | `android/app/build.gradle.kts` |
| **appId in firebase_options** | `1:28158895372:android:7da1f25f88abc96b719529` | Must match com.boltlog.app in google-services.json |
| **Package in google-services.json** | `com.boltlog.app` | `android/app/google-services.json` |

**Important:** If `firebase_options.dart` uses the appId for `com.example.boltlog` instead of `com.boltlog.app`, Firebase Auth and Storage can fail. Run `flutterfire configure` to fix, or ensure the appId matches your app's package.

---

## 5. Network & Device

| Check | Notes |
|-------|-------|
| **Internet** | Device must have working internet |
| **Firewall / VPN** | May block Firebase |
| **Emulator** | Some Storage issues only on emulator; test on real device |

---

## 6. File & Metadata

| Check | Limit / Value |
|-------|----------------|
| **File size** | Under 10MB (rules and `AppConstants.maxImageSizeBytes`) |
| **Content type** | `image/jpeg` in `SettableMetadata` |
| **Path** | `drivers/{uid}/car_book.jpg`, `driver_license.jpg`, `selfie.jpg` |

---

## 7. Common Error Codes

| Code | Meaning | Fix |
|------|---------|-----|
| `storage/unauthorized` | Rules deny the request | Check rules and auth |
| `storage/unauthenticated` | No auth token | Ensure user is signed in |
| `storage/unknown` | Generic / server error | Retry, check network, try real device |
| `storage/object-not-found` | Wrong path or bucket | Check path and bucket |
| `storage/bucket-not-found` | Bucket missing | Enable Storage and create bucket |

---

## 8. Debug Steps

1. **Exact error** – Use the app’s error message (including “Details:”) to identify the code.
2. **Rules Playground** – Simulate a **create** with **Authenticated: ON** and the correct path.
3. **Real device** – Test on a physical device, not only emulator.
4. **Fresh sign-in** – Sign out, sign in again, then try upload.
5. **Different flow** – Try both email signup and Google Sign-In to see if one works.

---

## 9. Temporary Test Rule (Debug Only)

To see if rules are the problem, you can temporarily relax them:

```
// TEMPORARY - for debugging only. Remove after testing.
match /drivers/{userId}/{fileName} {
  allow read, write: if request.auth != null;
}
```

If uploads work with this rule, the issue is likely in your stricter conditions (e.g. `userId`, size, or `contentType`). Revert to the secure rules after testing.

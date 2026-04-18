# Image Upload Fix Summary

## Latest Changes (Feb 2025)

- **Path-only upload**: Upload saves storage path (e.g. `drivers/uid_xxx/car_book.jpg`) instead of calling getDownloadURL. Avoids "object not found" - URL is fetched when displaying.
- **StorageImage / StorageAvatar**: New widgets in `lib/widgets/storage_image.dart` - handle both full URLs and paths. When path, fetch URL on display.
- **putDataReturnPath**: New method - uploads file and returns path only. Used for signup, driver completion, and account edit.
- **Storage rules**: Permissive (any authenticated user). Deploy: `npx firebase-tools deploy --only storage`
- **Speed**: Parallel compress + parallel upload for all 3 images; 2s signup pre-delay.
- **putData** with bucket fallback; putFile as fallback if putData fails.
- **User error message**: When this error occurs, the app now shows "Storage is still processing. Please try again in a moment." instead of "Image files could not be found" (which was misleading).
- **StorageService**: Tries default, `boltlog.firebasestorage.app`, then `boltlog.appspot.com`
- **putFile fallback**: If putData fails, tries putFile with temp file (better on some Android devices)
- **StorageUploadException**: Error now shows `[code] message` (e.g. `[storage/unauthorized] User does not have permission`)
- **Signup delay**: 4 seconds after token refresh before uploads

**To debug:** Run `flutter run` and watch the console when uploading. Look for:
`StorageService putData bucket=... attempt 1/3 path=... code=... msg=...`

**Verify bucket:** Firebase Console → Storage → Files. Check the bucket name at the top (e.g. `boltlog.firebasestorage.app` or `boltlog.appspot.com`).

---

## Changes Made

### 1. Storage Rules (storage.rules)
- **drivers/{userId}/** – transporter documents (car_book.jpg, driver_license.jpg, selfie.jpg)
- **senders/{userId}/** – client documents (profile, ID, etc.)
- Each user can only read/write their own folder (`request.auth.uid == userId`)
- Deploy: `npx firebase-tools deploy --only storage`

### 2. StorageService (lib/services/storage_service.dart)
- **Explicit bucket**: Uses `FirebaseStorage.instanceFor(app, bucket)` with the bucket from Firebase options
- **Error logging**: Logs `code` and `message` on each failed attempt (check debug console / `flutter run` output)

### 3. Driver Account Edit Screen (lib/screens/driver_account_edit_screen.dart)
- **Fixed callback**: `onImageSelected(null)` → `onImageSelected(null, null)` when clearing an image

---

## Critical: Deploy Storage Rules

```cmd
npx firebase-tools deploy --only storage
```

Or via Firebase Console: Storage → Rules → paste from `storage.rules` → Publish

---

## If Uploads Still Fail

1. **Deploy storage rules** (often the cause):
   ```cmd
   npx firebase-tools deploy --only storage
   ```

2. **Run the app with `flutter run`** and watch the debug console when you try to upload
3. Look for lines like: `StorageService putFile attempt 1/3 path=...` or `putData attempt...`
4. **Error codes**:
   - `storage/unauthenticated` → User not signed in or token invalid. Try sign out + sign in again
   - `storage/unauthorized` or `storage/canceled` → Rules not deployed or network issue
   - `storage/object-not-found` → Propagation delay (retries should help) or rules rejecting path

5. **Try temporary permissive rules** (to test if rules are the issue):
   - Copy `storage.rules.debug` content over `storage.rules`
   - Run `npx firebase-tools deploy --only storage`
   - Test uploads. If they work, the issue is path matching in rules. Revert to normal rules.

6. **Verify in Firebase Console**:
   - Storage → Files: confirm bucket is `boltlog.firebasestorage.app`
   - Storage → Rules: confirm rules are published (not just saved)

---

## Storage Folder Structure

Organized by signup email for easy sorting in Firebase Console.

| Folder   | Purpose                    | Example paths                                      |
|----------|----------------------------|----------------------------------------------------|
| drivers/ | Transporter documents      | `drivers/admin_at_boltlog_org/car_book.jpg`, etc. |
| senders/ | Client documents           | `senders/john_at_gmail_com/profile.jpg` (when added) |
| Fallback | Phone auth (no email)      | `drivers/uid_{userId}/...`                         |

---

## Outcome

**Current status:** Image uploads still failing for some users.

**What was tried:**
- Path-only upload (skip getDownloadURL during upload)
- Permissive storage rules (allow all authenticated users)
- putFile as primary on Android
- Sequential uploads
- Longer auth delays before upload
- StorageImage/StorageAvatar for path-to-URL on display

**Verified:**
- Firebase Storage bucket: `boltlog.firebasestorage.app` ✓
- Storage rules: Simulated write allowed in Playground ✓
- drivers/ folder exists in Storage ✓

**Cloud Function fallback:** When REST API and SDK both fail, tries `uploadDriverImage` Cloud Function. Uses Admin SDK server-side – bypasses all client auth/Storage rules.

**To deploy the Cloud Function:**
```cmd
cd functions
npm install
cd ..
npx firebase-tools deploy --only functions
```

**Upload order:** 1) REST API, 2) SDK (putFile/putData), 3) Cloud Function
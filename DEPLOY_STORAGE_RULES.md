# Deploy Firebase Storage Rules

## Quick Deploy (After Login)

Once you're logged into Firebase, run:
```powershell
firebase deploy --only storage
```

## Step-by-Step Instructions

### Option 1: Using Firebase CLI (Recommended)

1. **Login to Firebase:**
   ```powershell
   firebase login
   ```
   - This will open a browser window
   - Sign in with your Google account that has access to the `boltlog` project
   - Return to the terminal when done

2. **Deploy the rules:**
   ```powershell
   firebase deploy --only storage
   ```

3. **Verify deployment:**
   - Go to [Firebase Console](https://console.firebase.google.com/)
   - Select project: **boltlog**
   - Navigate to **Storage** → **Rules** tab
   - You should see the deployed rules

### Option 2: Manual Deployment via Firebase Console

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: **boltlog**
3. Click on **Storage** in the left sidebar
4. Click on the **Rules** tab
5. Copy the entire contents of `storage.rules` file
6. Paste into the rules editor
7. Click **Publish**

## What the Rules Do (Current - Debug Mode)

The storage rules currently allow:
- ✅ Any authenticated user to read/write anywhere (for debugging upload issues)
- ⚠️ **Tighten rules** after uploads work: restrict to `drivers/{userId}/` and add size/contentType checks

## Files Created

- `storage.rules` - The security rules file
- `.firebaserc` - Firebase project configuration
- `firebase.json` - Updated with storage rules reference

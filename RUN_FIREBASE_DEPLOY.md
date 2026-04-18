# How to Deploy Firebase Storage Rules

## Where to Run the Commands

**Location:** Open PowerShell or Command Prompt in this directory:
```
C:\Users\ZETDC\Desktop\Boltlog\boltlog
```

## Step-by-Step Instructions

### Step 1: Open Terminal
- **Option A:** Right-click in the `boltlog` folder → "Open in Terminal" or "Open PowerShell window here"
- **Option B:** Open PowerShell/CMD and run:
  ```powershell
  cd C:\Users\ZETDC\Desktop\Boltlog\boltlog
  ```

### Step 2: Login to Firebase
Run this command:
```powershell
firebase login
```

**What happens:**
- A browser window will open
- Sign in with your Google account (the one with access to the "boltlog" Firebase project)
- Return to the terminal when it says "Success! Logged in as..."

### Step 3: Deploy Storage Rules
After logging in, run:
```powershell
firebase deploy --only storage
```

**What happens:**
- The rules will be uploaded to Firebase
- You'll see "Deploy complete!" when done

## Quick Copy-Paste Commands

Copy and paste these one at a time:

```powershell
firebase login
```

(Wait for browser login, then run:)

```powershell
firebase deploy --only storage
```

## Alternative: Use the HTML Helper

If you prefer not to use the command line:
1. Open `deploy_rules_helper.html` in your browser
2. Click "Copy Rules to Clipboard"
3. Go to [Firebase Console](https://console.firebase.google.com/project/boltlog/storage/boltlog.firebasestorage.app/rules)
4. Paste and click "Publish"

---

**Current Directory:** `C:\Users\ZETDC\Desktop\Boltlog\boltlog`

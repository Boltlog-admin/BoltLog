# Fix Firebase Authentication Error

## The Problem
Your Firebase credentials expired. You need to re-authenticate.

## Solution: Run This Command

In your PowerShell terminal (where you saw the error), run:

```powershell
firebase login --reauth
```

## What Will Happen

1. **A browser window will open automatically**
2. **Sign in with your Google account** (the one with access to the "boltlog" Firebase project)
3. **Click "Allow"** to grant Firebase CLI access
4. **Return to the terminal** - you'll see "Success! Logged in as [your-email]"

## After Re-authentication

Once you're logged in, run the deploy command again:

```powershell
firebase deploy --only storage
```

## Full Command Sequence

```powershell
# Step 1: Re-authenticate
firebase login --reauth

# Step 2: Wait for browser login to complete

# Step 3: Deploy storage rules
firebase deploy --only storage
```

## If Browser Doesn't Open

If the browser doesn't open automatically:
1. The terminal will show a URL
2. Copy that URL
3. Paste it into your browser
4. Complete the login
5. Return to terminal

---

**Note:** Make sure you're logged into the correct Google account that has access to the "boltlog" Firebase project.

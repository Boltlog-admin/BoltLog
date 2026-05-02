# Fix: Firebase Storage 412 – "Service account missing necessary permissions"

Your app logs show:
```text
REST upload failed: 412
"A required service account is missing necessary permissions. Please resolve by visiting 
the Storage page of the Firebase Console and re-linking your Firebase bucket..."
```

Follow these steps to fix it.

---

## Fix via command line (recommended if Console asks for org access)

If the Google Cloud Console keeps asking for "organization" or "Principal Access Boundary" access, use **gcloud** in CMD or PowerShell instead. This applies the permission at **project** level and often works without org-level rights.

**1. Install Google Cloud SDK** (if not already):

- Download: https://cloud.google.com/sdk/docs/install  
- Or with Chocolatey: `choco install gcloudsdk`

**2. Log in and set project:**

```bash
gcloud auth login
gcloud config set project boltlog
```

**3. Grant the Firebase Storage service account the right role (project-level):**

```bash
gcloud projects add-iam-policy-binding boltlog --member="serviceAccount:firebase-storage@boltlog.iam.gserviceaccount.com" --role="roles/storage.objectAdmin"
```

If that fails (e.g. service account not found), try granting on the **bucket** directly:

```bash
gcloud storage buckets add-iam-policy-binding gs://boltlog.firebasestorage.app --member="serviceAccount:firebase-storage@boltlog.iam.gserviceaccount.com" --role="roles/storage.objectAdmin"
```

**4. Wait 1–2 minutes, then try uploading again from the app.**

**5. If uploads still fail with 412, grant the Firebase Storage service agent on the bucket:**

Your project uses the Firebase Storage service agent. Grant it Storage Object Admin on the bucket:

```bash
gcloud storage buckets add-iam-policy-binding gs://boltlog.firebasestorage.app --member="serviceAccount:service-28158895372@gcp-sa-firebasestorage.iam.gserviceaccount.com" --role="roles/storage.objectAdmin"
```

(Replace `28158895372` with your project number if different – run `gcloud projects describe boltlog --format="value(projectNumber)"` to get it.)

**6. If 412 persists, grant Storage Admin (full) on the bucket to the same service agent:**

Some projects need the stronger `storage.admin` role on the bucket:

```bash
gcloud storage buckets add-iam-policy-binding gs://boltlog.firebasestorage.app --member="serviceAccount:service-28158895372@gcp-sa-firebasestorage.iam.gserviceaccount.com" --role="roles/storage.admin"
```

**7. Enable billing and deploy the upload Cloud Function (reliable workaround):**  
Cloud Functions need an **active** billing account (not just linked). Your project is linked to an account but it shows `billingEnabled: false`, so deploy will keep failing with 403 until the account is active.

- **Activate billing:** Go to [Billing](https://console.cloud.google.com/billing), open the billing account linked to **boltlog**, and ensure it is **open/active** (add a payment method if required).
- **Create App Engine (required for 1st-gen functions):**  
  In **Google Cloud SDK Shell** (or CMD with gcloud on PATH), run once billing is active:
  ```bash
  gcloud app create --region=us-central
  ```
- **Deploy functions:**  
  ```bash
  cd C:\Users\ZETDC\Desktop\Boltlog\boltlog
  npx firebase-tools deploy --only functions
  ```

```bash
cd C:\Users\ZETDC\Desktop\Boltlog\boltlog
npx firebase-tools deploy --only functions
```

Then the app will use the `uploadDriverImage` function when the SDK gets 412, and uploads will work.

---

## Step 1: Open your Firebase project

1. Go to **[Firebase Console](https://console.firebase.google.com/)** and sign in.
2. Select project **boltlog**.

---

## Step 2: Check Storage and bucket

1. In the left menu, click **Build → Storage**.
2. If you see a message like **"Get started"** or **"Secure your files"**, finish the Storage setup (choose a location, accept defaults).
3. If Storage is already set up, note the **bucket name** (e.g. `boltlog.firebasestorage.app`).

---

## Step 3: Fix permissions in Google Cloud Console

The 412 usually means the **default Firebase Storage service account** does not have the right role on the bucket.

1. Open **[Google Cloud Console](https://console.cloud.google.com/)** and select project **boltlog** (top bar).
2. Go to **IAM & Admin → [IAM](https://console.cloud.google.com/iam-admin/iam)**.
3. In the list, find the principal that looks like:
   - `firebase-storage@boltlog.iam.gserviceaccount.com`
   - or **Firebase Storage** in the "Name" column.
4. Click the **pencil (Edit)** for that principal.
5. Click **+ ADD ANOTHER ROLE** and add:
   - **Storage Object Admin**  
   (or at least **Storage Object Creator** and **Storage Object Viewer**).
6. Save.

If you don’t see that service account:

- Go to **IAM & Admin → [Service accounts](https://console.cloud.google.com/iam-admin/serviceaccounts)**.
- Look for **Firebase Storage** or `firebase-storage@...`.
- If it’s missing, go back to **Firebase Console → Storage**, (re)start Storage setup so the bucket and service account are created/linked.

---

## Step 4: Re-link bucket (if the console offers it)

1. In **Firebase Console**, go to **Build → Storage**.
2. Open the **three-dots menu** or **Settings** for the default bucket.
3. If you see an option like **"Re-link bucket"** or **"Fix bucket"**, use it and follow the prompts.

---

## Step 5: Wait and test

- Permission changes can take a few minutes to apply.
- In your app, try again: sign up as driver and upload **Car book** / **Driver license** / **Selfie**.
- Watch the device log for `StorageService` messages; 412 should disappear once permissions are correct.

---

## Optional: Cloud Function fallback

The log also shows:
```text
StorageService Cloud Function fallback failed: [firebase_functions/not-found] NOT_FOUND
```

That means the **uploadDriverImage** Cloud Function is not deployed. It’s only used as a fallback when the SDK/REST upload fails. Fixing the 412 (Steps 1–4) is enough for uploads to work; you don’t have to deploy the function unless you want that fallback.

---

## Summary

| Issue              | Fix |
|--------------------|-----|
| **412 – service account permissions** | Google Cloud Console → IAM → give `firebase-storage@boltlog.iam.gserviceaccount.com` (or Firebase Storage SA) role **Storage Object Admin** on the project/bucket. |
| **Cloud Function NOT_FOUND**          | Optional: deploy the `uploadDriverImage` function. Not required if 412 is fixed. |

After fixing the service account permissions and re-testing uploads, image upload and loading should work.

# Deploy Cloud Functions via GitHub Actions

The workflow **Deploy Cloud Functions** (`.github/workflows/deploy-functions.yml`) runs on:

- **Push** to `main` or `master` when `functions/`, `firebase.json`, or `.firebaserc` change
- **Manual run**: Actions → Deploy Cloud Functions → Run workflow

## 1. GitHub secret (required)

Add **FIREBASE_TOKEN** so the workflow can deploy:

1. Repo **Settings** → **Secrets and variables** → **Actions**
2. **New repository secret**: name `FIREBASE_TOKEN`
3. Value: run the **setup script** (or the command below) and paste the token:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\setup-github-secrets.ps1
   ```
   Or: `npx firebase login:ci` → copy the printed token into the secret.

You can use the same **FIREBASE_TOKEN** as for the “Deploy Firestore rules” workflow.

## 2. Optional: automatic GCP IAM fix (recommended)

If you add **GCP_SA_KEY**, the workflow will **automatically** apply the required Cloud Build permissions before each deploy, so you don’t need to run the fix script locally.

1. In Google Cloud Console: **IAM & Admin** → **Service Accounts** → **Create** (e.g. name `github-actions-functions`).
2. Grant this service account **Project IAM Admin** (or **Owner**) on the **boltlog** project so it can add IAM bindings.
3. Create a **JSON key** for the service account and download it.
4. In GitHub: **Settings** → **Secrets and variables** → **Actions** → **New repository secret**: name `GCP_SA_KEY`, value = entire contents of the JSON key file.

The workflow will then run `gcloud projects add-iam-policy-binding` for Storage Object Viewer, Artifact Registry Writer, Logs Writer, and Cloud Run Builder before every deploy.

## 3. One-time GCP IAM (if you don’t use GCP_SA_KEY)

The first time you deploy Cloud Functions (from GitHub or locally), the GCP project **boltlog** must have the right permissions for Cloud Build. Otherwise you get “Build error details not available” or “Access to bucket … denied”.

**Option A – Automatic (recommended, from a machine with gcloud):**

From the repo root, run:

```powershell
# Windows (PowerShell)
.\scripts\fix-and-deploy-functions.ps1
```

This script will:

- Find or install the Google Cloud SDK and prompt for `gcloud auth login` if needed
- Grant **Storage Object Viewer** to the Compute and Cloud Build service accounts
- Grant **Artifact Registry Writer**, **Logs Writer**, and **Cloud Run Builder** to the Cloud Build service account
- Optionally reset the artifacts bucket and run a deploy

You only need to run it **once** per project (or after changing project/region). After that, GitHub Actions can deploy with only **FIREBASE_TOKEN**.

**Option B – Manual (Google Cloud Console):**

In [IAM](https://console.cloud.google.com/iam-admin/iam?project=boltlog), ensure these principals have the listed roles:

| Principal | Role |
|-----------|------|
| `28158895372-compute@developer.gserviceaccount.com` | Storage Object Viewer |
| `28158895372@cloudbuild.gserviceaccount.com` | Storage Object Viewer, Artifact Registry Writer, Logs Writer, Cloud Run Builder |

## 4. After setup

- Push changes to `functions/` (or `firebase.json` / `.firebaserc`) on `main`/`master` to trigger a deploy.
- Or run **Actions** → **Deploy Cloud Functions** → **Run workflow** manually.

If the build fails, see **functions/DEPLOY_TROUBLESHOOTING.md** for logs and artifact-bucket reset.

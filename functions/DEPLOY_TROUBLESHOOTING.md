# Cloud Functions deploy troubleshooting

## "Precondition failed" / `Cannot update a GCF function without sourceUrl`

**What it means:** The Firebase CLI decided your **source hash** matches what is already deployed (`firebase-functions-hash` on the function), so it **skipped uploading** the zip. It still tried to **PATCH** the function, and the Cloud Functions API rejects that update **without** a new `sourceUploadUrl` — hence *Precondition failed*.

**Fix (pick one):**

1. **Change the source hash** — e.g. bump `boltlog.deployStamp` in `functions/package.json`, or make any small edit under `functions/`, commit, redeploy.
2. **Use Node 20** for the CLI (matches `engines.node` and avoids odd CLI behavior): in Cloud Shell, `nvm install 20 && nvm use 20`, then `npm ci --prefix functions` and deploy again.
3. Use a **current** `firebase-tools` (e.g. `npx firebase-tools@15 deploy ...`).

---

# Cloud Functions deploy: "Build error details not available"

**Deploying via GitHub:** See [.github/DEPLOY_FUNCTIONS_SETUP.md](../../.github/DEPLOY_FUNCTIONS_SETUP.md) for secrets and one-time GCP IAM. The same IAM and troubleshooting below apply to both local and GitHub deploys.

## 1. Get the real error (required)

The Firebase CLI hides the actual build error. You must open the **Cloud Build** log:

1. When deploy fails, copy the log URL from the error (e.g.  
   `https://console.cloud.google.com/cloud-build/builds;region=us-central1/XXXX?project=28158895372`).
2. Open it in your browser (signed in as **admin@boltlog.org**).
3. On the **build detail page**, use the **“Build log”** or **“Logs”** section **on that same page** (the stepper with each step’s log). Do **not** use “View in Logs Explorer” / Cloud Logging for the first look—build step logs often show up only in the Build UI.
4. If you see **“No logs were found for this build or step”**:
   - **Permission:** Your account needs to view logs. In **IAM** (https://console.cloud.google.com/iam-admin/iam?project=boltlog), ensure your user has **Logs Viewer** (or **Viewer** / **Owner**). Add role **Logs Viewer** if needed.
   - **Build can’t write logs:** The fix script grants the Cloud Build service account **Logs Writer**. Run `.\scripts\fix-and-deploy-functions.ps1` once so future builds emit logs.
   - **Expired:** Logs are kept ~30 days; old builds may have no logs left.
5. Copy the **exact error line** from the failed step (e.g. permission denied, 404, npm error). That is what we need to fix.

## 2. If the log shows artifact/cache 404 or "NoSuchKey"

Sometimes the build fails because of a bad/corrupted artifact cache. You can force a clean build by deleting the artifacts bucket so Google recreates it:

1. Go to **Cloud Storage** → **Buckets**:  
   https://console.cloud.google.com/storage/browser?project=boltlog
2. Find the bucket **`us.artifacts.boltlog.appspot.com`** (or any bucket named `*.artifacts.*` for this project).
3. **Delete the bucket** (empty it first if needed, then delete the bucket).
4. Run deploy again:  
   `npx firebase-tools deploy --only functions`

**Warning:** Only delete the artifacts bucket. Do not delete `gcf-sources-*` or your app’s data buckets.

## 3. IAM (already applied by script)

The script `scripts\fix-and-deploy-functions.ps1` grants:

- **Storage Object Viewer** to `28158895372-compute@developer.gserviceaccount.com` and `28158895372@cloudbuild.gserviceaccount.com`
- **Artifact Registry Writer** to `28158895372@cloudbuild.gserviceaccount.com`

If you change the project or create a new one, run that script again (or grant the same roles in IAM).

## 4. Deploy again

From the project root:

```powershell
npx firebase-tools deploy --only functions
```

Or run the full fix + deploy:

```powershell
.\scripts\fix-and-deploy-functions.ps1
```

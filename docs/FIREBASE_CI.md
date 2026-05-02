# Firebase + GitHub Actions (Firestore rules)

## Automatic behavior (already in the repo)

- **Push to `main`** that changes `firestore.rules`, `firebase.json`, or the deploy workflow → **deploys** Firestore rules (if `FIREBASE_TOKEN` is set).
- **Pull requests** into `main` that touch those files → **dry-run** validation (same token requirement).

## One-command setup (local machine)

You still need a **one-time browser login** for Firebase (Google does not allow fully headless token creation).

### Windows (PowerShell, from repo root)

```powershell
.\scripts\setup-firebase-github-secret.ps1
```

Optional: after the secret is set, trigger the workflow once:

```powershell
.\scripts\setup-firebase-github-secret.ps1 -RunDeployWorkflow
```

### macOS / Linux

```bash
chmod +x scripts/setup-firebase-github-secret.sh
./scripts/setup-firebase-github-secret.sh
```

Optional:

```bash
./scripts/setup-firebase-github-secret.sh --run-workflow
```

### Prerequisites

| Tool | Install |
|------|--------|
| Node.js | [nodejs.org](https://nodejs.org/) |
| GitHub CLI `gh` | [cli.github.com](https://cli.github.com/) (Windows: `winget install GitHub.cli`) |

Run `gh auth login` once if you haven’t (the script will prompt).

### If you already have a CI token

```powershell
$env:FIREBASE_CI_TOKEN = "paste-token-here"
.\scripts\setup-firebase-github-secret.ps1 -SkipFirebaseLogin
```

```bash
FIREBASE_CI_TOKEN='paste-token-here' ./scripts/setup-firebase-github-secret.sh --skip-login
```

## Manual alternative

1. `npx firebase-tools login:ci` → copy token  
2. GitHub repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret** → name `FIREBASE_TOKEN`  

## Verify

- **Actions** tab → workflow **Deploy Firestore rules** → latest run should succeed.  
- Firebase Console → Firestore → **Rules** → check **Published** time.

---

## Cloud Functions deploy (`Deploy Cloud Functions` workflow)

Uses **Workload Identity Federation** (secrets `GCP_WORKLOAD_IDENTITY_PROVIDER` and `GCP_SERVICE_ACCOUNT_EMAIL`).

### Error: `iam.serviceAccounts.ActAs` on `boltlog@appspot.gserviceaccount.com`

Deploy runs as your **GitHub Actions service account** (the email in `GCP_SERVICE_ACCOUNT_EMAIL`). That account must be allowed to **act as** the App Engine default account used at runtime.

A **project Owner** (or IAM Admin) must grant **Service Account User** on the default App Engine service account:

```bash
# Replace GITHUB_ACTIONS_SA with the exact value of GCP_SERVICE_ACCOUNT_EMAIL (from repo secrets).
gcloud iam service-accounts add-iam-policy-binding boltlog@appspot.gserviceaccount.com \
  --member="serviceAccount:GITHUB_ACTIONS_SA" \
  --role="roles/iam.serviceAccountUser" \
  --project=boltlog
```

Alternatively, grant the same role **at project level** for that member (broader):

```bash
gcloud projects add-iam-policy-binding boltlog \
  --member="serviceAccount:GITHUB_ACTIONS_SA" \
  --role="roles/iam.serviceAccountUser"
```

Then re-run the **Deploy Cloud Functions** workflow.

**Note:** `npm warn deprecated …` lines from `firebase-tools` are harmless. They do not cause deploy failure.

### Error: `Build failed` / code 13 (Cloud Build) on function update

IAM is OK, but **Cloud Build** (the step that runs `npm install` and packs the function image) failed. Open the **Cloud Build** log URL printed in the GitHub Actions log (region `us-central1`) and read the **failed step** (often `npm ci` / missing lockfile / dependency error).

- Ensure `functions/package-lock.json` is committed and in sync (`npm install` in `functions/` locally, then commit).
- Do **not** delete the project’s `us.artifacts.*.appspot.com` bucket to “clear cache”; it breaks Artifact Registry–backed builds.
- The **Deploy Cloud Functions** workflow grants **`roles/iam.serviceAccountUser`** to **`PROJECT_NUMBER@cloudbuild.gserviceaccount.com`** on **`PROJECT@appspot.gserviceaccount.com`** and **`PROJECT_NUMBER-compute@developer.gserviceaccount.com`**. Without that, Cloud Build often fails with a generic build error. If you deploy only from a laptop, apply the same bindings once (see `.github/workflows/deploy-functions.yml`).

### Error: `Precondition failed` / `Cannot update a GCF function without sourceUrl`

The CLI matched your local **functions source hash** to the deployed label and **skipped uploading** the zip, then tried to update the function anyway. Bump `boltlog.deployStamp` in `functions/package.json` (or any change under `functions/`), pull in Cloud Shell, and redeploy. Use **Node 20** when running the CLI (`nvm use 20`) and a current **firebase-tools** (e.g. `npx firebase-tools@15`). See `functions/DEPLOY_TROUBLESHOOTING.md`.

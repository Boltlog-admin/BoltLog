# Scripts

| Script | Purpose |
|--------|--------|
| **setup-github-secrets.ps1** | One-time: run to get **FIREBASE_TOKEN** (opens `firebase login:ci`) and print instructions for **GCP_SA_KEY**. Run with: `powershell -ExecutionPolicy Bypass -File .\scripts\setup-github-secrets.ps1` (avoids changing system script policy). |
| **fix-and-deploy-functions.ps1** | Local deploy: installs/finds gcloud, applies GCP IAM, resets artifacts bucket, runs `firebase deploy --only functions`. Use when not using GitHub Actions or to fix IAM from your machine. |

**Deploy via GitHub (recommended):** Add the two secrets (see [.github/DEPLOY_FUNCTIONS_SETUP.md](../.github/DEPLOY_FUNCTIONS_SETUP.md)), then push to `main` or run the “Deploy Cloud Functions” workflow. The workflow applies IAM and artifact reset automatically when **GCP_SA_KEY** is set.

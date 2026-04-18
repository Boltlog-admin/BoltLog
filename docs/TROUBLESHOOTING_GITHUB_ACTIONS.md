# GitHub Actions not running?

## 1. Enable Actions on the repository

**GitHub** → your repo → **Settings** → **Actions** → **General**

- Under **Actions permissions**, choose **Allow all actions and reusable workflows** (or at least allow local actions).
- Save.

## 2. Forks only

If this repo is a **fork**, open the **Actions** tab once. GitHub may show a banner: enable workflows on this fork — **accept**.

Forks do not run scheduled or push workflows until you enable them.

## 3. Confirm the workflow files are on the default branch

Workflows only apply to the branch you use as default (usually `main`). On GitHub, check that `.github/workflows/*.yml` exists on **main** for the latest commit.

## 4. Start a run manually

**Actions** → select **Build Android APK** (or **CI health check**) → **Run workflow** → branch **main** → **Run workflow**.

If manual runs work but pushes don’t, check branch name (must be `main` or `master` for our workflows).

## 5. Organization / billing

- **Private** repos need Actions minutes (free tier has a monthly allowance).
- Some **organizations** restrict which workflows can run — ask an org admin.

## 6. Still nothing?

Open **Actions** → left sidebar: you should see workflow names. If the list is empty, workflow files may not be on GitHub (push again) or Actions is disabled at account/org level.

After fixing settings, push any small commit to `main` or use **Run workflow** once.

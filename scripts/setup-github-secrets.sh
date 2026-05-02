#!/usr/bin/env bash
# One-time setup: get FIREBASE_TOKEN for GitHub Actions. Run from repo root.
set -e
cd "$(dirname "$0")/.."
[ -f firebase.json ] || { echo "Run from repo root."; exit 1; }

echo "=== GitHub Actions secrets setup for Boltlog ==="
echo ""
echo "1. FIREBASE_TOKEN (required)"
echo "   Run the command below; copy the token into GitHub: Settings → Secrets → Actions → New secret → FIREBASE_TOKEN"
echo ""
npx firebase-tools login:ci
echo ""
echo "2. GCP_SA_KEY (optional – auto IAM + artifact reset)"
echo "   Create SA: https://console.cloud.google.com/iam-admin/serviceaccounts?project=boltlog"
echo "   Grant: Project IAM Admin. Create JSON key. Add secret GCP_SA_KEY with full JSON."
echo ""
echo "Then: push to main or Actions → Deploy Cloud Functions → Run workflow"

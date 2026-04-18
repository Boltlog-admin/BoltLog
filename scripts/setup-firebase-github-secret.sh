#!/usr/bin/env bash
# One-shot: Firebase CI token -> GitHub secret FIREBASE_TOKEN -> optional workflow
#
# Prerequisites: Node.js, GitHub CLI (gh), gh auth login
#
# Usage (from repo root):
#   chmod +x scripts/setup-firebase-github-secret.sh
#   ./scripts/setup-firebase-github-secret.sh
#
# With token already in env:
#   FIREBASE_CI_TOKEN=... ./scripts/setup-firebase-github-secret.sh --skip-login
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SKIP_LOGIN=false
RUN_WORKFLOW=false
for arg in "$@"; do
  case "$arg" in
    --skip-login) SKIP_LOGIN=true ;;
    --run-workflow) RUN_WORKFLOW=true ;;
  esac
done

command -v gh >/dev/null 2>&1 || { echo "Install GitHub CLI: https://cli.github.com/"; exit 1; }

if ! gh auth status &>/dev/null; then
  echo "GitHub CLI: signing in..."
  gh auth login
fi

if [[ -n "${FIREBASE_CI_TOKEN:-}" ]]; then
  TOKEN="$FIREBASE_CI_TOKEN"
  echo "Using FIREBASE_CI_TOKEN from environment."
elif [[ "$SKIP_LOGIN" == true ]]; then
  read -r -p "Paste Firebase CI token: " TOKEN
else
  echo ""
  echo "Firebase will open a browser for one-time login, then print a CI token."
  echo ""
  # Capture last line that looks like a token (Firebase prints banner + token)
  OUT="$(npx --yes firebase-tools login:ci 2>&1)" || true
  echo "$OUT"
  TOKEN="$(echo "$OUT" | grep -E '^[A-Za-z0-9_-]{30,}$' | tail -n1)"
  if [[ -z "${TOKEN:-}" ]]; then
    read -r -p "Paste the Firebase CI token: " TOKEN
  fi
fi

if [[ -z "${TOKEN:-}" ]]; then
  echo "Error: no token." >&2
  exit 1
fi

echo "Uploading FIREBASE_TOKEN to GitHub Actions secrets..."
printf '%s' "$TOKEN" | gh secret set FIREBASE_TOKEN

echo "Done. Secret FIREBASE_TOKEN is set."
echo "Pushes to main that change firestore.rules will deploy automatically."
echo "Or run: gh workflow run deploy-firestore-rules.yml"
echo ""

if [[ "$RUN_WORKFLOW" == true ]]; then
  gh workflow run deploy-firestore-rules.yml && echo "Triggered deploy-firestore-rules.yml" || true
fi

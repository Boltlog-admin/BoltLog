# One-time setup: get values for GitHub Actions secrets (FIREBASE_TOKEN, optional GCP_SA_KEY).
# Run from repo root. Then add the output to repo Settings -> Secrets and variables -> Actions.
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $repoRoot "firebase.json"))) {
    Write-Error "Run from repo root or scripts folder. firebase.json not found."
}

Write-Host "=== GitHub Actions secrets setup for Boltlog ===" -ForegroundColor Cyan
Write-Host ""

# 1. FIREBASE_TOKEN
Write-Host "1. FIREBASE_TOKEN (required)" -ForegroundColor Yellow
Write-Host "   Run this and paste the token into GitHub secret FIREBASE_TOKEN:"
Write-Host "   npx firebase login:ci" -ForegroundColor White
Write-Host "   Opening browser for Firebase login in 3s..."
Start-Sleep -Seconds 3
Push-Location $repoRoot
try {
    npx firebase-tools login:ci 2>&1 | Out-Host
} finally {
    Pop-Location
}
Write-Host "   Copy the token above, then: GitHub repo -> Settings -> Secrets -> Actions -> New repository secret -> Name: FIREBASE_TOKEN" -ForegroundColor Gray
Write-Host ""

# 2. GCP_SA_KEY (optional)
Write-Host "2. GCP_SA_KEY (optional - enables auto IAM + artifact reset before each deploy)" -ForegroundColor Yellow
Write-Host "   - Create service account: https://console.cloud.google.com/iam-admin/serviceaccounts?project=boltlog" -ForegroundColor Gray
Write-Host "   - Grant role: Project IAM Admin (or Owner)" -ForegroundColor Gray
Write-Host "   - Create key (JSON), download file" -ForegroundColor Gray
Write-Host "   - GitHub -> Settings -> Secrets -> Actions -> New secret -> Name: GCP_SA_KEY, Value: paste entire JSON" -ForegroundColor Gray
Write-Host ""

Write-Host "After adding secrets, push to main or run workflow: Actions -> Deploy Cloud Functions -> Run workflow" -ForegroundColor Green

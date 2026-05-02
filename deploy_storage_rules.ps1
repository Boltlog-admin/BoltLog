# Deploy Firebase Storage Rules
# This script will deploy the storage.rules file to Firebase

Write-Host "=== Firebase Storage Rules Deployment ===" -ForegroundColor Cyan
Write-Host ""

# Check if Firebase CLI is installed
Write-Host "Checking Firebase CLI..." -ForegroundColor Yellow
$firebaseVersion = firebase --version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Firebase CLI is not installed!" -ForegroundColor Red
    Write-Host "Please install it with: npm install -g firebase-tools" -ForegroundColor Yellow
    exit 1
}
Write-Host "✓ Firebase CLI found: $firebaseVersion" -ForegroundColor Green
Write-Host ""

# Check if storage.rules exists
if (-not (Test-Path "storage.rules")) {
    Write-Host "ERROR: storage.rules file not found!" -ForegroundColor Red
    exit 1
}
Write-Host "✓ storage.rules file found" -ForegroundColor Green
Write-Host ""

# Check if .firebaserc exists, create if not
if (-not (Test-Path ".firebaserc")) {
    Write-Host "Creating .firebaserc file..." -ForegroundColor Yellow
    $firebaserc = @{
        projects = @{
            default = "boltlog"
        }
    } | ConvertTo-Json
    $firebaserc | Out-File -FilePath ".firebaserc" -Encoding utf8
    Write-Host "✓ .firebaserc created" -ForegroundColor Green
    Write-Host ""
}

# Check authentication
Write-Host "Checking Firebase authentication..." -ForegroundColor Yellow
$authCheck = firebase projects:list 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "⚠ Authentication required!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Please run the following command to login:" -ForegroundColor Cyan
    Write-Host "  firebase login" -ForegroundColor White
    Write-Host ""
    Write-Host "After logging in, run this script again to deploy the rules." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Alternatively, you can deploy manually:" -ForegroundColor Cyan
    Write-Host "  1. Go to https://console.firebase.google.com/" -ForegroundColor White
    Write-Host "  2. Select project: boltlog" -ForegroundColor White
    Write-Host "  3. Go to Storage > Rules" -ForegroundColor White
    Write-Host "  4. Copy contents of storage.rules and paste" -ForegroundColor White
    Write-Host "  5. Click Publish" -ForegroundColor White
    exit 1
}

Write-Host "✓ Authenticated" -ForegroundColor Green
Write-Host ""

# Set project
Write-Host "Setting Firebase project to: boltlog" -ForegroundColor Yellow
firebase use boltlog
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to set project" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Project set" -ForegroundColor Green
Write-Host ""

# Deploy storage rules
Write-Host "Deploying storage rules..." -ForegroundColor Yellow
Write-Host ""
firebase deploy --only storage
if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "✓ Storage rules deployed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Rules are now active. Driver image uploads should work correctly." -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "✗ Deployment failed. Please check the error messages above." -ForegroundColor Red
    exit 1
}

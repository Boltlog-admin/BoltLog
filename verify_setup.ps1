# Verify Firebase Storage Rules Setup
Write-Host "=== Firebase Storage Rules Setup Verification ===" -ForegroundColor Cyan
Write-Host ""

$allGood = $true

# Check storage.rules
if (Test-Path "storage.rules") {
    Write-Host "[OK] storage.rules file exists" -ForegroundColor Green
    $rulesContent = Get-Content "storage.rules" -Raw
    if ($rulesContent -match "drivers/\{userId\}") {
        Write-Host "[OK] Rules contain drivers path pattern" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Rules may not have correct drivers path" -ForegroundColor Yellow
        $allGood = $false
    }
} else {
    Write-Host "[ERROR] storage.rules file missing!" -ForegroundColor Red
    $allGood = $false
}

# Check firebase.json
if (Test-Path "firebase.json") {
    Write-Host "[OK] firebase.json exists" -ForegroundColor Green
    $firebaseJson = Get-Content "firebase.json" | ConvertFrom-Json
    if ($firebaseJson.storage -and $firebaseJson.storage.rules) {
        Write-Host "[OK] firebase.json references storage.rules" -ForegroundColor Green
    } else {
        Write-Host "[WARN] firebase.json may not reference storage rules" -ForegroundColor Yellow
    }
} else {
    Write-Host "[ERROR] firebase.json missing!" -ForegroundColor Red
    $allGood = $false
}

# Check .firebaserc
if (Test-Path ".firebaserc") {
    Write-Host "[OK] .firebaserc exists" -ForegroundColor Green
    $firebaserc = Get-Content ".firebaserc" | ConvertFrom-Json
    if ($firebaserc.projects.default -eq "boltlog") {
        Write-Host "[OK] Project set to boltlog" -ForegroundColor Green
    }
} else {
    Write-Host "[WARN] .firebaserc missing (will be created on first deploy)" -ForegroundColor Yellow
}

Write-Host ""
if ($allGood) {
    Write-Host "=== Setup Complete! ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next step: Deploy rules to Firebase" -ForegroundColor Yellow
    Write-Host "1. Use the HTML helper (deploy_rules_helper.html)" -ForegroundColor White
    Write-Host "2. Or run: firebase login" -ForegroundColor White
    Write-Host "3. Then: firebase deploy --only storage" -ForegroundColor White
} else {
    Write-Host "=== Setup Issues Found ===" -ForegroundColor Red
    Write-Host "Please fix the errors above" -ForegroundColor Yellow
}

# Simple script to deploy Firebase Storage Rules
# Run this after you've logged in with: firebase login

Write-Host "Deploying Firebase Storage Rules..." -ForegroundColor Cyan
Write-Host ""

# Check if user is logged in
$testAuth = firebase projects:list 2>&1 | Out-String
if ($testAuth -match "Authentication Error") {
    Write-Host "⚠ You need to login first!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Run this command first:" -ForegroundColor Cyan
    Write-Host "  firebase login" -ForegroundColor White
    Write-Host ""
    Write-Host "Then run this script again." -ForegroundColor Yellow
    exit 1
}

# Deploy
Write-Host "Deploying..." -ForegroundColor Yellow
firebase deploy --only storage

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "✓ Success! Storage rules deployed." -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "✗ Deployment failed. Check errors above." -ForegroundColor Red
}

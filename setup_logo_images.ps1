# Script to set up logo images from "Boltlog Logo" folder
# This script copies images to their required locations

Write-Host "Setting up logo images from 'Boltlog Logo' folder..." -ForegroundColor Cyan

$logoFolder = "assets/images/Boltlog Logo"
$androidDrawable = "android/app/src/main/res/drawable"

# Check if Boltlog Logo folder exists
if (-not (Test-Path $logoFolder)) {
    Write-Host "Error: Folder '$logoFolder' not found!" -ForegroundColor Red
    Write-Host "Please create the folder and add your images:" -ForegroundColor Yellow
    Write-Host "  - 1-removebg-preview.png" -ForegroundColor Yellow
    Write-Host "  - 2.png" -ForegroundColor Yellow
    Write-Host "  - 3.png" -ForegroundColor Yellow
    exit 1
}

# Check and copy image 1 (splash screen)
$image1 = Join-Path $logoFolder "1-removebg-preview.png"
if (Test-Path $image1) {
    Write-Host "✓ Found: 1-removebg-preview.png" -ForegroundColor Green
} else {
    Write-Host "⚠ Missing: 1-removebg-preview.png" -ForegroundColor Yellow
}

# Check and copy image 2 (launcher icon)
$image2 = Join-Path $logoFolder "2.png"
if (Test-Path $image2) {
    Write-Host "✓ Found: 2.png" -ForegroundColor Green
} else {
    Write-Host "⚠ Missing: 2.png" -ForegroundColor Yellow
}

# Check and copy image 3 (launch screen) to Android drawable
$image3 = Join-Path $logoFolder "3 no background.png"
$androidImage3 = Join-Path $androidDrawable "launch_3.png"

if (Test-Path $image3) {
    Write-Host "✓ Found: 3 no background.png" -ForegroundColor Green
    # Ensure drawable folder exists
    if (-not (Test-Path $androidDrawable)) {
        New-Item -ItemType Directory -Path $androidDrawable -Force | Out-Null
    }
    # Copy to Android drawable folder (rename to launch_3.png for Android resource naming)
    Copy-Item -Path $image3 -Destination $androidImage3 -Force
    Write-Host "✓ Copied 3 no background.png to Android drawable folder as launch_3.png" -ForegroundColor Green
} else {
    Write-Host "⚠ Missing: 3 no background.png" -ForegroundColor Yellow
    Write-Host "  Note: This image is needed for the native launch screen" -ForegroundColor Yellow
}

Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "1. Ensure all three images are in: $logoFolder" -ForegroundColor White
Write-Host "2. Run: flutter pub get" -ForegroundColor White
Write-Host "3. Run: flutter pub run flutter_launcher_icons" -ForegroundColor White
Write-Host "4. Run: flutter clean && flutter run" -ForegroundColor White

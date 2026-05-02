# Script to update launcher icon from image "2" in root folder
# This script will find the image file and generate launcher icons

Write-Host "Searching for image file '2' in root folder..." -ForegroundColor Cyan

# Check for common image extensions
$imageExtensions = @(".png", ".jpg", ".jpeg", ".ico")
$imageFile = $null

foreach ($ext in $imageExtensions) {
    $filePath = "2$ext"
    if (Test-Path $filePath) {
        $imageFile = $filePath
        Write-Host "Found: $imageFile" -ForegroundColor Green
        break
    }
}

if (-not $imageFile) {
    Write-Host "Error: Image file '2' not found in root folder!" -ForegroundColor Red
    Write-Host "Please ensure the file exists with one of these extensions: .png, .jpg, .jpeg, .ico" -ForegroundColor Yellow
    exit 1
}

# Update pubspec.yaml
Write-Host "`nUpdating pubspec.yaml..." -ForegroundColor Cyan
$pubspecPath = "pubspec.yaml"
$pubspecContent = Get-Content $pubspecPath -Raw

# Update image_path
$pubspecContent = $pubspecContent -replace 'image_path:\s*"[^"]*"', "image_path: `"$imageFile`""
$pubspecContent = $pubspecContent -replace 'adaptive_icon_foreground:\s*"[^"]*"', "adaptive_icon_foreground: `"$imageFile`""

Set-Content -Path $pubspecPath -Value $pubspecContent -NoNewline
Write-Host "Updated pubspec.yaml to use: $imageFile" -ForegroundColor Green

# Run flutter pub get
Write-Host "`nRunning 'flutter pub get'..." -ForegroundColor Cyan
flutter pub get

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error running 'flutter pub get'" -ForegroundColor Red
    exit 1
}

# Generate launcher icons
Write-Host "`nGenerating launcher icons..." -ForegroundColor Cyan
flutter pub run flutter_launcher_icons

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n✓ Launcher icons successfully generated!" -ForegroundColor Green
    Write-Host "The app icon has been replaced with: $imageFile" -ForegroundColor Green
} else {
    Write-Host "`nError generating launcher icons" -ForegroundColor Red
    exit 1
}

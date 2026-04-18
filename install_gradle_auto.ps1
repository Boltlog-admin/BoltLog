# Automatic Gradle 8.14 Installation Script
# Finds an existing gradle-8.14-all.zip under your user profile and
# copies it to the Gradle wrapper directory used by Android builds.

$gradleVersion = "8.14"
$targetDir = "$env:USERPROFILE\.gradle\wrapper\dists\gradle-$gradleVersion-all"
$targetZip = Join-Path $targetDir "gradle-$gradleVersion-all.zip"

Write-Host "=== AUTO GRADLE INSTALLATION ===" -ForegroundColor Cyan
Write-Host ""

# Ensure target directory exists
Write-Host "Ensuring Gradle target directory exists..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
Write-Host "Target directory: $targetDir"
Write-Host ""

# If zip already present, we're done
if (Test-Path $targetZip) {
    Write-Host "✓ Gradle zip already present at target location." -ForegroundColor Green
    Write-Host "  $targetZip"
    exit 0
}

Write-Host "Searching for 'gradle-$gradleVersion-all.zip' under $env:USERPROFILE ..." -ForegroundColor Yellow
$existing = Get-ChildItem -Path $env:USERPROFILE -Recurse -Filter "gradle-$gradleVersion-all.zip" -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $existing) {
    Write-Host "✗ Could not find gradle-$gradleVersion-all.zip anywhere under your user profile." -ForegroundColor Red
    Write-Host "  Please download it (if not already) and place it in, e.g., your Downloads folder." -ForegroundColor Yellow
    exit 1
}

Write-Host "Found existing Gradle zip at:" -ForegroundColor Cyan
Write-Host "  $($existing.FullName)" -ForegroundColor Gray
Write-Host ""

Write-Host "Copying to target wrapper directory..." -ForegroundColor Yellow
Copy-Item -Path $existing.FullName -Destination $targetZip -Force

Write-Host "✓ Successfully copied Gradle zip to wrapper directory." -ForegroundColor Green
Write-Host "  Target: $targetZip" -ForegroundColor Gray
Write-Host ""
Write-Host "Gradle will extract and use this when you run your Android build." -ForegroundColor Cyan


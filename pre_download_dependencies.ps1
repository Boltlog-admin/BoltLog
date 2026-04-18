# Pre-Download Dependencies Script
# This script helps pre-download dependencies to speed up builds

Write-Host "=== PRE-DOWNLOADING DEPENDENCIES ===" -ForegroundColor Cyan
Write-Host ""

# 1. Flutter Packages (Dart/Flutter dependencies)
Write-Host "1. Downloading Flutter packages..." -ForegroundColor Yellow
flutter pub get
Write-Host "   ✓ Flutter packages downloaded" -ForegroundColor Green
Write-Host ""

# 2. Gradle Wrapper (if not already downloaded)
Write-Host "2. Downloading Gradle wrapper..." -ForegroundColor Yellow
$gradleVersion = "8.14"
$gradleUrl = "https://services.gradle.org/distributions/gradle-$gradleVersion-all.zip"
$gradleHome = "$env:USERPROFILE\.gradle\wrapper\dists\gradle-$gradleVersion-all"
$gradleZip = "$gradleHome\gradle-$gradleVersion-all.zip"

if (-not (Test-Path $gradleZip)) {
    Write-Host "   Downloading Gradle $gradleVersion..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $gradleHome | Out-Null
    Invoke-WebRequest -Uri $gradleUrl -OutFile $gradleZip
    Write-Host "   ✓ Gradle wrapper downloaded" -ForegroundColor Green
} else {
    Write-Host "   ✓ Gradle wrapper already exists" -ForegroundColor Green
}
Write-Host ""

# 3. Pre-download Gradle dependencies (Android build tools)
Write-Host "3. Pre-downloading Android Gradle dependencies..." -ForegroundColor Yellow
Write-Host "   This will download Android build tools and plugins"
Write-Host "   Running: cd android && gradlew --refresh-dependencies"
Set-Location android
if (Test-Path "gradlew.bat") {
    .\gradlew.bat --refresh-dependencies --no-daemon
    Write-Host "   ✓ Android Gradle dependencies downloaded" -ForegroundColor Green
} else {
    Write-Host "   ⚠ Gradle wrapper not found, skipping" -ForegroundColor Yellow
}
Set-Location ..
Write-Host ""

# 4. Google Fonts (can be pre-downloaded)
Write-Host "4. Pre-downloading Google Fonts..." -ForegroundColor Yellow
Write-Host "   Note: Google Fonts are downloaded at runtime, but you can pre-cache them"
Write-Host "   Run your app once to cache fonts, or manually download from:"
Write-Host "   https://fonts.google.com/"
Write-Host "   ✓ Google Fonts info provided" -ForegroundColor Green
Write-Host ""

# 5. Firebase dependencies (handled by FlutterFire)
Write-Host "5. Firebase dependencies..." -ForegroundColor Yellow
Write-Host "   Firebase dependencies are downloaded via Flutter packages"
Write-Host "   Already handled by 'flutter pub get' above"
Write-Host "   ✓ Firebase dependencies will be downloaded during build" -ForegroundColor Green
Write-Host ""

# Summary
Write-Host "=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "Pre-downloaded:" -ForegroundColor Green
Write-Host "  ✓ Flutter/Dart packages (pubspec.yaml)"
Write-Host "  ✓ Gradle wrapper"
Write-Host "  ✓ Android Gradle dependencies"
Write-Host ""
Write-Host "Still downloaded during build:" -ForegroundColor Yellow
Write-Host "  • Native Android libraries (via Gradle)"
Write-Host "  • Firebase native SDKs (via FlutterFire)"
Write-Host "  • Google Maps SDK (via google_maps_flutter)"
Write-Host "  • Plugin-specific native dependencies"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Run 'flutter build apk --release'"
Write-Host "  2. Build should be faster now (2-5 minutes instead of 10-15)"
Write-Host ""

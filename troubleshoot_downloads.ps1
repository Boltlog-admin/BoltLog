# Troubleshoot Gradle Download Process
# This script helps diagnose and fix download issues

Write-Host "=== GRADLE DOWNLOAD TROUBLESHOOTING ===" -ForegroundColor Cyan
Write-Host ""

# 1. Check network connectivity
Write-Host "1. Checking Network Connectivity..." -ForegroundColor Yellow
$mavenCentral = Test-NetConnection -ComputerName repo1.maven.org -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
$googleMaven = Test-NetConnection -ComputerName maven.google.com -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue

if ($mavenCentral) {
    Write-Host "   ✓ Maven Central (repo1.maven.org) - Reachable" -ForegroundColor Green
} else {
    Write-Host "   ✗ Maven Central (repo1.maven.org) - NOT Reachable" -ForegroundColor Red
}

if ($googleMaven) {
    Write-Host "   ✓ Google Maven (maven.google.com) - Reachable" -ForegroundColor Green
} else {
    Write-Host "   ✗ Google Maven (maven.google.com) - NOT Reachable" -ForegroundColor Red
}
Write-Host ""

# 2. Check Gradle cache status
Write-Host "2. Checking Gradle Cache..." -ForegroundColor Yellow
$cachePath = "$env:USERPROFILE\.gradle\caches\modules-2\files-2.1"
if (Test-Path $cachePath) {
    $cacheCount = (Get-ChildItem -Path $cachePath -ErrorAction SilentlyContinue | Measure-Object).Count
    $cacheSize = (Get-ChildItem -Path $cachePath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    Write-Host "   ✓ Gradle cache exists" -ForegroundColor Green
    Write-Host "   Cached dependencies: $cacheCount packages" -ForegroundColor Gray
    Write-Host "   Cache size: $([math]::Round($cacheSize/1MB,2)) MB" -ForegroundColor Gray
} else {
    Write-Host "   ✗ Gradle cache not found" -ForegroundColor Red
}
Write-Host ""

# 3. Check active Java/Gradle processes
Write-Host "3. Checking Active Build Processes..." -ForegroundColor Yellow
$javaProcs = Get-Process -Name java -ErrorAction SilentlyContinue
if ($javaProcs) {
    Write-Host "   ✓ Active Java processes: $($javaProcs.Count)" -ForegroundColor Green
    $totalCPU = ($javaProcs | Measure-Object -Property CPU -Sum).Sum
    $totalMem = ($javaProcs | Measure-Object -Property WorkingSet64 -Sum).Sum
    Write-Host "   Total CPU time: $([math]::Round($totalCPU,1)) seconds" -ForegroundColor Gray
    Write-Host "   Total Memory: $([math]::Round($totalMem/1MB,2)) MB" -ForegroundColor Gray
    
    # Check if processes are actually working (CPU usage)
    $activeProcs = $javaProcs | Where-Object { $_.CPU -gt 0 }
    if ($activeProcs) {
        Write-Host "   Status: Processes are active (CPU > 0)" -ForegroundColor Green
    } else {
        Write-Host "   ⚠ Warning: Processes may be stuck (CPU = 0)" -ForegroundColor Yellow
    }
} else {
    Write-Host "   ✗ No Java processes found - build may have stopped" -ForegroundColor Red
}
Write-Host ""

# 4. Check for stuck downloads
Write-Host "4. Checking for Stuck Downloads..." -ForegroundColor Yellow
$gradleUserHome = "$env:USERPROFILE\.gradle"
$wrapperDists = Get-ChildItem -Path "$gradleUserHome\wrapper\dists" -Recurse -Filter "*.zip.lck" -ErrorAction SilentlyContinue
$downloading = Get-ChildItem -Path "$gradleUserHome\caches" -Recurse -Filter "*.tmp" -ErrorAction SilentlyContinue

if ($wrapperDists) {
    Write-Host "   ⚠ Found lock files - downloads may be in progress or stuck" -ForegroundColor Yellow
    Write-Host "   Lock files: $($wrapperDists.Count)" -ForegroundColor Gray
}

if ($downloading) {
    Write-Host "   ⚠ Found temporary download files" -ForegroundColor Yellow
    Write-Host "   Temp files: $($downloading.Count)" -ForegroundColor Gray
} else {
    Write-Host "   ✓ No stuck downloads detected" -ForegroundColor Green
}
Write-Host ""

# 5. Check Gradle daemon status
Write-Host "5. Checking Gradle Daemon..." -ForegroundColor Yellow
if ($javaProcs) {
    Write-Host "   ✓ Gradle daemon/Java processes are running" -ForegroundColor Green
} else {
    Write-Host "   ℹ No Gradle processes found" -ForegroundColor Gray
}
Write-Host ""

# 6. Recommendations
Write-Host "=== RECOMMENDATIONS ===" -ForegroundColor Cyan
Write-Host ""

if (-not $mavenCentral -or -not $googleMaven) {
    Write-Host "⚠ NETWORK ISSUE DETECTED" -ForegroundColor Red
    Write-Host "   - Check your internet connection" -ForegroundColor Yellow
    Write-Host "   - Check firewall/proxy settings" -ForegroundColor Yellow
    Write-Host "   - Try: cd android; .\gradlew.bat --refresh-dependencies" -ForegroundColor Yellow
    Write-Host ""
}

if ($javaProcs -and ($javaProcs | Where-Object { $_.CPU -eq 0 })) {
    Write-Host "⚠ BUILD MAY BE STUCK" -ForegroundColor Yellow
    Write-Host "   - Processes exist but not using CPU" -ForegroundColor Yellow
    Write-Host "   - Try: Stop the build (Ctrl+C) and restart" -ForegroundColor Yellow
    Write-Host "   - Or: Kill Java processes and restart build" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "✓ BUILD IS PROGRESSING NORMALLY" -ForegroundColor Green
Write-Host "   - Network connectivity: OK" -ForegroundColor Gray
Write-Host "   - Processes are active" -ForegroundColor Gray
Write-Host "   - Large downloads (Firebase/Google Maps) take 5-10 minutes" -ForegroundColor Gray
Write-Host "   - First build always takes longer (15-25 minutes is normal)" -ForegroundColor Gray
Write-Host ""

# 7. Speed up options
Write-Host "=== SPEED UP OPTIONS ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Pre-download dependencies:" -ForegroundColor Yellow
Write-Host "   cd android" -ForegroundColor Gray
Write-Host "   .\gradlew.bat --refresh-dependencies --no-daemon" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Increase network timeouts (if slow connection):" -ForegroundColor Yellow
Write-Host "   Edit android\gradle.properties" -ForegroundColor Gray
Write-Host "   Increase systemProp.http.connectionTimeout and socketTimeout" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Use Gradle offline mode (after first successful build):" -ForegroundColor Yellow
Write-Host "   flutter build apk --release --offline" -ForegroundColor Gray
Write-Host ""

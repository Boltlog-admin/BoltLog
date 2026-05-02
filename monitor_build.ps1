# Continuous Build Monitor
# Updates every 5 seconds until APK is ready
# Press Ctrl+C to stop

Write-Host "=== CONTINUOUS BUILD MONITOR ===" -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop monitoring" -ForegroundColor Yellow
Write-Host ""

while ($true) {
    Clear-Host
    Write-Host "=== BUILD STATUS - $(Get-Date -Format 'HH:mm:ss') ===" -ForegroundColor Cyan
    Write-Host ""
    
    # Check APK
    $apkExists = Test-Path "build\app\outputs\flutter-apk\app-release.apk"
    if ($apkExists) {
        Write-Host "✓ APK: READY!" -ForegroundColor Green
        $apk = Get-Item "build\app\outputs\flutter-apk\app-release.apk"
        Write-Host "  Size: $([math]::Round($apk.Length / 1MB, 2)) MB"
        Write-Host ""
        Write-Host "Build completed successfully!" -ForegroundColor Green
        break
    } else {
        Write-Host "✗ APK: Not ready yet" -ForegroundColor Yellow
    }
    
    # Check build directory
    $buildDir = Test-Path "build"
    Write-Host "Build Dir: $buildDir"
    
    # Check processes
    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match "gradle|java|dart" }
    Write-Host "Active Processes: $($procs.Count)"
    
    if ($procs.Count -gt 0) {
        $totalCPU = ($procs | Measure-Object -Property CPU -Sum).Sum
        Write-Host "Total CPU Time: $([math]::Round($totalCPU, 1)) seconds"
        Write-Host ""
        Write-Host "Status: Build is running..." -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "Status: No processes - build may have stopped" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "Next update in 5 seconds..." -ForegroundColor Gray
    Start-Sleep -Seconds 5
}

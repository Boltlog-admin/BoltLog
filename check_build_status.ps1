# Build Status Monitoring Script
# Run this script to check your Flutter build progress

Write-Host "=== FLUTTER BUILD STATUS ===" -ForegroundColor Cyan
Write-Host ""

# Check if APK exists
$apkPath = "build\app\outputs\flutter-apk\app-release.apk"
$apkExists = Test-Path $apkPath

if ($apkExists) {
    Write-Host "✓ APK Status: READY!" -ForegroundColor Green
    $apk = Get-Item $apkPath
    Write-Host "  Location: $($apk.FullName)"
    Write-Host "  Size: $([math]::Round($apk.Length / 1MB, 2)) MB"
    Write-Host "  Created: $($apk.LastWriteTime)"
} else {
    Write-Host "✗ APK Status: Not yet generated" -ForegroundColor Yellow
}

Write-Host ""

# Check build directory
$buildDirExists = Test-Path "build"
if ($buildDirExists) {
    Write-Host "✓ Build Directory: Exists" -ForegroundColor Green
    $dirSize = (Get-ChildItem "build" -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    Write-Host "  Size: $([math]::Round($dirSize / 1MB, 2)) MB"
} else {
    Write-Host "✗ Build Directory: Not created yet" -ForegroundColor Yellow
}

Write-Host ""

# Check active processes
$procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match "gradle|java|dart" }
$procCount = $procs.Count

if ($procCount -gt 0) {
    Write-Host "✓ Active Build Processes: $procCount" -ForegroundColor Green
    Write-Host ""
    Write-Host "Process Details:"
    $procs | Select-Object ProcessName, Id, @{Name="CPU(s)";Expression={[math]::Round($_.CPU, 1)}}, @{Name="Memory(MB)";Expression={[math]::Round($_.WorkingSet64 / 1MB, 2)}} | Format-Table -AutoSize
    
    $totalCPU = ($procs | Measure-Object -Property CPU -Sum).Sum
    $totalMem = ($procs | Measure-Object -Property WorkingSet64 -Sum).Sum
    Write-Host "Total CPU Time: $([math]::Round($totalCPU, 1)) seconds"
    Write-Host "Total Memory: $([math]::Round($totalMem / 1MB, 2)) MB"
} else {
    Write-Host "✗ Active Processes: None" -ForegroundColor Yellow
    Write-Host "  Build may have completed or stopped"
}

Write-Host ""

# Determine build phase
Write-Host "Build Phase:" -ForegroundColor Cyan
if ($apkExists) {
    Write-Host "  ✓ COMPLETED" -ForegroundColor Green
} elseif ($buildDirExists) {
    Write-Host "  → COMPILATION (actively building)" -ForegroundColor Yellow
} elseif ($procCount -gt 0) {
    Write-Host "  → DEPENDENCY DOWNLOAD (downloading dependencies)" -ForegroundColor Yellow
} else {
    Write-Host "  ? UNKNOWN (no active build detected)" -ForegroundColor Red
}

Write-Host ""

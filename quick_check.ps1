chbuild # Quick Build Status Check
# Run this script frequently to check build progress

$apkPath = "C:\Users\ZETDC\Desktop\Boltlog\boltlog\build\app\outputs\flutter-apk\app-release.apk"
$apkExists = Test-Path $apkPath
$procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match "gradle|java|dart" }

Write-Host "=== BUILD STATUS - $(Get-Date -Format 'HH:mm:ss') ==="
Write-Host "APK Ready: $apkExists"
Write-Host "Active Processes: $($procs.Count)"

if ($apkExists) {
    Write-Host ""
    Write-Host "SUCCESS! APK is ready!" -ForegroundColor Green
    $apk = Get-Item $apkPath
    Write-Host "Size: $([math]::Round($apk.Length/1MB,2)) MB"
    Write-Host "Location: $($apk.FullName)"
} elseif ($procs.Count -gt 0) {
    Write-Host "Status: Still building"
    $totalCPU = ($procs | Measure-Object -Property CPU -Sum).Sum
    Write-Host "Total CPU Time: $([math]::Round($totalCPU,1)) seconds"
} else {
    Write-Host "Status: No processes - build may have completed or stopped"
}

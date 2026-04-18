# Boltlog — local verification (same gates as CI).
# Exit 0 = healthy for automated checks; non-zero = fix errors/tests before release.
#
# Usage (PowerShell, from repo root):
#   .\scripts\verify_app.ps1
# Optional: $env:FLUTTER_ROOT or place flutter on PATH.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

function Find-Flutter {
    if ($env:FLUTTER_ROOT) {
        $cand = Join-Path $env:FLUTTER_ROOT "bin\flutter.bat"
        if (Test-Path $cand) { return $cand }
    }
    $cmd = Get-Command flutter -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

$flutter = Find-Flutter
if (-not $flutter) {
    Write-Host "FAIL: flutter not found. Add Flutter to PATH or set FLUTTER_ROOT." -ForegroundColor Red
    exit 1
}

Write-Host "Using: $flutter" -ForegroundColor Cyan
Write-Host ""

$failed = $false

Write-Host "== flutter pub get ==" -ForegroundColor Yellow
& $flutter pub get
if ($LASTEXITCODE -ne 0) { $failed = $true }

# Only analyzer *errors* fail the script (warnings/infos still printed).
Write-Host ""
Write-Host "== flutter analyze (errors fatal; infos/warnings non-fatal) ==" -ForegroundColor Yellow
& $flutter analyze --no-fatal-infos --no-fatal-warnings
if ($LASTEXITCODE -ne 0) {
    Write-Host "Analyzer reported errors. Fix before release." -ForegroundColor Red
    $failed = $true
}

Write-Host ""
Write-Host "== flutter test ==" -ForegroundColor Yellow
& $flutter test
if ($LASTEXITCODE -ne 0) {
    $failed = $true
}

Write-Host ""
if ($failed) {
    Write-Host "VERIFY: FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "VERIFY: OK (analyze had no errors; all tests passed)" -ForegroundColor Green
Write-Host "Note: Full product status still needs manual QA + Firebase/backend checks." -ForegroundColor DarkGray
exit 0

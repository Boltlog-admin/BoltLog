# BoltLog - Windows release APK: optional Defender exclusions, clean Gradle cache, flutter build apk.
# Run elevated once so Defender can exclude Gradle folders (fixes "Could not move temporary workspace").
#
# Usage:
#   .\scripts\windows_build_apk.ps1
#   .\scripts\windows_build_apk.ps1 -SkipDefender -SkipClean   # fast retry
#
param(
    [switch] $SkipDefender,
    [switch] $SkipClean
)

$ErrorActionPreference = "Continue"
$repo = Split-Path -Parent $PSScriptRoot
$gradleHome = Join-Path $env:USERPROFILE ".gradle-boltapk"
$tempGradle = Join-Path $env:LOCALAPPDATA "Temp\gradle-jvm-tmp"

function Find-Flutter {
    if ($env:FLUTTER_ROOT) {
        $cand = Join-Path $env:FLUTTER_ROOT "bin\flutter.bat"
        if (Test-Path $cand) { return $cand }
    }
    foreach ($p in @("C:\src\flutter\bin\flutter.bat")) {
        if (Test-Path $p) { return $p }
    }
    $cmd = Get-Command flutter -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Add-DefenderPaths {
    $added = @()
    $failed = @()

    foreach ($path in @($gradleHome, $repo)) {
        try {
            Add-MpPreference -ExclusionPath $path -ErrorAction Stop
            $added += $path
        } catch {
            $failed += "$path :: $($_.Exception.Message)"
        }
    }

    if ($added.Count -gt 0) {
        Write-Host "Defender exclusions added for:" -ForegroundColor Green
        $added | ForEach-Object { Write-Host "  $_" }
    }

    if ($failed.Count -gt 0) {
        Write-Warning "Could not add one or more Defender exclusions."
        $failed | ForEach-Object { Write-Warning "  $_" }
    }
}

if (-not $SkipDefender) {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = [Security.Principal.WindowsPrincipal]$id
    $isAdmin = $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        try {
            Add-DefenderPaths
        } catch {
            Write-Warning "Defender: $_"
        }
    } else {
        Write-Warning "Not running as Administrator - Defender exclusions were skipped."
        Write-Warning "Double-click scripts\Run-WindowsApkBuild-Admin.cmd (accept UAC) to add exclusions and build."
    }
}

if (-not $SkipClean) {
    Get-Process -Name java -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Remove-Item (Join-Path $gradleHome "caches") -Recurse -Force -ErrorAction SilentlyContinue
}

New-Item -ItemType Directory -Force -Path $gradleHome | Out-Null
New-Item -ItemType Directory -Force -Path $tempGradle | Out-Null

$flutter = Find-Flutter
if (-not $flutter) {
    Write-Host "FAIL: flutter not found. Set FLUTTER_ROOT or install Flutter." -ForegroundColor Red
    exit 1
}

$sdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
$lp = Join-Path $repo "android\local.properties"
if (Test-Path $lp) {
    Get-Content $lp -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_ -match '^\s*sdk\.dir\s*=\s*(.+)\s*$') {
            $sdk = $matches[1].Trim().Replace('\\', '\')
        }
    }
}
if (-not (Test-Path $sdk)) {
    Write-Warning "Android SDK not found at $sdk - install SDK or set sdk.dir in android/local.properties."
}

$env:GRADLE_USER_HOME = $gradleHome
$env:ANDROID_HOME = $sdk
$env:ANDROID_SDK_ROOT = $sdk
$env:TMP = $tempGradle
$env:TEMP = $tempGradle

Set-Location $repo
Write-Host "Using Flutter: $flutter" -ForegroundColor Cyan
Write-Host "GRADLE_USER_HOME=$gradleHome" -ForegroundColor Cyan

$log = Join-Path $repo "build-apk-last.log"
& $flutter pub get
$buildArgs = @("build", "apk", "--android-skip-build-dependency-validation")
& $flutter @buildArgs 2>&1 | Tee-Object -FilePath $log

$apk = Join-Path $repo "build\app\outputs\flutter-apk\app-release.apk"
if (Test-Path $apk) {
    Write-Host ""
    Write-Host "OK: $apk" -ForegroundColor Green
    Get-Item $apk | Select-Object FullName, Length, LastWriteTime
    exit 0
}

Write-Host ""
Write-Host "Build did not produce app-release.apk. See: $log" -ForegroundColor Red
exit 1

#Requires -Version 5.1
<#
.SYNOPSIS
  One-shot setup: Firebase CI token -> GitHub Actions secret FIREBASE_TOKEN -> optional workflow run.

  Prerequisites:
  - Node.js (for npx firebase-tools)
  - GitHub CLI: https://cli.github.com/  (winget install GitHub.cli)
  - gh auth login (this script runs it if needed)

  Usage (from repo root):
    .\scripts\setup-firebase-github-secret.ps1

  If you already have a token (e.g. from CI):
    $env:FIREBASE_CI_TOKEN = "your-token"
    .\scripts\setup-firebase-github-secret.ps1 -SkipFirebaseLogin
#>
param(
  [switch]$SkipFirebaseLogin,
  [switch]$RunDeployWorkflow
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

function Test-Gh {
  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "Install GitHub CLI: winget install GitHub.cli  or  https://cli.github.com/"
    exit 1
  }
}

function Ensure-GhAuth {
  gh auth status 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Write-Host "GitHub CLI: signing in..."
    gh auth login
  }
}

Test-Gh
Ensure-GhAuth

$token = $null
if ($env:FIREBASE_CI_TOKEN) {
  $token = $env:FIREBASE_CI_TOKEN.Trim()
  Write-Host "Using FIREBASE_CI_TOKEN from environment."
}
elseif ($SkipFirebaseLogin) {
  $token = Read-Host "Paste Firebase CI token"
}
else {
  Write-Host ""
  Write-Host "Firebase will open a browser for a one-time login, then print a CI token."
  Write-Host ""
  $raw = & npx --yes firebase-tools login:ci 2>&1 | ForEach-Object { "$_" }
  # Token is usually a long alphanumeric line (often last meaningful line)
  $candidate = $raw | Where-Object { $_ -match '^[A-Za-z0-9_\-]{30,}$' } | Select-Object -Last 1
  if ($candidate) { $token = $candidate.Trim() }
  if (-not $token) {
    Write-Host ($raw -join "`n")
    $token = Read-Host "Paste the Firebase CI token shown above"
  }
}

if ([string]::IsNullOrWhiteSpace($token)) {
  Write-Error "No token provided."
  exit 1
}

Write-Host "Uploading FIREBASE_TOKEN to GitHub Actions secrets for this repo..."
$token | gh secret set FIREBASE_TOKEN
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Done. Secret FIREBASE_TOKEN is set."
Write-Host ""
Write-Host "Next pushes that change firestore.rules (on main) will deploy rules automatically."
Write-Host "Or run: gh workflow run deploy-firestore-rules.yml"
Write-Host ""

if ($RunDeployWorkflow) {
  gh workflow run "deploy-firestore-rules.yml" 2>$null
  if ($LASTEXITCODE -eq 0) {
    Write-Host "Triggered workflow deploy-firestore-rules.yml"
  } else {
    Write-Host "Run manually: gh workflow run deploy-firestore-rules.yml"
    gh workflow list
  }
}

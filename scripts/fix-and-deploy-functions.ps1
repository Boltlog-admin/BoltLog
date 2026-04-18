# Fix Cloud Functions deploy: grant gcf-sources bucket access to Compute + Cloud Build
# service accounts, then deploy. Uses gcloud (installs via winget if missing).
$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $ProjectRoot "firebase.json"))) {
    Write-Error "Could not find project root (firebase.json). Run from repo root or scripts folder."
}

function Find-Gcloud {
    $g = Get-Command gcloud -ErrorAction SilentlyContinue
    if ($g) { return $g.Source }
    $paths = @(
        "${env:ProgramFiles(x86)}\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd",
        "${env:ProgramFiles}\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd",
        "$env:LOCALAPPDATA\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

$gcloud = Find-Gcloud
if (-not $gcloud) {
    Write-Host "Google Cloud SDK not found. Installing via winget..."
    winget install -e --id Google.CloudSDK --accept-package-agreements --accept-source-agreements
    $gcloud = Find-Gcloud
    if (-not $gcloud) {
        Write-Host "Install may have completed. Please open a NEW terminal and run this script again."
        exit 1
    }
}

$gcloudDir = Split-Path (Split-Path $gcloud)
$env:Path = "$gcloudDir;$env:Path"

$authList = & $gcloud auth list --format="value(account)" 2>$null
$active = $authList | Where-Object { $_ -and $_ -notmatch "^\s*$" } | Select-Object -First 1
if (-not $active) {
    Write-Host "Google Cloud CLI is not logged in. Opening browser to sign in..."
    & $gcloud auth login
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Host "Granting Storage Object Viewer to service accounts (project: boltlog)..."
& $gcloud projects add-iam-policy-binding boltlog --member="serviceAccount:28158895372-compute@developer.gserviceaccount.com" --role="roles/storage.objectViewer" --quiet
if ($LASTEXITCODE -ne 0) { Write-Host "If you see an auth error, run: gcloud auth login"; exit $LASTEXITCODE }
& $gcloud projects add-iam-policy-binding boltlog --member="serviceAccount:28158895372@cloudbuild.gserviceaccount.com" --role="roles/storage.objectViewer" --quiet
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Granting Artifact Registry Writer to Cloud Build (needed for function image push)..."
& $gcloud projects add-iam-policy-binding boltlog --member="serviceAccount:28158895372@cloudbuild.gserviceaccount.com" --role="roles/artifactregistry.writer" --quiet
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Granting Logs Writer to Cloud Build (so build logs are visible)..."
& $gcloud projects add-iam-policy-binding boltlog --member="serviceAccount:28158895372@cloudbuild.gserviceaccount.com" --role="roles/logging.logWriter" --quiet
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Granting Cloud Run Builder to Cloud Build (required for function build)..."
& $gcloud projects add-iam-policy-binding boltlog --member="serviceAccount:28158895372@cloudbuild.gserviceaccount.com" --role="roles/run.builder" --quiet
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$ArtifactsBucket = "us.artifacts.boltlog.appspot.com"
Write-Host "Resetting artifacts bucket (fix build cache)..."
$errPreference = $ErrorActionPreference
$ErrorActionPreference = "SilentlyContinue"
& $gcloud storage rm --recursive "gs://$ArtifactsBucket" --quiet 2>&1 | Out-Null
& $gcloud storage buckets delete "gs://$ArtifactsBucket" --quiet 2>&1 | Out-Null
$ErrorActionPreference = $errPreference
Write-Host "Artifacts bucket step done. Deploy will recreate if needed."
Start-Sleep -Seconds 5

Write-Host "Waiting 30s for IAM propagation, then deploying functions..."
Start-Sleep -Seconds 30
Push-Location $ProjectRoot
try {
    npx firebase-tools deploy --only functions
} finally {
    Pop-Location
}

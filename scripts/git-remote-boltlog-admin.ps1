# Point this repo at https://github.com/Boltlog-admin/BoltLog and use org commit author.
# Push still uses your Windows/Git credential: sign in as Boltlog-admin (or use SSH) or you get 403.
param(
    [switch]$Ssh
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path (Join-Path $root ".git"))) {
    throw "Could not find repo root (.git). Expected parent of scripts/ to be BoltLog root."
}

Push-Location $root
try {
    $url = if ($Ssh) { "git@github.com:Boltlog-admin/BoltLog.git" } else { "https://github.com/Boltlog-admin/BoltLog.git" }
    git remote remove origin 2>$null
    git remote add origin $url
    git config user.name "Boltlog-admin"
    git config user.email "Boltlog-admin@users.noreply.github.com"
    Write-Host "origin -> $url"
    Write-Host "local author -> Boltlog-admin <Boltlog-admin@users.noreply.github.com>"
    Write-Host ""
    Write-Host "Next: git push -u origin main"
    Write-Host "If you see 'denied to <other user>', clear the saved GitHub login for this PC:"
    Write-Host "  Git Credential Manager: remove github.com / Or sign out in git-credential-manager"
    Write-Host "  Then push again and authenticate as Boltlog-admin."
}
finally {
    Pop-Location
}

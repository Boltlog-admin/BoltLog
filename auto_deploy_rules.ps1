# Comprehensive Firebase Storage Rules Deployment Script
$ErrorActionPreference = "Continue"
Write-Host "=== Firebase Storage Rules Auto-Deployment ===" -ForegroundColor Cyan
Write-Host ""

# Method 1: Try Firebase CLI
Write-Host "[Method 1] Attempting Firebase CLI deployment..." -ForegroundColor Yellow
$firebaseDeploy = firebase deploy --only storage 2>&1 | Out-String
if ($LASTEXITCODE -eq 0) {
    Write-Host "SUCCESS: Deployed via Firebase CLI!" -ForegroundColor Green
    exit 0
}

Write-Host ""

# Method 2: Open Firebase Console
Write-Host "[Method 2] Opening Firebase Console..." -ForegroundColor Yellow
$consoleUrl = "https://console.firebase.google.com/project/boltlog/storage/boltlog.firebasestorage.app/rules"
Start-Process $consoleUrl
Write-Host "Browser opened to Firebase Console" -ForegroundColor Green
Write-Host ""

# Method 3: Create HTML helper
Write-Host "[Method 3] Creating HTML helper file..." -ForegroundColor Yellow
$rulesContent = Get-Content "storage.rules" -Raw
$htmlTemplate = @'
<!DOCTYPE html>
<html>
<head>
    <title>Firebase Storage Rules Deployment</title>
    <style>
        body { font-family: Arial, sans-serif; padding: 20px; background: #f5f5f5; }
        .container { max-width: 900px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; }
        h1 { color: #1E40AF; }
        .rules-box { background: #1E293B; color: #E2E8F0; padding: 20px; border-radius: 8px; font-family: monospace; white-space: pre-wrap; }
        .copy-btn { background: #2563EB; color: white; border: none; padding: 12px 24px; border-radius: 6px; cursor: pointer; font-size: 16px; margin: 10px 0; }
        .copy-btn:hover { background: #1E40AF; }
        .success { background: #10B981; color: white; padding: 15px; border-radius: 6px; margin: 10px 0; display: none; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Firebase Storage Rules Deployment</h1>
        <p><strong>Instructions:</strong></p>
        <ol>
            <li>Click "Copy Rules" button below</li>
            <li>Go to <a href="https://console.firebase.google.com/project/boltlog/storage/boltlog.firebasestorage.app/rules" target="_blank">Firebase Console</a></li>
            <li>Paste rules and click Publish</li>
        </ol>
        <button class="copy-btn" onclick="copyRules()">Copy Rules to Clipboard</button>
        <div class="success" id="successMsg">Rules copied!</div>
        <h3>Storage Rules:</h3>
        <div class="rules-box" id="rulesContent">RULES_PLACEHOLDER</div>
    </div>
    <script>
        const rulesText = `RULES_JS_PLACEHOLDER`;
        function copyRules() {
            navigator.clipboard.writeText(rulesText).then(() => {
                document.getElementById('successMsg').style.display = 'block';
                setTimeout(() => document.getElementById('successMsg').style.display = 'none', 3000);
            });
        }
    </script>
</body>
</html>
'@

$rulesEscaped = $rulesContent -replace '`', '\`' -replace '\$', '\$' -replace '<', '&lt;' -replace '>', '&gt;'
$htmlContent = $htmlTemplate -replace 'RULES_PLACEHOLDER', $rulesEscaped -replace 'RULES_JS_PLACEHOLDER', ($rulesContent -replace '`', '\`' -replace '\$', '\$')

$htmlContent | Out-File -FilePath "deploy_rules_helper.html" -Encoding UTF8
Start-Process "deploy_rules_helper.html"
Write-Host "HTML helper created and opened" -ForegroundColor Green
Write-Host ""

# Display rules
Write-Host "[Method 4] Rules content:" -ForegroundColor Yellow
Write-Host ("=" * 60) -ForegroundColor Gray
Get-Content "storage.rules"
Write-Host ("=" * 60) -ForegroundColor Gray
Write-Host ""

Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "Firebase Console and HTML helper opened" -ForegroundColor Green
Write-Host "Copy rules from HTML page or console output above" -ForegroundColor Yellow
Write-Host "Paste into Firebase Console and click Publish" -ForegroundColor Yellow

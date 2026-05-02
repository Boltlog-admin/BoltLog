@echo off
REM Fix Google Cloud setup via CMD so Cloud Functions can deploy.
REM Run this AFTER activating billing in Console: https://console.cloud.google.com/billing

set GCLOUD="C:\Program Files (x86)\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd"

echo Setting project to boltlog...
cmd /c %GCLOUD% config set project boltlog
echo.
echo Creating App Engine app (required for Cloud Functions)...
%GCLOUD% app create --region=us-central --quiet
if errorlevel 1 (
  echo.
  echo App Engine create failed. If it says "billing account" or "PERMISSION_DENIED":
  echo 1. Go to https://console.cloud.google.com/billing
  echo 2. Open the billing account linked to boltlog and activate it (add payment method if needed).
  echo 3. Run this script again.
  goto :error
)

echo.
echo Deploying Cloud Functions...
cd /d "%~dp0"
call npx firebase-tools deploy --only functions
if errorlevel 1 goto :error

echo.
echo Done. Image uploads in the app should work now.
pause
goto :eof

:error
echo.
echo Something failed. Check the messages above.
pause
exit /b 1

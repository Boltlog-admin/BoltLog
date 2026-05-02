@echo off
cd /d "%~dp0"
set "PS1=%~dp0windows_build_apk.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -Wait -Verb RunAs -FilePath powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','%PS1%'"
echo Exit code: %ERRORLEVEL%
pause

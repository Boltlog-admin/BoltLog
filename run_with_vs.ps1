# Script to run Flutter with Visual Studio environment configured
# This ensures Flutter can find the Visual Studio toolchain

Write-Host "Setting up Visual Studio 2022 environment..." -ForegroundColor Cyan

$vsPath = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"

if (Test-Path $vsPath) {
    Write-Host "Found Visual Studio 2022 Community" -ForegroundColor Green
    
    # Call VsDevCmd.bat and then run flutter commands
    cmd /c "`"$vsPath`" -arch=x64 -host_arch=x64 && flutter doctor -v"
} else {
    Write-Host "Visual Studio 2022 Community not found at expected path" -ForegroundColor Red
    Write-Host "Please ensure Visual Studio 2022 is installed with 'Desktop development with C++' workload" -ForegroundColor Yellow
}

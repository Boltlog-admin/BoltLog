# Windows Development Setup Guide

## Problem
Flutter cannot find a suitable Visual Studio toolchain to build Windows apps.

**Current Issue Detected:**
- Flutter is detecting Visual Studio 2026 Insiders (pre-release version)
- Missing required components: MSVC v142 build tools, C++ CMake tools, Windows 10 SDK

## Solution

You have two options:

### Option 1: Fix Visual Studio 2026 Insiders (Recommended if you want to use it)

1. Open **Visual Studio Installer**
2. Find **Visual Studio 2026 Insiders**
3. Click **Modify**
4. Ensure the **"Desktop development with C++"** workload is selected
5. Under Individual components, make sure these are checked:
   - **MSVC v142 - VS 2019 C++ x64/x86 build tools** (or latest version available)
   - **C++ CMake tools for Windows**
   - **Windows 10 SDK** (version 10.0.19041.0 or higher)
6. Click **Modify** to install the missing components

### Option 2: Use Visual Studio 2022 Community (More Stable)

You have Visual Studio 2022 Community installed. To make Flutter use it instead:

1. Open **Visual Studio Installer**
2. Find **Visual Studio 2022 Community**
3. Click **Modify**
4. Ensure the **"Desktop development with C++"** workload is selected with:
   - MSVC v143 - VS 2022 C++ x64/x86 build tools
   - Windows 10 SDK
   - C++ CMake tools for Windows
5. Install/repair if needed

**Note:** Flutter may prefer VS 2026 Insiders if both are installed. You may need to uninstall VS 2026 Insiders or configure Flutter to use VS 2022.

### Step 1: Download Visual Studio 2022

1. Go to: https://visualstudio.microsoft.com/downloads/
2. Download **Visual Studio 2022 Community** (free) or Professional/Enterprise if you have a license

### Step 2: Install Required Components

During installation, select the following workload:

**"Desktop development with C++"**

This workload includes:
- MSVC v143 - VS 2022 C++ x64/x86 build tools
- Windows 10 SDK (or Windows 11 SDK)
- C++ CMake tools for Windows
- Testing tools for core features

### Step 3: Verify Installation

After installation, restart your terminal and run:

```powershell
flutter doctor -v
```

You should see:
- ✅ Visual Studio - develop for Windows
- ✅ Visual Studio - develop Windows apps (Visual Studio Community 2022)

### Step 4: Run Your App

Once Visual Studio is properly installed, you can run:

```powershell
flutter run -d windows
```

## Alternative: Install Only Build Tools

If you don't want the full Visual Studio IDE, you can install just the build tools:

1. Download "Build Tools for Visual Studio 2022" from the same page
2. During installation, select "C++ build tools" workload
3. Include Windows 10/11 SDK

## Quick Check

To verify if Visual Studio is installed but not detected:

```powershell
# Check if Visual Studio is installed
& "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat" -arch=x64 -host_arch=x64 && cl
```

If this works, Visual Studio is installed but Flutter can't find it. You may need to:
1. Restart your terminal/IDE
2. Run `flutter doctor` again
3. Ensure you're using the correct Visual Studio installation

## Troubleshooting

### If Visual Studio is installed but missing components:

1. **Open Visual Studio Installer** (search for it in Start menu)
2. **Find your Visual Studio installation** (2022 Community or 2026 Insiders)
3. **Click "Modify"**
4. **Select "Desktop development with C++" workload**
5. **Under Individual components, verify these are checked:**
   - MSVC v142 or v143 C++ build tools (latest version)
   - C++ CMake tools for Windows
   - Windows 10 SDK (10.0.19041.0 or higher)
6. **Click "Modify" to install missing components**
7. **Restart your terminal/IDE** after installation completes
8. **Run `flutter doctor -v` again** to verify

### If Flutter detects the wrong Visual Studio version:

If Flutter is detecting VS 2026 Insiders but you want to use VS 2022:
1. You can uninstall VS 2026 Insiders, OR
2. Ensure VS 2022 has all required components installed
3. Flutter should automatically prefer the stable version

### Quick Fix Script

Use the provided `run_with_vs.ps1` script to run Flutter with Visual Studio environment configured:

```powershell
powershell -ExecutionPolicy Bypass -File .\run_with_vs.ps1
```

### Minimum Requirements:

- Visual Studio 2022 (or 2019)
- Windows 10 SDK (10.0.19041.0 or higher)
- MSVC v143 - VS 2022 C++ x64/x86 build tools

## Notes

- Visual Studio Code is NOT the same as Visual Studio - you need the full Visual Studio IDE or Build Tools
- The Community edition is free and sufficient for Flutter development
- Installation can take 30-60 minutes depending on your internet speed

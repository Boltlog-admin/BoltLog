# 📸 Setting Up Logo Images

## Folder Structure
The logo images should be placed in: `assets/images/Boltlog Logo/`

## Required Images

### 1. `1-removebg-preview.png`
- **Used for**: Splash screen (the Flutter splash screen that shows after app launch)
- **Location**: `assets/images/Boltlog Logo/1-removebg-preview.png`
- **Status**: ✅ Code updated to use this image

### 2. `2.png`
- **Used for**: App launcher icon (the icon shown on device home screen)
- **Location**: `assets/images/Boltlog Logo/2.png`
- **Status**: ✅ Code updated to use this image
- **Note**: After adding this file, run:
  ```powershell
  flutter pub get
  flutter pub run flutter_launcher_icons
  ```

### 3. `3 no background.png` (transparent)
- **Used for**: Native launch screen (shows before Flutter loads)
- **Location**: `assets/images/Boltlog Logo/3 no background.png`
- **Android Location**: `android/app/src/main/res/drawable/launch_3.png` (auto-copied by script)
- **Status**: ✅ Code updated to use this image
- **Note**: The setup script automatically copies this to the Android drawable folder

## Setup Instructions

### Step 1: Add Images to Assets Folder
1. Copy `1-removebg-preview.png` to: `assets/images/Boltlog Logo/`
2. Copy `2.png` to: `assets/images/Boltlog Logo/`

### Step 2: Launch Image for Android (Automatic)
1. Place `3 no background.png` in: `assets/images/Boltlog Logo/`
2. Run the setup script: `.\setup_logo_images.ps1`
   - This automatically copies the file to `android/app/src/main/res/drawable/launch_3.png`

### Step 3: Update pubspec.yaml (if needed)
The `pubspec.yaml` already references the assets folder, so images in `assets/images/` should be automatically included.

### Step 4: Generate Launcher Icons
After adding `2.png`, run:
```powershell
flutter pub get
flutter pub run flutter_launcher_icons
```

### Step 5: Clean and Rebuild
```powershell
flutter clean
flutter pub get
flutter run
```

## Image Specifications

### For Launcher Icon (2.png)
- **Recommended size**: 1024x1024 pixels
- **Format**: PNG with transparency
- **Background**: Transparent or white

### For Splash Screen (1-removebg-preview.png)
- **Recommended size**: 512x512 pixels or larger
- **Format**: PNG with transparency
- **Background**: Transparent (removebg suggests background removed)

### For Launch Screen (3 no background.png)
- **Recommended size**: 512x512 pixels or larger
- **Format**: PNG with transparency
- **Background**: Transparent (no background)
- **File name**: `3 no background.png` (exact name required)

## Current Status

✅ **Splash Screen**: Updated to use `1-removebg-preview.png`
✅ **Launcher Icon Config**: Updated to use `2.png`
✅ **Launch Background**: Updated to use `3.png` (as `launch_image_3.png`)

⚠️ **Action Required**: 
- Add the three image files to their respective locations
- Run `flutter pub run flutter_launcher_icons` after adding `2.png`

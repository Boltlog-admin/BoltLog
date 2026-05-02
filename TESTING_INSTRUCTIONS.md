# Testing Instructions

## Current Status

- **Android Emulator:** Available (emulator-5554)
- **Build Status:** Background build in progress
- **Direct Run:** Starting on emulator for immediate testing

## Testing Options

### Option 1: Direct Run (Recommended for Testing)
```bash
flutter run -d emulator-5554
```
- Builds debug version (faster)
- Installs and runs automatically
- Hot reload enabled for quick iterations
- **Status:** Running now

### Option 2: Wait for Release APK
```bash
# Check if build completed
Test-Path build\app\outputs\flutter-apk\app-release.apk

# Install APK manually
adb install build\app\outputs\flutter-apk\app-release.apk
```

## What to Test

### 1. Authentication Flow
- [ ] Splash screen displays
- [ ] Sign up as Sender
- [ ] Sign up as Transporter
- [ ] Login functionality
- [ ] Role-based navigation

### 2. Location Features
- [ ] Location picker opens
- [ ] Google Maps displays (with API key)
- [ ] Tap on map to select location
- [ ] Search for addresses
- [ ] Get current GPS location
- [ ] Save locations
- [ ] Use saved locations

### 3. Sender Features
- [ ] Request transport screen
- [ ] Enter package details
- [ ] Price calculation works
- [ ] Submit transport request
- [ ] View delivery history
- [ ] Real-time status updates

### 4. Transporter Features
- [ ] View available deliveries
- [ ] Accept delivery
- [ ] View active deliveries
- [ ] Mark as picked up
- [ ] Mark as delivered
- [ ] Real-time updates

### 5. Additional Features
- [ ] Chat functionality (if integrated)
- [ ] Rating system (if integrated)
- [ ] Price negotiation (if integrated)

## Testing Checklist

### Critical Paths
1. **New User Journey:**
   - Sign up → Select role → Complete profile → Use app

2. **Sender Journey:**
   - Login → Request transport → Enter details → Submit → Track delivery

3. **Transporter Journey:**
   - Login → View available → Accept → Pick up → Deliver → Get rated

### Known Issues to Watch For
- Google Maps API key validation
- Location permissions
- Real-time Firestore updates
- Navigation between screens

## Debug Commands

### View Logs
```bash
flutter logs
```

### Hot Reload
Press `r` in terminal while app is running

### Hot Restart
Press `R` in terminal while app is running

### Stop App
Press `q` in terminal

## Building Release APK

Once testing is complete:
```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

## Next Steps

1. Test all features on emulator
2. Fix any issues found
3. Build release APK when ready
4. Test release APK before distribution


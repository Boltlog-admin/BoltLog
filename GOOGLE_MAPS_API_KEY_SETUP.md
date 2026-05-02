# Google Maps API Key Configuration

## ✅ API Key Configured

Your Google Maps API key has been successfully configured:

**API Key:** `AIzaSyClL3xASi4tP-Y7c9Cc9mmJ6P0CL3P98J4`

## Configuration Files Updated

### Android
- **File:** `android/app/src/main/AndroidManifest.xml`
- **Added:** Google Maps API key meta-data
- **Added:** Location permissions (ACCESS_FINE_LOCATION, ACCESS_COARSE_LOCATION)

### iOS
- **File:** `ios/Runner/AppDelegate.swift`
- **Added:** GoogleMaps import and API key initialization
- **File:** `ios/Runner/Info.plist`
- **Added:** Location usage descriptions

## Features Enabled

✅ Interactive Google Maps widget in location picker
✅ Tap on map to select location
✅ Search for addresses
✅ Get current GPS location
✅ Reverse geocoding (coordinates to address)
✅ Map markers for selected locations
✅ Camera animations

## Testing

1. Run the app: `flutter run`
2. Navigate to "Request Transport"
3. Tap on pickup or dropoff location field
4. You should see an interactive Google Map
5. Tap anywhere on the map to select that location
6. The address will be automatically filled

## Important Notes

⚠️ **API Key Restrictions:** Make sure to restrict your API key in Google Cloud Console:
- Restrict to Android apps (package name: `com.example.boltlog`)
- Restrict to iOS apps (bundle ID: your iOS bundle ID)
- Enable only these APIs:
  - Maps SDK for Android
  - Maps SDK for iOS
  - Geocoding API
  - Places API (optional, for better search)

⚠️ **Billing:** Google Maps requires a billing account, but provides $200 free credit per month.

## Troubleshooting

If maps don't load:
1. Check API key is correct in both AndroidManifest.xml and AppDelegate.swift
2. Verify API key restrictions in Google Cloud Console
3. Ensure Maps SDK is enabled for your project
4. Check that billing is enabled on your Google Cloud project


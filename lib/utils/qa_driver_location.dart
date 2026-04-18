import 'package:geolocator/geolocator.dart';

import '../config/testing_flags.dart';

/// Resolves a lat/lng for transporter discovery. Uses GPS when possible; in QA
/// builds can fall back so simulators / denied-GPS flows still work.
class QaDriverLocation {
  QaDriverLocation._();

  static Future<({double lat, double lng})?> resolve() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return _fallbackOrNull();
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return _fallbackOrNull();
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      return (lat: pos.latitude, lng: pos.longitude);
    } catch (_) {
      return _fallbackOrNull();
    }
  }

  static ({double lat, double lng})? _fallbackOrNull() {
    if (!TestingFlags.useQaFallbackDriverBaseLocation) {
      return null;
    }
    return (
      lat: TestingFlags.qaFallbackDriverBaseLat,
      lng: TestingFlags.qaFallbackDriverBaseLng,
    );
  }
}

import 'dart:math' as math;
import '../models/ride_model.dart';
import '../services/pricing_service.dart';

/// inDrive-style: show only nearby requests to driver, sorted by distance to pickup.
const double defaultMaxRadiusKm = 30.0;

double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const double R = 6371;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return R * c;
}

/// Distance from driver (or any point) to ride pickup. Returns null if ride has no pickup coords.
double? distanceToPickupKm(RideModel ride, double driverLat, double driverLng) {
  if (ride.pickupLat == null || ride.pickupLng == null) return null;
  return _haversineKm(driverLat, driverLng, ride.pickupLat!, ride.pickupLng!);
}

/// Straight-line km from pickup to drop-off (for compact transporter UI). Null if coords missing.
double? pickupToDropoffKm(RideModel ride) {
  if (ride.pickupLat == null ||
      ride.pickupLng == null ||
      ride.dropoffLat == null ||
      ride.dropoffLng == null) {
    return null;
  }
  return PricingService.calculateDistance(
    ride.pickupLat!,
    ride.pickupLng!,
    ride.dropoffLat!,
    ride.dropoffLng!,
  );
}

/// Filter rides to those within maxRadiusKm of driver, then rank by:
/// 1) distance to pickup (closest first),
/// 2) fresh negotiation activity (newer request first as responsiveness proxy).
/// Rides without pickup coords are included at the end.
List<RideModel> filterAndSortRidesByDistance(
  List<RideModel> rides, {
  required double? driverLat,
  required double? driverLng,
  double maxRadiusKm = defaultMaxRadiusKm,
}) {
  if (driverLat == null || driverLng == null) return rides;
  final withDistance = <(RideModel, double?)>[];
  for (final r in rides) {
    final d = distanceToPickupKm(r, driverLat, driverLng);
    withDistance.add((r, d));
  }
  withDistance.sort((a, b) {
    int byRecency() {
      return b.$1.createdAt.compareTo(a.$1.createdAt);
    }

    final da = a.$2;
    final db = b.$2;
    if (da == null && db == null) return byRecency();
    if (da == null) return 1;
    if (db == null) return -1;
    if (da > maxRadiusKm && db > maxRadiusKm) {
      final distanceCmp = da.compareTo(db);
      return distanceCmp != 0 ? distanceCmp : byRecency();
    }
    if (da > maxRadiusKm) return 1;
    if (db > maxRadiusKm) return -1;
    final distanceCmp = da.compareTo(db);
    return distanceCmp != 0 ? distanceCmp : byRecency();
  });
  return withDistance
      .where((e) => e.$2 == null || e.$2! <= maxRadiusKm)
      .map((e) => e.$1)
      .toList();
}

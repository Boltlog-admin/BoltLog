import '../models/ride_model.dart';

/// Determines whether chat should be available for a given ride.
///
/// Rules (aligned with inDrive-style flow):
/// - Chat is available while the delivery is active:
///   status in ['open', 'pending', 'in_progress', 'parcel_collected'].
/// - After completion, chat stays available for a short grace window
///   (e.g. 2 days) to handle lost items / follow-up.
/// - After the grace window or if cancelled, chat is disabled.
bool isChatAllowedForRide(RideModel ride, {Duration graceAfterCompletion = const Duration(days: 2)}) {
  switch (ride.status) {
    case 'open':
    case 'pending':
    case 'in_progress':
    case 'parcel_collected':
      return true;
    case 'completed':
      if (ride.completedAt == null) return false;
      return DateTime.now().difference(ride.completedAt!) <= graceAfterCompletion;
    case 'cancelled':
    default:
      return false;
  }
}


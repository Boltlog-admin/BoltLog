/// Shared wording for sender tracking map + transporter navigation map
/// so both sides understand they share the same live trip phase.
class LiveMapCopy {
  LiveMapCopy._();

  /// Sender: titles on [ActiveRideMapScreen] and related trip UI.
  static String senderMapTitle({
    required String rideStatus,
    required bool hasLiveGps,
    bool awaitingSenderPickupConfirm = false,
    bool awaitingSenderDeliveryConfirm = false,
  }) {
    switch (rideStatus) {
      case 'completed':
        return 'Delivered';
      case 'parcel_collected':
        if (awaitingSenderDeliveryConfirm) {
          return 'Transporter marked delivered — confirm receipt';
        }
        if (awaitingSenderPickupConfirm) {
          return 'Pickup by transporter — please confirm';
        }
        return hasLiveGps
            ? 'Live · Transporter travelling to delivery'
            : 'Parcel collected — waiting for live location…';
      case 'in_progress':
        return hasLiveGps
            ? 'Live · Transporter travelling to pickup'
            : 'Transporter assigned — waiting for GPS…';
      default:
        return hasLiveGps
            ? 'Live · Transporter heading to pickup'
            : 'Waiting for transporter GPS…';
    }
  }

  /// Transporter: [ActiveRideMapScreen] app bar + top banner title.
  static String transporterNavTitle({required bool toDelivery}) {
    return toDelivery
        ? 'Live · Travelling to delivery'
        : 'Live · Travelling to pickup';
  }

  /// Shown under the sender map title (both parties, same trip).
  static const String senderMapSharedTripHint =
      'Same live trip — you and your transporter both see updates.';

  /// Shown on transporter map (their position syncs to sender).
  static const String transporterSharedTripHint =
      'Same live trip — sender sees your position on their map.';

  /// Transporter: technical line under title (GPS stream).
  static const String transporterRealtimeGpsLine =
      'Real-time GPS — distance updates as you move';
}

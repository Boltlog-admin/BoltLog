import 'package:boltlog/constants/app_constants.dart';
import 'package:boltlog/models/ride_model.dart';
import 'package:boltlog/services/ride_service.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _baseRideMap({
  String status = 'open',
  String? driverId,
  String? negotiatingTransporterId,
  String? acceptedTransporterId,
  String? awaitingSenderConfirmDriverId,
}) {
  return <String, dynamic>{
    'userId': 'sender_uid',
    'pickupLocation': 'A',
    'dropoffLocation': 'B',
    'createdAt': DateTime.now().toIso8601String(),
    'status': status,
    if (driverId != null) 'driverId': driverId,
    if (negotiatingTransporterId != null)
      'negotiatingTransporterId': negotiatingTransporterId,
    if (acceptedTransporterId != null)
      'acceptedTransporterId': acceptedTransporterId,
    if (awaitingSenderConfirmDriverId != null)
      'awaitingSenderConfirmDriverId': awaitingSenderConfirmDriverId,
  };
}

void main() {
  group('AppConstants role helpers', () {
    test('isDriverRole matches Driver and transporter labels', () {
      expect(AppConstants.isDriverRole('Driver'), true);
      expect(AppConstants.isDriverRole('driver'), true);
      expect(AppConstants.isDriverRole('transporter'), true);
      expect(AppConstants.isDriverRole('Transporter'), true);
      expect(AppConstants.isDriverRole('Passenger'), false);
      expect(AppConstants.isDriverRole(null), false);
    });

    test('isPassengerRole matches passenger and empty', () {
      expect(AppConstants.isPassengerRole('Passenger'), true);
      expect(AppConstants.isPassengerRole(null), true);
    });

    test('Driver and transporter roles are mutually exclusive with passenger', () {
      expect(AppConstants.isDriverRole('Driver'), true);
      expect(AppConstants.isPassengerRole('Driver'), false);
    });
  });

  group('RideModel.fromMap uid fields', () {
    test('parses negotiatingTransporterId as string', () {
      final r = RideModel.fromMap(
        _baseRideMap(negotiatingTransporterId: 'tid_123'),
        'rid1',
      );
      expect(r.negotiatingTransporterId, 'tid_123');
    });
  });

  group('rideInTransporterRequestBrowseList', () {
    const tid = 'transporter_a';

    test('open ride with no driver is visible', () {
      final ride = RideModel.fromMap(_baseRideMap(), 'r1');
      expect(rideInTransporterRequestBrowseList(ride, tid), true);
    });

    test('cancelled ride is hidden', () {
      final ride = RideModel.fromMap(_baseRideMap(status: 'cancelled'), 'r2');
      expect(rideInTransporterRequestBrowseList(ride, tid), false);
    });

    test('another transporter awaiting sender hides ride from others', () {
      final ride = RideModel.fromMap(
        _baseRideMap(
          status: 'pending',
          awaitingSenderConfirmDriverId: 'someone_else',
        ),
        'r3',
      );
      expect(rideInTransporterRequestBrowseList(ride, tid), false);
    });

    test('this transporter awaiting sender still sees ride', () {
      final ride = RideModel.fromMap(
        _baseRideMap(
          status: 'pending',
          awaitingSenderConfirmDriverId: tid,
        ),
        'r4',
      );
      expect(rideInTransporterRequestBrowseList(ride, tid), true);
    });
  });
}

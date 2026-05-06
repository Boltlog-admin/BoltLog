import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import '../models/ride_model.dart';
import '../screens/active_ride_map_screen.dart';
import '../screens/request_detail_screen.dart';
import '../services/error_handler_service.dart';
import '../services/ride_service.dart';

/// Shared transporter commit → sender must confirm before [ActiveRideMapScreen] opens for both.
///
/// [usePushReplacement] — use `false` from home dashboard so Back returns to the dashboard.
Future<void> transporterAcceptRideOpenMap(
  BuildContext context,
  RideModel ride,
  String transporterId, {
  bool usePushReplacement = true,
}) async {
  if (ride.id == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Request ID is missing'),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }
  final rideService = RideService();
  final authUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
  final tid = authUid.isNotEmpty ? authUid : transporterId.trim();
  if (tid.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sign in to accept this request.'),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }
  try {
    // Offers are optional for commit; rules may deny subcollection writes — never block accept.
    unawaited(
      rideService
          .createOrUpdateOffer(
            ride.id!,
            tid,
            priceOffer: ride.finalPrice ?? ride.counterOffer ?? ride.price,
          )
          .catchError((Object e, StackTrace st) {
        debugPrint(
          'transporterAcceptRideOpenMap: createOrUpdateOffer skipped: $e\n$st',
        );
      }),
    );
    final wroteNewCommit = await rideService.acceptRide(ride.id!, tid);
    if (!context.mounted) return;
    final latestRide = await rideService
        .getRideById(ride.id!)
        .timeout(const Duration(milliseconds: 900), onTimeout: () => null);
    if (!context.mounted) return;
    final r = latestRide ?? ride;
    final onMap = r.driverId?.trim() == tid &&
        (r.status == 'in_progress' ||
            r.status == 'parcel_collected' ||
            r.status == 'completed');
    if (onMap) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Delivery started — opening live map.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
      final route = MaterialPageRoute<void>(
        builder: (_) => ActiveRideMapScreen(ride: r),
      );
      if (usePushReplacement) {
        Navigator.of(context).pushReplacement(route);
      } else {
        Navigator.of(context).push(route);
      }
      return;
    }
    final waitingOnSender = r.awaitingSenderConfirmDriverId?.trim() == tid &&
        (r.status == 'pending' || r.status == 'open');
    final waitingBody = !wroteNewCommit && waitingOnSender
        ? 'You\'re already waiting for the sender to confirm. The live map opens when they accept.'
        : 'Request sent.\nWaiting for sender\'s reply — the live map opens when they confirm.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          waitingBody,
          style: const TextStyle(height: 1.35),
        ),
        backgroundColor: const Color(0xFF2563EB),
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
      ),
    );
    final detailRoute = MaterialPageRoute<void>(
      builder: (_) => RequestDetailScreen(ride: r),
    );
    if (usePushReplacement) {
      Navigator.of(context).pushReplacement(detailRoute);
    } else {
      Navigator.of(context).push(detailRoute);
    }
  } catch (e) {
    if (!context.mounted) return;
    final latestRide = await rideService.getRideById(ride.id!);
    final myDriverId = latestRide?.driverId?.trim();
    final awaiting =
        latestRide?.awaitingSenderConfirmDriverId?.trim();
    final waitingOnSender = awaiting == tid &&
        (latestRide?.status == 'pending' || latestRide?.status == 'open');
    if (waitingOnSender) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Waiting for sender\'s reply — the live map opens when they confirm.',
            style: const TextStyle(height: 1.35),
          ),
          backgroundColor: const Color(0xFF2563EB),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        ),
      );
      final r = latestRide!;
      final detailRoute = MaterialPageRoute<void>(
        builder: (_) => RequestDetailScreen(ride: r),
      );
      if (usePushReplacement) {
        Navigator.of(context).pushReplacement(detailRoute);
      } else {
        Navigator.of(context).push(detailRoute);
      }
      return;
    }
    final alreadyAssignedToMe = latestRide != null &&
        myDriverId == tid &&
        (latestRide.status == 'in_progress' ||
            latestRide.status == 'parcel_collected' ||
            latestRide.status == 'completed');
    if (alreadyAssignedToMe) {
      final route = MaterialPageRoute<void>(
        builder: (_) => ActiveRideMapScreen(ride: latestRide!),
      );
      if (usePushReplacement) {
        Navigator.of(context).pushReplacement(route);
      } else {
        Navigator.of(context).push(route);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ErrorHandlerService.messageForDisplay(e)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

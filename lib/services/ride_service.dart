import 'dart:convert';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

import '../config/testing_flags.dart';
import '../constants/app_constants.dart';
import 'package:flutter/foundation.dart';
import '../models/ride_model.dart';
import '../models/user_model.dart';
import '../models/transporter_offer_model.dart';
import 'messaging_service.dart';
import 'pricing_service.dart';
import 'notification_service.dart';
import 'user_service.dart';

/// Rides counted as transporter **Active** (dashboard stat, Active Deliveries list):
/// - **On the job:** assigned driver is this transporter and status is [in_progress]
///   or [parcel_collected].
/// - **Agreed, not started:** status [pending], [priceStatus] `accepted`, and this
///   transporter is [negotiatingTransporterId] or [acceptedTransporterId].
/// Open price haggling (`priceStatus` pending) is excluded — those stay under Current Requests.
bool transporterCommittedActiveItem(RideModel ride, String transporterId) {
  final tid = transporterId.trim();
  if (tid.isEmpty) return false;
  if (ride.status == 'cancelled' || ride.status == 'completed') return false;

  final driverId = ride.driverId?.trim();
  if (driverId != null && driverId.isNotEmpty && driverId == tid) {
    return ride.status == 'in_progress' || ride.status == 'parcel_collected';
  }

  if (ride.status != 'pending') return false;
  if (ride.priceStatus != 'accepted') return false;
  final neg = ride.negotiatingTransporterId?.trim();
  final acc = ride.acceptedTransporterId?.trim();
  return neg == tid || acc == tid;
}

/// “Current requests” / browse lists for transporters. Returns false once this
/// transporter has accepted the job ([driverId] set to them) or the ride is
/// no longer in the open / pending negotiation phase.
bool rideInTransporterRequestBrowseList(RideModel ride, String transporterId) {
  final tid = transporterId.trim();
  if (tid.isEmpty) return true;

  final st = ride.status;
  if (st == 'cancelled' ||
      st == 'completed' ||
      st == 'in_progress' ||
      st == 'parcel_collected') {
    return false;
  }

  final awaiting = ride.awaitingSenderConfirmDriverId?.trim();
  if (awaiting != null && awaiting.isNotEmpty && awaiting != tid) {
    return false;
  }

  final d = ride.driverId?.trim();
  if (d != null && d.isNotEmpty) {
    if (!ride.isDriverSlotOpen && d != tid) {
      return false;
    }
    if (d == tid) {
      return false;
    }
  }

  return true;
}

/// Same rules as [RideModel.isDriverSlotOpen] for raw Firestore `driverId` values.
bool rideDriverSlotOpenFromField(dynamic driverIdField) {
  if (driverIdField == null) return true;
  final d = driverIdField.toString().trim();
  if (d.isEmpty) return true;
  final lower = d.toLowerCase();
  return lower == 'unassigned' || lower == 'none' || lower == 'null';
}

/// inDrive-style negotiation: a state machine that manages a digital "handshake."
/// - open: rider proposed_price broadcast; drivers can counter (+10% / +20% / +30% or custom).
/// - pending + priceStatus pending: NEGOTIATING (counter-offers exchanged).
/// - pending + priceStatus accepted: rider locked on one driver; finalPrice set; driver must "Accept" to proceed.
/// - in_progress: both agreed; final_fare locked; commission only if [TestingFlags.enableAcceptanceFeeDeduction].
/// Concurrency: only the first driver the rider "Accepts" is linked (transaction + acceptedTransporterId).
class RideService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> _deleteSubcollectionDocs(
    DocumentReference<Map<String, dynamic>> parentRef,
    String subcollectionName,
  ) async {
    const pageSize = 200;
    while (true) {
      final snapshot = await parentRef
          .collection(subcollectionName)
          .limit(pageSize)
          .get();
      if (snapshot.docs.isEmpty) break;

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (snapshot.docs.length < pageSize) break;
    }
  }

  /// [userId], [awaitingSenderConfirmDriverId], etc. may be a String UID or a
  /// [DocumentReference] to `users/{uid}`.
  String? _uidStringFromRideField(dynamic v) {
    if (v == null) return null;
    if (v is String) {
      final t = v.trim();
      return t.isEmpty ? null : t;
    }
    if (v is DocumentReference) {
      final path = v.path;
      final i = path.lastIndexOf('/');
      if (i >= 0 && i + 1 <= path.length) {
        return path.substring(i + 1);
      }
    }
    return null;
  }

  bool _rideOwnedBySenderUid(Map<String, dynamic> rideData, String senderUid) {
    final owner = _uidStringFromRideField(rideData['userId']);
    return owner != null && owner == senderUid;
  }

  // Create a new ride request. inDrive-style: broadcast to nearby drivers via push.
  Future<String> createRide(RideModel ride) async {
    try {
      final docRef = await _firestore.collection('rides').add(ride.toMap());
      final rideId = docRef.id;

      // Option B: Notify nearby drivers (push when request is created)
      if (ride.pickupLat != null && ride.pickupLng != null) {
        try {
          final userService = UserService();
          final nearbyDrivers = await userService.getNearbyDriversOnce(
            latitude: ride.pickupLat!,
            longitude: ride.pickupLng!,
            radiusKm: 25.0,
          );
          final notificationService = NotificationService();
          final priceStr = ride.price != null ? '\$${ride.price!.toStringAsFixed(2)} – ' : '';
          final message = '$priceStr${ride.pickupLocation} to ${ride.dropoffLocation}';
          for (final driver in nearbyDrivers) {
            await notificationService.createNotification(
              userId: driver.uid,
              type: 'new_request_nearby',
              title: 'New request near you',
              message: message,
              rideId: rideId,
              data: {'rideId': rideId},
            );
          }
        } catch (e) {
          debugPrint('Error notifying nearby drivers: $e');
        }
      }
      return rideId;
    } catch (e) {
      throw Exception('Error creating ride: $e');
    }
  }

  // Enforce only one active ride per user (open / pending / in progress / parcel_collected)
  Future<bool> userHasActiveRide(String userId) async {
    try {
      final querySnapshot = await _firestore
          .collection('rides')
          .where('userId', isEqualTo: userId)
          .where('status',
              whereIn: ['open', 'pending', 'in_progress', 'parcel_collected'])
          .limit(1)
          .get();
      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      throw Exception('Error checking active rides: $e');
    }
  }

  // Get user's rides with pagination
  Future<List<RideModel>> getUserRides(
    String userId, {
    int limit = 50,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      Query query = _firestore
          .collection('rides')
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final querySnapshot = await query.get();

      return querySnapshot.docs
          .map((doc) => RideModel.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    } catch (e) {
      throw Exception('Error getting user rides: $e');
    }
  }

  // Stream user's rides with pagination
  Stream<List<RideModel>> streamUserRides(String userId, {int limit = 50}) {
    return _firestore
        .collection('rides')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => RideModel.fromMap(doc.data() as Map<String, dynamic>, doc.id))
            .toList());
  }

  // Update ride status
  Future<void> updateRideStatus(String rideId, String status, {String? driverId}) async {
    try {
      final updateData = <String, dynamic>{'status': status};
      if (driverId != null) updateData['driverId'] = driverId;
      if (status == 'completed') {
        updateData['completedAt'] = DateTime.now().toIso8601String();
      }

      await _firestore.collection('rides').doc(rideId).update(updateData);
    } catch (e) {
      throw Exception('Error updating ride status: $e');
    }
  }

  // Get ride by ID
  Future<RideModel?> getRide(String rideId) async {
    try {
      final doc = await _firestore.collection('rides').doc(rideId).get();
      if (doc.exists) {
        return RideModel.fromMap(doc.data()!, doc.id);
      }
      return null;
    } catch (e) {
      throw Exception('Error getting ride: $e');
    }
  }

  /// One-time fetch of a ride by ID (e.g. for notification deep link).
  Future<RideModel?> getRideById(String rideId) async {
    final snapshot = await _firestore.collection('rides').doc(rideId).get();
    if (snapshot.exists && snapshot.data() != null) {
      return RideModel.fromMap(snapshot.data()!, snapshot.id);
    }
    return null;
  }

  // Stream a single ride by ID for real-time updates
  Stream<RideModel?> streamRideById(String rideId) {
    return _firestore
        .collection('rides')
        .doc(rideId)
        .snapshots()
        .map((snapshot) {
      if (snapshot.exists) {
        return RideModel.fromMap(snapshot.data()!, snapshot.id);
      }
      return null;
    });
  }

  /// Transporter writes live GPS to the ride document so the sender's tracking map
  /// updates in real time via [streamRideById].
  Future<void> updateDriverLiveLocationOnRide(
    String rideId,
    double latitude,
    double longitude,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw Exception('Not signed in');
    }
    try {
      final rideRef = _firestore.collection('rides').doc(rideId);
      final snap = await rideRef.get();
      if (!snap.exists) throw Exception('Ride not found');
      final data = snap.data()!;
      final driverId = data['driverId'] as String?;
      final accepted = data['acceptedTransporterId'] as String?;
      final negotiating = data['negotiatingTransporterId'] as String?;
      final status = data['status'] as String? ?? '';
      if (status == 'cancelled' || status == 'completed') {
        throw Exception('Ride is not active');
      }
      final allowed = driverId == uid ||
          accepted == uid ||
          (status == 'pending' && (negotiating == uid || accepted == uid));
      if (!allowed) {
        throw Exception('Not assigned to this delivery');
      }
      await rideRef.update({
        'driverLiveLat': latitude,
        'driverLiveLng': longitude,
        'driverLocationUpdatedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception('Error updating live location: $e');
    }
  }

  // Cancel ride (convenience wrapper)
  Future<void> cancelRide(String rideId) async {
    await cancelRideWithReason(rideId, cancelledBy: 'sender');
  }

  /// Cancels every non-finished request this sender created (`rides.userId`).
  /// Call while still authenticated, **before** [FirebaseAuth.signOut].
  /// Uses [cancelRideWithReason] (soft cancel + nested cleanup; transporters are notified if relevant).
  Future<void> cleanupSenderRidesBeforeLogout(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('rides')
          .where('userId', isEqualTo: userId)
          .limit(100)
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final status = data['status'] as String? ?? '';
        if (status == 'completed' || status == 'cancelled') continue;
        try {
          await cancelRideWithReason(doc.id, cancelledBy: 'sender');
        } catch (e) {
          debugPrint('cleanupSenderRidesBeforeLogout ${doc.id}: $e');
        }
      }
    } catch (e) {
      debugPrint('cleanupSenderRidesBeforeLogout: $e');
    }
  }

  /// inDrive-style cancellation: free when open/pending (before driver committed);
  /// after driver accepted, cancel is "late" – notify driver and store reason.
  Future<void> cancelRideWithReason(
    String rideId, {
    required String cancelledBy,
    String? cancellationReason,
  }) async {
    final rideRef = _firestore.collection('rides').doc(rideId);
    final rideSnap = await rideRef.get();
    if (!rideSnap.exists) throw Exception('Ride not found');
    final data = rideSnap.data()!;
    final status = data['status'] as String? ?? 'open';
    final driverId = data['driverId'] as String?;

    // Notify the other party
    try {
      final notificationService = NotificationService();
      if (cancelledBy == 'transporter') {
        final senderId = _uidStringFromRideField(data['userId']);
        if (senderId != null) {
          await notificationService.createNotification(
            userId: senderId,
            type: 'ride_cancelled',
            title: 'Driver cancelled',
            message: 'The transporter has cancelled this delivery. You can create a new request.',
            rideId: rideId,
            data: {'rideId': rideId, 'cancelledBy': cancelledBy},
          );
        }
      } else if (driverId != null && (status == 'in_progress' || status == 'parcel_collected')) {
        await notificationService.createNotification(
          userId: driverId,
          type: 'ride_cancelled',
          title: 'Request cancelled',
          message: 'The sender has cancelled this delivery.',
          rideId: rideId,
          data: {'rideId': rideId, 'cancelledBy': cancelledBy},
        );
      }
    } catch (e) {
      debugPrint('Error notifying of cancellation: $e');
    }

    // Soft cancel: keep the ride document (history + no “vanishing” if nested deletes fail).
    final now = DateTime.now().toIso8601String();
    await rideRef.update({
      'status': 'cancelled',
      'cancelledAt': now,
      'cancelledBy': cancelledBy,
      if (cancellationReason != null && cancellationReason.trim().isNotEmpty)
        'cancellationReason': cancellationReason.trim(),
      'updatedAt': now,
    });

    // Best-effort cleanup of nested docs; failures do not leave the ride in an unknown state.
    try {
      await _deleteSubcollectionDocs(rideRef, 'messages');
    } catch (e) {
      debugPrint('cancelRide cleanup messages: $e');
    }
    try {
      await _deleteSubcollectionDocs(rideRef, 'offers');
    } catch (e) {
      debugPrint('cancelRide cleanup offers: $e');
    }
    try {
      await _deleteSubcollectionDocs(rideRef, 'viewers');
    } catch (e) {
      debugPrint('cancelRide cleanup viewers: $e');
    }
  }

  /// True if cancellation is "free" (inDrive: before driver is committed). After driver accepted, late cancel.
  bool isFreeCancellation(RideModel ride) {
    if (ride.status == 'cancelled') return false;
    return ride.isDriverSlotOpen &&
        (ride.status == 'open' || (ride.status == 'pending' && ride.acceptedTransporterId == null));
  }

  // Get available rides for transporters (open, no driver assigned)
  // Rides are automatically excluded when:
  // Only 'open' rides are available. When an order is in negotiation (status 'pending'
  // or negotiatingTransporterId set), it is unavailable to other transporters.
  Stream<List<RideModel>> streamAvailableRides() {
    return _firestore
        .collection('rides')
        .where('status', isEqualTo: 'open')
        .snapshots()
        .map((snapshot) {
          final rides = <RideModel>[];
          for (var doc in snapshot.docs) {
            final data = doc.data();
            // Only include rides where driverId is null, missing, or empty
            final driverId = data['driverId'];

            // Only include rides that are still open, have no driver, and are not in negotiation.
            // Rides in negotiation (status 'pending' or negotiatingTransporterId set) are unavailable to other transporters.
            final negotiatingTransporterId = data['negotiatingTransporterId']?.toString().trim();
            final isInNegotiation = negotiatingTransporterId != null && negotiatingTransporterId.isNotEmpty;
            if ((driverId == null ||
                (driverId is String && driverId.isEmpty) ||
                (driverId?.toString().trim().isEmpty ?? false)) &&
                data['status'] == 'open' &&
                !isInNegotiation) {
              try {
                final ride = RideModel.fromMap(data, doc.id);
                if (ride.negotiatingTransporterId != null &&
                    ride.negotiatingTransporterId!.trim().isNotEmpty) continue;
                if (ride.isDriverSlotOpen && ride.status == 'open') {
                  rides.add(ride);
                } else {
                  // excluded
                }
              } catch (e) {
                // Skip invalid documents
                continue;
              }
            } else {
              // excluded by driverId filter
            }
          }

          // Sort by createdAt descending (newest first)
          rides.sort((a, b) => b.createdAt.compareTo(a.createdAt));

          return rides;
        });
  }

  /// Transporter-specific negotiations that should remain visible even after logout.
  /// These are rides where the transporter is the active negotiatingTransporterId and
  /// the ride is still in the negotiation phase (priceStatus can be `pending` or `accepted`).
  Stream<List<RideModel>> streamTransporterNegotiations(String transporterId) {
    return _firestore
        .collection('rides')
        .where('status', isEqualTo: 'pending')
        .where('negotiatingTransporterId', isEqualTo: transporterId)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => RideModel.fromMap(doc.data() as Map<String, dynamic>, doc.id))
              .where((ride) => ride.status != 'cancelled')
              .where((ride) {
                final ps = ride.priceStatus;
                return ps == null ||
                    ps == 'pending' ||
                    ps == 'accepted';
              })
              .where((ride) => rideInTransporterRequestBrowseList(ride, transporterId))
              .toList();
        });
  }

  /// Open listings + this transporter’s pending negotiations (same merge as [TransporterDashboardScreen]).
  Stream<List<RideModel>> streamTransporterRequestInbox(String transporterId) {
    final controller = StreamController<List<RideModel>>.broadcast();
    var openRides = <RideModel>[];
    var negRides = <RideModel>[];

    void emit() {
      final byId = <String, RideModel>{};
      for (final r in openRides) {
        if (!rideInTransporterRequestBrowseList(r, transporterId)) continue;
        final id = r.id;
        if (id != null) byId[id] = r;
      }
      for (final r in negRides) {
        if (!rideInTransporterRequestBrowseList(r, transporterId)) continue;
        final id = r.id;
        if (id != null) byId[id] = r;
      }
      controller.add(byId.values.toList());
    }

    final sub1 = streamAvailableRides().listen(
      (list) {
        openRides = list;
        emit();
      },
      onError: controller.addError,
    );
    final sub2 = streamTransporterNegotiations(transporterId).listen(
      (list) {
        negRides = list;
        emit();
      },
      onError: controller.addError,
    );

    controller.onCancel = () async {
      await sub1.cancel();
      await sub2.cancel();
    };

    return controller.stream;
  }

  /// Sender approved this transporter but [driverId] not set yet (defensive if [negotiatingTransporterId] diverges).
  Stream<List<RideModel>> streamTransporterPendingDriverAcceptance(
      String transporterId) {
    return _firestore
        .collection('rides')
        .where('acceptedTransporterId', isEqualTo: transporterId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => RideModel.fromMap(doc.data() as Map<String, dynamic>, doc.id))
              .where((ride) {
                final d = ride.driverId?.trim();
                return d == null || d.isEmpty;
              })
              .where((ride) => ride.status != 'cancelled')
              .toList();
        });
  }

  /// Transporter "active" items = accepted/in-progress deliveries + active negotiations.
  Stream<List<RideModel>> streamTransporterActiveItems(String transporterId) {
    final controller = StreamController<List<RideModel>>.broadcast();

    List<RideModel> _deliveries = [];
    List<RideModel> _negotiations = [];
    List<RideModel> _pendingAccept = [];

    void emitMerged() {
      final byId = <String, RideModel>{};
      for (final r in _deliveries) {
        final id = r.id;
        if (id != null) byId[id] = r;
      }
      for (final r in _negotiations) {
        final id = r.id;
        if (id != null) byId[id] = r;
      }
      for (final r in _pendingAccept) {
        final id = r.id;
        if (id != null) byId[id] = r;
      }
      final merged = byId.values.toList();
      controller.add(
        merged
            .where((r) => transporterCommittedActiveItem(r, transporterId))
            .toList(),
      );
    }

    final sub1 = streamTransporterDeliveries(transporterId).listen(
      (data) {
        _deliveries = data;
        emitMerged();
      },
      onError: controller.addError,
    );
    final sub2 = streamTransporterNegotiations(transporterId).listen(
      (data) {
        _negotiations = data;
        emitMerged();
      },
      onError: controller.addError,
    );
    final sub3 = streamTransporterPendingDriverAcceptance(transporterId).listen(
      (data) {
        _pendingAccept = data;
        emitMerged();
      },
      onError: controller.addError,
    );

    controller.onCancel = () async {
      await sub1.cancel();
      await sub2.cancel();
      await sub3.cancel();
    };

    return controller.stream;
  }

  // Get transporter's active deliveries
  Stream<List<RideModel>> streamTransporterDeliveries(String transporterId) {
    return _firestore
        .collection('rides')
        .where('driverId', isEqualTo: transporterId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => RideModel.fromMap(doc.data() as Map<String, dynamic>, doc.id))
            .where((ride) =>
                ride.status != 'completed' && ride.status != 'cancelled')
            .toList());
  }

  // Get transporter's completed deliveries (for earnings calculation) with pagination
  Stream<List<RideModel>> streamTransporterCompletedDeliveries(
    String transporterId, {
    int limit = 50,
  }) {
    return _firestore
        .collection('rides')
        .where('driverId', isEqualTo: transporterId)
        .where('status', isEqualTo: 'completed')
        .orderBy('completedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => RideModel.fromMap(doc.data() as Map<String, dynamic>, doc.id))
            .toList());
  }

  // --- Transporter offers (inDrive-style interest) ---

  CollectionReference<Map<String, dynamic>> _offerCollection(String rideId) {
    return _firestore
        .collection('rides')
        .doc(rideId)
        .collection('offers');
  }

  // Transporter expresses interest in a ride (creates or updates an offer)
  Future<void> createOrUpdateOffer(
    String rideId,
    String transporterId, {
    double? priceOffer,
  }) async {
    try {
      final offersRef = _offerCollection(rideId);
      final existing = await offersRef
          .where('transporterId', isEqualTo: transporterId)
          .limit(1)
          .get();

      final now = DateTime.now().toIso8601String();

      if (existing.docs.isNotEmpty) {
        await existing.docs.first.reference.update({
          'priceOffer': priceOffer,
          'updatedAt': now,
        });
      } else {
        await offersRef.add({
          'rideId': rideId,
          'transporterId': transporterId,
          'priceOffer': priceOffer,
          'status': 'pending',
          'createdAt': now,
          'updatedAt': now,
        });
      }
    } on FirebaseException catch (e) {
      // Offers are optional for assignment; acceptRide updates the ride doc. Don't block map navigation.
      if (e.code == 'permission-denied') {
        debugPrint('createOrUpdateOffer: permission-denied (skipping): $e');
        return;
      }
      throw Exception('Error creating offer: $e');
    } catch (e) {
      throw Exception('Error creating offer: $e');
    }
  }

  // Stream offers for a specific ride
  Stream<List<TransporterOfferModel>> streamOffersForRide(String rideId) {
    return _offerCollection(rideId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) =>
                TransporterOfferModel.fromMap(doc.data(), doc.id))
            .toList());
  }

  // Mark selected and rejected offers when a transporter is chosen
  Future<void> markSelectedOffer(
      String rideId, String selectedOfferId) async {
    try {
      final offersRef = _offerCollection(rideId);
      final snapshot = await offersRef.get();

      for (final doc in snapshot.docs) {
        final newStatus =
            doc.id == selectedOfferId ? 'selected' : 'rejected';
        await doc.reference.update({
          'status': newStatus,
          'updatedAt': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      throw Exception('Error updating offer statuses: $e');
    }
  }

  /// When sender declines an offer (without counter-offer), reject that offer and reopen the ride
  /// so it becomes visible to other transporters again.
  Future<void> rejectOfferAndReopenRide(String rideId, String offerId) async {
    try {
      final offerDoc = await _offerCollection(rideId).doc(offerId).get();
      if (!offerDoc.exists) return;
      final offerData = offerDoc.data() as Map<String, dynamic>?;
      final transporterId = offerData?['transporterId'] as String?;
      final rideSnap = await _firestore.collection('rides').doc(rideId).get();
      final senderUserId =
          _uidStringFromRideField(rideSnap.data()?['userId']);

      await _firestore.collection('rides').doc(rideId).update({
        'status': 'open',
        'counterOffer': null,
        'priceStatus': null,
        'negotiatingTransporterId': null,
        'lastCounterOfferBy': null,
        'acceptedTransporterId': null,
        'finalPrice': null,
        'lastReopenReason': 'sender_declined',
        'updatedAt': DateTime.now().toIso8601String(),
      });
      await _offerCollection(rideId).doc(offerId).update({
        'status': 'rejected',
        'updatedAt': DateTime.now().toIso8601String(),
      });

      if (transporterId != null && senderUserId != null) {
        try {
          await NotificationService().createNotification(
            userId: transporterId,
            type: 'offer_declined',
            title: 'Offer Declined',
            message:
                'The sender has declined your offer. This request is open to other transporters.',
            rideId: rideId,
            data: {'rideId': rideId},
          );
          await MessagingService().sendSenderDeclinedServiceMessage(
            rideId: rideId,
            senderId: senderUserId,
            transporterId: transporterId,
          );
        } catch (e) {
          debugPrint('rejectOfferAndReopenRide notify/chat: $e');
        }
      }
    } catch (e) {
      throw Exception('Error rejecting offer and reopening ride: $e');
    }
  }

  /// When transporter declines the request, reopen the ride so it is visible to other transporters again.
  Future<void> transporterDeclineRequest(String rideId, String transporterId) async {
    try {
      final offersRef = _offerCollection(rideId);
      final snapshot = await offersRef
          .where('transporterId', isEqualTo: transporterId)
          .limit(1)
          .get();
      await _firestore.collection('rides').doc(rideId).update({
        'status': 'open',
        'counterOffer': null,
        'priceStatus': null,
        'negotiatingTransporterId': null,
        'lastCounterOfferBy': null,
        'acceptedTransporterId': null,
        'finalPrice': null,
        'lastReopenReason': 'transporter_declined',
        'updatedAt': DateTime.now().toIso8601String(),
      });
      for (final doc in snapshot.docs) {
        await doc.reference.update({
          'status': 'rejected',
          'updatedAt': DateTime.now().toIso8601String(),
        });
      }

      final rideDoc = await _firestore.collection('rides').doc(rideId).get();
      final senderId = _uidStringFromRideField(rideDoc.data()?['userId']);
      if (senderId != null) {
        try {
          await NotificationService().createNotification(
            userId: senderId,
            type: 'transporter_declined_request',
            title: 'Transporter Declined',
            message:
                'A transporter has declined your request. It is open again for other transporters.',
            rideId: rideId,
            data: {'rideId': rideId},
          );
          await MessagingService().sendTransporterDeclinedServiceMessage(
            rideId: rideId,
            transporterId: transporterId,
            senderId: senderId,
          );
        } catch (e) {
          debugPrint('transporterDeclineRequest notify/chat: $e');
        }
      }
    } catch (e) {
      throw Exception('Error declining request: $e');
    }
  }

  /// Clears [RideModel.lastReopenReason] after the sender has seen the transporter-decline UX.
  Future<void> clearLastReopenReason(String rideId) async {
    try {
      await _firestore.collection('rides').doc(rideId).update({
        'lastReopenReason': FieldValue.delete(),
      });
    } catch (e) {
      debugPrint('clearLastReopenReason: $e');
    }
  }

  Never _throwTransporterCommitCallableFailure(String code, String? message) {
    final msg = message?.trim();
    final c = code.toLowerCase().replaceAll('_', '-');
    switch (c) {
      case 'unauthenticated':
        throw Exception('Sign in to accept this request.');
      case 'permission-denied':
        throw Exception(
          msg ?? 'You are not allowed to perform this action as this user.',
        );
      case 'invalid-argument':
      case 'failed-precondition':
      case 'not-found':
        throw Exception(msg ?? 'This request can no longer be accepted.');
      case 'unavailable':
      case 'deadline-exceeded':
      case 'resource-exhausted':
        throw Exception(
          'Could not reach the server. Check your connection and try again.',
        );
      case 'internal':
        throw Exception(
          msg ?? 'Server error while accepting. Please try again in a moment.',
        );
      default:
        if (msg != null && msg.isNotEmpty) {
          throw Exception(msg);
        }
        throw Exception('Request failed ($code)');
    }
  }

  Never _throwFromTransporterCommitCallable(FirebaseFunctionsException e) {
    _throwTransporterCommitCallableFailure(e.code, e.message);
  }

  /// Primary path: Firebase Callable SDK (handles CORS on web and attaches auth reliably).
  /// Falls back to Firestore queue first, then HTTPS, then client transaction.
  Future<Map<String, dynamic>> _invokeTransporterCommitRide({
    required String rideId,
    required String transporterId,
  }) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'transporterCommitRide',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 5)),
      );
      final result = await callable.call(<String, dynamic>{
        'rideId': rideId,
        'transporterId': transporterId,
      });
      final data = result.data;
      if (data is Map) {
        return Map<String, dynamic>.from(data as Map);
      }
      throw Exception('Invalid server response from transporterCommitRide');
    } on FirebaseFunctionsException catch (e, st) {
      debugPrint(
        'transporterCommitRide callable failed (${e.code}): ${e.message} '
        '— trying direct fallbacks\n$st',
      );
      try {
        // Fast fallback: explicit HTTPS call with auth token.
        return await _transporterCommitRideViaHttps(
          rideId: rideId,
          transporterId: transporterId,
        );
      } catch (_) {
        try {
          // Fast local fallback when callable/HTTPS path is blocked.
          return await _transporterCommitRideViaClientTransaction(
            rideId: rideId,
            transporterId: transporterId,
          );
        } catch (_) {
          // Last fallback: queue worker path (can be slower due to polling).
          return _transporterCommitRideViaQueue(
            rideId: rideId,
            transporterId: transporterId,
          );
        }
      }
    }
  }

  /// Last-resort fallback: perform the transporter commit transition directly from
  /// client Firestore transaction (subject to security rules).
  Future<Map<String, dynamic>> _transporterCommitRideViaClientTransaction({
    required String rideId,
    required String transporterId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty || uid != transporterId) {
      throw Exception('Sign in with the selected transporter account before accepting.');
    }
    final rideRef = _firestore.collection('rides').doc(rideId);
    String? senderUserId;
    bool wroteCommit = false;

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(rideRef);
      if (!snap.exists) {
        throw Exception('Ride not found');
      }
      final data = snap.data() ?? <String, dynamic>{};
      final status = (data['status'] as String?) ?? 'open';
      if (status == 'cancelled' ||
          status == 'completed' ||
          status == 'in_progress' ||
          status == 'parcel_collected') {
        throw Exception('This request can no longer be accepted.');
      }

      senderUserId = _uidStringFromRideField(data['userId']);
      final awaiting = _uidStringFromRideField(data['awaitingSenderConfirmDriverId']);
      final driverId = _uidStringFromRideField(data['driverId']);
      if (awaiting == transporterId || driverId == transporterId) {
        wroteCommit = false;
        return;
      }
      if (awaiting != null && awaiting.isNotEmpty && awaiting != transporterId) {
        throw Exception('Another transporter is already waiting for sender confirmation.');
      }

      final update = <String, dynamic>{
        'awaitingSenderConfirmDriverId': transporterId,
        'negotiatingTransporterId': transporterId,
        'status': 'pending',
        'updatedAt': DateTime.now().toIso8601String(),
      };
      tx.update(rideRef, update);
      wroteCommit = true;
    });

    return <String, dynamic>{
      'wroteCommit': wroteCommit,
      'senderUserId': senderUserId,
    };
  }

  /// Firebase Callable HTTP API with explicit ID token (works when the
  /// `cloud_functions` channel omits auth on some Android builds).
  Future<Map<String, dynamic>> _transporterCommitRideViaHttps({
    required String rideId,
    required String transporterId,
  }) async {
    final app = Firebase.app();
    final projectId = app.options.projectId;
    if (projectId == null || projectId.isEmpty) {
      throw Exception('Firebase is not configured.');
    }
    final user = FirebaseAuth.instanceFor(app: app).currentUser;
    if (user == null) {
      throw Exception('Your session expired. Please sign in again.');
    }
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw Exception('Could not refresh sign-in. Please sign in again.');
    }
    final uri = Uri.parse(
      'https://us-central1-$projectId.cloudfunctions.net/transporterCommitRide',
    );
    final resp = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'data': {
              'rideId': rideId,
              'transporterId': transporterId,
            },
          }),
        )
        .timeout(const Duration(seconds: 15));

    dynamic decoded;
    try {
      decoded = jsonDecode(resp.body);
    } catch (_) {
      final snippet = resp.body.length > 400
          ? '${resp.body.substring(0, 400)}…'
          : resp.body;
      debugPrint(
        'transporterCommitRide HTTPS: parse fail status=${resp.statusCode} '
        'len=${resp.body.length} body=$snippet',
      );
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        debugPrint(
          'transporterCommitRide HTTPS blocked (${resp.statusCode}); '
          'falling back to Firestore queue trigger.',
        );
        return _transporterCommitRideViaQueue(
          rideId: rideId,
          transporterId: transporterId,
        );
      }
      throw Exception(
        'Server error (${resp.statusCode}). Check connection and try again.',
      );
    }
    if (decoded is! Map) {
      throw Exception('Invalid server response.');
    }
    final envelope = Map<String, dynamic>.from(decoded as Map);
    if (envelope.containsKey('error')) {
      final err = envelope['error'];
      if (err is Map) {
        final errMap = Map<String, dynamic>.from(err as Map);
        final status = (errMap['status'] as String?) ?? 'INTERNAL';
        final message = errMap['message'] as String?;
        _throwTransporterCommitCallableFailure(status, message);
      }
      _throwTransporterCommitCallableFailure('internal', 'Request failed');
    }
    final result = envelope['result'];
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    throw Exception('Invalid server response.');
  }

  Future<Map<String, dynamic>> _transporterCommitRideViaQueue({
    required String rideId,
    required String transporterId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Your session expired. Please sign in again.');
    }
    final reqRef = _firestore.collection('transporterCommitRequests').doc();
    final now = DateTime.now().toIso8601String();
    await reqRef.set({
      'rideId': rideId,
      'transporterId': transporterId,
      'requesterUid': user.uid,
      'status': 'pending',
      'createdAt': now,
      'updatedAt': now,
    });

    Future<Map<String, dynamic>?> readRideCommitState() async {
      final rideSnap = await _firestore.collection('rides').doc(rideId).get();
      if (!rideSnap.exists) return null;
      final rideData = rideSnap.data() ?? const <String, dynamic>{};
      final awaiting =
          (rideData['awaitingSenderConfirmDriverId'] as String?)?.trim();
      final driverId = (rideData['driverId'] as String?)?.trim();
      final status = (rideData['status'] as String?) ?? '';
      final senderUserId = _uidStringFromRideField(rideData['userId']);

      final waitingOnSender = awaiting == transporterId &&
          (status == 'pending' || status == 'open');
      final alreadyAssigned = driverId == transporterId;

      if (waitingOnSender || alreadyAssigned) {
        return <String, dynamic>{
          'wroteCommit': false,
          'senderUserId': senderUserId,
        };
      }
      return null;
    }

    // Keep queue fallback responsive: long waits make accept feel stuck.
    final end = DateTime.now().add(const Duration(seconds: 8));
    var tick = 0;
    while (DateTime.now().isBefore(end)) {
      final snap = await reqRef.get();
      if (snap.exists) {
        final data = snap.data() ?? const <String, dynamic>{};
        final status = (data['status'] as String?) ?? '';
        if (status == 'done') {
          return <String, dynamic>{
            'wroteCommit': data['wroteCommit'],
            'senderUserId': data['senderUserId'],
          };
        }
        if (status == 'error') {
          final code = (data['errorCode'] as String?) ?? 'internal';
          final msg = data['errorMessage'] as String?;
          _throwTransporterCommitCallableFailure(code, msg);
        }
      }
      // Defensive: if the queue status doc lags/fails to update, still trust the ride state.
      if (tick % 3 == 0) {
        final rideCommitState = await readRideCommitState();
        if (rideCommitState != null) return rideCommitState;
      }
      tick += 1;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    final rideCommitState = await readRideCommitState();
    if (rideCommitState != null) return rideCommitState;
    throw Exception(
      'Timed out waiting for server. Please try again. '
      'If this keeps happening, the server worker may be unavailable.',
    );
  }

  bool _jsonBool(dynamic v) {
    if (v == true) return true;
    if (v is String && v.toLowerCase() == 'true') return true;
    return false;
  }

  Future<void> _sendTransporterCommitNotifications(
    String rideId,
    String tid, {
    String? senderUserId,
  }) async {
    var senderId = senderUserId;
    if (senderId == null || senderId.isEmpty) {
      final rideDoc = await _firestore.collection('rides').doc(rideId).get();
      final rideData = rideDoc.data();
      senderId = _uidStringFromRideField(rideData?['userId']);
    }
    if (senderId == null || senderId.isEmpty) return;
    try {
      await NotificationService().createNotification(
        userId: senderId,
        type: 'transporter_awaits_sender_confirm',
        title: 'Transporter accepted your request',
        message:
            'A transporter is ready to deliver. Open the request to confirm or view their profile.',
        rideId: rideId,
        data: {'rideId': rideId},
      );
      await NotificationService().createNotification(
        userId: tid,
        type: 'waiting_sender_confirm',
        title: 'Waiting for sender',
        message:
            'The sender must confirm before the trip starts and the map opens.',
        rideId: rideId,
        data: {'rideId': rideId},
      );
    } catch (e) {
      debugPrint('transporterRequestSenderConfirmation notify: $e');
    }
  }

  Future<void> _sendTransporterCommitChatNudge(
    String rideId,
    String tid, {
    String? senderUserId,
  }) async {
    var senderId = senderUserId;
    if (senderId == null || senderId.isEmpty) {
      final rideDoc = await _firestore.collection('rides').doc(rideId).get();
      final rideData = rideDoc.data();
      senderId = _uidStringFromRideField(rideData?['userId']);
    }
    if (senderId == null || senderId.isEmpty) return;
    try {
      await MessagingService().sendTransporterAwaitingSenderMessage(
        rideId: rideId,
        senderId: senderId,
        transporterId: tid,
      );
    } catch (e) {
      debugPrint('transporterRequestSenderConfirmation chat nudge: $e');
    }
  }

  /// Transporter commits to the job; **[driverId]** is set only after the sender confirms
  /// via [senderConfirmTransporterAndStartRide]. Notifies the sender to accept/decline or view details.
  ///
  /// Returns `true` if this call wrote a new commit; `false` if the server treated it as
  /// idempotent (already waiting or already assigned) — UI should still show waiting state.
  Future<bool> transporterRequestSenderConfirmation(
    String rideId,
    String transporterId,
  ) async {
    try {
      final tid = transporterId.trim();
      if (tid.isEmpty) {
        throw Exception('Invalid transporter account');
      }

      debugPrint(
        'transporterRequestSenderConfirmation start '
        'project=${Firebase.app().options.projectId} ride=$rideId tid=$tid',
      );

      final app = Firebase.app();
      final currentUser = FirebaseAuth.instanceFor(app: app).currentUser;
      if (currentUser == null) {
        throw Exception('Your session expired. Please sign in again.');
      }
      final authUid = currentUser.uid.trim();
      if (authUid != tid) {
        throw Exception(
          'Sign in with the selected transporter account before accepting.',
        );
      }

      // Callable first (web + mobile); HTTPS + queue fallbacks inside [_invokeTransporterCommitRide].
      final map = await _invokeTransporterCommitRide(
        rideId: rideId,
        transporterId: tid,
      );
      final wroteCommit = _jsonBool(map['wroteCommit']);
      final senderUserId = map['senderUserId'] as String?;
      if (!wroteCommit) {
        debugPrint(
          'transporterRequestSenderConfirmation: idempotent (wroteCommit=false) '
          'ride=$rideId tid=$tid — UI should still show waiting-on-sender from ride snapshot',
        );
        return false;
      }
      unawaited(_sendTransporterCommitNotifications(
        rideId,
        tid,
        senderUserId: senderUserId,
      ));
      unawaited(_sendTransporterCommitChatNudge(
        rideId,
        tid,
        senderUserId: senderUserId,
      ));
      return true;
    } on FirebaseFunctionsException catch (e, st) {
      debugPrint(
        'transporterCommitRide FirebaseFunctionsException: ${e.code} '
        '${e.message}\n$st',
      );
      _throwFromTransporterCommitCallable(e);
    } on FirebaseException catch (e, st) {
      debugPrint(
        'transporterRequestSenderConfirmation Firestore: ${e.code} '
        '${e.message}\n$st',
      );
      rethrow;
    } catch (e, st) {
      debugPrint('transporterRequestSenderConfirmation: $e\n$st');
      rethrow;
    }
  }

  /// Sender confirms the transporter after [transporterRequestSenderConfirmation].
  /// Sets [driverId], moves to [in_progress], applies platform fee when enabled, then chat/notifications.
  Future<void> senderConfirmTransporterAndStartRide(String rideId) async {
    final senderUid = FirebaseAuth.instance.currentUser?.uid;
    if (senderUid == null) {
      throw Exception('You must be signed in');
    }

    try {
      await _firestore.runTransaction((transaction) async {
        final rideRef = _firestore.collection('rides').doc(rideId);
        final rideSnap = await transaction.get(rideRef);
        if (!rideSnap.exists) {
          throw Exception('Ride not found');
        }
        final rideData = rideSnap.data() as Map<String, dynamic>;
        if (!_rideOwnedBySenderUid(rideData, senderUid)) {
          throw Exception('Only the sender can confirm this delivery');
        }
        final tid = _uidStringFromRideField(
          rideData['awaitingSenderConfirmDriverId'],
        );
        if (tid == null || tid.isEmpty) {
          throw Exception('No transporter is waiting for your confirmation');
        }

        final userRef = _firestore.collection('users').doc(tid);

        final price = (rideData['price'] as num?)?.toDouble() ?? 0.0;
        final counterOffer = (rideData['counterOffer'] as num?)?.toDouble();
        final lockedFare = rideData['finalPrice'] != null
            ? (rideData['finalPrice'] as num).toDouble()
            : (counterOffer ?? price);

        final updatePayload = <String, dynamic>{
          'driverId': tid,
          'status': 'in_progress',
          'awaitingSenderConfirmDriverId': FieldValue.delete(),
          'updatedAt': DateTime.now().toIso8601String(),
        };
        if (rideData['finalPrice'] == null) {
          updatePayload['finalPrice'] = lockedFare;
        }

        if (TestingFlags.enableAcceptanceFeeDeduction && lockedFare > 0) {
          final fee = lockedFare * PricingService.platformFeePercentage;
          if (fee > 0) {
            final userSnap = await transaction.get(userRef);
            if (!userSnap.exists) {
              throw Exception('Transporter account not found');
            }
            final userData = userSnap.data() as Map<String, dynamic>;
            final currentBalance =
                (userData['driverWalletBalance'] as num?)?.toDouble() ?? 0.0;
            if (currentBalance < fee) {
              throw Exception(
                'Transporter has insufficient balance for the platform fee. '
                'Ask them to top up, then try again.',
              );
            }
            final newBalance = currentBalance - fee;
            final nowIso = DateTime.now().toIso8601String();
            transaction.update(userRef, {
              'driverWalletBalance': newBalance,
            });
            final walletTxnRef =
                _firestore.collection('walletTransactions').doc();
            transaction.set(walletTxnRef, {
              'userId': tid,
              'type': 'deduction',
              'amount': fee,
              'paymentMethod': 'platform_fee',
              'status': 'completed',
              'reference': 'ACCEPT_$rideId',
              'rideId': rideId,
              'agreedPrice': lockedFare,
              'platformFeeRate': PricingService.platformFeePercentage,
              'balanceAfter': newBalance,
              'createdAt': nowIso,
              'completedAt': nowIso,
            });
          }
        }

        transaction.update(rideRef, updatePayload);
      });

      try {
        final rideDoc = await _firestore.collection('rides').doc(rideId).get();
        final data = rideDoc.data();
        final senderUserId = _uidStringFromRideField(data?['userId']);
        final driverId = (data?['driverId'] as String?)?.trim();
        if (senderUserId != null && driverId != null && driverId.isNotEmpty) {
          await MessagingService().sendTransporterSelectedMessage(
            rideId: rideId,
            senderId: senderUserId,
            transporterId: driverId,
          );
          await NotificationService().createNotification(
            userId: driverId,
            type: 'sender_confirmed_start',
            title: 'Sender confirmed',
            message:
                'The sender confirmed this delivery. Open the app to view the live map.',
            rideId: rideId,
            data: {'rideId': rideId},
          );
        }
      } catch (chatError) {
        debugPrint('senderConfirmTransporterAndStartRide chat: $chatError');
      }
    } catch (e, st) {
      debugPrint('senderConfirmTransporterAndStartRide: $e\n$st');
      rethrow;
    }
  }

  /// Sender declines the transporter who committed; ride reopens for others.
  Future<void> senderDeclineTransporterCommit(String rideId) async {
    final senderUid = FirebaseAuth.instance.currentUser?.uid;
    if (senderUid == null) {
      throw Exception('You must be signed in');
    }

    final rideRef = _firestore.collection('rides').doc(rideId);
    final rideSnap = await rideRef.get();
    if (!rideSnap.exists) {
      throw Exception('Ride not found');
    }
    final rideData = rideSnap.data() as Map<String, dynamic>;
    if (!_rideOwnedBySenderUid(rideData, senderUid)) {
      throw Exception('Only the sender can update this request');
    }
    final tid =
        _uidStringFromRideField(rideData['awaitingSenderConfirmDriverId']);
    if (tid == null || tid.isEmpty) {
      throw Exception('Nothing to decline');
    }

    await rideRef.update({
      'status': 'open',
      'awaitingSenderConfirmDriverId': FieldValue.delete(),
      'negotiatingTransporterId': null,
      'acceptedTransporterId': null,
      'counterOffer': null,
      'priceStatus': null,
      'finalPrice': null,
      'lastCounterOfferBy': null,
      'lastReopenReason': 'sender_declined_transporter_commit',
      'updatedAt': DateTime.now().toIso8601String(),
    });

    try {
      await NotificationService().createNotification(
        userId: tid,
        type: 'sender_declined_transporter_commit',
        title: 'Not selected',
        message:
            'The sender did not confirm you for this delivery. The request is open to others.',
        rideId: rideId,
        data: {'rideId': rideId},
      );
    } catch (e) {
      debugPrint('senderDeclineTransporterCommit notify: $e');
    }
  }

  /// @deprecated Use [transporterRequestSenderConfirmation] (sender must confirm before map).
  /// Returns whether a new commit was written (see [transporterRequestSenderConfirmation]).
  Future<bool> acceptRide(String rideId, String transporterId) async {
    try {
      return transporterRequestSenderConfirmation(rideId, transporterId);
    } catch (e, st) {
      debugPrint('acceptRide primary path failed, trying direct fallback: $e\n$st');
      final tid = transporterId.trim();
      if (tid.isEmpty) rethrow;
      final map = await _transporterCommitRideViaClientTransaction(
        rideId: rideId,
        transporterId: tid,
      );
      final wroteCommit = _jsonBool(map['wroteCommit']);
      final senderUserId = map['senderUserId'] as String?;
      if (wroteCommit) {
        await _sendTransporterCommitNotifications(
          rideId,
          tid,
          senderUserId: senderUserId,
        );
        await _sendTransporterCommitChatNudge(
          rideId,
          tid,
          senderUserId: senderUserId,
        );
      }
      return wroteCommit;
    }
  }

  // Check balance and notify transporter if insufficient
  Future<bool> checkBalanceAndNotify(String transporterId, double requiredAmount) async {
    if (!TestingFlags.enableAcceptanceFeeDeduction) {
      return true;
    }
    try {
      final userDoc = await _firestore.collection('users').doc(transporterId).get();
      if (!userDoc.exists) {
        return false;
      }
      
      final userData = userDoc.data() as Map<String, dynamic>? ?? {};
      double currentBalance = (userData['driverWalletBalance'] as num?)?.toDouble() ?? 0.0;
      
      if (currentBalance < requiredAmount) {
        // Notify transporter to top up
        final notificationService = NotificationService();
        await notificationService.createNotification(
          userId: transporterId,
          type: 'insufficient_balance',
          title: 'Insufficient Balance',
          message: 'Your wallet balance (\$${currentBalance.toStringAsFixed(2)}) is insufficient. Please top up \$${requiredAmount.toStringAsFixed(2)} to accept this request.',
          data: {
            'requiredAmount': requiredAmount,
            'currentBalance': currentBalance,
            'shortfall': requiredAmount - currentBalance,
          },
        );
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('Error checking balance: $e');
      return false;
    }
  }

  // Mark as picked up / parcel collected (notify sender so both see status)
  Future<void> markPickedUp(String rideId) async {
    final now = DateTime.now().toIso8601String();
    await _firestore.collection('rides').doc(rideId).update({
      'status': 'parcel_collected',
      'pickupMarkedByDriverAt': now,
      'updatedAt': now,
    });
    try {
      final rideDoc = await _firestore.collection('rides').doc(rideId).get();
      final userId = _uidStringFromRideField(rideDoc.data()?['userId']);
      if (userId != null) {
        final notificationService = NotificationService();
        await notificationService.createNotification(
          userId: userId,
          type: 'parcel_collected',
          title: 'Parcel Collected',
          message:
              'The transporter collected your parcel. Please open the app and confirm pickup.',
          rideId: rideId,
        );
      }
    } catch (e) {
      debugPrint('Error notifying sender of parcel collected: $e');
    }
  }

  /// Sender acknowledges that they agree the parcel was collected.
  Future<void> senderConfirmParcelCollected(String rideId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in');
    final ref = _firestore.collection('rides').doc(rideId);
    final snap = await ref.get();
    if (!snap.exists) throw Exception('Ride not found');
    final data = snap.data()!;
    if (!_rideOwnedBySenderUid(data, uid)) {
      throw Exception('Only the sender can confirm pickup');
    }
    final now = DateTime.now().toIso8601String();
    await ref.update({
      'pickupConfirmedBySenderAt': now,
      'updatedAt': now,
    });
  }

  /// Transporter marks delivery complete — [status] stays `parcel_collected` until [senderConfirmDeliveryComplete].
  Future<void> markDelivered(String rideId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in');
    final ref = _firestore.collection('rides').doc(rideId);
    final snap = await ref.get();
    if (!snap.exists) throw Exception('Ride not found');
    final data = snap.data()!;
    final driverId = data['driverId'] as String?;
    if (driverId != uid) {
      throw Exception('Only the assigned transporter can mark delivered');
    }
    if (data['deliveryMarkedByDriverAt'] != null &&
        (data['deliveryMarkedByDriverAt'] as String).isNotEmpty) {
      throw Exception('Already marked — waiting for sender to confirm delivery');
    }
    final now = DateTime.now().toIso8601String();
    await ref.update({
      'deliveryMarkedByDriverAt': now,
      'updatedAt': now,
    });
    final senderId = _uidStringFromRideField(data['userId']);
    if (senderId != null) {
      try {
        await NotificationService().createNotification(
          userId: senderId,
          type: 'delivery_pending_sender_confirm',
          title: 'Confirm Delivery',
          message:
              'The transporter marked the parcel as delivered. Please confirm in the app to complete the trip.',
          rideId: rideId,
        );
      } catch (e) {
        debugPrint('notify sender delivery pending: $e');
      }
    }
  }

  /// Sender confirms receipt — sets [status] to `completed` and finalizes the trip.
  Future<void> senderConfirmDeliveryComplete(String rideId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in');
    final ref = _firestore.collection('rides').doc(rideId);
    final snap = await ref.get();
    if (!snap.exists) throw Exception('Ride not found');
    final data = snap.data()!;
    if (data['userId'] != uid) {
      throw Exception('Only the sender can confirm delivery');
    }
    if (data['deliveryMarkedByDriverAt'] == null) {
      throw Exception('Transporter has not marked delivery yet');
    }
    final now = DateTime.now().toIso8601String();
    await ref.update({
      'status': 'completed',
      'completedAt': now,
      'deliveryConfirmedBySenderAt': now,
      'updatedAt': now,
    });
    final driverId = data['driverId'] as String?;
    if (driverId != null) {
      try {
        await NotificationService().createNotification(
          userId: driverId,
          type: 'delivery_confirmed_by_sender',
          title: 'Delivery Confirmed',
          message: 'The sender confirmed receipt. This delivery is complete.',
          rideId: rideId,
        );
      } catch (e) {
        debugPrint('notify transporter delivery confirmed: $e');
      }
    }
  }

  // Track when the sender views the request (so transporter can see "Sender has viewed")
  Future<void> updateSenderLastViewed(String rideId) async {
    try {
      await _firestore.collection('rides').doc(rideId).update({
        'senderLastViewedAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // Silently fail - not critical
    }
  }

  // Track when a transporter views a request
  Future<void> trackRequestView(String rideId, String transporterId) async {
    try {
      final viewersRef = _firestore
          .collection('rides')
          .doc(rideId)
          .collection('viewers')
          .doc(transporterId);
      
      await viewersRef.set({
        'transporterId': transporterId,
        'viewedAt': DateTime.now().toIso8601String(),
        'lastSeenAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Error tracking request view: $e');
    }
  }

  // Update last seen when transporter is still viewing
  Future<void> updateViewerLastSeen(String rideId, String transporterId) async {
    try {
      final viewerRef = _firestore
          .collection('rides')
          .doc(rideId)
          .collection('viewers')
          .doc(transporterId);
      
      await viewerRef.set({
        'transporterId': transporterId,
        'lastSeenAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      // Silently fail - not critical
    }
  }

  // Stream online transporters viewing a request
  Stream<List<UserModel>> streamOnlineViewers(String rideId) {
    return _firestore
        .collection('rides')
        .doc(rideId)
        .collection('viewers')
        .snapshots()
        .asyncMap((viewersSnapshot) async {
      final onlineTransporters = <UserModel>[];
      
      for (var viewerDoc in viewersSnapshot.docs) {
        final viewerData = viewerDoc.data();
        final transporterId = viewerData['transporterId'] as String?;
        final lastSeenAt = viewerData['lastSeenAt'] as String?;
        
        if (transporterId == null) continue;
        
        // Check if viewer was active in last 30 seconds
        if (lastSeenAt != null) {
          final lastSeen = DateTime.parse(lastSeenAt);
          final now = DateTime.now();
          if (now.difference(lastSeen).inSeconds > 30) {
            continue; // Skip offline viewers
          }
        }
        
        // Get transporter user data
        try {
          final userDoc = await _firestore
              .collection('users')
              .doc(transporterId)
              .get();
          
          if (userDoc.exists) {
            final userData = userDoc.data()!;
            final user = UserModel.fromMap(userData);
            // Driver/transporter accounts only; availability defaults match [UserModel.fromMap]
            // (missing isAvailable means available — do not use ?? false here).
            if (AppConstants.isDriverRole(user.role) && (user.isAvailable ?? true)) {
              onlineTransporters.add(user);
            }
          }
        } catch (e) {
          // Skip if user not found
          continue;
        }
      }
      
      return onlineTransporters;
    });
  }

  // Submit counter-offer (transporter submits counter-offer to sender)
  // Changes ride status to 'pending' to indicate negotiation in progress
  Future<void> submitCounterOffer(
    String rideId,
    String transporterId,
    double counterOffer,
  ) async {
    try {
      // Ensure transporter is verified before allowing negotiation
      final userDoc = await _firestore.collection('users').doc(transporterId).get();
      if (!userDoc.exists) {
        throw Exception('Transporter account not found');
      }
      final userData = userDoc.data() as Map<String, dynamic>;
      final verificationStatus =
          (userData['verificationStatus'] as String? ?? '').toLowerCase();

      if (!TestingFlags.relaxTransporterVerification &&
          AppConstants.isDriverRole(userData['role'] as String?) &&
          verificationStatus != 'auto_verified' &&
          verificationStatus != 'verified') {
        throw Exception(
            'Your documents are still being verified. You cannot negotiate on requests yet.');
      }

      // Get ride to find sender ID
      final rideDoc = await _firestore.collection('rides').doc(rideId).get();
      if (!rideDoc.exists) {
        throw Exception('Ride not found');
      }
      final rideData = rideDoc.data() as Map<String, dynamic>;
      final senderId = _uidStringFromRideField(rideData['userId']);
      
      // Update the ride with counter-offer; mark this transporter as the one in negotiation (works for any sender/transporter)
      await _firestore.collection('rides').doc(rideId).update({
        'counterOffer': counterOffer,
        'priceStatus': 'pending',
        'status': 'pending',
        'lastCounterOfferBy': 'transporter',
        'negotiatingTransporterId': transporterId,
        'acceptedTransporterId': null,
        'finalPrice': null,
        'lastReopenReason': FieldValue.delete(),
        'updatedAt': DateTime.now().toIso8601String(),
      });

      // Also create/update the offer in the offers subcollection
      await createOrUpdateOffer(
        rideId,
        transporterId,
        priceOffer: counterOffer,
      );

      // Notify sender about the counter-offer
      if (senderId != null) {
        final notificationService = NotificationService();
        await notificationService.createNotification(
          userId: senderId,
          type: 'counter_offer',
          title: 'New Price Offer',
          message: 'A transporter has made a counter-offer of \$${counterOffer.toStringAsFixed(2)}. You can accept, reject, or make your own offer.',
          rideId: rideId,
          data: {
            'counterOffer': counterOffer,
            'transporterId': transporterId,
            'rideId': rideId,
          },
        );
      }
    } catch (e) {
      throw Exception('Error submitting counter-offer: $e');
    }
  }

  // Sender sends counter-counter-offer (renegotiates)
  Future<void> sendSenderCounterOffer(
    String rideId,
    String offerId,
    double senderCounterOffer,
  ) async {
    try {
      final rideRef = _firestore.collection('rides').doc(rideId);
      final offerRef = _offerCollection(rideId).doc(offerId);

      await _firestore.runTransaction((transaction) async {
        final offerSnap = await transaction.get(offerRef);
        if (!offerSnap.exists) {
          throw Exception('Offer not found');
        }

        final offerData = offerSnap.data() as Map<String, dynamic>;
        final transporterId = offerData['transporterId'] as String?;

        if (transporterId == null) {
          throw Exception('Transporter ID not found in offer');
        }

        // Update ride with sender's counter-offer; keep this transporter as the one in negotiation.
        // Clear transporter-commit wait: negotiation reopened — transporter must respond, not sender.
        transaction.update(rideRef, {
          'counterOffer': senderCounterOffer,
          'priceStatus': 'pending',
          'status': 'pending',
          'lastCounterOfferBy': 'sender',
          'negotiatingTransporterId': transporterId,
          'acceptedTransporterId': null,
          'finalPrice': null,
          'awaitingSenderConfirmDriverId': FieldValue.delete(),
          'lastReopenReason': FieldValue.delete(),
          'updatedAt': DateTime.now().toIso8601String(),
        });

        // Update the offer with sender's counter-offer
        transaction.update(offerRef, {
          'priceOffer': senderCounterOffer,
          'status': 'pending', // Keep as pending
          'updatedAt': DateTime.now().toIso8601String(),
        });
      });

      // Notify transporter about sender's counter-offer
      final offerDoc = await _offerCollection(rideId).doc(offerId).get();
      final offerData = offerDoc.data();
      final transporterId = offerData?['transporterId'] as String?;

      if (transporterId != null) {
        final notificationService = NotificationService();
        await notificationService.createNotification(
          userId: transporterId,
          type: 'sender_counter_offer',
          title: 'Sender Made a Counter-Offer',
          message: 'The sender has made a counter-offer of \$${senderCounterOffer.toStringAsFixed(2)}. You can accept, reject, or make another offer.',
          rideId: rideId,
          data: {
            'counterOffer': senderCounterOffer,
            'rideId': rideId,
          },
        );
      }
    } catch (e) {
      throw Exception('Error sending sender counter-offer: $e');
    }
  }

  /// Sender responds to a transporter offer (accept / decline / counter).
  ///
  /// **Invariants (same as [transporterRequestSenderConfirmation]):** accepting a
  /// price here only locks the agreed amount; **driverId** and **in_progress** are
  /// set only after the transporter commits ([transporterRequestSenderConfirmation])
  /// and the sender confirms ([senderConfirmTransporterAndStartRide]). Whether the
  /// sender entered from request details or this counter-offer flow, the map opens
  /// only after that two-step handshake.
  Future<void> respondToCounterOffer(
    String rideId,
    String offerId,
    bool accepted, {
    double? senderCounterOffer, // Optional: if sender wants to counter-offer
  }) async {
    try {
      final rideRef = _firestore.collection('rides').doc(rideId);
      final offerRef = _offerCollection(rideId).doc(offerId);

      // Firestore rules (and offer subcollection rules) require `rides.counterOffer`
      // to match the transporter's offer price when the sender sets `priceStatus`
      // to `accepted`. Transporters who only used [createOrUpdateOffer] never set
      // `counterOffer` on the ride, so we stage it in a prior write. Security rules
      // evaluate reads against the committed DB state *before* a transaction runs,
      // so this cannot be done in the same transaction as the accept.
      final offerPre = await offerRef.get();
      if (!offerPre.exists) {
        throw Exception('Offer not found');
      }
      final offerPreData = offerPre.data() as Map<String, dynamic>;
      final offerPrice =
          (offerPreData['priceOffer'] as num?)?.toDouble();
      final offerTransporterId = offerPreData['transporterId'] as String?;

      if (accepted) {
        if (offerPrice == null) {
          throw Exception('Offer price is missing');
        }
        if (offerTransporterId == null) {
          throw Exception('Transporter ID not found in offer');
        }
        final ridePre = await rideRef.get();
        if (!ridePre.exists) {
          throw Exception('Ride not found');
        }
        final rd = ridePre.data() as Map<String, dynamic>;
        final existingCounter =
            (rd['counterOffer'] as num?)?.toDouble();
        final neg = _uidStringFromRideField(rd['negotiatingTransporterId']);
        if (neg != null &&
            neg.isNotEmpty &&
            neg != offerTransporterId) {
          throw Exception(
            'Another transporter is already negotiating this request.',
          );
        }
        if (existingCounter != null && existingCounter != offerPrice) {
          throw Exception(
            'This offer no longer matches the request. Please refresh and try again.',
          );
        }
        if (existingCounter == null) {
          final status = rd['status'] as String? ?? 'open';
          await rideRef.update({
            'counterOffer': offerPrice,
            'priceStatus': 'pending',
            'status': status == 'open' ? 'pending' : status,
            'lastCounterOfferBy': 'transporter',
            'negotiatingTransporterId': offerTransporterId,
            'acceptedTransporterId': null,
            'finalPrice': null,
            'awaitingSenderConfirmDriverId': FieldValue.delete(),
            'lastReopenReason': FieldValue.delete(),
            'updatedAt': DateTime.now().toIso8601String(),
          });
        }
      }

      await _firestore.runTransaction((transaction) async {
        // Get the offer to get the counter-offer price
        final offerSnap = await transaction.get(offerRef);
        if (!offerSnap.exists) {
          throw Exception('Offer not found');
        }

        final offerData = offerSnap.data() as Map<String, dynamic>;
        // Firestore stores numeric values as num (which may be int or double),
        // so we need to safely convert to double to avoid type cast errors.
        final counterOffer =
            (offerData['priceOffer'] as num?)?.toDouble();
        final transporterId = offerData['transporterId'] as String?;

        // If sender sent a counter-offer, handle it
        if (senderCounterOffer != null && !accepted) {
          if (transporterId == null) {
            throw Exception('Transporter ID not found in offer');
          }

          // Update ride with sender's counter-offer; this offer's transporter is the one in negotiation
          transaction.update(rideRef, {
            'counterOffer': senderCounterOffer,
            'priceStatus': 'pending',
            'status': 'pending',
            'lastCounterOfferBy': 'sender',
            'negotiatingTransporterId': transporterId,
            'acceptedTransporterId': null,
            'finalPrice': null,
            'awaitingSenderConfirmDriverId': FieldValue.delete(),
            'lastReopenReason': FieldValue.delete(),
            'updatedAt': DateTime.now().toIso8601String(),
          });

          // Update the offer with sender's counter-offer
          transaction.update(offerRef, {
            'priceOffer': senderCounterOffer,
            'status': 'pending', // Keep as pending
            'updatedAt': DateTime.now().toIso8601String(),
          });

          // Notification will be sent after transaction
          return; // Exit early, don't process accept/reject
        }

        if (accepted) {
          if (transporterId == null) {
            throw Exception('Transporter ID not found in offer');
          }
          if (counterOffer == null) {
            throw Exception('Offer price is missing');
          }
          final rideSnapTx = await transaction.get(rideRef);
          if (!rideSnapTx.exists) {
            throw Exception('Ride not found');
          }
          final rideTxData = rideSnapTx.data() as Map<String, dynamic>;
          final rideCounter =
              (rideTxData['counterOffer'] as num?)?.toDouble();
          if (rideCounter == null || rideCounter != counterOffer) {
            throw Exception(
              'Offer no longer matches the request. Please refresh and try again.',
            );
          }

          // Update ride with accepted counter-offer
          // When sender accepts, set priceStatus to 'accepted' but keep status as 'pending'
          final updateData = <String, dynamic>{
            'price': counterOffer,
            'finalPrice': counterOffer,
            'counterOffer': null,
            'priceStatus': 'accepted',
            'status': 'pending',
            'acceptedTransporterId': transporterId,
            'negotiatingTransporterId': transporterId, // keep for clarity; this transporter was chosen
            'awaitingSenderConfirmDriverId': FieldValue.delete(),
            'lastReopenReason': FieldValue.delete(),
            'updatedAt': DateTime.now().toIso8601String(),
          };
          transaction.update(rideRef, updateData);

          // Mark this offer as selected
          transaction.update(offerRef, {
            'status': 'selected',
            'updatedAt': DateTime.now().toIso8601String(),
          });

          // Reject all other offers
          final allOffers = await _offerCollection(rideId).get();
          for (var doc in allOffers.docs) {
            if (doc.id != offerId) {
              transaction.update(doc.reference, {
                'status': 'rejected',
                'updatedAt': DateTime.now().toIso8601String(),
              });
            }
          }
          
          // Deduction (if enabled) when transporter accepts in acceptRide().
        } else {
          // Decline: reopen as a normal open request (same idea as [rejectOfferAndReopenRide]).
          // Any transporter can see/offer again; sender home shows "Waiting for transporters".
          transaction.update(rideRef, {
            'counterOffer': null,
            'priceStatus': null,
            'status': 'open',
            'negotiatingTransporterId': null,
            'lastCounterOfferBy': null,
            'acceptedTransporterId': null,
            'finalPrice': null,
            'awaitingSenderConfirmDriverId': FieldValue.delete(),
            'lastReopenReason': 'sender_declined',
            'updatedAt': DateTime.now().toIso8601String(),
          });

          transaction.update(offerRef, {
            'status': 'rejected',
            'updatedAt': DateTime.now().toIso8601String(),
          });
        }
      });

      // If sender accepted the counter-offer, notify transporter so they can take delivery
      if (accepted) {
        final offerDoc = await _offerCollection(rideId).doc(offerId).get();
        final offerData = offerDoc.data();
        final transporterId = offerData?['transporterId'] as String?;

        if (transporterId != null) {
          final rideDoc = await _firestore.collection('rides').doc(rideId).get();
          final rideData = rideDoc.data();
          final agreedPrice =
              (rideData?['price'] as num?)?.toDouble() ?? 0.0;
          final senderUserId = _uidStringFromRideField(rideData?['userId']);

          final notificationService = NotificationService();
          await notificationService.createNotification(
            userId: transporterId,
            type: 'counter_offer_accepted',
            title: 'Offer Accepted',
            message:
                'The sender has accepted your offer of \$${agreedPrice.toStringAsFixed(2)}. You can now accept the delivery request.',
            rideId: rideId,
            data: {
              'price': agreedPrice,
              'rideId': rideId,
            },
          );

          if (senderUserId != null) {
            await MessagingService().sendTransporterSelectedMessage(
              rideId: rideId,
              senderId: senderUserId,
              transporterId: transporterId,
            );
          }
        }
      }

      // If sender sent a counter-offer, notify transporter
      if (senderCounterOffer != null && !accepted) {
        final offerDoc = await _offerCollection(rideId).doc(offerId).get();
        final offerData = offerDoc.data();
        final transporterId = offerData?['transporterId'] as String?;

        if (transporterId != null) {
          final notificationService = NotificationService();
          await notificationService.createNotification(
            userId: transporterId,
            type: 'sender_counter_offer',
            title: 'Sender Made a Counter-Offer',
            message: 'The sender has made a counter-offer of \$${senderCounterOffer.toStringAsFixed(2)}. You can accept, reject, or make another offer.',
            rideId: rideId,
            data: {
              'counterOffer': senderCounterOffer,
              'rideId': rideId,
            },
          );
        }
      }

      // If sender declined the counter-offer (no new amount), notify + chat message
      if (!accepted && senderCounterOffer == null) {
        final offerDoc = await _offerCollection(rideId).doc(offerId).get();
        final offerData = offerDoc.data();
        final transporterId = offerData?['transporterId'] as String?;
        final rideDoc = await _firestore.collection('rides').doc(rideId).get();
        final senderUserId =
            _uidStringFromRideField(rideDoc.data()?['userId']);

        if (transporterId != null) {
          final notificationService = NotificationService();
          await notificationService.createNotification(
            userId: transporterId,
            type: 'counter_offer_declined',
            title: 'Offer Declined',
            message:
                'The sender has declined your offer. This request is now open to other transporters.',
            rideId: rideId,
            data: {
              'rideId': rideId,
            },
          );
          if (senderUserId != null) {
            try {
              await MessagingService().sendSenderDeclinedServiceMessage(
                rideId: rideId,
                senderId: senderUserId,
                transporterId: transporterId,
              );
            } catch (e) {
              debugPrint('sendSenderDeclinedServiceMessage: $e');
            }
          }
        }
      }
    } catch (e) {
      // Insufficient-balance notification only when fee deduction is enabled
      if (TestingFlags.enableAcceptanceFeeDeduction &&
          e.toString().contains('Insufficient balance')) {
        try {
          final offerDoc = await _offerCollection(rideId).doc(offerId).get();
          final offerData = offerDoc.data();
          final transporterId = offerData?['transporterId'] as String?;
          
          if (transporterId != null) {
            final rideDoc = await _firestore.collection('rides').doc(rideId).get();
            final rideData = rideDoc.data();
            final agreed = (rideData?['finalPrice'] as num?)?.toDouble() ??
                (rideData?['price'] as num?)?.toDouble() ?? 0.0;
            final fee = agreed * PricingService.platformFeePercentage;
            
            final notificationService = NotificationService();
            await notificationService.createNotification(
              userId: transporterId,
              type: 'insufficient_balance',
              title: 'Insufficient Balance',
              message: 'Your wallet balance is insufficient. Please top up \$${fee.toStringAsFixed(2)} to accept this request.',
              rideId: rideId,
              data: {
                'requiredAmount': fee,
                'rideId': rideId,
              },
            );
          }
        } catch (notifError) {
          debugPrint('Error sending notification: $notifError');
        }
      }
      throw Exception('Error responding to counter-offer: $e');
    }
  }
}



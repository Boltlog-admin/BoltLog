import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:math' as math;
import '../models/ride_model.dart';
import '../models/user_model.dart';
import '../services/app_resume_service.dart';
import '../services/ride_service.dart';
import '../services/user_service.dart';
import '../services/routing_service.dart';
import '../services/pricing_service.dart';
import '../services/error_handler_service.dart';
import '../constants/app_constants.dart';
import '../config/testing_flags.dart';
import '../theme/app_theme.dart';
import '../utils/negotiation_utils.dart';
import 'active_ride_map_screen.dart';

class RequestDetailScreen extends StatefulWidget {
  final RideModel ride;

  const RequestDetailScreen({super.key, required this.ride});

  @override
  State<RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends State<RequestDetailScreen> {
  final RideService _rideService = RideService();
  final UserService _userService = UserService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isOffering = false;
  Set<Polyline> _routePolylines = {};
  bool _routeRequested = false;
  bool _lockNavigation = false;

  /// Transporter: sender declined negotiation. Sender: transporter declined request.
  StreamSubscription<RideModel?>? _rideDeclineSub;
  RideModel? _previousRideSnapshot;
  bool _transporterExitAfterSenderDeclineHandled = false;
  bool _senderExitAfterTransporterDeclineHandled = false;
  /// Avoid double navigation when transporter accepts (stream + accept handler).
  bool _navigatedToLiveMap = false;
  bool _cancelledExitHandled = false;
  bool _busySenderConfirm = false;

  void _showNegotiationLockDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Negotiation in progress'),
        content: const Text(
          'You have an active negotiation for this delivery. '
          'Finish or cancel it before leaving this screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _previousRideSnapshot = widget.ride;
    // Track when transporter views this request
    _trackView();
    // Update last seen every 20 seconds while viewing
    _startViewerTracking();
    _listenDeclineExitSignals();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.ride.id != null) {
        AppResumeService.instance.saveRideScreen(
          ride: widget.ride,
          screen: AppResumeService.screenRequestDetail,
        );
      }
    });
    // Opened request detail while ride already live (e.g. from list) → go straight to map.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _navigatedToLiveMap) return;
      final r = widget.ride;
      if (r.id != null &&
          r.driverId != null &&
          r.driverId!.trim().isNotEmpty &&
          (r.status == 'in_progress' || r.status == 'parcel_collected')) {
        _navigatedToLiveMap = true;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ActiveRideMapScreen(ride: r),
          ),
        );
      }
    });
  }

  /// Transporter: sender declined → pop. Sender: transporter declined → snackbar + pop.
  /// Both: when transporter commits (in_progress + driverId), go to shared live map.
  void _listenDeclineExitSignals() {
    final rideId = widget.ride.id;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (rideId == null || uid == null) return;

    _rideDeclineSub = _rideService.streamRideById(rideId).listen((ride) {
      if (!mounted) return;
      if (ride == null) {
        if (!_cancelledExitHandled) {
          _cancelledExitHandled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'This request is no longer available.',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                backgroundColor: Colors.grey.shade800,
              ),
            );
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          });
        }
        return;
      }
      if (ride.status == 'cancelled') {
        if (!_cancelledExitHandled) {
          _cancelledExitHandled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'This request was cancelled.',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                backgroundColor: Colors.grey.shade800,
              ),
            );
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          });
        }
        _previousRideSnapshot = ride;
        return;
      }
      final prev = _previousRideSnapshot;

      if (uid != ride.userId) {
        if (_transporterExitAfterSenderDeclineHandled) {
          _previousRideSnapshot = ride;
          return;
        }
        final wasPendingWithMe = _previousRideSnapshot?.status == 'pending' &&
            _previousRideSnapshot?.negotiatingTransporterId == uid;
        final nowOpen = ride.status == 'open' &&
            (ride.negotiatingTransporterId == null ||
                ride.negotiatingTransporterId!.trim().isEmpty);

        if (wasPendingWithMe && nowOpen) {
          _transporterExitAfterSenderDeclineHandled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Sender declined this service. Returning to your dashboard.',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                backgroundColor: const Color(0xFFEA580C),
              ),
            );
            Navigator.of(context).pop();
          });
        }
      } else {
        if (!_senderExitAfterTransporterDeclineHandled &&
            ride.lastReopenReason == 'transporter_declined') {
          _senderExitAfterTransporterDeclineHandled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'A transporter declined this request. It is open again for others.',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                backgroundColor: const Color(0xFFEA580C),
              ),
            );
            try {
              await _rideService.clearLastReopenReason(rideId);
            } catch (_) {}
            if (mounted) Navigator.of(context).pop();
          });
        }
      }

      // Sender + transporter: live delivery started → same map screen for both.
      if (!_navigatedToLiveMap) {
        final nowLive = ride.driverId != null &&
            ride.driverId!.trim().isNotEmpty &&
            (ride.status == 'in_progress' || ride.status == 'parcel_collected');
        final wasLive = prev != null &&
            prev.driverId != null &&
            prev.driverId!.trim().isNotEmpty &&
            (prev.status == 'in_progress' || prev.status == 'parcel_collected');
        if (nowLive && !wasLive) {
          _navigatedToLiveMap = true;
          final rideForMap = ride;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => ActiveRideMapScreen(ride: rideForMap),
              ),
            );
          });
        }
      }

      _previousRideSnapshot = ride;
    });
  }

  void _trackView() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || widget.ride.id == null) return;
    try {
      if (user.uid == widget.ride.userId) {
        await _rideService.updateSenderLastViewed(widget.ride.id!);
      } else {
        await _rideService.trackRequestView(widget.ride.id!, user.uid);
      }
    } catch (e) {
      // Silently fail
    }
  }

  void _startViewerTracking() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && widget.ride.id != null) {
      // Update last seen every 20 seconds
      Future.delayed(const Duration(seconds: 20), () {
        if (mounted) {
          _rideService.updateViewerLastSeen(widget.ride.id!, user.uid);
          _startViewerTracking(); // Continue tracking
        }
      });
    }
  }

  @override
  void dispose() {
    _rideDeclineSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final transporterId = user?.uid ?? '';

    return WillPopScope(
      onWillPop: () async {
        if (_lockNavigation) {
          _showNegotiationLockDialog();
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () {
              if (_lockNavigation) {
                _showNegotiationLockDialog();
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
          title: Text(
            'Request details',
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1E40AF),
              letterSpacing: -0.25,
            ),
          ),
        ),
        // Persist request details: stream live ride, fallback to initial so details don't disappear
        body: StreamBuilder<RideModel?>(
          stream: widget.ride.id != null
              ? _rideService.streamRideById(widget.ride.id!)
              : Stream.value(widget.ride),
          builder: (context, rideSnap) {
            final ride = rideSnap.data ?? widget.ride;
            _lockNavigation = negotiationInProgress(ride);
            return SafeArea(
              child: StreamBuilder<UserModel?>(
                stream: user != null
                    ? _userService.streamUser(user!.uid)
                    : Stream.value(null),
                builder: (context, userSnap) {
                  final userModel = userSnap.data;
                  final isTransporter =
                      user != null && user!.uid != ride.userId;
                final isSender = user != null && user!.uid == ride.userId;
                  final isDriver =
                      AppConstants.isDriverRole(userModel?.role);
                  final verificationStatus =
                      (userModel?.verificationStatus ?? 'pending')
                          .toLowerCase();
                  final isVerified = verificationStatus == 'auto_verified' ||
                      verificationStatus == 'verified';
                  final canActAsTransporter =
                      TestingFlags.relaxTransporterVerification ||
                          !isDriver ||
                          isVerified;
                  bool senderViewedRecently = false;
                  if (ride.senderLastViewedAt != null) {
                    try {
                      final viewedAt =
                          DateTime.parse(ride.senderLastViewedAt!);
                      senderViewedRecently =
                          DateTime.now().difference(viewedAt).inMinutes <= 10;
                    } catch (_) {}
                  }

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.primary.withOpacity(0.08),
                              AppColors.primaryDark.withOpacity(0.03),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.primary.withOpacity(0.18),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.local_shipping_outlined,
                                color: AppColors.primaryDark,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Delivery request',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primaryDark,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Created ${_formatDate(ride.createdAt)}',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Text(
                                ride.status.toUpperCase(),
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isTransporter &&
                          ride.awaitingSenderToConfirmTransporter &&
                          ride.awaitingSenderConfirmDriverId?.trim() ==
                              transporterId &&
                          // Sender renegotiation clears awaiting in Firestore; keep UI safe if stale.
                          !(ride.priceStatus == 'pending' &&
                              ride.lastCounterOfferBy == 'sender')) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.indigo.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.hourglass_top,
                                  color: Colors.indigo.shade800, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Waiting for sender\'s reply. When they confirm acceptance, you\'ll move to the live map.',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.indigo.shade900,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      // Negotiation status: transporter view (sees sender activity + counters)
                      if (isTransporter &&
                            ride.status == 'pending' &&
                            ride.priceStatus == 'pending' &&
                            (ride.negotiatingTransporterId == null ||
                                ride.negotiatingTransporterId == transporterId)) ...[
                          if (ride.lastCounterOfferBy == 'transporter')
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border:
                                    Border.all(color: Colors.amber.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.schedule,
                                      color: Colors.amber.shade800, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Sender viewing, waiting for reply',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.amber.shade900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (senderViewedRecently)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.visibility,
                                      color: Colors.blue.shade800, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Sender has viewed',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.blue.shade900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          // Only the transporter in active negotiation sees sender's counter (works for any sender + multiple transporters)
                          if (ride.lastCounterOfferBy == 'sender' &&
                              ride.counterOffer != null &&
                              (ride.negotiatingTransporterId == null ||
                                  ride.negotiatingTransporterId == transporterId))
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.green.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.tag_faces,
                                      color: Colors.green.shade800, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: RichText(
                                      text: TextSpan(
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.green.shade900,
                                        ),
                                        children: [
                                          const TextSpan(
                                            text: 'Sender\'s counter-offer: ',
                                          ),
                                          TextSpan(
                                            text:
                                                '\$${ride.counterOffer!.toStringAsFixed(2)}. '
                                                'You can accept or renegotiate.',
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.green.shade900,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                        // Negotiation status: sender view (sees latest transporter counter-offer)
                        if (isSender &&
                            ride.status == 'pending' &&
                            ride.priceStatus == 'pending' &&
                            ride.lastCounterOfferBy == 'transporter' &&
                            ride.counterOffer != null) ...[
                          InkWell(
                            onTap: () => _showSenderOfferActions(context, ride),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.amber.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.attach_money,
                                      color: Colors.amber.shade800, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: RichText(
                                      text: TextSpan(
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.amber.shade900,
                                        ),
                                        children: [
                                          const TextSpan(
                                            text: 'Transporter proposed: ',
                                          ),
                                          TextSpan(
                                            text:
                                                '\$${ride.counterOffer!.toStringAsFixed(2)}. ',
                                          ),
                                          const TextSpan(
                                            text:
                                                'Tap to accept, decline, or counter.',
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.chevron_right, size: 22, color: Colors.orange),
                                ],
                              ),
                            ),
                          ),
                        ],
                        if (isSender && ride.awaitingSenderToConfirmTransporter) ...[
                          _senderTransporterConfirmationCard(context, ride),
                        ],
                        _buildCommitmentStateBar(ride),
                        if (isTransporter) ...[
                          const SizedBox(height: 10),
                          _buildSenderPaymentMethodBadge(ride),
                        ],
                        const SizedBox(height: 12),
                        // Request Map (kept as primary context on top half)
                        Text(
                          'Live Request Map',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1E40AF),
                          ),
                        ),
                        const SizedBox(height: 12),
              
              // Map with route between pickup and dropoff
              if (ride.pickupLat != null &&
                  ride.pickupLng != null &&
                  ride.dropoffLat != null &&
                  ride.dropoffLng != null) ...[
                Container(
                  height: MediaQuery.of(context).size.height * 0.5,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(
                          (ride.pickupLat! + ride.dropoffLat!) / 2,
                          (ride.pickupLng! + ride.dropoffLng!) / 2,
                        ),
                        zoom: 12,
                      ),
                      markers: {
                        Marker(
                          markerId: const MarkerId('pickup'),
                          position: LatLng(ride.pickupLat!, ride.pickupLng!),
                          infoWindow: const InfoWindow(title: 'Pickup'),
                          icon: BitmapDescriptor.defaultMarkerWithHue(
                            BitmapDescriptor.hueBlue,
                          ),
                        ),
                        Marker(
                          markerId: const MarkerId('dropoff'),
                          position: LatLng(ride.dropoffLat!, ride.dropoffLng!),
                          infoWindow: const InfoWindow(title: 'Dropoff'),
                          icon: BitmapDescriptor.defaultMarkerWithHue(
                            BitmapDescriptor.hueRed,
                          ),
                        ),
                      },
                      polylines: _buildRoutePolylines(ride),
                      myLocationEnabled: false,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: true,
                      compassEnabled: true,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Builder(
                builder: (context) {
                  if (!isSender || ride.id == null || ride.id!.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _firestore
                        .collection('rides')
                        .doc(ride.id)
                        .collection('viewers')
                        .snapshots(),
                    builder: (context, viewersSnap) {
                      final count = viewersSnap.data?.docs.length ?? 0;
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.blue.shade50,
                              Colors.indigo.shade50,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.blue.shade100),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.85),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.visibility,
                                color: Color(0xFF2563EB),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '$count transporter${count == 1 ? '' : 's'} viewing this request',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF1E40AF),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 16),
              const SizedBox(height: 20),

              // Action Buttons (for transporters): show when open or when pending (negotiating / sender accepted)
              if (user != null &&
                  user.uid != ride.userId &&
                  (ride.status == 'open' ||
                      (ride.status == 'pending' && ride.isDriverSlotOpen))) ...[
                if (isTransporter && isDriver)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'You can accept at the suggested price or send a counter-offer.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                if (isTransporter && isDriver && !isVerified)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.amber.shade800, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Verify your documents (ID and selfie) to accept or negotiate offers.',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.amber.shade900,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (isTransporter && isDriver && !isVerified) const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1E40AF),
                          side: const BorderSide(color: Color(0xFF1E40AF), width: 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Text(
                          'Back to Requests',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _isOffering || !canActAsTransporter
                            ? null
                            : () => _offerRequest(ride, transporterId),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                        ),
                        child: _isOffering
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Text(
                                ride.priceStatus == 'accepted'
                                    ? 'Accept delivery'
                                    : 'Accept Offer',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _isOffering || !canActAsTransporter
                        ? null
                        : () => _showRenegotiateDialog(ride, transporterId),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2563EB),
                      side: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      (ride.negotiatingTransporterId == transporterId ||
                              ride.counterOffer == null)
                          ? 'Make offer / Counter-offer'
                          : 'Renegotiate Price',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _isOffering ? null : _declineRequest,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade400, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      'Skip for now',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
              if (isSender &&
                  ride.id != null &&
                  ride.status != 'completed' &&
                  ride.status != 'cancelled') ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () => _showSenderCancelDialog(context, ride),
                    icon: const Icon(Icons.cancel_outlined, size: 20),
                    label: const Text('Cancel request'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
              // Transporter cancel (inDrive-style: driver can cancel, sender is notified)
              if (user != null &&
                  isTransporter &&
                  transporterId != null &&
                  (ride.acceptedTransporterId == transporterId || ride.driverId == transporterId) &&
                  ride.status != 'completed' &&
                  ride.status != 'cancelled') ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () => _showTransporterCancelDialog(context, ride),
                    icon: const Icon(Icons.cancel_outlined, size: 20),
                    label: const Text('Cancel delivery'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade400),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade600),
        const SizedBox(width: 12),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1E40AF),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _senderPaymentMethodLabel(RideModel ride) {
    final method = (ride.senderPaymentMethod ?? 'cash').trim().toLowerCase();
    if (method == 'ecocash') return 'EcoCash';
    return 'Cash';
  }

  IconData _senderPaymentMethodIcon(RideModel ride) {
    final method = (ride.senderPaymentMethod ?? 'cash').trim().toLowerCase();
    if (method == 'ecocash') return Icons.account_balance_wallet;
    return Icons.money;
  }

  Color _senderPaymentMethodColor(RideModel ride) {
    final method = (ride.senderPaymentMethod ?? 'cash').trim().toLowerCase();
    if (method == 'ecocash') return Colors.green.shade700;
    return Colors.orange.shade800;
  }

  Widget _buildSenderPaymentMethodBadge(RideModel ride) {
    final accent = _senderPaymentMethodColor(ride);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(_senderPaymentMethodIcon(ride), size: 18, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Sender payment method: ${_senderPaymentMethodLabel(ride)}',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  List<String> _cancelReasonPresets({required bool isTransporter}) {
    if (isTransporter) {
      return const ['Vehicle issue', 'Too far from pickup', 'Traffic delay'];
    }
    return const ['Changed my plans', 'Wrong request details', 'No longer needed'];
  }

  Widget _buildCommitmentStateBar(RideModel ride) {
    final isCommitted = ride.awaitingSenderToConfirmTransporter;
    final isConfirmed = ride.status == 'in_progress' ||
        ride.status == 'parcel_collected' ||
        ride.status == 'completed';
    final remaining = ride.createdAt
        .add(const Duration(minutes: 10))
        .difference(DateTime.now());
    final countdown = remaining.isNegative
        ? 'Offer window expired'
        : 'Offer window ${remaining.inMinutes.toString().padLeft(2, '0')}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}';

    Widget stage(String label, bool active) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 16,
            color: active ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? const Color(0xFF1E40AF) : Colors.grey.shade600,
            ),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              stage('Offered', true),
              stage('Awaiting sender', isCommitted || isConfirmed),
              stage('Confirmed', isConfirmed),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            countdown,
            style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  // Calculate distance between two coordinates in km (Haversine formula)
  double _calculateDistanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371; // km
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _deg2rad(double deg) {
    return deg * (math.pi / 180);
  }

  Future<void> _showSenderOfferActions(
      BuildContext context, RideModel ride) async {
    if (ride.id == null) return;

    try {
      // Find the active offer for the negotiating transporter so we know offerId
      final offers =
          await _rideService.streamOffersForRide(ride.id!).first;
      final activeOffer = offers.firstWhere(
        (o) =>
            o.transporterId == ride.negotiatingTransporterId &&
            o.status == 'pending',
        orElse: () => offers.firstWhere(
          (o) => o.transporterId == ride.negotiatingTransporterId,
          orElse: () => offers.first,
        ),
      );

      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) {
          return _SenderOfferActionsBottomSheet(
            parentContext: context,
            rideService: _rideService,
            rideId: ride.id!,
            offerId: activeOffer.id!,
            ride: ride,
            counterOffer: ride.counterOffer,
            price: ride.price,
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading offer: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Build route polylines using actual road route
  Set<Polyline> _buildRoutePolylines(RideModel ride) {
    // If we already have a computed route, use it
    if (_routePolylines.isNotEmpty) {
      return _routePolylines;
    }

    // Otherwise, trigger async load once and show no line until it's ready
    if (!_routeRequested &&
        ride.pickupLat != null &&
        ride.pickupLng != null &&
        ride.dropoffLat != null &&
        ride.dropoffLng != null) {
      _routeRequested = true;
      _loadActualRoute(ride);
    }

    return <Polyline>{};
  }

  // Load actual route from Google Directions API
  void _loadActualRoute(RideModel ride) async {
    if (ride.pickupLat == null ||
        ride.pickupLng == null ||
        ride.dropoffLat == null ||
        ride.dropoffLng == null) {
      return;
    }

    try {
      final routingService = RoutingService();
      final route = await routingService.getRoute(
        originLat: ride.pickupLat!,
        originLng: ride.pickupLng!,
        destLat: ride.dropoffLat!,
        destLng: ride.dropoffLng!,
      );

      if (route != null && mounted) {
        setState(() {
          _routePolylines = {
            Polyline(
              polylineId: const PolylineId('route'),
              points: route.points,
              color: const Color(0xFF2563EB),
              width: 4,
            ),
          };
        });
      }
    } catch (e) {
      // If routing fails, don't draw a fallback straight line
    }
  }

  Future<void> _declineRequest() async {
    final rideId = widget.ride.id;
    final user = FirebaseAuth.instance.currentUser;
    if (rideId != null && user != null && user.uid != widget.ride.userId) {
      try {
        await _rideService.transporterDeclineRequest(rideId, user.uid);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('You declined this request. It is now open to other transporters.'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _offerRequest(RideModel ride, String transporterId) async {
    if (ride.id == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: Request ID is missing'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      _isOffering = true;
    });

    try {
      // Create offer first
      await _rideService.createOrUpdateOffer(
        ride.id!,
        transporterId,
        priceOffer: ride.finalPrice ?? ride.counterOffer ?? ride.price,
      );

      final wroteNewCommit =
          await _rideService.acceptRide(ride.id!, transporterId);

      if (mounted) {
        final latestRide = await _rideService.getRideById(ride.id!);
        if (!mounted) return;
        final r = latestRide ?? ride;
        final tid = transporterId.trim();
        final onMap = r.driverId?.trim() == tid &&
            (r.status == 'in_progress' ||
                r.status == 'parcel_collected' ||
                r.status == 'completed');
        if (onMap) {
          _navigatedToLiveMap = true;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Delivery started — opening live map.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ActiveRideMapScreen(ride: r),
            ),
          );
          return;
        }
        final waitingOnSender = r.awaitingSenderConfirmDriverId?.trim() == tid &&
            (r.status == 'pending' || r.status == 'open');
        final senderRenegotiated = r.priceStatus == 'pending' &&
            r.lastCounterOfferBy == 'sender' &&
            !waitingOnSender;
        if (senderRenegotiated) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'The sender proposed a new price. Review and accept, counter, or decline.',
                style: GoogleFonts.inter(height: 1.35),
              ),
              backgroundColor: const Color(0xFF2563EB),
              duration: const Duration(seconds: 4),
            ),
          );
        } else if (waitingOnSender) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                !wroteNewCommit
                    ? 'You\'re already waiting for the sender to confirm. The live map opens after they accept.'
                    : 'Waiting for the sender to confirm. The live map opens after they accept.',
              ),
              backgroundColor: Color(0xFF2563EB),
              duration: Duration(seconds: 4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Request updated. Continue on this screen to finish or negotiate.',
                style: GoogleFonts.inter(height: 1.35),
              ),
              backgroundColor: const Color(0xFF2563EB),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        final latestRide = await _rideService.getRideById(ride.id!);
        final tid = transporterId.trim();
        final awaiting =
            latestRide?.awaitingSenderConfirmDriverId?.trim();
        if (awaiting == tid &&
            (latestRide?.status == 'pending' ||
                latestRide?.status == 'open')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Waiting for the sender to confirm. The live map opens after they accept.',
              ),
              backgroundColor: Color(0xFF2563EB),
              duration: Duration(seconds: 4),
            ),
          );
          return;
        }
        final alreadyAssignedToMe = latestRide != null &&
            latestRide.driverId?.trim() == tid &&
            (latestRide.status == 'in_progress' ||
                latestRide.status == 'parcel_collected' ||
                latestRide.status == 'completed');
        if (alreadyAssignedToMe) {
          _navigatedToLiveMap = true;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ActiveRideMapScreen(ride: latestRide),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(ErrorHandlerService.messageForDisplay(e)),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isOffering = false;
        });
      }
    }
  }

  Future<void> _showTransporterCancelDialog(BuildContext context, RideModel ride) async {
    if (ride.id == null) return;
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Cancel delivery?',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The sender will be notified. You can add a reason (optional).',
              style: GoogleFonts.inter(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'e.g. Unable to complete',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              maxLines: 2,
              style: GoogleFonts.inter(fontSize: 14),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _cancelReasonPresets(isTransporter: true)
                  .map(
                    (reason) => ActionChip(
                      label: Text(reason),
                      onPressed: () => reasonController.text = reason,
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Keep delivery', style: GoogleFonts.inter()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Cancel delivery', style: GoogleFonts.inter(color: Colors.red.shade700)),
          ),
        ],
      ),
    );
    final reason = reasonController.text.trim().isEmpty ? null : reasonController.text.trim();
    reasonController.dispose();
    if (confirmed != true || !mounted) return;
    try {
      await _rideService.cancelRideWithReason(
        ride.id!,
        cancelledBy: 'transporter',
        cancellationReason: reason,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Delivery cancelled. Sender has been notified.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showSenderCancelDialog(BuildContext context, RideModel ride) async {
    if (ride.id == null) return;
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Cancel ride?',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This permanently removes the ride from active requests for you and any transporters.',
              style: GoogleFonts.inter(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'e.g. Change of plans',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              maxLines: 2,
              style: GoogleFonts.inter(fontSize: 14),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _cancelReasonPresets(isTransporter: false)
                  .map(
                    (reason) => ActionChip(
                      label: Text(reason),
                      onPressed: () => reasonController.text = reason,
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Keep ride', style: GoogleFonts.inter()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Cancel ride', style: GoogleFonts.inter(color: Colors.red.shade700)),
          ),
        ],
      ),
    );
    final reason = reasonController.text.trim().isEmpty ? null : reasonController.text.trim();
    reasonController.dispose();
    if (confirmed != true || !mounted) return;
    try {
      await _rideService.cancelRideWithReason(
        ride.id!,
        cancelledBy: 'sender',
        cancellationReason: reason,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request cancelled.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _senderTransporterConfirmationCard(
      BuildContext context, RideModel ride) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_shipping, color: Colors.blue.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'A transporter accepted your request',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1E40AF),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Confirm to start the delivery and open the live map for both of you. '
            'You can review their profile first.',
            style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed:
                    _busySenderConfirm ? null : () => _senderConfirmAndStart(ride),
                child: Text(
                  'Accept transporter',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
              ),
              OutlinedButton(
                onPressed: _busySenderConfirm
                    ? null
                    : () => _showDriverDetailsForConfirmation(context, ride),
                child: Text(
                  'View driver details',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed:
                    _busySenderConfirm ? null : () => _senderDeclineCommit(ride),
                child: Text(
                  'Decline',
                  style: GoogleFonts.inter(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _senderConfirmAndStart(RideModel ride) async {
    if (ride.id == null) return;
    setState(() => _busySenderConfirm = true);
    try {
      await _rideService.senderConfirmTransporterAndStartRide(ride.id!);
      if (!mounted) return;
      _navigatedToLiveMap = true;
      final latest = await _rideService.getRideById(ride.id!);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ActiveRideMapScreen(ride: latest ?? ride),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorHandlerService.messageForDisplay(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busySenderConfirm = false);
    }
  }

  Future<void> _senderDeclineCommit(RideModel ride) async {
    if (ride.id == null) return;
    setState(() => _busySenderConfirm = true);
    try {
      await _rideService.senderDeclineTransporterCommit(ride.id!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This transporter was not selected. The request is open to others.',
          ),
          backgroundColor: Color(0xFFEA580C),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorHandlerService.messageForDisplay(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busySenderConfirm = false);
    }
  }

  Future<void> _showDriverDetailsForConfirmation(
      BuildContext context, RideModel ride) async {
    final tid = ride.awaitingSenderConfirmDriverId?.trim();
    if (tid == null || tid.isEmpty) return;
    final user = await _userService.getUser(tid);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Driver details',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1E40AF),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (user == null)
                    Text(
                      'Could not load this profile.',
                      style: GoogleFonts.inter(color: Colors.grey.shade700),
                    )
                  else ...[
                    _detailRow('Name', user.displayName ?? user.idFullName ?? '—'),
                    _detailRow('Phone', user.phoneNumber ?? '—'),
                    _detailRow('Vehicle', user.vehicleNumber ?? '—'),
                    _detailRow('Truck type', user.truckType ?? '—'),
                    _detailRow(
                      'Rating',
                      user.rating != null
                          ? user.rating!.toStringAsFixed(1)
                          : '—',
                    ),
                    _detailRow(
                      'Verification',
                      user.verificationStatus ?? '—',
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busySenderConfirm
                        ? null
                        : () {
                            Navigator.of(ctx).pop();
                            _senderConfirmAndStart(ride);
                          },
                    child: Text(
                      'Accept transporter',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _busySenderConfirm
                        ? null
                        : () {
                            Navigator.of(ctx).pop();
                            _senderDeclineCommit(ride);
                          },
                    child: Text(
                      'Decline',
                      style: GoogleFonts.inter(
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade900),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showRenegotiateDialog(
      RideModel ride, String transporterId) async {
    // Use latest counter-offer (sender's or ours) as base so renegotiate reflects current amount
    final basePrice = ride.counterOffer ?? ride.price ?? 0.0;
    if (basePrice <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No offer amount to counter.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    final controller = TextEditingController(
      text: basePrice.toStringAsFixed(2),
    );

    await showDialog(
      context: context,
      builder: (dialogContext) {
        Future<void> sendCounterOffer(double value) async {
          setState(() => _isOffering = true);
          try {
            await _rideService.submitCounterOffer(
              ride.id!,
              transporterId,
              value,
            );
            if (mounted) {
              Navigator.of(dialogContext).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Counter offer \$${value.toStringAsFixed(2)} sent to sender.',
                  ),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error: ${e.toString()}'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          } finally {
            if (mounted) setState(() => _isOffering = false);
          }
        }

        return AlertDialog(
          title: Text(
            'Counter-offer',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1E40AF),
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sender\'s offer: \$${basePrice.toStringAsFixed(2)}',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Quick counter (tap to send):',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1E40AF),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _QuickCounterButton(
                        label: '+10%',
                        amount: basePrice * 1.10,
                        onPressed: _isOffering
                            ? null
                            : () => sendCounterOffer(basePrice * 1.10),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _QuickCounterButton(
                        label: '+20%',
                        amount: basePrice * 1.20,
                        onPressed: _isOffering
                            ? null
                            : () => sendCounterOffer(basePrice * 1.20),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _QuickCounterButton(
                        label: '+30%',
                        amount: basePrice * 1.30,
                        onPressed: _isOffering
                            ? null
                            : () => sendCounterOffer(basePrice * 1.30),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Or enter custom amount:',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1E40AF),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Your price',
                    prefixText: '\$',
                    labelStyle: GoogleFonts.inter(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(color: Colors.grey.shade700),
              ),
            ),
            ElevatedButton(
              onPressed: _isOffering
                  ? null
                  : () async {
                      final value = double.tryParse(controller.text.trim());
                      if (value == null || value < PricingService.minimumFloorPrice) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Minimum \$${PricingService.minimumFloorPrice.toStringAsFixed(2)}.',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      await sendCounterOffer(value);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
              ),
              child: Text(
                'Send Offer',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Sender counter-offer sheet: keeps [FocusNode] + controller in [State] and
/// uses keyboard insets so the soft keyboard does not dismiss while typing.
class _SenderOfferActionsBottomSheet extends StatefulWidget {
  final BuildContext parentContext;
  final RideService rideService;
  final String rideId;
  final String offerId;
  /// Snapshot when the sheet opened (display only).
  final RideModel ride;
  final double? counterOffer;
  final double? price;

  const _SenderOfferActionsBottomSheet({
    required this.parentContext,
    required this.rideService,
    required this.rideId,
    required this.offerId,
    required this.ride,
    this.counterOffer,
    this.price,
  });

  @override
  State<_SenderOfferActionsBottomSheet> createState() =>
      _SenderOfferActionsBottomSheetState();
}

class _SenderOfferActionsBottomSheetState
    extends State<_SenderOfferActionsBottomSheet> {
  late final TextEditingController _counterController;
  late final FocusNode _amountFocusNode;

  @override
  void initState() {
    super.initState();
    _counterController = TextEditingController(
      text: widget.counterOffer?.toStringAsFixed(2) ??
          widget.price?.toStringAsFixed(2) ??
          '',
    );
    _amountFocusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _amountFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _counterController.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  void _snackOnParent(String message, {Color? color}) {
    final c = widget.parentContext;
    if (!c.mounted) return;
    ScaffoldMessenger.of(c).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color ?? Colors.grey.shade800,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Transporter offer',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1E40AF),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Current offer: \$${widget.counterOffer?.toStringAsFixed(2) ?? '-'}',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Counter-offer (optional)',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1E40AF),
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _counterController,
                  focusNode: _amountFocusNode,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    prefixText: '\$',
                    hintText: 'Leave empty to just accept or decline',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          try {
                            await widget.rideService.respondToCounterOffer(
                              widget.rideId,
                              widget.offerId,
                              false,
                            );
                            _snackOnParent('Offer declined',
                                color: Colors.orange);
                          } catch (e) {
                            _snackOnParent('Error: ${e.toString()}',
                                color: Colors.red);
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                          side: BorderSide(color: Colors.red.shade300),
                        ),
                        child: Text(
                          'Decline',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          try {
                            await widget.rideService.respondToCounterOffer(
                              widget.rideId,
                              widget.offerId,
                              true,
                            );
                            if (!context.mounted) return;
                            Navigator.of(context).pop();
                            _snackOnParent(
                              'Offer accepted. When the transporter commits to the job, '
                              'tap Accept transporter here to start — then the live map opens for both of you.',
                              color: Colors.green,
                            );
                          } catch (e) {
                            _snackOnParent('Error: ${e.toString()}',
                                color: Colors.red);
                          }
                        },
                        child: Text(
                          'Accept',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          final text = _counterController.text.trim();
                          final value = double.tryParse(text);
                          if (value == null ||
                              value < PricingService.minimumFloorPrice) {
                            _snackOnParent(
                              'Minimum \$${PricingService.minimumFloorPrice.toStringAsFixed(2)}.',
                              color: Colors.red,
                            );
                            return;
                          }
                          Navigator.of(context).pop();
                          try {
                            await widget.rideService.respondToCounterOffer(
                              widget.rideId,
                              widget.offerId,
                              false,
                              senderCounterOffer: value,
                            );
                            _snackOnParent(
                              'Counter-offer \$${value.toStringAsFixed(2)} sent.',
                              color: Colors.green,
                            );
                          } catch (e) {
                            _snackOnParent('Error: ${e.toString()}',
                                color: Colors.red);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                        ),
                        child: Text(
                          'Counter',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
        ),
      ),
    );
  }
}

/// Quick counter-offer button: +10%, +20%, +30% of sender's offer.
class _QuickCounterButton extends StatelessWidget {
  final String label;
  final double amount;
  final VoidCallback? onPressed;

  const _QuickCounterButton({
    required this.label,
    required this.amount,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF2563EB),
        side: const BorderSide(color: Color(0xFF2563EB)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            '\$${amount.toStringAsFixed(2)}',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }
}

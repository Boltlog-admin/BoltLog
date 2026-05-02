import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/ride_model.dart';
import '../models/user_model.dart';
import '../services/ride_service.dart';
import '../services/user_service.dart';
import '../services/routing_service.dart';
import '../services/pricing_service.dart';
import '../config/testing_flags.dart';
import '../constants/app_constants.dart';
import '../utils/ride_distance_utils.dart';
import '../utils/transporter_accept_nav.dart';
import 'request_detail_screen.dart';

class TransporterDashboardScreen extends StatefulWidget {
  const TransporterDashboardScreen({super.key});

  @override
  State<TransporterDashboardScreen> createState() => _TransporterDashboardScreenState();
}

class _TransporterDashboardScreenState extends State<TransporterDashboardScreen> {
  GoogleMapController? _mapController;
  bool _isMapView = false; // Default to list view
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  List<RideModel> _rides = [];
  List<RideModel>? _cachedRides;
  /// Accept-in-progress for a specific ride id (list card actions).
  String? _busyRideId;
  final Set<String> _skippedRideIds = <String>{};
  /// Invalidates in-flight [_updateMapMarkers] so stale async results do not overwrite the map.
  int _mapMarkersGeneration = 0;

  @override
  void initState() {
    super.initState();
    // Set transporter as online when dashboard opens
    _setOnlineStatus();
  }

  void _setOnlineStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final userService = UserService();
        await userService.updateDriverProfile(
          uid: user.uid,
          isAvailable: true,
        );
      } catch (e) {
        // Silently fail
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rideService = RideService();
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Requests',
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1E40AF),
                letterSpacing: -0.25,
              ),
            ),
            Text(
              'Open and negotiating near you',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: Colors.grey.shade600,
                height: 1.2,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isMapView ? Icons.list_rounded : Icons.map_rounded,
            ),
            onPressed: () {
              setState(() {
                _isMapView = !_isMapView;
              });
            },
            tooltip: _isMapView ? 'List view' : 'Map view',
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<UserModel?>(
          stream: user != null ? UserService().streamUser(user!.uid) : Stream.value(null),
          builder: (context, userSnap) {
            final userModel = userSnap.data;
            final isDriver = AppConstants.isDriverRole(userModel?.role);
            final verificationStatus = (userModel?.verificationStatus ?? 'pending').toLowerCase();
            final isVerified = verificationStatus == 'auto_verified' || verificationStatus == 'verified';
            // In testing mode, hide the licence verification banner entirely.
            final showVerificationBanner = !TestingFlags.relaxTransporterVerification &&
                isDriver &&
                !isVerified;

            return StreamBuilder<List<RideModel>>(
              stream: rideService.streamAvailableRides(),
              builder: (context, openSnapshot) {
                if (openSnapshot.data != null) _cachedRides = openSnapshot.data;
                final openRides = openSnapshot.data ?? _cachedRides ?? [];

                return StreamBuilder<List<RideModel>>(
                  stream: rideService.streamTransporterNegotiations(user?.uid ?? ''),
                  builder: (context, negSnapshot) {
                    final negRides = negSnapshot.data ?? [];

                    final rides = <RideModel>[];
                    final byId = <String, RideModel>{};
                    for (final r in openRides) {
                      final id = r.id;
                      if (id == null) continue;
                      byId[id] = r;
                    }
                    for (final r in negRides) {
                      final id = r.id;
                      if (id == null) continue;
                      byId[id] = r;
                    }
                    rides.addAll(byId.values);
                    rides.retainWhere(
                      (r) => rideInTransporterRequestBrowseList(
                        r,
                        user?.uid ?? '',
                      ),
                    );

                    if (openSnapshot.connectionState == ConnectionState.waiting &&
                        openRides.isEmpty &&
                        negSnapshot.connectionState == ConnectionState.waiting &&
                        negRides.isEmpty) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if ((openSnapshot.hasError && openRides.isEmpty) &&
                        negRides.isEmpty) {
                      final errorMsg = openSnapshot.error?.toString() ?? 'Unknown error';
                      return Center(
                        child: Text(
                          'Error: $errorMsg',
                          style: GoogleFonts.inter(color: Colors.red),
                        ),
                      );
                    }

                // QA mode: bypass request narrowing so transporters can test end-to-end
                // acceptance even when profile/location metadata is incomplete.
                List<RideModel> filteredRidesForList;
                List<RideModel> filteredRidesForMap;
                if (TestingFlags.relaxTransporterVerification) {
                  filteredRidesForList = rides;
                  filteredRidesForMap = rides;
                } else {
                  final driverTruckType = userModel?.truckType;
                  final vehicleMatched = rides
                      .where((ride) {
                        final orderType = ride.transportType;
                        if (orderType == null || orderType.isEmpty) {
                          return true;
                        }
                        return driverTruckType != null &&
                            driverTruckType.isNotEmpty &&
                            orderType == driverTruckType;
                      })
                      .toList();
                  // List: nearby only. Map: all matching requests so pins show real pickup/dropoff.
                  filteredRidesForList = filterAndSortRidesByDistance(
                    List<RideModel>.from(vehicleMatched),
                    driverLat: userModel?.currentLat,
                    driverLng: userModel?.currentLng,
                    maxRadiusKm: defaultMaxRadiusKm,
                    applyRadiusFilter: true,
                  );
                  filteredRidesForMap = filterAndSortRidesByDistance(
                    List<RideModel>.from(vehicleMatched),
                    driverLat: userModel?.currentLat,
                    driverLng: userModel?.currentLng,
                    applyRadiusFilter: false,
                  );
                }

                bool skipId(RideModel r) =>
                    r.id != null && _skippedRideIds.contains(r.id);
                filteredRidesForList =
                    filteredRidesForList.where((r) => !skipId(r)).toList();
                filteredRidesForMap =
                    filteredRidesForMap.where((r) => !skipId(r)).toList();

                final filteredRides =
                    _isMapView ? filteredRidesForMap : filteredRidesForList;
                _rides = filteredRides;

                Widget content;
                if (filteredRides.isEmpty) {
                  content = Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.local_shipping,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No current requests',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'New transport requests will appear here',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  );
                } else {
                  if (_isMapView) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      _updateMapMarkers(
                        context,
                        filteredRides,
                        user?.uid ?? '',
                        driverLat: userModel?.currentLat,
                        driverLng: userModel?.currentLng,
                      );
                    });
                    content = _buildMapView(
                      context,
                      filteredRides,
                      user?.uid ?? '',
                      driverLat: userModel?.currentLat,
                      driverLng: userModel?.currentLng,
                    );
                  } else {
                    content = _buildListView(
                      filteredRides,
                      user?.uid ?? '',
                      driverLat: userModel?.currentLat,
                      driverLng: userModel?.currentLng,
                    );
                  }
                }

                Widget finalContent = content;

                if (showVerificationBanner) {
                  finalContent = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
                                'Licence ID still under verification. You can browse requests but must be verified to accept or negotiate.',
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
                      const SizedBox(height: 8),
                      Expanded(child: content),
                    ],
                  );
                }

                return Column(
                  children: [
                    Expanded(child: finalContent),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8, top: 4),
                      child: Text(
                        'Developed by Fidinsky Tech Solutions',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade500,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildMapView(
    BuildContext context,
    List<RideModel> rides,
    String transporterId, {
    double? driverLat,
    double? driverLng,
  }) {
    // Calculate initial camera position based on rides
    LatLng? initialPosition;
    if (rides.isNotEmpty) {
      final firstRide = rides.first;
      if (firstRide.pickupLat != null && firstRide.pickupLng != null) {
        initialPosition = LatLng(firstRide.pickupLat!, firstRide.pickupLng!);
      }
    }

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: initialPosition ?? const LatLng(-19.4500, 29.8167), // Gweru default
            zoom: 12,
          ),
          onMapCreated: (controller) {
            _mapController = controller;
            _updateMapMarkers(
              context,
              rides,
              transporterId,
              driverLat: driverLat,
              driverLng: driverLng,
            );
          },
          markers: _markers,
          polylines: _polylines,
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          zoomControlsEnabled: true,
          mapType: MapType.normal,
          compassEnabled: true,
        ),
        Positioned(
          bottom: 24,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.white,
            elevation: 2,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.touch_app, size: 18, color: Colors.grey.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tap a blue pickup pin to accept or open full details.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.grey.shade800,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Legend
        Positioned(
          top: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.location_on, color: const Color(0xFF2563EB), size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Pickup',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.location_on, color: Colors.red.shade400, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Dropoff',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Opens the same accept / details flow as list cards (map had pins only before).
  Future<void> _showMapRequestSheet(
    BuildContext context,
    RideModel ride,
    String transporterId, {
    double? driverLat,
    double? driverLng,
  }) async {
    final authUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final tid = authUid.isNotEmpty ? authUid : transporterId.trim();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(tid)
                  .snapshots(),
              builder: (context, userSnap) {
                final userData =
                    userSnap.data?.data() as Map<String, dynamic>? ?? {};
                final isDriverRole =
                    AppConstants.isDriverRole(userData['role'] as String?);
                final verificationStatus =
                    (userData['verificationStatus'] as String? ?? 'pending')
                        .toLowerCase();
                final isVerified = verificationStatus == 'auto_verified' ||
                    verificationStatus == 'verified';
                final canActAsTransporter =
                    TestingFlags.relaxTransporterVerification ||
                        !isDriverRole ||
                        isVerified;

                final waitingForSender = ride.awaitingSenderToConfirmTransporter &&
                    ride.awaitingSenderConfirmDriverId?.trim() == tid &&
                    !(ride.priceStatus == 'pending' &&
                        ride.lastCounterOfferBy == 'sender');

                final showTransporterActions = !waitingForSender &&
                    (ride.status == 'open' ||
                        (ride.status == 'pending' && ride.isDriverSlotOpen));
                final lockedToOtherNegotiator =
                    ride.negotiatingTransporterId != null &&
                        ride.negotiatingTransporterId!.isNotEmpty &&
                        ride.negotiatingTransporterId != tid;
                final committedToOther = ride.acceptedTransporterId != null &&
                    ride.acceptedTransporterId!.isNotEmpty &&
                    ride.acceptedTransporterId != tid;
                final canInteract = showTransporterActions &&
                    canActAsTransporter &&
                    !lockedToOtherNegotiator &&
                    !committedToOther;

                final busy = _busyRideId == ride.id;
                final acceptLabel = ride.priceStatus == 'accepted'
                    ? 'Accept delivery'
                    : 'Accept';

                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Text(
                        'Request',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1E40AF),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _transporterDistanceSummary(
                        ride: ride,
                        driverLat: driverLat,
                        driverLng: driverLng,
                      ),
                      const SizedBox(height: 10),
                      _buildSenderPaymentMethodBadge(ride),
                      if (waitingForSender) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Waiting for sender\'s reply. When they confirm, you\'ll go to the live map.',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.indigo.shade900,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      if (!canActAsTransporter && showTransporterActions) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Complete verification to accept or counter-offer.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 46,
                        child: ElevatedButton(
                          onPressed: !canInteract || busy
                              ? null
                              : () async {
                                  Navigator.of(sheetCtx).pop();
                                  if (!context.mounted) return;
                                  await _acceptFromDashboard(
                                    context,
                                    ride,
                                    tid,
                                  );
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: busy
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : Text(
                                  acceptLabel,
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () {
                                Navigator.of(sheetCtx).pop();
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        RequestDetailScreen(ride: ride),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: Text(
                          'View full details',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF2563EB),
                          side: const BorderSide(color: Color(0xFF2563EB)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _updateMapMarkers(
    BuildContext context,
    List<RideModel> rides,
    String transporterId, {
    double? driverLat,
    double? driverLng,
  }) async {
    final generation = ++_mapMarkersGeneration;
    final Set<Marker> markers = {};
    final Set<Polyline> polylines = {};

    void openSheet(RideModel ride) {
      if (!context.mounted) return;
      _showMapRequestSheet(
        context,
        ride,
        transporterId,
        driverLat: driverLat,
        driverLng: driverLng,
      );
    }

    for (int i = 0; i < rides.length; i++) {
      final ride = rides[i];
      final pickupLat = ride.pickupLat;
      final pickupLng = ride.pickupLng;
      final dropoffLat = ride.dropoffLat;
      final dropoffLng = ride.dropoffLng;
      final hasPickup = pickupLat != null && pickupLng != null;
      final hasDropoff = dropoffLat != null && dropoffLng != null;

      double? toPickupKmVal;
      if (driverLat != null && driverLng != null && hasPickup) {
        toPickupKmVal = distanceToPickupKm(ride, driverLat, driverLng);
      }
      final pickupDistanceSnippet = toPickupKmVal != null
          ? '~${toPickupKmVal.toStringAsFixed(1)} km from you'
          : 'Enable location for distance';

      if (hasPickup && hasDropoff) {
        final legKm = pickupToDropoffKm(ride);
        final legSnippet = legKm != null
            ? '~${legKm.toStringAsFixed(1)} km from pickup'
            : 'Open details for address';

        markers.add(
          Marker(
            markerId: MarkerId('pickup_${ride.id}_$i'),
            position: LatLng(pickupLat!, pickupLng!),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
            infoWindow: InfoWindow(
              title: 'Pickup point',
              snippet: pickupDistanceSnippet,
            ),
            onTap: () => openSheet(ride),
          ),
        );

        markers.add(
          Marker(
            markerId: MarkerId('dropoff_${ride.id}_$i'),
            position: LatLng(dropoffLat!, dropoffLng!),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(
              title: 'Drop-off point',
              snippet: legSnippet,
            ),
            onTap: () => openSheet(ride),
          ),
        );

        try {
          final routingService = RoutingService();
          final route = await routingService.getRoute(
            originLat: pickupLat!,
            originLng: pickupLng!,
            destLat: dropoffLat!,
            destLng: dropoffLng!,
          );
          if (!mounted || generation != _mapMarkersGeneration) {
            return;
          }
          if (route != null) {
            polylines.add(
              Polyline(
                polylineId: PolylineId('route_${ride.id}_$i'),
                points: route.points,
                color: const Color(0xFF2563EB),
                width: 3,
              ),
            );
          }
        } catch (e) {
          // If routing fails, skip drawing the route for this ride
        }
      } else if (hasPickup) {
        final snippet = '$pickupDistanceSnippet · Drop-off pin when coords available';
        markers.add(
          Marker(
            markerId: MarkerId('pickup_${ride.id}_$i'),
            position: LatLng(pickupLat!, pickupLng!),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
            infoWindow: InfoWindow(
              title: 'Pickup point',
              snippet: snippet,
            ),
            onTap: () => openSheet(ride),
          ),
        );
      } else if (hasDropoff) {
        markers.add(
          Marker(
            markerId: MarkerId('dropoff_${ride.id}_$i'),
            position: LatLng(dropoffLat!, dropoffLng!),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
            infoWindow: InfoWindow(
              title: 'Drop-off point',
              snippet: 'Pickup coordinates missing — open details',
            ),
            onTap: () => openSheet(ride),
          ),
        );
      }
    }

    if (!mounted || generation != _mapMarkersGeneration) {
      return;
    }

    if (markers.isNotEmpty && _mapController != null) {
      final bounds = _calculateBounds(markers);
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 100),
      );
    }

    if (!mounted || generation != _mapMarkersGeneration) {
      return;
    }
    setState(() {
      _markers = markers;
      _polylines = polylines;
    });
  }

  LatLngBounds _calculateBounds(Set<Marker> markers) {
    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;

    for (var marker in markers) {
      final lat = marker.position.latitude;
      final lng = marker.position.longitude;
      minLat = minLat < lat ? minLat : lat;
      maxLat = maxLat > lat ? maxLat : lat;
      minLng = minLng < lng ? minLng : lng;
      maxLng = maxLng > lng ? maxLng : lng;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  /// Compact copy: no addresses (those stay on [RequestDetailScreen]).
  Widget _transporterDistanceSummary({
    required RideModel ride,
    double? driverLat,
    double? driverLng,
  }) {
    final legKm = pickupToDropoffKm(ride);
    final toPickup = (driverLat != null && driverLng != null)
        ? distanceToPickupKm(ride, driverLat, driverLng)
        : null;

    final legText = legKm != null
        ? 'Trip distance: ${legKm.toStringAsFixed(1)} km'
        : 'Trip distance: --';

    final youText = toPickup != null
        ? 'Distance to pickup: ${toPickup.toStringAsFixed(1)} km'
        : 'Distance to pickup: calculating...';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.route, size: 16, color: Colors.grey.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  legText,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    height: 1.35,
                    color: const Color(0xFF1E40AF),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.near_me_outlined, size: 16, color: Colors.grey.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  youText,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    height: 1.35,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_senderPaymentMethodIcon(ride), size: 14, color: accent),
          const SizedBox(width: 6),
          Text(
            'Paid by sender: ${_senderPaymentMethodLabel(ride)}',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListView(
    List<RideModel> rides,
    String transporterId, {
    double? driverLat,
    double? driverLng,
  }) {
    return RefreshIndicator(
      onRefresh: () async {},
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: rides.length,
        itemBuilder: (context, index) {
          final ride = rides[index];
          return _buildDeliveryCard(
            context,
            ride,
            transporterId,
            driverLat: driverLat,
            driverLng: driverLng,
          );
        },
      ),
    );
  }

  Widget _buildDeliveryCard(
    BuildContext context,
    RideModel ride,
    String transporterId, {
    double? driverLat,
    double? driverLng,
  }) {
    final authUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final effectiveTid = authUid.isNotEmpty ? authUid : transporterId.trim();
    if (effectiveTid.isEmpty) {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Sign in to view and accept requests.',
            style: GoogleFonts.inter(color: Colors.grey.shade700),
          ),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(effectiveTid).snapshots(),
      builder: (context, userSnapshot) {
        final userData = userSnapshot.data?.data() as Map<String, dynamic>? ?? {};
        final ratePer10Km = (userData['ratePer10Km'] as num?)?.toDouble();
        double? distanceKm;
        double? yourRateForTrip;
        if (ride.pickupLat != null && ride.pickupLng != null && ride.dropoffLat != null && ride.dropoffLng != null) {
          distanceKm = PricingService.calculateDistance(
            ride.pickupLat!, ride.pickupLng!,
            ride.dropoffLat!, ride.dropoffLng!,
          );
          yourRateForTrip = PricingService.calculateDriverPriceForDistance(distanceKm, ratePer10Km);
        }

        final isDriverRole =
            AppConstants.isDriverRole(userData['role'] as String?);
        final verificationStatus =
            (userData['verificationStatus'] as String? ?? 'pending').toLowerCase();
        final isVerified = verificationStatus == 'auto_verified' ||
            verificationStatus == 'verified';
        final canActAsTransporter = TestingFlags.relaxTransporterVerification ||
            !isDriverRole ||
            isVerified;

        final waitingForSender = ride.awaitingSenderToConfirmTransporter &&
            ride.awaitingSenderConfirmDriverId?.trim() == effectiveTid &&
            !(ride.priceStatus == 'pending' &&
                ride.lastCounterOfferBy == 'sender');

        final showTransporterActions = !waitingForSender &&
            (ride.status == 'open' ||
                (ride.status == 'pending' && ride.isDriverSlotOpen));
        final lockedToOtherNegotiator =
            ride.negotiatingTransporterId != null &&
                ride.negotiatingTransporterId!.isNotEmpty &&
                ride.negotiatingTransporterId != effectiveTid;
        final committedToOther =
            ride.acceptedTransporterId != null &&
                ride.acceptedTransporterId!.isNotEmpty &&
                ride.acceptedTransporterId != effectiveTid;
        final canInteract = showTransporterActions &&
            canActAsTransporter &&
            !lockedToOtherNegotiator &&
            !committedToOther;

        final acceptLabel = ride.priceStatus == 'accepted'
            ? 'Accept delivery'
            : 'Accept';

        final busy = _busyRideId == ride.id;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (ride.packageDescription != null) ...[
                        Text(
                          ride.packageDescription!,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1E40AF),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                      ],
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (ride.packageType != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2563EB).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                ride.packageType!.toUpperCase(),
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF2563EB),
                                ),
                              ),
                            ),
                          if (ride.weight != null)
                            Text(
                              '${ride.weight} kg',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          if (ride.status == 'open')
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'OPEN',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.green.shade800,
                                ),
                              ),
                            ),
                          if (waitingForSender)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.indigo.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'WAITING FOR SENDER',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.indigo.shade900,
                                ),
                              ),
                            )
                          else if (ride.status == 'pending' && ride.isDriverSlotOpen)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                ride.priceStatus == 'accepted'
                                    ? 'READY TO ACCEPT'
                                    : 'NEGOTIATING',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (ride.price != null || yourRateForTrip != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (ride.price != null) ...[
                        Text(
                          'Sender offer',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        Text(
                          '\$${ride.price!.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF2563EB),
                          ),
                        ),
                      ],
                      if (yourRateForTrip != null) ...[
                        if (ride.price != null) const SizedBox(height: 6),
                        Text(
                          'Trip distance',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        Text(
                          distanceKm != null
                              ? '${distanceKm.toStringAsFixed(1)} km'
                              : '--',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1E40AF),
                          ),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _transporterDistanceSummary(
              ride: ride,
              driverLat: driverLat,
              driverLng: driverLng,
            ),
            const SizedBox(height: 10),
            _buildSenderPaymentMethodBadge(ride),
            if (waitingForSender) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.indigo.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.mark_chat_unread_outlined,
                        color: Colors.indigo.shade800, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Waiting for sender\'s reply. When they confirm, you\'ll go to the live map automatically.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
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
            if (!canActAsTransporter && showTransporterActions) ...[
              const SizedBox(height: 10),
              Text(
                'Complete verification to accept or counter-offer.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.amber.shade900,
                ),
              ),
            ],
            if (lockedToOtherNegotiator || committedToOther) ...[
              const SizedBox(height: 10),
              Text(
                'Another transporter is linked to this request. Open details for more info.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (showTransporterActions) ...[
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: !canInteract || busy
                      ? null
                      : () => _acceptFromDashboard(context, ride, effectiveTid),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white70,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          acceptLabel,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: !canInteract || busy
                      ? null
                      : () => _showQuickCounterOfferDialog(
                            context,
                            ride,
                            effectiveTid,
                          ),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(
                    'Counter-offer',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2563EB),
                    side: const BorderSide(color: Color(0xFF2563EB)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: TextButton.icon(
                  onPressed: busy
                      ? null
                      : () {
                          final id = ride.id;
                          if (id == null || id.isEmpty) return;
                          setState(() => _skippedRideIds.add(id));
                        },
                  icon: const Icon(Icons.skip_next_outlined, size: 18),
                  label: Text(
                    'Skip for now',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        // Sender already accepted price: same outcome as Accept — live map.
                        if (canInteract &&
                            ride.priceStatus == 'accepted' &&
                            ride.isDriverSlotOpen &&
                            (ride.status == 'open' ||
                                ride.status == 'pending')) {
                          setState(() => _busyRideId = ride.id);
                          try {
                            await transporterAcceptRideOpenMap(
                              context,
                              ride,
                              effectiveTid,
                              usePushReplacement: true,
                            );
                          } finally {
                            if (mounted) {
                              setState(() => _busyRideId = null);
                            }
                          }
                          return;
                        }
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => RequestDetailScreen(ride: ride),
                          ),
                        );
                      },
                icon: const Icon(Icons.info_outline, size: 20),
                label: Text(
                  'View request details',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF1E40AF),
                ),
              ),
            ),
            ],
          ),
        ),
    );
      },
    );
  }

  Future<void> _acceptFromDashboard(
    BuildContext context,
    RideModel ride,
    String transporterId,
  ) async {
    if (ride.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request ID is missing'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
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
    setState(() => _busyRideId = ride.id);
    try {
      await transporterAcceptRideOpenMap(
        context,
        ride,
        tid,
        usePushReplacement: true,
      );
    } finally {
      if (mounted) setState(() => _busyRideId = null);
    }
  }

  void _showQuickCounterOfferDialog(BuildContext context, RideModel ride, String transporterId) {
    final base = ride.counterOffer ?? ride.price;
    final controller = TextEditingController(
      text: base != null ? base.toStringAsFixed(2) : '',
    );
    final rideService = RideService();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Counter-offer',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1E40AF),
          ),
        ),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Your price offer',
            prefixText: '\$',
            labelStyle: GoogleFonts.inter(),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: Colors.grey.shade700),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final text = controller.text.trim();
              final value = double.tryParse(text);
              if (value == null || value <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid price'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              try {
                if (ride.id != null) {
                  await rideService.submitCounterOffer(
                    ride.id!,
                    transporterId,
                    value,
                  );
                  if (context.mounted) {
                    Navigator.of(context).pop(); // close dialog only
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Counter offer sent successfully!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    // After sending a counter-offer, open full request details so
                    // transporter can see the negotiation state and history instead
                    // of the card "disappearing" from the dashboard list.
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (ctx) => RequestDetailScreen(ride: ride),
                      ),
                    );
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: ${e.toString()}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
            ),
            child: Text(
              'Send Offer',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}

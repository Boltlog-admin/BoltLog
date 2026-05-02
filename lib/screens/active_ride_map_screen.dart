import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/ride_model.dart';
import '../services/app_resume_service.dart';
import '../config/testing_flags.dart';
import '../services/ride_service.dart';
import '../services/routing_service.dart';
import '../services/notification_service.dart';
import '../utils/live_map_copy.dart';
import '../widgets/map_call_action_bar.dart';

class ActiveRideMapScreen extends StatefulWidget {
  final RideModel ride;

  const ActiveRideMapScreen({super.key, required this.ride});

  @override
  State<ActiveRideMapScreen> createState() => _ActiveRideMapScreenState();
}

class _ActiveRideMapScreenState extends State<ActiveRideMapScreen> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  double? _driverLat;
  double? _driverLng;
  double? _pickupLat;
  double? _pickupLng;
  double? _dropoffLat;
  double? _dropoffLng;
  bool _isLoading = true;
  bool _hasArrivedAtPickup = false;
  RouteInfo? _currentRouteInfo; // Store route info with traffic
  bool _hasArrivedAtDropoff = false;
  bool _isCollecting = false;
  bool _isDelivering = false;
  bool _isSenderConfirmingPickup = false;
  bool _isSenderConfirmingDelivery = false;
  bool _isParcelCollected = false; // Track if parcel is already collected
  RideModel? _currentRide; // Streamed ride so map persists across status updates
  bool _poppedOnCancelled = false;
  /// Continuous GPS (real-time) instead of polling every few seconds.
  StreamSubscription<Position>? _positionSubscription;
  /// Traffic / road distance refresh (does not block live GPS marker).
  Timer? _trafficRefreshTimer;
  final RideService _rideService = RideService();
  static const double _arrivalRadiusMeters = 50.0; // 50 meters radius to consider "arrived"
  /// Throttle Firestore writes so sender can stream transporter position without excess cost.
  DateTime? _lastRideLocationPush;
  /// True when the signed-in user is the assigned transporter ([RideModel.driverId]).
  late final bool _viewingAsTransporter;
  /// Transporter: OS location off or permission denied — prompt to fix + nudge sender once.
  bool _transporterGpsBlocked = false;
  Timer? _gpsRetryTimer;
  DateTime? _lastSenderGpsNudgeNotification;
  static const Duration _driverLocationFreshness = Duration(seconds: 90);
  static const Duration _senderGpsNudgeCooldown = Duration(minutes: 8);

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _viewingAsTransporter =
        uid != null && uid == widget.ride.driverId;
    if (widget.ride.id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AppResumeService.instance.saveRideScreen(
          ride: widget.ride,
          screen: AppResumeService.screenActiveMap,
        );
      });
    }
    _initializeMap();
  }

  bool _hasFreshTransporterGps(RideModel ride) {
    if (ride.driverLiveLat == null || ride.driverLiveLng == null) {
      return false;
    }
    final at = ride.driverLocationUpdatedAt;
    if (at == null || at.isEmpty) return false;
    try {
      final t = DateTime.parse(at);
      return DateTime.now().difference(t) <= _driverLocationFreshness;
    } catch (_) {
      return false;
    }
  }

  void _seedDriverPositionFromRide(RideModel ride) {
    if (ride.driverLiveLat != null && ride.driverLiveLng != null) {
      _driverLat = ride.driverLiveLat;
      _driverLng = ride.driverLiveLng;
    }
  }

  /// Sender view: apply streamed transporter coordinates (written by transporter device).
  void _syncSenderDriverFromStream(RideModel ride) {
    if (_viewingAsTransporter) return;
    final lat = ride.driverLiveLat;
    final lng = ride.driverLiveLng;
    if (lat == null || lng == null) return;
    if (_driverLat != null &&
        _driverLng != null &&
        (_driverLat! - lat).abs() < 1e-7 &&
        (_driverLng! - lng).abs() < 1e-7) {
      return;
    }
    setState(() {
      _driverLat = lat;
      _driverLng = lng;
    });
    _updateMap();
    unawaited(_updateRouteWithTraffic());
  }

  Future<void> _notifySenderTransporterGpsPaused() async {
    final ride = _currentRide ?? widget.ride;
    final senderId = ride.userId;
    final rideId = ride.id;
    if (senderId.isEmpty || rideId == null) return;
    final now = DateTime.now();
    if (_lastSenderGpsNudgeNotification != null &&
        now.difference(_lastSenderGpsNudgeNotification!) < _senderGpsNudgeCooldown) {
      return;
    }
    _lastSenderGpsNudgeNotification = now;
    try {
      await NotificationService().createNotification(
        userId: senderId,
        type: 'transporter_gps',
        title: 'Live location paused',
        message:
            'Your transporter may need to turn on GPS and location permission so you can track this delivery.',
        rideId: rideId,
        data: {'rideId': rideId},
      );
    } catch (e) {
      debugPrint('GPS nudge notification: $e');
    }
  }

  void _scheduleTransporterGpsRetry() {
    _gpsRetryTimer?.cancel();
    _gpsRetryTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted || !_viewingAsTransporter) return;
      unawaited(_startRealtimeLocationTracking());
    });
  }

  Future<void> _initializeMap() async {
    try {
      // Check if parcel is already collected
      _isParcelCollected = widget.ride.status == 'parcel_collected';

      if (_viewingAsTransporter) {
        await _getCurrentLocation();
      } else {
        _seedDriverPositionFromRide(widget.ride);
      }

      // Get coordinates for pickup and dropoff directly from ride (set during booking)
      _pickupLat = widget.ride.pickupLat;
      _pickupLng = widget.ride.pickupLng;
      _dropoffLat = widget.ride.dropoffLat;
      _dropoffLng = widget.ride.dropoffLng;

      if (mounted) {
        _updateMap();
        setState(() {
          _isLoading = false;
        });
      }
      if (_viewingAsTransporter) {
        await _startRealtimeLocationTracking();
      } else {
        unawaited(_updateRouteWithTraffic());
      }
    } catch (e) {
      debugPrint('Error initializing map: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Live GPS stream + periodic traffic-aware route refresh for distance/ETA.
  Future<void> _startRealtimeLocationTracking() async {
    if (!_viewingAsTransporter) return;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _transporterGpsBlocked = true);
        unawaited(_notifySenderTransporterGpsPaused());
        _scheduleTransporterGpsRetry();
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) setState(() => _transporterGpsBlocked = true);
          unawaited(_notifySenderTransporterGpsPaused());
          _scheduleTransporterGpsRetry();
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _transporterGpsBlocked = true);
        unawaited(_notifySenderTransporterGpsPaused());
        _scheduleTransporterGpsRetry();
        return;
      }

      _gpsRetryTimer?.cancel();
      if (mounted && _transporterGpsBlocked) {
        setState(() => _transporterGpsBlocked = false);
      }

      await _positionSubscription?.cancel();
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 8, // meters — updates as the transporter moves
        ),
      ).listen(
        (position) {
          if (!mounted) return;
          setState(() {
            _driverLat = position.latitude;
            _driverLng = position.longitude;
          });
          _updateMap();
          unawaited(_pushLiveLocationToRideIfDue(position));
          if (!_isParcelCollected) {
            _checkArrivalAtPickup();
          } else {
            _checkArrivalAtDropoff();
          }
        },
        onError: (e) {
          debugPrint('Position stream: $e');
          if (!mounted || !_viewingAsTransporter) return;
          setState(() => _transporterGpsBlocked = true);
          unawaited(_notifySenderTransporterGpsPaused());
          _scheduleTransporterGpsRetry();
        },
      );

      _trafficRefreshTimer?.cancel();
      _trafficRefreshTimer =
          Timer.periodic(const Duration(seconds: 15), (_) {
        _updateRouteWithTraffic();
      });
      unawaited(_updateRouteWithTraffic());
    } catch (e) {
      debugPrint('Real-time location: $e');
    }
  }

  Future<void> _getCurrentLocation() async {
    if (!_viewingAsTransporter) return;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _transporterGpsBlocked = true);
        unawaited(_notifySenderTransporterGpsPaused());
        _scheduleTransporterGpsRetry();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) setState(() => _transporterGpsBlocked = true);
          unawaited(_notifySenderTransporterGpsPaused());
          _scheduleTransporterGpsRetry();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _transporterGpsBlocked = true);
        unawaited(_notifySenderTransporterGpsPaused());
        _scheduleTransporterGpsRetry();
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (mounted) {
        setState(() {
          _driverLat = position.latitude;
          _driverLng = position.longitude;
          _transporterGpsBlocked = false;
        });
        _updateMap();
        unawaited(_pushLiveLocationToRideIfDue(position));
      }
    } catch (e) {
      debugPrint('Error getting current location: $e');
    }
  }

  Future<void> _pushLiveLocationToRideIfDue(Position position) async {
    if (!_viewingAsTransporter) return;
    final id = widget.ride.id;
    if (id == null) return;
    final now = DateTime.now();
    if (_lastRideLocationPush != null &&
        now.difference(_lastRideLocationPush!) < const Duration(seconds: 8)) {
      return;
    }
    _lastRideLocationPush = now;
    try {
      await _rideService.updateDriverLiveLocationOnRide(
        id,
        position.latitude,
        position.longitude,
      );
    } catch (e) {
      debugPrint('Live location sync: $e');
    }
  }

  /// QA: simulate driver GPS by tapping the map ([TestingFlags.allowMapTapSimulateDriverGps]).
  Future<void> _pushSimulatedTapLocation(LatLng position) async {
    if (!TestingFlags.allowMapTapSimulateDriverGps || !_viewingAsTransporter) {
      return;
    }
    final id = widget.ride.id;
    if (id == null) return;
    setState(() {
      _driverLat = position.latitude;
      _driverLng = position.longitude;
      _transporterGpsBlocked = false;
    });
    _lastRideLocationPush = null;
    _updateMap();
    unawaited(_updateRouteWithTraffic());
    try {
      await _rideService.updateDriverLiveLocationOnRide(
        id,
        position.latitude,
        position.longitude,
      );
    } catch (e) {
      debugPrint('Simulated tap location sync: $e');
    }
    _checkArrivalAtPickup();
    _checkArrivalAtDropoff();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Location pin moved (${TestingFlags.buildLabel})',
          style: GoogleFonts.inter(fontSize: 14),
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _checkArrivalAtPickup() {
    if (!_viewingAsTransporter) return;
    if (_driverLat == null || _driverLng == null || _pickupLat == null || _pickupLng == null) {
      return;
    }

    final distance = Geolocator.distanceBetween(
      _driverLat!,
      _driverLng!,
      _pickupLat!,
      _pickupLng!,
    );

    if (distance <= _arrivalRadiusMeters && !_hasArrivedAtPickup) {
      setState(() {
        _hasArrivedAtPickup = true;
      });
      
      // Show notification
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('You have arrived at the pickup location!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } else if (distance > _arrivalRadiusMeters && _hasArrivedAtPickup) {
      setState(() {
        _hasArrivedAtPickup = false;
      });
    }
  }

  void _checkArrivalAtDropoff() {
    if (!_viewingAsTransporter) return;
    if (_driverLat == null || _driverLng == null || _dropoffLat == null || _dropoffLng == null) {
      return;
    }

    final distance = Geolocator.distanceBetween(
      _driverLat!,
      _driverLng!,
      _dropoffLat!,
      _dropoffLng!,
    );

    if (distance <= _arrivalRadiusMeters && !_hasArrivedAtDropoff) {
      setState(() {
        _hasArrivedAtDropoff = true;
      });
      
      // Show notification
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('You have arrived at the delivery location!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } else if (distance > _arrivalRadiusMeters && _hasArrivedAtDropoff) {
      setState(() {
        _hasArrivedAtDropoff = false;
      });
    }
  }

  void _updateMap() {
    final Set<Marker> markers = {};
    final Set<Polyline> polylines = {};

    // Add driver's current location marker (green)
    if (_driverLat != null && _driverLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('driver_location'),
          position: LatLng(_driverLat!, _driverLng!),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(
            title: _viewingAsTransporter ? 'Your location' : 'Transporter',
            snippet: _viewingAsTransporter
                ? 'You — live GPS to sender'
                : 'Live position from transporter',
          ),
        ),
      );
    }

    if (!_isParcelCollected) {
      // Show pickup location and route
      if (_pickupLat != null && _pickupLng != null) {
        markers.add(
          Marker(
            markerId: const MarkerId('pickup'),
            position: LatLng(_pickupLat!, _pickupLng!),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
            infoWindow: InfoWindow(
              title: 'Pickup Location',
              snippet: (_currentRide ?? widget.ride).pickupLocation,
            ),
          ),
        );
      }

      // Add route from driver to pickup (green line) - actual road route
      if (_driverLat != null && _driverLng != null && _pickupLat != null && _pickupLng != null) {
        _addRoutePolyline(
          polylines,
          const PolylineId('route_to_pickup'),
          _driverLat!,
          _driverLng!,
          _pickupLat!,
          _pickupLng!,
          Colors.green,
        );
      }
    } else {
      // Show dropoff location and route
      if (_dropoffLat != null && _dropoffLng != null) {
        markers.add(
          Marker(
            markerId: const MarkerId('dropoff'),
            position: LatLng(_dropoffLat!, _dropoffLng!),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(
              title: 'Delivery Location',
              snippet: (_currentRide ?? widget.ride).dropoffLocation,
            ),
          ),
        );
      }

      // Add route from driver to dropoff (red/blue line) - actual road route
      if (_driverLat != null && _driverLng != null && _dropoffLat != null && _dropoffLng != null) {
        _addRoutePolyline(
          polylines,
          const PolylineId('route_to_dropoff'),
          _driverLat!,
          _driverLng!,
          _dropoffLat!,
          _dropoffLng!,
          Colors.red,
        );
      }
    }

    setState(() {
      _markers = markers;
      _polylines = polylines;
    });

    // Fit bounds to show driver and destination
    if (markers.length >= 2 && _mapController != null) {
      _fitBounds(markers);
    } else if (_driverLat != null && _driverLng != null && _mapController != null) {
      // Just center on driver if destination not available
      _mapController!.animateCamera(
        CameraUpdate.newLatLng(LatLng(_driverLat!, _driverLng!)),
      );
    }
  }

  void _fitBounds(Set<Marker> markers) {
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

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 100),
    );
  }

  // Add route polyline using actual road route with traffic info
  void _addRoutePolyline(
    Set<Polyline> polylines,
    PolylineId polylineId,
    double originLat,
    double originLng,
    double destLat,
    double destLng,
    Color color,
  ) async {
    void addFallbackLine() {
      polylines.add(
        Polyline(
          polylineId: polylineId,
          points: <LatLng>[
            LatLng(originLat, originLng),
            LatLng(destLat, destLng),
          ],
          color: color,
          width: 5,
        ),
      );
    }

    try {
      final routingService = RoutingService();
      // Get optimized route with traffic information
      final route = await routingService.getOptimizedRoute(
        originLat: originLat,
        originLng: originLng,
        destLat: destLat,
        destLng: destLng,
        optimization: RouteOptimization.fastest,
      );

      if (route != null) {
        // Store route info for displaying traffic
        setState(() {
          _currentRouteInfo = route;
        });

        polylines.add(
          Polyline(
            polylineId: polylineId,
            points: route.points,
            color: color,
            width: 5,
            patterns: [PatternItem.dash(20), PatternItem.gap(10)],
          ),
        );
      } else {
        // Keep a visible driver-to-destination direction line even if routing is unavailable.
        addFallbackLine();
      }

      // Update state to show the route
      if (mounted) {
        setState(() {
          _polylines = polylines;
        });
      }
    } catch (e) {
      // If routing fails (network/API/quota), still show a simple direction line.
      addFallbackLine();
      if (mounted) {
        setState(() {
          _polylines = polylines;
        });
      }
    }
  }

  Future<void> _confirmParcelCollected() async {
    setState(() {
      _isCollecting = true;
    });

    try {
      // Update ride status to parcel_collected
      await _rideService.markPickedUp(widget.ride.id!);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Parcel collection confirmed!'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Update state to show dropoff route
        setState(() {
          _isParcelCollected = true;
          _hasArrivedAtPickup = false;
          _isCollecting = false;
        });
        _updateMap();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isCollecting = false;
        });
      }
    }
  }

  Future<void> _confirmParcelDelivered() async {
    setState(() {
      _isDelivering = true;
    });

    try {
      // Update ride status to completed
      await _rideService.markDelivered(widget.ride.id!);
      
      if (mounted) {
        setState(() {
          _isDelivering = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Delivery marked. Waiting for the sender to confirm receipt in the app.',
            ),
            backgroundColor: Colors.green,
          ),
        );
        // Trip completes only after sender confirms (e.g. from request detail / notifications flow).
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isDelivering = false;
        });
      }
    }
  }

  Future<void> _senderConfirmPickupAck() async {
    final id = widget.ride.id;
    if (id == null) return;
    setState(() => _isSenderConfirmingPickup = true);
    try {
      await _rideService.senderConfirmParcelCollected(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Pickup confirmed. You can keep following the trip on the map.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSenderConfirmingPickup = false);
    }
  }

  Future<void> _senderConfirmReceiptComplete() async {
    final id = widget.ride.id;
    if (id == null) return;
    setState(() => _isSenderConfirmingDelivery = true);
    try {
      await _rideService.senderConfirmDeliveryComplete(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Delivery confirmed. Thank you for using BoltLog!',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSenderConfirmingDelivery = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Calculate initial camera position
    LatLng initialPosition = const LatLng(-19.4500, 29.8167); // Default Gweru
    if (_pickupLat != null && _pickupLng != null) {
      initialPosition = LatLng(_pickupLat!, _pickupLng!);
    } else if (_driverLat != null && _driverLng != null) {
      initialPosition = LatLng(_driverLat!, _driverLng!);
    }

    return StreamBuilder<RideModel?>(
      stream: _rideService.streamRideById(widget.ride.id!),
      builder: (context, snapshot) {
        _currentRide = snapshot.data;
        final currentRide = _currentRide ?? widget.ride;

        if (currentRide.status == 'cancelled') {
          if (!_poppedOnCancelled) {
            _poppedOnCancelled = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'This delivery was cancelled.',
                    style: GoogleFonts.inter(color: Colors.white),
                  ),
                  backgroundColor: Colors.grey.shade800,
                ),
              );
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            });
          }
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final mapAppBarTitle = _viewingAsTransporter
            ? LiveMapCopy.transporterNavTitle(toDelivery: _isParcelCollected)
            : LiveMapCopy.senderMapTitle(
                rideStatus: currentRide.status,
                hasLiveGps: _hasFreshTransporterGps(currentRide),
              );

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!_viewingAsTransporter) {
            _syncSenderDriverFromStream(currentRide);
          }
        });

        final liveTrip = currentRide.status == 'in_progress' ||
            currentRide.status == 'parcel_collected';
        final senderWaitingOnTransporterGps =
            !_viewingAsTransporter && liveTrip && !_hasFreshTransporterGps(currentRide);

        // Keep UI in sync when status becomes parcel_collected (e.g. from another device)
        if (currentRide.status == 'parcel_collected' && !_isParcelCollected) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _isParcelCollected = true;
              });
              _updateMap();
            }
          });
        }

        final showDistanceOverlay = !_transporterGpsBlocked &&
            !senderWaitingOnTransporterGps &&
            ((!_isParcelCollected &&
                    _driverLat != null &&
                    _driverLng != null &&
                    _pickupLat != null &&
                    _pickupLng != null) ||
                (_isParcelCollected &&
                    _driverLat != null &&
                    _driverLng != null &&
                    _dropoffLat != null &&
                    _dropoffLng != null));

        final showTransporterCollectBtn = _viewingAsTransporter &&
            !_isParcelCollected &&
            _hasArrivedAtPickup;
        final showTransporterDeliverBtn = _viewingAsTransporter &&
            _isParcelCollected &&
            _hasArrivedAtDropoff &&
            (currentRide.deliveryMarkedByDriverAt == null ||
                currentRide.deliveryMarkedByDriverAt!.isEmpty);
        final showSenderPickupBtn = !_viewingAsTransporter &&
            currentRide.awaitingSenderPickupConfirm;
        final showSenderDeliveryBtn = !_viewingAsTransporter &&
            currentRide.awaitingSenderDeliveryConfirm &&
            !currentRide.awaitingSenderPickupConfirm;
        final elevateLocationCard = (!_isParcelCollected && _hasArrivedAtPickup) ||
            (_isParcelCollected && _hasArrivedAtDropoff) ||
            showTransporterCollectBtn ||
            showTransporterDeliverBtn ||
            showSenderPickupBtn ||
            showSenderDeliveryBtn;

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Color(0xFF1E40AF)),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              mapAppBarTitle,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E40AF),
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Trip safety',
                onPressed: () => _showTripSafetyActions(currentRide),
                icon: const Icon(Icons.shield_outlined, color: Color(0xFF1E40AF)),
              ),
            ],
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          GoogleMap(
                            initialCameraPosition: CameraPosition(
                              target: initialPosition,
                              zoom: 14,
                            ),
                            onMapCreated: (controller) {
                              _mapController = controller;
                              _updateMap();
                            },
                            markers: _markers,
                            polylines: _polylines,
                            myLocationEnabled: true,
                            myLocationButtonEnabled: true,
                            zoomControlsEnabled: true,
                            mapType: MapType.normal,
                            compassEnabled: true,
                            onTap: (LatLng position) {
                              unawaited(_pushSimulatedTapLocation(position));
                            },
                          ),
                          if (senderWaitingOnTransporterGps)
                            Positioned(
                              top: 12,
                              left: 12,
                              right: 12,
                              child: Material(
                                elevation: 3,
                                borderRadius: BorderRadius.circular(12),
                                color: Colors.amber.shade50,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.gps_off,
                                        color: Colors.amber.shade900,
                                        size: 22,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Waiting for transporter GPS. Distance and live route will appear when they turn on location and share their position.',
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey.shade900,
                                            height: 1.25,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          if (_viewingAsTransporter && _transporterGpsBlocked)
                            Positioned(
                              top: 12,
                              left: 12,
                              right: 12,
                              child: Material(
                                elevation: 3,
                                borderRadius: BorderRadius.circular(12),
                                color: Colors.red.shade50,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            Icons.location_off,
                                            color: Colors.red.shade800,
                                            size: 22,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              'Turn on GPS and allow location access for this app so the sender can follow your trip. We’ll notify the sender that live tracking is paused until location is on.',
                                              style: GoogleFonts.inter(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.grey.shade900,
                                                height: 1.25,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        children: [
                                          TextButton(
                                            onPressed: () async {
                                              await Geolocator.openLocationSettings();
                                            },
                                            child: Text(
                                              'Device location',
                                              style: GoogleFonts.inter(
                                                fontWeight: FontWeight.w600,
                                                color: const Color(0xFF2563EB),
                                              ),
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () async {
                                              await Geolocator.openAppSettings();
                                            },
                                            child: Text(
                                              'App permissions',
                                              style: GoogleFonts.inter(
                                                fontWeight: FontWeight.w600,
                                                color: const Color(0xFF2563EB),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          // Distance indicator
                          if (showDistanceOverlay)
                            Positioned(
                              top: 16,
                              left: 16,
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
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.navigation,
                                      color: const Color(0xFF2563EB),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _viewingAsTransporter
                                                ? LiveMapCopy.transporterNavTitle(
                                                    toDelivery: _isParcelCollected,
                                                  )
                                                : LiveMapCopy.senderMapTitle(
                                                    rideStatus: currentRide.status,
                                                    hasLiveGps: _hasFreshTransporterGps(
                                                      currentRide,
                                                    ),
                                                  ),
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFF1E40AF),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _viewingAsTransporter
                                                ? LiveMapCopy.transporterSharedTripHint
                                                : LiveMapCopy.senderMapSharedTripHint,
                                            style: GoogleFonts.inter(
                                              fontSize: 10,
                                              height: 1.2,
                                              color: Colors.grey.shade800,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.gps_fixed,
                                                size: 12,
                                                color: Colors.green.shade700,
                                              ),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  _viewingAsTransporter
                                                      ? LiveMapCopy
                                                          .transporterRealtimeGpsLine
                                                      : 'Sender view: transporter GPS updates the map and ETA.',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.green.shade800,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _isParcelCollected
                                                ? 'Distance to delivery'
                                                : 'Distance to pickup',
                                            style: GoogleFonts.inter(
                                              fontSize: 10,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                          Text(
                                            _getDistanceText(),
                                            style: GoogleFonts.inter(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: const Color(0xFF1E40AF),
                                            ),
                                          ),
                                          if (_currentRouteInfo != null &&
                                              _currentRouteInfo!.hasTrafficDelay)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 4),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    _currentRouteInfo!.trafficIcon,
                                                    size: 12,
                                                    color: _currentRouteInfo!
                                                        .trafficColor,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '${_currentRouteInfo!.trafficDelayMinutes} min delay',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 10,
                                                      color: _currentRouteInfo!
                                                          .trafficColor,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if ((!_isParcelCollected &&
                                            _hasArrivedAtPickup) ||
                                        (_isParcelCollected &&
                                            _hasArrivedAtDropoff))
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'ARRIVED',
                                          style: GoogleFonts.inter(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.green,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          // Location card (pickup or dropoff)
                          Positioned(
                            bottom: elevateLocationCard ? 100 : 16,
                            left: 16,
                            right: 16,
                            child: Card(
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.location_on,
                                          color: _isParcelCollected
                                              ? Colors.red.shade400
                                              : const Color(0xFF2563EB),
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _isParcelCollected
                                                    ? 'Delivery location'
                                                    : (_viewingAsTransporter
                                                        ? 'Pickup location (your next stop)'
                                                        : 'Pickup location'),
                                                style: GoogleFonts.inter(
                                                  fontSize: 10,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                              Text(
                                                _isParcelCollected
                                                    ? currentRide.dropoffLocation
                                                    : currentRide.pickupLocation,
                                                style: GoogleFonts.inter(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  color:
                                                      const Color(0xFF1E40AF),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (currentRide.packageDescription != null)
                                      ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          currentRide.packageDescription!,
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Confirm Parcel Collected button (shown when arrived at pickup)
                          if (showTransporterCollectBtn)
                            Positioned(
                              bottom: 16,
                              left: 16,
                              right: 16,
                              child: SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: ElevatedButton.icon(
                                  onPressed: _isCollecting
                                      ? null
                                      : _confirmParcelCollected,
                                  icon: _isCollecting
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                          ),
                                        )
                                      : const Icon(Icons.check_circle, size: 24),
                                  label: Text(
                                    _isCollecting
                                        ? 'Confirming...'
                                        : 'Confirm Parcel Collected',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 2,
                                  ),
                                ),
                              ),
                            ),
                          // Confirm Parcel Delivered (until transporter marks delivered once)
                          if (showTransporterDeliverBtn)
                            Positioned(
                              bottom: 16,
                              left: 16,
                              right: 16,
                              child: SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: ElevatedButton.icon(
                                  onPressed: _isDelivering
                                      ? null
                                      : _confirmParcelDelivered,
                                  icon: _isDelivering
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                          ),
                                        )
                                      : const Icon(Icons.done_all, size: 24),
                                  label: Text(
                                    _isDelivering
                                        ? 'Confirming...'
                                        : 'Confirm Parcel Delivered',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 2,
                                  ),
                                ),
                              ),
                            ),
                          // Sender: confirm transporter picked up the parcel
                          if (showSenderPickupBtn)
                            Positioned(
                              bottom: 16,
                              left: 16,
                              right: 16,
                              child: SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: ElevatedButton.icon(
                                  onPressed: _isSenderConfirmingPickup
                                      ? null
                                      : _senderConfirmPickupAck,
                                  icon: _isSenderConfirmingPickup
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                          ),
                                        )
                                      : const Icon(Icons.inventory_2_outlined,
                                          size: 24),
                                  label: Text(
                                    _isSenderConfirmingPickup
                                        ? 'Confirming...'
                                        : 'Confirm parcel was collected',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        const Color(0xFF15803D),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 2,
                                  ),
                                ),
                              ),
                            ),
                          // Sender: complete trip after transporter marked delivered
                          if (showSenderDeliveryBtn)
                            Positioned(
                              bottom: 16,
                              left: 16,
                              right: 16,
                              child: SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: ElevatedButton.icon(
                                  onPressed: _isSenderConfirmingDelivery
                                      ? null
                                      : _senderConfirmReceiptComplete,
                                  icon: _isSenderConfirmingDelivery
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                          ),
                                        )
                                      : const Icon(Icons.verified_outlined,
                                          size: 24),
                                  label: Text(
                                    _isSenderConfirmingDelivery
                                        ? 'Confirming...'
                                        : 'I received my parcel — complete trip',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        const Color(0xFF1E40AF),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 2,
                                  ),
                                ),
                              ),
                            ),
                          // Transporter: waiting on sender to confirm receipt
                          if (_viewingAsTransporter &&
                              _isParcelCollected &&
                              currentRide.deliveryMarkedByDriverAt != null &&
                              currentRide.deliveryMarkedByDriverAt!.isNotEmpty &&
                              currentRide.status != 'completed')
                            Positioned(
                              bottom: 16,
                              left: 16,
                              right: 16,
                              child: Material(
                                elevation: 2,
                                borderRadius: BorderRadius.circular(12),
                                color: Colors.amber.shade50,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.hourglass_top,
                                        color: Colors.amber.shade800,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Waiting for the sender to confirm receipt in the app.',
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.grey.shade900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: MapCallActionBar(ride: currentRide),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  String _getDistanceText() {
    // If we have route info with traffic, use that
    if (_currentRouteInfo != null) {
      final distance = _currentRouteInfo!.distanceKm;
      final eta = _currentRouteInfo!.durationInTrafficMinutes ?? _currentRouteInfo!.durationMinutes;
      
      if (distance < 1) {
        return '${(distance * 1000).toStringAsFixed(0)} m • $eta min';
      } else {
        return '${distance.toStringAsFixed(1)} km • $eta min';
      }
    }
    
    // Fallback to straight-line distance
    if (_isParcelCollected) {
      if (_driverLat == null || _driverLng == null || _dropoffLat == null || _dropoffLng == null) {
        return 'Calculating...';
      }

      final distance = Geolocator.distanceBetween(
        _driverLat!,
        _driverLng!,
        _dropoffLat!,
        _dropoffLng!,
      );

      if (distance < 1000) {
        return '${distance.toStringAsFixed(0)} m';
      } else {
        return '${(distance / 1000).toStringAsFixed(1)} km';
      }
    } else {
      if (_driverLat == null || _driverLng == null || _pickupLat == null || _pickupLng == null) {
        return 'Calculating...';
      }

      final distance = Geolocator.distanceBetween(
        _driverLat!,
        _driverLng!,
        _pickupLat!,
        _pickupLng!,
      );

      if (distance < 1000) {
        return '${distance.toStringAsFixed(0)} m';
      } else {
        return '${(distance / 1000).toStringAsFixed(1)} km';
      }
    }
  }

  // Update route with current traffic information
  Future<void> _updateRouteWithTraffic() async {
    if (!_isParcelCollected) {
      if (_driverLat != null && _driverLng != null && _pickupLat != null && _pickupLng != null) {
        await _refreshRoute(_driverLat!, _driverLng!, _pickupLat!, _pickupLng!);
      }
    } else {
      if (_driverLat != null && _driverLng != null && _dropoffLat != null && _dropoffLng != null) {
        await _refreshRoute(_driverLat!, _driverLng!, _dropoffLat!, _dropoffLng!);
      }
    }
  }

  // Refresh route with latest traffic data
  Future<void> _refreshRoute(
    double originLat,
    double originLng,
    double destLat,
    double destLng,
  ) async {
    try {
      final routingService = RoutingService();
      final route = await routingService.getOptimizedRoute(
        originLat: originLat,
        originLng: originLng,
        destLat: destLat,
        destLng: destLng,
        optimization: RouteOptimization.fastest,
      );

      if (route != null && mounted) {
        setState(() {
          _currentRouteInfo = route;
        });
      }
    } catch (e) {
      // Silently fail - keep existing route
    }
  }

  @override
  void dispose() {
    _gpsRetryTimer?.cancel();
    _positionSubscription?.cancel();
    _trafficRefreshTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _showTripSafetyActions(RideModel ride) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share trip'),
              subtitle: const Text('Copy trip code to share'),
              onTap: () async {
                final code = 'Ride ${ride.id ?? 'unknown'}';
                await Clipboard.setData(ClipboardData(text: code));
                if (mounted) {
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Trip code copied')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.sos_outlined, color: Colors.red),
              title: const Text('Emergency'),
              subtitle: const Text('Shows emergency guidance'),
              onTap: () {
                Navigator.of(ctx).pop();
                showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Emergency'),
                    content: const Text(
                      'If you are in danger, call local emergency services immediately and share your live location with a trusted contact.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.verified_outlined),
              title: const Text('Delivery proof checklist'),
              subtitle: const Text('Photo, recipient name, and timestamp'),
              onTap: () {
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Collect proof before confirming delivery.'),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

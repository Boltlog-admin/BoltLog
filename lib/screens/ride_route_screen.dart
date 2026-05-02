import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../models/ride_model.dart';
import '../services/routing_service.dart';

class RideRouteScreen extends StatefulWidget {
  final RideModel ride;

  const RideRouteScreen({super.key, required this.ride});

  @override
  State<RideRouteScreen> createState() => _RideRouteScreenState();
}

class _RideRouteScreenState extends State<RideRouteScreen> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  double? _driverLat;
  double? _driverLng;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeMap();
  }

  Future<void> _initializeMap() async {
    try {
      // Get driver's current location
      await _getCurrentLocation();
      
      // Get coordinates for pickup and dropoff directly from ride (set during booking)
      final pickupLat = widget.ride.pickupLat;
      final pickupLng = widget.ride.pickupLng;
      final dropoffLat = widget.ride.dropoffLat;
      final dropoffLng = widget.ride.dropoffLng;

      // Update markers and polylines
      if (mounted) {
        await _updateMapMarkers(
          _driverLat,
          _driverLng,
          pickupLat,
          pickupLng,
          dropoffLat,
          dropoffLng,
        );
        setState(() {
          _isLoading = false;
        });
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

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location services are disabled. Please enable them.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permissions are denied.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permissions are permanently denied.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      setState(() {
        _driverLat = position.latitude;
        _driverLng = position.longitude;
      });
    } catch (e) {
      debugPrint('Error getting current location: $e');
    }
  }

  Future<void> _updateMapMarkers(
    double? driverLat,
    double? driverLng,
    double? pickupLat,
    double? pickupLng,
    double? dropoffLat,
    double? dropoffLng,
  ) async {
    final Set<Marker> markers = {};
    final Set<Polyline> polylines = {};
    final routingService = RoutingService();

    // Add driver's current location marker (green)
    if (driverLat != null && driverLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('driver_location'),
          position: LatLng(driverLat, driverLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(
            title: 'Your Location',
            snippet: 'Driver current position',
          ),
        ),
      );
    }

    // Add pickup marker (blue)
    if (pickupLat != null && pickupLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(pickupLat, pickupLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: InfoWindow(
            title: 'Pickup Location',
            snippet: widget.ride.pickupLocation,
          ),
        ),
      );
    }

    // Add dropoff marker (red)
    if (dropoffLat != null && dropoffLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('dropoff'),
          position: LatLng(dropoffLat, dropoffLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: 'Dropoff Location',
            snippet: widget.ride.dropoffLocation,
          ),
        ),
      );
    }

    // Add route from driver to pickup (green line) using real road route when possible
    if (driverLat != null && driverLng != null && pickupLat != null && pickupLng != null) {
      try {
        final route = await routingService.getRoute(
          originLat: driverLat,
          originLng: driverLng,
          destLat: pickupLat,
          destLng: pickupLng,
        );
        if (route != null) {
          polylines.add(
            Polyline(
              polylineId: const PolylineId('route_driver_to_pickup'),
              points: route.points,
              color: Colors.green,
              width: 4,
              patterns: [PatternItem.dash(20), PatternItem.gap(10)],
            ),
          );
        }
      } catch (_) {
        // If routing fails, skip drawing this segment
      }
    }

    // Add route from pickup to dropoff (blue line) using real road route when possible
    if (pickupLat != null && pickupLng != null && dropoffLat != null && dropoffLng != null) {
      try {
        final route = await routingService.getRoute(
          originLat: pickupLat,
          originLng: pickupLng,
          destLat: dropoffLat,
          destLng: dropoffLng,
        );
        if (route != null) {
          polylines.add(
            Polyline(
              polylineId: const PolylineId('route_pickup_to_dropoff'),
              points: route.points,
              color: const Color(0xFF2563EB), // Blue-600
              width: 4,
              patterns: [PatternItem.dash(20), PatternItem.gap(10)],
            ),
          );
        }
      } catch (_) {
        // If routing fails, skip drawing this segment
      }
    }

    setState(() {
      _markers = markers;
      _polylines = polylines;
    });

    // Fit bounds to show all markers
    if (markers.isNotEmpty && _mapController != null) {
      _fitBounds(markers);
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

  @override
  Widget build(BuildContext context) {
    // Calculate initial camera position
    LatLng initialPosition = const LatLng(-19.4500, 29.8167); // Default Gweru
    if (widget.ride.pickupLat != null && widget.ride.pickupLng != null) {
      initialPosition = LatLng(widget.ride.pickupLat!, widget.ride.pickupLng!);
    } else if (_driverLat != null && _driverLng != null) {
      initialPosition = LatLng(_driverLat!, _driverLng!);
    }

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
          'Ride Route',
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E40AF), // Blue-700
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: initialPosition,
                    zoom: 12,
                  ),
                  onMapCreated: (controller) {
                    _mapController = controller;
                    if (_markers.isNotEmpty) {
                      _fitBounds(_markers);
                    }
                  },
                  markers: _markers,
                  polylines: _polylines,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  zoomControlsEnabled: true,
                  mapType: MapType.normal,
                  compassEnabled: true,
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
                            Icon(Icons.location_on, color: Colors.green, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              'Your Location',
                              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
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
                // Ride details card
                Positioned(
                  bottom: 16,
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
                          if (widget.ride.packageDescription != null) ...[
                            Text(
                              widget.ride.packageDescription!,
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1E40AF),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.location_on, size: 16, color: const Color(0xFF2563EB)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Pickup',
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    Text(
                                      widget.ride.pickupLocation,
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        color: const Color(0xFF1E40AF),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.location_on, size: 16, color: Colors.red.shade400),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Dropoff',
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    Text(
                                      widget.ride.dropoffLocation,
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        color: const Color(0xFF1E40AF),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
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

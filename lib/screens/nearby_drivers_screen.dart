import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../models/user_model.dart';
import '../services/user_service.dart';
import '../widgets/storage_image.dart';

class NearbyDriversScreen extends StatefulWidget {
  const NearbyDriversScreen({super.key});

  @override
  State<NearbyDriversScreen> createState() => _NearbyDriversScreenState();
}

class _NearbyDriversScreenState extends State<NearbyDriversScreen> {
  final UserService _userService = UserService();
  GoogleMapController? _mapController;
  bool _isMapView = false;
  Set<Marker> _markers = {};
  double? _userLat;
  double? _userLng;
  double _radiusKm = 10.0;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      setState(() {
        _userLat = position.latitude;
        _userLng = position.longitude;
      });

      if (_isMapView && _mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLng(
            LatLng(position.latitude, position.longitude),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  String _getTruckTypeIcon(String? truckType) {
    switch (truckType?.toLowerCase()) {
      case 'bike_express':
        return '🏍️';
      case 'runner':
        return '🚐';
      case 'pickup':
        return '🚚';
      case 'truck_5t':
        return '🚛';
      case 'truck_10t':
        return '🚛';
      case 'truck_20t':
        return '🚛';
      // Legacy support
      case 'small':
        return '🚗';
      case 'medium':
        return '🚐';
      case 'large':
        return '🚚';
      case 'refrigerated':
        return '❄️';
      case 'flatbed':
        return '🚛';
      default:
        return '🚚';
    }
  }

  String _getTruckTypeLabel(String? truckType) {
    switch (truckType?.toLowerCase()) {
      case 'bike_express':
        return 'Bike Express';
      case 'runner':
        return 'Runner';
      case 'pickup':
        return 'Pickup (1.2t)';
      case 'truck_5t':
        return 'Truck (5t)';
      case 'truck_10t':
        return 'Truck (10t)';
      case 'truck_20t':
        return 'Truck (20t)';
      // Legacy support
      case 'small':
        return 'Small Truck';
      case 'medium':
        return 'Medium Truck';
      case 'large':
        return 'Large Truck';
      case 'refrigerated':
        return 'Refrigerated';
      case 'flatbed':
        return 'Flatbed';
      default:
        return truckType ?? 'Truck';
    }
  }

  void _updateMapMarkers(List<UserModel> drivers) {
    final Set<Marker> markers = {};

    // Add user location marker
    if (_userLat != null && _userLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('user_location'),
          position: LatLng(_userLat!, _userLng!),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: 'Your Location'),
        ),
      );
    }

    // Add driver markers
    for (int i = 0; i < drivers.length; i++) {
      final driver = drivers[i];
      if (driver.currentLat != null && driver.currentLng != null) {
        markers.add(
          Marker(
            markerId: MarkerId('driver_${driver.uid}_$i'),
            position: LatLng(driver.currentLat!, driver.currentLng!),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
            infoWindow: InfoWindow(
              title: driver.displayName ?? 'Driver',
              snippet: '${_getTruckTypeLabel(driver.truckType)} • ${driver.rating != null ? "${driver.rating!.toStringAsFixed(1)} ⭐" : "No rating"}',
            ),
          ),
        );
      }
    }

    // Fit bounds to show all markers
    if (markers.isNotEmpty && _mapController != null) {
      final bounds = _calculateBounds(markers);
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 100),
      );
    }

    setState(() {
      _markers = markers;
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

  @override
  Widget build(BuildContext context) {
    if (_userLat == null || _userLng == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: Text(
            'Nearby Drivers',
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E40AF),
            ),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Nearby Drivers',
          style: GoogleFonts.inter(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E40AF),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isMapView ? Icons.list : Icons.map,
              color: const Color(0xFF1E40AF),
            ),
            onPressed: () {
              setState(() {
                _isMapView = !_isMapView;
              });
            },
            tooltip: _isMapView ? 'List View' : 'Map View',
          ),
        ],
      ),
      body: StreamBuilder<List<UserModel>>(
        stream: _userService.getNearbyDrivers(
          latitude: _userLat!,
          longitude: _userLng!,
          radiusKm: _radiusKm,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
                style: GoogleFonts.inter(color: Colors.red),
              ),
            );
          }

          final drivers = snapshot.data ?? [];

          if (_isMapView) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _updateMapMarkers(drivers);
            });
          }

          if (drivers.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.local_shipping_outlined,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No drivers nearby',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Try increasing the search radius',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            );
          }

          if (_isMapView) {
            return _buildMapView(drivers);
          } else {
            return _buildListView(drivers);
          }
        },
      ),
    );
  }

  Widget _buildMapView(List<UserModel> drivers) {
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(_userLat!, _userLng!),
            zoom: 12,
          ),
          onMapCreated: (controller) {
            _mapController = controller;
            _updateMapMarkers(drivers);
          },
          markers: _markers,
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
                      'You',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.local_shipping, color: Colors.orange, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Drivers',
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

  Widget _buildListView(List<UserModel> drivers) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: drivers.length,
      itemBuilder: (context, index) {
        final driver = drivers[index];
        return _buildDriverCard(driver);
      },
    );
  }

  Widget _buildDriverCard(UserModel driver) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Driver avatar: prefer truck side view for transporters, then selfie/photo
            StorageAvatar(
              pathOrUrl: (driver.truckSideImageUrl != null && driver.truckSideImageUrl!.isNotEmpty)
                  ? driver.truckSideImageUrl
                  : ((driver.photoUrl != null && driver.photoUrl!.isNotEmpty)
                      ? driver.photoUrl
                      : driver.selfieImageUrl),
              radius: 30,
              backgroundColor: const Color(0xFF2563EB).withOpacity(0.1),
              child: ((driver.truckSideImageUrl == null || driver.truckSideImageUrl!.isEmpty) &&
                      (driver.photoUrl == null || driver.photoUrl!.isEmpty) &&
                      (driver.selfieImageUrl == null || driver.selfieImageUrl!.isEmpty))
                  ? Icon(
                      Icons.person,
                      color: const Color(0xFF2563EB),
                      size: 30,
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            // Driver info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    driver.displayName ?? 'Driver',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E40AF),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        _getTruckTypeIcon(driver.truckType),
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _getTruckTypeLabel(driver.truckType),
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  if (driver.rating != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.star,
                          size: 14,
                          color: Colors.amber,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          driver.rating!.toStringAsFixed(1),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            // Status indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Available',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.green.shade700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}

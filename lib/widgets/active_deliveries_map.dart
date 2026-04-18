import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/ride_model.dart';
import '../services/routing_service.dart';

/// Shows "No deliveries" when list is empty, or a map of accepted deliveries (pickup/dropoff markers and routes).
class ActiveDeliveriesMapWidget extends StatefulWidget {
  final List<RideModel> deliveries;
  final double? height;

  const ActiveDeliveriesMapWidget({
    super.key,
    required this.deliveries,
    this.height,
  });

  @override
  State<ActiveDeliveriesMapWidget> createState() => _ActiveDeliveriesMapWidgetState();
}

class _ActiveDeliveriesMapWidgetState extends State<ActiveDeliveriesMapWidget> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  @override
  void didUpdateWidget(ActiveDeliveriesMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deliveries != widget.deliveries && widget.deliveries.isNotEmpty) {
      _updateMapMarkers(widget.deliveries);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.deliveries.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(
            'No deliveries',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
            ),
          ),
        ),
      );
    }

    LatLng? initialPosition;
    final first = widget.deliveries.first;
    if (first.pickupLat != null && first.pickupLng != null) {
      initialPosition = LatLng(first.pickupLat!, first.pickupLng!);
    }

    Widget map = GoogleMap(
      initialCameraPosition: CameraPosition(
        target: initialPosition ?? const LatLng(-19.4500, 29.8167),
        zoom: 12,
      ),
      onMapCreated: (controller) {
        _mapController = controller;
        _updateMapMarkers(widget.deliveries);
      },
      markers: _markers,
      polylines: _polylines,
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      zoomControlsEnabled: true,
      mapType: MapType.normal,
      compassEnabled: true,
    );

    if (widget.height != null) {
      map = SizedBox(height: widget.height, child: ClipRRect(borderRadius: BorderRadius.circular(12), child: map));
    }

    return map;
  }

  Future<void> _updateMapMarkers(List<RideModel> deliveries) async {
    final Set<Marker> markers = {};
    final Set<Polyline> polylines = {};
    final routingService = RoutingService();

    for (int i = 0; i < deliveries.length; i++) {
      final ride = deliveries[i];

      final pickupLat = ride.pickupLat;
      final pickupLng = ride.pickupLng;
      final dropoffLat = ride.dropoffLat;
      final dropoffLng = ride.dropoffLng;

      if (pickupLat == null || pickupLng == null || dropoffLat == null || dropoffLng == null) continue;

      markers.add(
        Marker(
          markerId: MarkerId('pickup_${ride.id}_$i'),
          position: LatLng(pickupLat, pickupLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: InfoWindow(title: 'Pickup', snippet: ride.pickupLocation),
        ),
      );
      markers.add(
        Marker(
          markerId: MarkerId('dropoff_${ride.id}_$i'),
          position: LatLng(dropoffLat, dropoffLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(title: 'Dropoff', snippet: ride.dropoffLocation),
        ),
      );

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
              polylineId: PolylineId('route_${ride.id}_$i'),
              points: route.points,
              color: const Color(0xFF2563EB),
              width: 3,
            ),
          );
        }
      } catch (_) {}
    }

    if (markers.isNotEmpty && _mapController != null) {
      final bounds = _bounds(markers);
      _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
    }

    if (mounted) {
      setState(() {
        _markers = markers;
        _polylines = polylines;
      });
    }
  }

  LatLngBounds _bounds(Set<Marker> markers) {
    double minLat = double.infinity, maxLat = -double.infinity;
    double minLng = double.infinity, maxLng = -double.infinity;
    for (var m in markers) {
      minLat = minLat < m.position.latitude ? minLat : m.position.latitude;
      maxLat = maxLat > m.position.latitude ? maxLat : m.position.latitude;
      minLng = minLng < m.position.longitude ? minLng : m.position.longitude;
      maxLng = maxLng > m.position.longitude ? maxLng : m.position.longitude;
    }
    return LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng));
  }
}

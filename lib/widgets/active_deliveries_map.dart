import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:math';
import '../models/ride_model.dart';
import '../services/routing_service.dart';

/// Map of rides with pickup (blue) and drop-off (red) pins, optional route polylines,
/// and transporter position when [currentLat]/[currentLng] are set.
class ActiveDeliveriesMapWidget extends StatefulWidget {
  final List<RideModel> deliveries;
  final double? height;
  final double? currentLat;
  final double? currentLng;
  final bool showPickupGuidesFromCurrent;
  final ValueChanged<RideModel>? onRequestTap;
  final bool quickLoad;

  const ActiveDeliveriesMapWidget({
    super.key,
    required this.deliveries,
    this.height,
    this.currentLat,
    this.currentLng,
    this.showPickupGuidesFromCurrent = false,
    this.onRequestTap,
    this.quickLoad = false,
  });

  @override
  State<ActiveDeliveriesMapWidget> createState() => _ActiveDeliveriesMapWidgetState();
}

class _ActiveDeliveriesMapWidgetState extends State<ActiveDeliveriesMapWidget> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  LatLng _initialCameraTarget() {
    if (widget.currentLat != null && widget.currentLng != null) {
      return LatLng(widget.currentLat!, widget.currentLng!);
    }
    if (widget.deliveries.isNotEmpty) {
      final first = widget.deliveries.first;
      if (first.pickupLat != null && first.pickupLng != null) {
        return LatLng(first.pickupLat!, first.pickupLng!);
      }
    }
    return const LatLng(-19.4500, 29.8167);
  }

  @override
  void didUpdateWidget(ActiveDeliveriesMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final deliveriesChanged = oldWidget.deliveries != widget.deliveries;
    final locationChanged = oldWidget.currentLat != widget.currentLat ||
        oldWidget.currentLng != widget.currentLng;
    if (deliveriesChanged || locationChanged) {
      _updateMapMarkers(widget.deliveries);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget map = GoogleMap(
      initialCameraPosition: CameraPosition(
        target: _initialCameraTarget(),
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
      map = SizedBox(
        height: widget.height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: map,
        ),
      );
    }

    if (widget.deliveries.isEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          map,
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Material(
              color: Colors.white.withOpacity(0.95),
              elevation: 2,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text(
                  'No open requests to show yet. Enable location so your position appears; pickup pins appear when requests match your area and vehicle.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return map;
  }

  Future<void> _updateMapMarkers(List<RideModel> deliveries) async {
    final Set<Marker> markers = {};
    final Set<Polyline> polylines = {};
    final routingService = RoutingService();
    final hasCurrentLocation =
        widget.currentLat != null && widget.currentLng != null;

    if (hasCurrentLocation) {
      markers.add(
        Marker(
          markerId: const MarkerId('driver_current_location'),
          position: LatLng(widget.currentLat!, widget.currentLng!),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'Your current location'),
        ),
      );
    }

    for (int i = 0; i < deliveries.length; i++) {
      final ride = deliveries[i];

      final pickupLat = ride.pickupLat;
      final pickupLng = ride.pickupLng;
      final dropoffLat = ride.dropoffLat;
      final dropoffLng = ride.dropoffLng;

      if (pickupLat == null || pickupLng == null) continue;

      markers.add(
        Marker(
          markerId: MarkerId('pickup_${ride.id}_$i'),
          position: LatLng(pickupLat, pickupLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          onTap: () => widget.onRequestTap?.call(ride),
          infoWindow: InfoWindow(
            title: 'Pickup',
            snippet: hasCurrentLocation
                ? '${_distanceKm(widget.currentLat!, widget.currentLng!, pickupLat, pickupLng).toStringAsFixed(1)} km from you'
                : ride.pickupLocation,
            onTap: () => widget.onRequestTap?.call(ride),
          ),
        ),
      );
      if (dropoffLat != null && dropoffLng != null) {
        markers.add(
          Marker(
            markerId: MarkerId('dropoff_${ride.id}_$i'),
            position: LatLng(dropoffLat, dropoffLng),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            onTap: () => widget.onRequestTap?.call(ride),
            infoWindow: InfoWindow(title: 'Dropoff', snippet: ride.dropoffLocation),
          ),
        );
      }

      if (widget.showPickupGuidesFromCurrent && hasCurrentLocation) {
        polylines.add(
          Polyline(
            polylineId: PolylineId('you_to_pickup_${ride.id}_$i'),
            points: [
              LatLng(widget.currentLat!, widget.currentLng!),
              LatLng(pickupLat, pickupLng),
            ],
            color: const Color(0xFF0EA5E9),
            width: 4,
            geodesic: true,
          ),
        );
      }

      if (dropoffLat != null && dropoffLng != null) {
        if (widget.quickLoad) {
          polylines.add(
            Polyline(
              polylineId: PolylineId('route_${ride.id}_$i'),
              points: [
                LatLng(pickupLat, pickupLng),
                LatLng(dropoffLat, dropoffLng),
              ],
              color: const Color(0xFF2563EB),
              width: 3,
              geodesic: true,
            ),
          );
          continue;
        }
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
    }

    _fitCamera(markers);

    if (mounted) {
      setState(() {
        _markers = markers;
        _polylines = polylines;
      });
    }
  }

  void _fitCamera(Set<Marker> markers) {
    if (_mapController == null || markers.isEmpty) return;
    if (markers.length == 1) {
      final p = markers.first.position;
      _mapController!.animateCamera(CameraUpdate.newLatLngZoom(p, 13));
      return;
    }
    try {
      final bounds = _bounds(markers);
      _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 72));
    } catch (_) {
      final p = markers.first.position;
      _mapController!.animateCamera(CameraUpdate.newLatLngZoom(p, 12));
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

  double _distanceKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a = (sin(dLat / 2) * sin(dLat / 2)) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            (sin(dLng / 2) * sin(dLng / 2));
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _toRadians(double value) => value * (3.141592653589793 / 180.0);
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/ride_model.dart';
import '../models/payment_method_model.dart';
import '../services/ride_service.dart';
import '../services/pricing_service.dart';
import '../services/routing_service.dart';
import '../services/payment_service.dart';
import '../services/error_handler_service.dart';
import 'request_detail_screen.dart';

class RideBookingScreen extends StatefulWidget {
  const RideBookingScreen({super.key});

  @override
  State<RideBookingScreen> createState() => _RideBookingScreenState();
}

class _RideBookingScreenState extends State<RideBookingScreen> {
  final TextEditingController pickupController = TextEditingController();
  final TextEditingController dropoffController = TextEditingController();
  final TextEditingController packageDescriptionController = TextEditingController();
  final TextEditingController priceController = TextEditingController();
  final RideService _rideService = RideService();
  String? _selectedTransportType;
  bool _isLoading = false;
  double? _suggestedPrice;
  double? _lastEstimatedDistanceKm; // From Directions API when available
  double? _pickupLat;
  double? _pickupLng;
  double? _dropoffLat;
  double? _dropoffLng;
  // Preview map route between pickup and dropoff before sending request
  Set<Polyline> _previewRoutePolylines = {};
  String? _transporterPaymentMethod; // 'cash' or 'ecocash' - how sender will pay transporter
  GoogleMapController? _mapController;

  // Guided sender flow (map-first).
  int _step = 0; // 0 pickup, 1 dropoff, 2 transport type, 3 description, 4 amount/payment
  bool _mapPickPickup = false;
  bool _mapPickDropoff = false;

  @override
  void initState() {
    super.initState();
    _transporterPaymentMethod = 'cash';
  }

  @override
  void dispose() {
    pickupController.dispose();
    dropoffController.dispose();
    packageDescriptionController.dispose();
    priceController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _calculatePrice() async {
    // Need transport type to calculate price
    if (_selectedTransportType == null) {
      setState(() {
        _suggestedPrice = null;
      });
      return;
    }

    // Use coordinates chosen from the map for both pickup and dropoff
    final pickupLat = _pickupLat;
    final pickupLng = _pickupLng;
    final dropoffLat = _dropoffLat;
    final dropoffLng = _dropoffLng;

    // Check if we have all coordinates now
    if (pickupLat == null ||
        pickupLng == null ||
        dropoffLat == null ||
        dropoffLng == null) {
      setState(() {
        _suggestedPrice = null;
        _lastEstimatedDistanceKm = null;
        _previewRoutePolylines = {};
      });
      return;
    }

    // Load preview route polyline for map preview
    _loadPreviewRoute(pickupLat, pickupLng, dropoffLat, dropoffLng);

    // inDrive-style: use Google Directions API (or Distance Matrix) for estimated distance,
    // then suggest recommended price from that baseline. Fallback to straight-line if API fails.
    double? estimatedDistanceKm;
    final routingService = RoutingService();
    try {
      final routeDistance = await routingService.getRouteDistance(
        originLat: pickupLat,
        originLng: pickupLng,
        destLat: dropoffLat,
        destLng: dropoffLng,
      );
      estimatedDistanceKm = routeDistance;
    } catch (_) {
      estimatedDistanceKm = null;
    }
    if (estimatedDistanceKm == null) {
      estimatedDistanceKm = PricingService.calculateDistance(
        pickupLat, pickupLng, dropoffLat, dropoffLng,
      );
    }

    final price = PricingService.calculatePriceFromDistance(
      transportType: _selectedTransportType,
      distanceKm: estimatedDistanceKm,
    );

    if (price != null) {
      if (mounted) {
        setState(() {
          _suggestedPrice = price;
          _lastEstimatedDistanceKm = estimatedDistanceKm;
          if (priceController.text.isEmpty) {
            priceController.text = price.toStringAsFixed(2);
          }
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _suggestedPrice = null;
          _lastEstimatedDistanceKm = null;
          _previewRoutePolylines = {};
        });
      }
    }
  }

  Future<void> _loadPreviewRoute(
    double pickupLat,
    double pickupLng,
    double dropoffLat,
    double dropoffLng,
  ) async {
    try {
      final routingService = RoutingService();
      final route = await routingService.getRoute(
        originLat: pickupLat,
        originLng: pickupLng,
        destLat: dropoffLat,
        destLng: dropoffLng,
      );
      if (route != null && mounted) {
        setState(() {
          _previewRoutePolylines = {
            Polyline(
              polylineId: const PolylineId('preview_route'),
              points: route.points,
              color: const Color(0xFF2563EB),
              width: 4,
            ),
          };
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _previewRoutePolylines = {};
        });
      }
    }
  }

  Future<void> _bookRide() async {
    if (_pickupLat == null ||
        _pickupLng == null ||
        _dropoffLat == null ||
        _dropoffLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select pickup and dropoff locations on the map'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (priceController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your price offer'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final price = double.tryParse(priceController.text);
    if (price == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid price'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    // inDrive-style: validate proposed price against minimum floor (and recommended)
    final validation = PricingService.validateProposedPrice(
      price,
      recommendedPrice: _suggestedPrice,
    );
    if (!validation.$1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(validation.$2 ?? 'Please enter a valid price'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }

      // Enforce only one active request per user
      final hasActive = await _rideService.userHasActiveRide(user.uid);
      if (hasActive) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'You already have an active transport request. Please complete or cancel it before creating another.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final ride = RideModel(
        userId: user.uid,
        pickupLocation: pickupController.text.trim(),
        dropoffLocation: dropoffController.text.trim(),
        pickupLat: _pickupLat,
        pickupLng: _pickupLng,
        dropoffLat: _dropoffLat,
        dropoffLng: _dropoffLng,
        notes: null,
        packageDescription: packageDescriptionController.text.trim().isEmpty 
            ? null 
            : packageDescriptionController.text.trim(),
        weight: null,
        dimensions: null,
        packageType: null,
        transportType: _selectedTransportType,
        estimatedValue: null,
        price: price,
        createdAt: DateTime.now(),
        status: 'open',
        senderPaymentMethod: _transporterPaymentMethod ?? 'cash', // Default to cash
      );

      final rideId = await _rideService.createRide(ride);

      if (mounted) {
        // Build a ride with ID so request details can stream and drive negotiation.
        final rideWithId = RideModel.fromMap(ride.toMap(), rideId);

        ErrorHandlerService.showSuccess(
          context,
          'Transport request created! Waiting for transporters…',
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => RequestDetailScreen(ride: rideWithId),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error booking ride: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _stepButtonLabel() {
    switch (_step) {
      case 0:
        return _pickupLat == null ? 'Select pickup location' : 'Pickup selected - continue';
      case 1:
        return _dropoffLat == null ? 'Select drop off location' : 'Drop off selected - continue';
      case 2:
        return _selectedTransportType == null
            ? 'Select transport type to continue'
            : 'Continue to item description';
      case 3:
        return packageDescriptionController.text.trim().isEmpty
            ? 'Enter item description to continue'
            : 'Continue to suggested amount';
      default:
        return _isLoading ? 'Requesting...' : 'Request Transport';
    }
  }

  void _handleMapTap(LatLng point) {
    if (!_mapPickPickup && !_mapPickDropoff) return;
    final label = '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';
    setState(() {
      if (_mapPickPickup) {
        _pickupLat = point.latitude;
        _pickupLng = point.longitude;
        pickupController.text = 'Pickup pin: $label';
        _mapPickPickup = false;
        _step = 1;
      } else if (_mapPickDropoff) {
        _dropoffLat = point.latitude;
        _dropoffLng = point.longitude;
        dropoffController.text = 'Drop off pin: $label';
        _mapPickDropoff = false;
        _step = 2;
      }
    });
    _calculatePrice();
  }

  void _handlePrimaryAction() {
    if (_step == 0) {
      if (_pickupLat == null) {
        setState(() {
          _mapPickPickup = true;
          _mapPickDropoff = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tap on the map to place pickup marker')),
        );
      } else {
        setState(() => _step = 1);
      }
      return;
    }
    if (_step == 1) {
      if (_dropoffLat == null) {
        setState(() {
          _mapPickDropoff = true;
          _mapPickPickup = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tap on the map to place drop off marker')),
        );
      } else {
        setState(() => _step = 2);
      }
      return;
    }
    if (_step == 2) {
      if (_selectedTransportType == null) return;
      setState(() => _step = 3);
      return;
    }
    if (_step == 3) {
      if (packageDescriptionController.text.trim().isEmpty) return;
      _calculatePrice();
      setState(() => _step = 4);
      return;
    }
    _bookRide();
  }

  @override
  Widget build(BuildContext context) {
    final initialTarget = _pickupLat != null && _pickupLng != null
        ? LatLng(_pickupLat!, _pickupLng!)
        : const LatLng(-17.8252, 31.0335); // Harare fallback

    final markers = <Marker>{
      if (_pickupLat != null && _pickupLng != null)
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(_pickupLat!, _pickupLng!),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'Pickup'),
        ),
      if (_dropoffLat != null && _dropoffLng != null)
        Marker(
          markerId: const MarkerId('dropoff'),
          position: LatLng(_dropoffLat!, _dropoffLng!),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Drop off'),
        ),
    };

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1E40AF)), // Blue-700
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Request Transport',
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E40AF), // Blue-700
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.45,
              width: double.infinity,
              child: GoogleMap(
                initialCameraPosition: CameraPosition(target: initialTarget, zoom: 12),
                onMapCreated: (c) => _mapController = c,
                onTap: _handleMapTap,
                markers: markers,
                polylines: _previewRoutePolylines,
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                zoomControlsEnabled: false,
                compassEnabled: true,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pickup: ${pickupController.text.isEmpty ? 'Not selected' : pickupController.text}',
                      style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Drop off: ${dropoffController.text.isEmpty ? 'Not selected' : dropoffController.text}',
                      style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 16),
                    if (_step >= 2) ...[
                      Text(
                        'Transport Type',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1E40AF),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildTransportTypeOption('bike_express', 'Bike Express', Icons.two_wheeler),
                            _buildTransportTypeOption('runner', 'Runner', Icons.airport_shuttle),
                            _buildTransportTypeOption('pickup', 'Pickup', Icons.local_shipping, mass: '1.2t'),
                            _buildTransportTypeOption('truck_5t', 'Truck', Icons.fire_truck, mass: '5t'),
                            _buildTransportTypeOption('truck_10t', 'Truck', Icons.fire_truck, mass: '10t'),
                            _buildTransportTypeOption('truck_20t', 'Truck', Icons.fire_truck, mass: '20t'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    if (_step >= 3) ...[
                      Text(
                        'Text description of item to collect',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1E40AF),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildTextField(
                        packageDescriptionController,
                        'e.g., 2 boxes of books, groceries, medicine',
                        Icons.description,
                      ),
                      const SizedBox(height: 18),
                    ],
                    if (_step >= 4) ...[
                      Text(
                        'Suggested Amount',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1E40AF),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange.shade100),
                        ),
                        child: Text(
                          _suggestedPrice == null
                              ? 'Select transport type and route to get a suggestion.'
                              : 'Recommended price: \$${_suggestedPrice!.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange.shade800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Your Price Offer *',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1E40AF),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: TextField(
                          controller: priceController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            color: const Color(0xFF1E40AF),
                          ),
                          decoration: InputDecoration(
                            hintText: '0.00',
                            hintStyle: GoogleFonts.inter(color: Colors.grey.shade400),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            prefixIcon: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                '\$',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  color: const Color(0xFF1E40AF),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'How will you pay the transporter?',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1E40AF),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildTransporterPaymentMethodSelector(),
                      const SizedBox(height: 18),
                    ],
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handlePrimaryAction,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Text(
                                _stepButtonLabel(),
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransportTypeOption(String value, String label, IconData icon, {String? mass}) {
    final isSelected = _selectedTransportType == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTransportType = isSelected ? null : value;
        });
        // Recalculate price when transport type changes
        _calculatePrice();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2563EB) : Colors.white, // Blue-600
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFF2563EB) : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected ? Colors.white : const Color(0xFF1E40AF),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : const Color(0xFF1E40AF), // Blue-700
                  ),
                ),
              ],
            ),
            if (mass != null) ...[
              const SizedBox(height: 2),
              Text(
                mass,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? Colors.white70 : Colors.grey.shade600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTransporterPaymentMethodSelector() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _transporterPaymentMethod = 'cash';
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: _transporterPaymentMethod == 'cash'
                      ? Colors.orange
                      : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _transporterPaymentMethod == 'cash'
                        ? Colors.orange
                        : Colors.grey.shade300,
                    width: _transporterPaymentMethod == 'cash' ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.money,
                      color: _transporterPaymentMethod == 'cash'
                          ? Colors.white
                          : Colors.grey.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Cash',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _transporterPaymentMethod == 'cash'
                            ? Colors.white
                            : Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _transporterPaymentMethod = 'ecocash';
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: _transporterPaymentMethod == 'ecocash'
                      ? Colors.green
                      : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _transporterPaymentMethod == 'ecocash'
                        ? Colors.green
                        : Colors.grey.shade300,
                    width: _transporterPaymentMethod == 'ecocash' ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.account_balance_wallet,
                      color: _transporterPaymentMethod == 'ecocash'
                          ? Colors.white
                          : Colors.grey.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'EcoCash',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _transporterPaymentMethod == 'ecocash'
                            ? Colors.white
                            : Colors.grey.shade700,
                      ),
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

  Widget _buildTextField(TextEditingController controller, String hintText, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.shade200,
          width: 1,
        ),
      ),
      child: TextField(
        controller: controller,
        style: GoogleFonts.inter(
          fontSize: 16,
          color: const Color(0xFF1E40AF), // Blue-700
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: GoogleFonts.inter(
            color: Colors.grey.shade400,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.all(16),
            child: Icon(icon, color: const Color(0xFF2563EB), size: 20), // Blue-600
          ),
        ),
      ),
    );
  }
}


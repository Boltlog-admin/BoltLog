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
import '../services/error_handler_service.dart';
import 'home_screen.dart';
import 'transporter_selection_screen.dart';
import 'transporter_viewers_screen.dart';
import 'location_picker_screen.dart';
import 'saved_locations_screen.dart';
import 'payment_methods_screen.dart';
import 'request_detail_screen.dart';
import '../widgets/address_autocomplete_field.dart';

class RideBookingScreen extends StatefulWidget {
  const RideBookingScreen({super.key});

  @override
  State<RideBookingScreen> createState() => _RideBookingScreenState();
}

class _RideBookingScreenState extends State<RideBookingScreen> {
  final TextEditingController pickupController = TextEditingController();
  final TextEditingController dropoffController = TextEditingController();
  final TextEditingController notesController = TextEditingController();
  final TextEditingController packageDescriptionController = TextEditingController();
  final TextEditingController weightController = TextEditingController();
  final TextEditingController dimensionsController = TextEditingController();
  final TextEditingController estimatedValueController = TextEditingController();
  final TextEditingController priceController = TextEditingController();
  final RideService _rideService = RideService();
  final PaymentService _paymentService = PaymentService();
  String _selectedPackageType = 'small';
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
  PaymentMethodModel? _selectedPaymentMethod;
  String? _transporterPaymentMethod; // 'cash' or 'ecocash' - how sender will pay transporter
  String? _senderPaymentMethod; // Alias for _transporterPaymentMethod

  @override
  void initState() {
    super.initState();
    // Listen to changes and calculate suggested price
    // Pickup and dropoff are now chosen only from the map (no free typing),
    // so we don't need to listen for manual text changes here.
    weightController.addListener(() => _calculatePrice());
    _selectedPackageType = 'small';
    _senderPaymentMethod = 'cash'; // Default to cash
  }

  @override
  void dispose() {
    pickupController.dispose();
    dropoffController.dispose();
    notesController.dispose();
    packageDescriptionController.dispose();
    weightController.dispose();
    dimensionsController.dispose();
    estimatedValueController.dispose();
    priceController.dispose();
    pickupController.removeListener(_calculatePrice);
    dropoffController.removeListener(_calculatePrice);
    weightController.removeListener(_calculatePrice);
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

  String _getPriceInfoText() {
    if (_selectedTransportType == null ||
        _pickupLat == null ||
        _pickupLng == null ||
        _dropoffLat == null ||
        _dropoffLng == null) {
      return '';
    }

    final distanceKm = PricingService.calculateDistance(
      _pickupLat!,
      _pickupLng!,
      _dropoffLat!,
      _dropoffLng!,
    );

    final isLocal = PricingService.isLocalRoute(distanceKm);
    final routeType = isLocal ? 'Local' : 'Inter-city';
    
    // Get price range if available
    final priceRange = PricingService.getPriceRange(
      transportType: _selectedTransportType,
      pickupLat: _pickupLat,
      pickupLng: _pickupLng,
      dropoffLat: _dropoffLat,
      dropoffLng: _dropoffLng,
    );

    if (priceRange != null) {
      return '$routeType route • $priceRange';
    }

    return '$routeType route • ${distanceKm.toStringAsFixed(1)} km';
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
        notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
        packageDescription: packageDescriptionController.text.trim().isEmpty 
            ? null 
            : packageDescriptionController.text.trim(),
        weight: weightController.text.trim().isEmpty 
            ? null 
            : double.tryParse(weightController.text.trim()),
        dimensions: dimensionsController.text.trim().isEmpty 
            ? null 
            : dimensionsController.text.trim(),
        packageType: _selectedPackageType,
        transportType: _selectedTransportType,
        estimatedValue: estimatedValueController.text.trim().isEmpty 
            ? null 
            : double.tryParse(estimatedValueController.text.trim()),
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

  @override
  Widget build(BuildContext context) {
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pickup location (map-only selection)
              Text(
                'Pickup Location',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF1E40AF),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.grey.shade200,
                    width: 1,
                  ),
                ),
                child: TextField(
                  controller: pickupController,
                  readOnly: true,
                  onTap: () async {
                    final result = await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LocationPickerScreen(
                          title: 'Select Pickup Location',
                        ),
                      ),
                    );
                    if (result != null && mounted) {
                      setState(() {
                        pickupController.text = result['address'];
                        _pickupLat = result['latitude'];
                        _pickupLng = result['longitude'];
                      });
                      _calculatePrice();
                    }
                  },
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    color: const Color(0xFF1E40AF),
                  ),
                  decoration: InputDecoration(
                    hintText: 'Tap to select pickup on map',
                    hintStyle: GoogleFonts.inter(
                      color: Colors.grey.shade400,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    prefixIcon: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Icon(
                        Icons.location_on,
                        color: Color(0xFF2563EB),
                        size: 20,
                      ),
                    ),
                    suffixIcon: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(
                        Icons.map,
                        color: Color(0xFF2563EB),
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Dropoff location (map-only selection)
              Text(
                'Dropoff Location',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF1E40AF),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.grey.shade200,
                    width: 1,
                  ),
                ),
                child: TextField(
                  controller: dropoffController,
                  readOnly: true,
                  onTap: () async {
                    final result = await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LocationPickerScreen(
                          title: 'Select Dropoff Location',
                        ),
                      ),
                    );
                    if (result != null && mounted) {
                      setState(() {
                        dropoffController.text = result['address'];
                        _dropoffLat = result['latitude'];
                        _dropoffLng = result['longitude'];
                      });
                      _calculatePrice();
                    }
                  },
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    color: const Color(0xFF1E40AF),
                  ),
                  decoration: InputDecoration(
                    hintText: 'Tap to select dropoff on map',
                    hintStyle: GoogleFonts.inter(
                      color: Colors.grey.shade400,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    prefixIcon: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 20,
                      ),
                    ),
                    suffixIcon: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(
                        Icons.map,
                        color: Color(0xFF2563EB),
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Route preview map (shows pickup → dropoff before sending request)
              if (_pickupLat != null &&
                  _pickupLng != null &&
                  _dropoffLat != null &&
                  _dropoffLng != null) ...[
                Text(
                  'Route Preview',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF1E40AF),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 200,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(
                          (_pickupLat! + _dropoffLat!) / 2,
                          (_pickupLng! + _dropoffLng!) / 2,
                        ),
                        zoom: 12,
                      ),
                      markers: {
                        Marker(
                          markerId: const MarkerId('pickup'),
                          position: LatLng(_pickupLat!, _pickupLng!),
                          infoWindow: const InfoWindow(title: 'Pickup'),
                          icon: BitmapDescriptor.defaultMarkerWithHue(
                            BitmapDescriptor.hueBlue,
                          ),
                        ),
                        Marker(
                          markerId: const MarkerId('dropoff'),
                          position: LatLng(_dropoffLat!, _dropoffLng!),
                          infoWindow: const InfoWindow(title: 'Dropoff'),
                          icon: BitmapDescriptor.defaultMarkerWithHue(
                            BitmapDescriptor.hueRed,
                          ),
                        ),
                      },
                      polylines: _previewRoutePolylines,
                      myLocationEnabled: false,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: true,
                      compassEnabled: true,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Package Description
              Text(
                'Package Description',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF1E40AF), // Blue-700
                ),
              ),
              const SizedBox(height: 8),
              _buildTextField(
                packageDescriptionController,
                'e.g., 2 boxes of books, fragile item',
                Icons.description,
              ),
              const SizedBox(height: 20),
              // Transport Type
              Text(
                'Transport Type',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF1E40AF), // Blue-700
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
              const SizedBox(height: 20),
              // Weight and Dimensions Row
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Weight (kg) (Optional)',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF1E40AF), // Blue-700
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.grey.shade200,
                              width: 1,
                            ),
                          ),
                          child: TextField(
                            controller: weightController,
                            keyboardType: TextInputType.number,
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              color: const Color(0xFF1E40AF), // Blue-700
                            ),
                            decoration: InputDecoration(
                              hintText: '0.0',
                              hintStyle: GoogleFonts.inter(
                                color: Colors.grey.shade400,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Dimensions (cm) (Optional)',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF1E40AF), // Blue-700
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.grey.shade200,
                              width: 1,
                            ),
                          ),
                          child: TextField(
                            controller: dimensionsController,
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              color: const Color(0xFF1E40AF), // Blue-700
                            ),
                            decoration: InputDecoration(
                              hintText: 'LxWxH',
                              hintStyle: GoogleFonts.inter(
                                color: Colors.grey.shade400,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Estimated Value
              Text(
                'Estimated Value (Optional)',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF1E40AF), // Blue-700
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.grey.shade200,
                    width: 1,
                  ),
                ),
                child: TextField(
                  controller: estimatedValueController,
                  keyboardType: TextInputType.number,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    color: const Color(0xFF1E40AF), // Blue-700
                  ),
                  decoration: InputDecoration(
                    hintText: '\$0.00',
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
                      child: Text(
                        '\$',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          color: const Color(0xFF1E40AF), // Blue-700
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Price Offer
              Text(
                'Your Price Offer *',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF1E40AF), // Blue-700
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.grey.shade200,
                    width: 1,
                  ),
                ),
                child: TextField(
                  controller: priceController,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    color: const Color(0xFF1E40AF), // Blue-700
                  ),
                  decoration: InputDecoration(
                    hintText: '0.00',
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
                      child: Text(
                        '\$',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          color: const Color(0xFF1E40AF), // Blue-700
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_suggestedPrice != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      size: 16,
                      color: Colors.orange.shade600,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Recommended price: \$${_suggestedPrice!.toStringAsFixed(2)}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange.shade600,
                            ),
                          ),
                          if (_selectedTransportType != null &&
                              _pickupLat != null &&
                              _dropoffLat != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              _getPriceInfoText(),
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                          if (_lastEstimatedDistanceKm != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Estimated route: ${_lastEstimatedDistanceKm!.toStringAsFixed(1)} km (Google Directions)',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 2),
                          Text(
                            'Minimum offer: \$${PricingService.minimumFloorPrice.toStringAsFixed(2)}',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          priceController.text = _suggestedPrice!.toStringAsFixed(2);
                        });
                      },
                      child: Text(
                        'Use recommended',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF2563EB), // Blue-600
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              // Notes (optional)
              Text(
                'Additional Notes (Optional)',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF1E40AF), // Blue-700
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.grey.shade200,
                    width: 1,
                  ),
                ),
                child: TextField(
                  controller: notesController,
                  maxLines: 3,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    color: const Color(0xFF1E40AF), // Blue-700
                  ),
                  decoration: InputDecoration(
                    hintText: 'Any special handling instructions...',
                    hintStyle: GoogleFonts.inter(
                      color: Colors.grey.shade400,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Transporter Payment Method (how sender will pay transporter)
              Text(
                'How will you pay the transporter?',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF1E40AF),
                ),
              ),
              const SizedBox(height: 8),
              _buildTransporterPaymentMethodSelector(),
              const SizedBox(height: 24),
              // Book ride button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _bookRide,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB), // Blue-600
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
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : Text(
                          'Request Transport',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPackageTypeOption(String value, String label) {
    final isSelected = _selectedPackageType == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPackageType = value;
        });
        _calculatePrice();
      },
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2563EB) : Colors.transparent, // Blue-600
          borderRadius: BorderRadius.circular(9),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : const Color(0xFF1E40AF), // Blue-700
            ),
          ),
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

  Widget _buildSenderPaymentMethodSelector() {
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
                  _senderPaymentMethod = 'cash';
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: _senderPaymentMethod == 'cash'
                      ? Colors.orange
                      : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _senderPaymentMethod == 'cash'
                        ? Colors.orange
                        : Colors.grey.shade300,
                    width: _senderPaymentMethod == 'cash' ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.money,
                      color: _senderPaymentMethod == 'cash'
                          ? Colors.white
                          : Colors.grey.shade700,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Cash',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _senderPaymentMethod == 'cash'
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
                  _senderPaymentMethod = 'ecocash';
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: _senderPaymentMethod == 'ecocash'
                      ? Colors.green
                      : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _senderPaymentMethod == 'ecocash'
                        ? Colors.green
                        : Colors.grey.shade300,
                    width: _senderPaymentMethod == 'ecocash' ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.account_balance_wallet,
                      color: _senderPaymentMethod == 'ecocash'
                          ? Colors.white
                          : Colors.grey.shade700,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'EcoCash',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _senderPaymentMethod == 'ecocash'
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


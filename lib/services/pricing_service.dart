import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';

import '../config/testing_flags.dart';

/// inDrive-style: we don't fix the price with APIs; we use them for a baseline.
/// Distance Matrix / Directions API provide "estimated distance" → we suggest a Recommended Price.
/// The actual final amount is determined by the users' agreement based on that data.
class PricingService {
  /// Minimum allowed proposed price (prevents $0.01 offers).
  static const double minimumFloorPrice = 1.0;

  /// Platform fee as decimal (e.g. 0.02 = 2%).
  static const double platformFeePercentage = 0.02;

  /// Whether wallet deduction runs when a transporter accepts ([TestingFlags.enableAcceptanceFeeDeduction]).
  static bool get deductFeeOnAcceptance => TestingFlags.enableAcceptanceFeeDeduction;

  /// Amount transporters see as payout for an agreed fare (net if fees on, full if off).
  static double transporterNetFromAgreed(double agreedPrice) =>
      deductFeeOnAcceptance ? agreedPrice * (1 - platformFeePercentage) : agreedPrice;

  // Calculate distance between two coordinates in kilometers
  static double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2) / 1000; // Convert to km
  }

  // Determine if route is local (intra-city) or inter-city
  // Local: within same city (typically < 30km)
  // Inter-city: between different cities (typically >= 30km)
  static bool isLocalRoute(double distanceKm) {
    return distanceKm < 30.0; // Threshold for local vs inter-city
  }

  /// Calculate delivery cost using driver's rate per 10 km.
  /// Used so transporter sees the trip cost based on their signed-up rate.
  static double? calculateDriverPriceForDistance(double distanceKm, double? ratePer10Km) {
    if (ratePer10Km == null || ratePer10Km <= 0) return null;
    return (distanceKm / 10.0) * ratePer10Km;
  }

  // Calculate price for Motorcycle (Bike Express) - Harare Pricing
  static double calculateMotorcyclePrice(double distanceKm) {
    if (distanceKm <= 3) {
      return 2.0;
    } else if (distanceKm <= 5) {
      return 3.0;
    } else if (distanceKm <= 7) {
      return 4.0;
    } else if (distanceKm <= 9) {
      return 5.0;
    } else if (distanceKm <= 14) {
      return 6.0;
    } else if (distanceKm <= 17) {
      return 7.0;
    } else if (distanceKm <= 19) {
      return 8.0;
    } else if (distanceKm <= 22) {
      return 9.0;
    } else {
      // 22km+: $0.4 per km
      return 9.0 + ((distanceKm - 22) * 0.4);
    }
  }

  // Calculate price for Van (Runner)
  static double calculateVanPrice(double distanceKm, bool isLocal) {
    if (!isLocal) {
      // Inter-city: $5 per parcel
      return 5.0;
    } else {
      // Intra-city: Use similar pricing to motorcycle for now
      // You can adjust this based on your requirements
      return calculateMotorcyclePrice(distanceKm) * 1.2;
    }
  }

  // Calculate price for Pickup Truck 1.5tn
  static double calculatePickupPrice(double distanceKm) {
    // $2 per km
    return distanceKm * 2.0;
  }

  // Calculate price for Truck 3-5tn - Gweru Pricing
  static double calculateTruck5tPrice(double distanceKm, bool isLocal) {
    if (isLocal && distanceKm <= 10) {
      // Local (10km): Price Range $40-$50
      // Return average or minimum
      return 45.0; // Average of $40-$50
    } else {
      // For longer distances, scale up
      return 45.0 + ((distanceKm - 10) * 3.0);
    }
  }

  // Calculate price for Truck 7.5tn - Gweru Pricing
  static double calculateTruck10tPrice(double distanceKm, bool isLocal) {
    if (isLocal && distanceKm <= 10) {
      // Local (10km): Starting Price $80
      return 80.0;
    } else {
      // Inter City: Distance * $2.5
      return distanceKm * 2.5;
    }
  }

  // Calculate price for Truck 10-15tn - Gweru Pricing
  static double calculateTruck20tPrice(double distanceKm, bool isLocal) {
    if (isLocal && distanceKm <= 10) {
      // Local: Starting Price $120 - $140
      return 130.0; // Average of $120-$140
    } else {
      // For longer distances (inter-city), scale up
      // Use similar rate to 7.5tn truck for inter-city
      return 130.0 + ((distanceKm - 10) * 2.5);
    }
  }

  // Main pricing calculation method
  static double? calculatePrice({
    required String? transportType,
    required double? pickupLat,
    required double? pickupLng,
    required double? dropoffLat,
    required double? dropoffLng,
  }) {
    // If no transport type selected, return null
    if (transportType == null) {
      return null;
    }

    // If coordinates are missing, return null
    if (pickupLat == null || 
        pickupLng == null || 
        dropoffLat == null || 
        dropoffLng == null) {
      return null;
    }

    // Calculate distance
    final distanceKm = calculateDistance(
      pickupLat,
      pickupLng,
      dropoffLat,
      dropoffLng,
    );

    // Determine if local or inter-city
    final isLocal = isLocalRoute(distanceKm);

    // Calculate price based on transport type
    switch (transportType) {
      case 'bike_express':
        return calculateMotorcyclePrice(distanceKm);
      
      case 'runner':
        return calculateVanPrice(distanceKm, isLocal);
      
      case 'pickup':
        return calculatePickupPrice(distanceKm);
      
      case 'truck_5t':
        return calculateTruck5tPrice(distanceKm, isLocal);
      
      case 'truck_10t':
        return calculateTruck10tPrice(distanceKm, isLocal);
      
      case 'truck_20t':
        return calculateTruck20tPrice(distanceKm, isLocal);
      
      default:
        // Default pricing for unknown types
        return distanceKm * 1.5;
    }
  }

  /// Recommended price from an estimated route distance (e.g. from Directions API or Distance Matrix).
  /// inDrive-style: the backend uses estimated distance as baseline; final amount is user-negotiated.
  static double? calculatePriceFromDistance({
    required String? transportType,
    required double distanceKm,
  }) {
    if (transportType == null) return null;
    final isLocal = isLocalRoute(distanceKm);
    switch (transportType) {
      case 'bike_express':
        return calculateMotorcyclePrice(distanceKm);
      case 'runner':
        return calculateVanPrice(distanceKm, isLocal);
      case 'pickup':
        return calculatePickupPrice(distanceKm);
      case 'truck_5t':
        return calculateTruck5tPrice(distanceKm, isLocal);
      case 'truck_10t':
        return calculateTruck10tPrice(distanceKm, isLocal);
      case 'truck_20t':
        return calculateTruck20tPrice(distanceKm, isLocal);
      default:
        return distanceKm * 1.5;
    }
  }

  /// Recommended price for this route (coordinates). Prefer using route/Matrix distance + calculatePriceFromDistance when available.
  static double? getRecommendedPrice({
    required String? transportType,
    required double? pickupLat,
    required double? pickupLng,
    required double? dropoffLat,
    required double? dropoffLng,
  }) {
    return calculatePrice(
      transportType: transportType,
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      dropoffLat: dropoffLat,
      dropoffLng: dropoffLng,
    );
  }

  /// Validates rider's proposed_price against minimum_floor_price and optional recommended_price.
  /// Returns [true, null] if valid; [false, errorMessage] if invalid.
  static (bool isValid, String? errorMessage) validateProposedPrice(
    double proposedPrice, {
    double? recommendedPrice,
  }) {
    if (proposedPrice < minimumFloorPrice) {
      return (false, 'Minimum offer is \$${minimumFloorPrice.toStringAsFixed(2)}.');
    }
    if (proposedPrice <= 0) {
      return (false, 'Please enter a valid price.');
    }
    return (true, null);
  }

  // Get price range for display (for trucks with ranges)
  static String? getPriceRange({
    required String? transportType,
    required double? pickupLat,
    required double? pickupLng,
    required double? dropoffLat,
    required double? dropoffLng,
  }) {
    if (transportType == null ||
        pickupLat == null ||
        pickupLng == null ||
        dropoffLat == null ||
        dropoffLng == null) {
      return null;
    }

    final distanceKm = calculateDistance(
      pickupLat,
      pickupLng,
      dropoffLat,
      dropoffLng,
    );

    final isLocal = isLocalRoute(distanceKm);

    switch (transportType) {
      case 'truck_5t':
        if (isLocal && distanceKm <= 10) {
          return '\$40 - \$50';
        }
        break;
      
      case 'truck_20t':
        if (isLocal && distanceKm <= 10) {
          return '\$120 - \$140';
        }
        break;
    }

    return null;
  }
}

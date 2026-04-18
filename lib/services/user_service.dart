import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/app_constants.dart';
import '../models/user_model.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Create or update user in Firestore - only for the authenticated user's own account
  Future<void> createOrUpdateUser(UserModel user) async {
    final currentUid = _auth.currentUser?.uid;
    if (currentUid == null || currentUid != user.uid) {
      throw Exception('You can only create or update your own account');
    }
    try {
      await _firestore.collection('users').doc(user.uid).set(
        user.toMap(),
        SetOptions(merge: true),
      );
    } catch (e) {
      throw Exception('Error creating/updating user: $e');
    }
  }

  // Get user from Firestore (with cache support for faster loading)
  Future<UserModel?> getUser(String uid, {Source source = Source.serverAndCache}) async {
    try {
      // Use cache first if available, then server
      // This makes subsequent app opens much faster
      final doc = await _firestore.collection('users').doc(uid).get(GetOptions(source: source));
      if (doc.exists) {
        return UserModel.fromMap(doc.data()!);
      }
      return null;
    } catch (e) {
      // If cache fails, try server directly
      if (source == Source.cache) {
        try {
          final doc = await _firestore.collection('users').doc(uid).get(GetOptions(source: Source.server));
          if (doc.exists) {
            return UserModel.fromMap(doc.data()!);
          }
        } catch (serverError) {
          throw Exception('Error getting user: $e');
        }
      }
      throw Exception('Error getting user: $e');
    }
  }

  // Update user profile - only the authenticated user's own account
  Future<void> updateUserProfile({
    required String uid,
    String? displayName,
    String? phoneNumber,
    String? photoUrl,
  }) async {
    final currentUid = _auth.currentUser?.uid;
    if (currentUid == null || currentUid != uid) {
      throw Exception('You can only edit your own account');
    }
    try {
      final updateData = <String, dynamic>{};
      if (displayName != null) updateData['displayName'] = displayName;
      if (phoneNumber != null) updateData['phoneNumber'] = phoneNumber;
      if (photoUrl != null) updateData['photoUrl'] = photoUrl;
      updateData['lastLoginAt'] = DateTime.now().toIso8601String();

      await _firestore.collection('users').doc(uid).update(updateData);
    } catch (e) {
      throw Exception('Error updating user profile: $e');
    }
  }

  // Update driver profile (role and driver-specific fields) - only the authenticated user's own account
  Future<void> updateDriverProfile({
    required String uid,
    String? role,
    String? truckType,
    double? ratePer10Km,
    String? carBookImageUrl,
    String? truckSideImageUrl,
    String? driverLicenseImageUrl,
    String? selfieImageUrl,
    bool? isAvailable,
    String? vehicleNumber,
    double? driverWalletBalance,
    double? currentLat,
    double? currentLng,
    String? verificationStatus,
    String? verificationNotes,
  }) async {
    final currentUid = _auth.currentUser?.uid;
    if (currentUid == null || currentUid != uid) {
      throw Exception('You can only edit your own account');
    }
    try {
      final updateData = <String, dynamic>{};
      if (role != null) updateData['role'] = role;
      if (truckType != null) updateData['truckType'] = truckType;
      if (ratePer10Km != null) updateData['ratePer10Km'] = ratePer10Km;
      if (carBookImageUrl != null) updateData['carBookImageUrl'] = carBookImageUrl;
      if (truckSideImageUrl != null) updateData['truckSideImageUrl'] = truckSideImageUrl;
      if (driverLicenseImageUrl != null) updateData['driverLicenseImageUrl'] = driverLicenseImageUrl;
      if (selfieImageUrl != null) updateData['selfieImageUrl'] = selfieImageUrl;
      if (isAvailable != null) updateData['isAvailable'] = isAvailable;
      if (vehicleNumber != null) updateData['vehicleNumber'] = vehicleNumber;
      if (driverWalletBalance != null) updateData['driverWalletBalance'] = driverWalletBalance;
      if (currentLat != null) updateData['currentLat'] = currentLat;
      if (currentLng != null) updateData['currentLng'] = currentLng;
      if (verificationStatus != null) {
        updateData['verificationStatus'] = verificationStatus;
        final s = verificationStatus.toLowerCase();
        if (s == 'auto_verified' || s == 'verified') {
          updateData['verifiedAt'] = DateTime.now().toIso8601String();
        }
      }
      if (verificationNotes != null) updateData['verificationNotes'] = verificationNotes;
      updateData['lastLoginAt'] = DateTime.now().toIso8601String();

      await _firestore.collection('users').doc(uid).update(updateData);
    } catch (e) {
      throw Exception('Error updating driver profile: $e');
    }
  }

  // Get current user from Firestore
  Future<UserModel?> getCurrentUser() async {
    final user = _auth.currentUser;
    if (user != null) {
      return await getUser(user.uid);
    }
    return null;
  }

  /// Fetch multiple users by ID. Returns list in same order as [uids]; null where user not found.
  Future<List<UserModel?>> getUsersByIds(List<String> uids) async {
    if (uids.isEmpty) return [];
    final results = await Future.wait(
      uids.map((id) => _firestore.collection('users').doc(id).get()),
    );
    return results
        .map((snap) => snap.exists ? UserModel.fromMap(snap.data()!) : null)
        .toList();
  }

  // Stream user data
  Stream<UserModel?> streamUser(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists ? UserModel.fromMap(doc.data()!) : null);
  }

  // Get nearby drivers within a radius (in kilometers)
  Stream<List<UserModel>> getNearbyDrivers({
    required double latitude,
    required double longitude,
    double radiusKm = 10.0, // Default 10km radius
  }) {
    // Get all available drivers and filter by distance in memory
    // Note: For production, consider using GeoFirestore for efficient geospatial queries
    // [AppConstants.roleDriver] must match signup writes; legacy `transporter` role is not in this query.
    return _firestore
        .collection('users')
        .where('role', isEqualTo: AppConstants.roleDriver)
        .where('isAvailable', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      final drivers = <UserModel>[];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final driverLat = data['currentLat']?.toDouble();
        final driverLng = data['currentLng']?.toDouble();
        
        if (driverLat != null && driverLng != null) {
          // Calculate distance
          final distance = _calculateDistance(
            latitude, longitude,
            driverLat, driverLng,
          );
          
          // Only include drivers within radius
          if (distance <= radiusKm) {
            drivers.add(UserModel.fromMap(data));
          }
        }
      }
      // Sort by distance (closest first)
      drivers.sort((a, b) {
        final distA = _calculateDistance(latitude, longitude, a.currentLat!, a.currentLng!);
        final distB = _calculateDistance(latitude, longitude, b.currentLat!, b.currentLng!);
        return distA.compareTo(distB);
      });
      return drivers;
    });
  }

  /// One-time fetch of nearby drivers (for push on new request). inDrive-style: broadcast to drivers near pickup.
  Future<List<UserModel>> getNearbyDriversOnce({
    required double latitude,
    required double longitude,
    double radiusKm = 25.0,
  }) async {
    final snapshot = await _firestore
        .collection('users')
        .where('role', isEqualTo: AppConstants.roleDriver)
        .where('isAvailable', isEqualTo: true)
        .get();
    final drivers = <UserModel>[];
    for (var doc in snapshot.docs) {
      final data = doc.data();
      final driverLat = data['currentLat']?.toDouble();
      final driverLng = data['currentLng']?.toDouble();
      if (driverLat != null && driverLng != null) {
        final distance = _calculateDistance(latitude, longitude, driverLat, driverLng);
        if (distance <= radiusKm) {
          drivers.add(UserModel.fromMap(data));
        }
      }
    }
    drivers.sort((a, b) {
      final distA = _calculateDistance(latitude, longitude, a.currentLat!, a.currentLng!);
      final distB = _calculateDistance(latitude, longitude, b.currentLat!, b.currentLng!);
      return distA.compareTo(distB);
    });
    return drivers;
  }

  // Calculate distance between two coordinates using Haversine formula
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // Earth radius in kilometers
    
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLon = (lon2 - lon1) * math.pi / 180.0;
    
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) *
        math.cos(lat2 * math.pi / 180.0) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return earthRadius * c;
  }
}



import '../config/testing_flags.dart';

class UserModel {
  final String uid;
  final String? email;
  final String? displayName;
  final String? phoneNumber;
  final String role; // 'Passenger' (Sender/Customer) or 'Driver' (Transporter)
  final String? photoUrl;
  final DateTime createdAt;
  final DateTime? lastLoginAt;
  // Driver-specific fields
  final double? currentLat;
  final double? currentLng;
  final String? truckType; // e.g., 'bike', 'sedan', 'pickup', 'closed_pickup', 'lorry'
  final bool? isAvailable; // Whether driver is available for new deliveries
  final String? vehicleNumber;
  final double? rating; // Average rating
  final double? ratePer10Km; // Driver's rate per 10 km (used to calculate delivery cost for sender requests)
  final String? carBookImageUrl; // Car registration book image
  final String? truckSideImageUrl; // Truck side-view image
  final String? driverLicenseImageUrl; // Driver license image
  final String? selfieImageUrl; // Driver selfie image
  // Driver wallet/balance
  final double? driverWalletBalance; // Remaining balance for driver fees/charges
  // Verification fields
  final String? verificationStatus; // 'pending', 'auto_verified', 'needs_review', 'rejected', 'verified'
  final String? verificationNotes;
  final String? idFullName;
  final String? carBookOwnerName;
  final double? faceMatchScore;
  final DateTime? verifiedAt;

  UserModel({
    required this.uid,
    this.email,
    this.displayName,
    this.phoneNumber,
    required this.role,
    this.photoUrl,
    required this.createdAt,
    this.lastLoginAt,
    this.currentLat,
    this.currentLng,
    this.truckType,
    this.isAvailable,
    this.vehicleNumber,
    this.rating,
    this.ratePer10Km,
    this.carBookImageUrl,
    this.truckSideImageUrl,
    this.driverLicenseImageUrl,
    this.selfieImageUrl,
    this.driverWalletBalance,
    this.verificationStatus,
    this.verificationNotes,
    this.idFullName,
    this.carBookOwnerName,
    this.faceMatchScore,
    this.verifiedAt,
  });

  // Convert to Firestore document
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'phoneNumber': phoneNumber,
      'role': role,
      'photoUrl': photoUrl,
      'createdAt': createdAt.toIso8601String(),
      'lastLoginAt': lastLoginAt?.toIso8601String(),
      'currentLat': currentLat,
      'currentLng': currentLng,
      'truckType': truckType,
      'isAvailable': isAvailable,
      'vehicleNumber': vehicleNumber,
      'rating': rating,
      'ratePer10Km': ratePer10Km,
      'carBookImageUrl': carBookImageUrl,
      'truckSideImageUrl': truckSideImageUrl,
      'driverLicenseImageUrl': driverLicenseImageUrl,
      'selfieImageUrl': selfieImageUrl,
      'driverWalletBalance': driverWalletBalance,
      'verificationStatus': verificationStatus,
      'verificationNotes': verificationNotes,
      'idFullName': idFullName,
      'carBookOwnerName': carBookOwnerName,
      'faceMatchScore': faceMatchScore,
      'verifiedAt': verifiedAt?.toIso8601String(),
    };
  }

  // Create from Firestore document
  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      email: map['email'],
      displayName: map['displayName'],
      phoneNumber: map['phoneNumber'],
      role: map['role'] ?? 'Passenger',
      photoUrl: map['photoUrl'],
      createdAt: DateTime.parse(map['createdAt'] ?? DateTime.now().toIso8601String()),
      lastLoginAt: map['lastLoginAt'] != null ? DateTime.parse(map['lastLoginAt']) : null,
      currentLat: map['currentLat']?.toDouble(),
      currentLng: map['currentLng']?.toDouble(),
      truckType: map['truckType'],
      isAvailable: map['isAvailable'] ?? true,
      vehicleNumber: map['vehicleNumber'],
      rating: map['rating']?.toDouble(),
      ratePer10Km: map['ratePer10Km']?.toDouble(),
      carBookImageUrl: map['carBookImageUrl'],
      truckSideImageUrl: map['truckSideImageUrl'],
      driverLicenseImageUrl: map['driverLicenseImageUrl'],
      selfieImageUrl: map['selfieImageUrl'],
      driverWalletBalance: map['driverWalletBalance']?.toDouble(),
      verificationStatus: map['verificationStatus'],
      verificationNotes: map['verificationNotes'],
      idFullName: map['idFullName'],
      carBookOwnerName: map['carBookOwnerName'],
      faceMatchScore: map['faceMatchScore']?.toDouble(),
      verifiedAt: map['verifiedAt'] != null ? DateTime.parse(map['verifiedAt']) : null,
    );
  }

  // Create from Firebase User
  factory UserModel.fromFirebaseUser({
    required String uid,
    String? email,
    String? displayName,
    String? phoneNumber,
    String role = 'Passenger',
    String? photoUrl,
    double? currentLat,
    double? currentLng,
    String? truckType,
    bool? isAvailable,
    String? vehicleNumber,
    double? rating,
    double? ratePer10Km,
    String? carBookImageUrl,
    String? truckSideImageUrl,
    String? driverLicenseImageUrl,
    String? selfieImageUrl,
    double? driverWalletBalance,
  }) {
    final initialBalance = role == 'Driver'
        ? (driverWalletBalance ??
            (TestingFlags.relaxTransporterVerification
                ? TestingFlags.qaDefaultDriverWallet
                : 10.0))
        : driverWalletBalance;
    final defaultVerificationStatus = role == 'Driver'
        ? (TestingFlags.relaxTransporterVerification
            ? 'auto_verified'
            : 'pending')
        : 'verified';
    final now = DateTime.now();
    final verifiedAtDriver =
        role == 'Driver' && defaultVerificationStatus == 'auto_verified'
            ? now
            : null;

    return UserModel(
      uid: uid,
      email: email,
      displayName: displayName,
      phoneNumber: phoneNumber,
      role: role,
      photoUrl: photoUrl,
      createdAt: now,
      lastLoginAt: now,
      currentLat: currentLat,
      currentLng: currentLng,
      truckType: truckType,
      isAvailable: role == 'Driver' ? (isAvailable ?? true) : isAvailable,
      vehicleNumber: vehicleNumber,
      rating: rating,
      ratePer10Km: ratePer10Km,
      carBookImageUrl: carBookImageUrl,
      truckSideImageUrl: truckSideImageUrl,
      driverLicenseImageUrl: driverLicenseImageUrl,
      selfieImageUrl: selfieImageUrl,
      driverWalletBalance: initialBalance,
      verificationStatus: defaultVerificationStatus,
      verificationNotes: null,
      idFullName: null,
      carBookOwnerName: null,
      faceMatchScore: null,
      verifiedAt: verifiedAtDriver,
    );
  }
}


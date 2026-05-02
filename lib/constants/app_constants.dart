class AppConstants {
  // Ride Status
  static const String rideStatusPending = 'pending';
  static const String rideStatusAccepted = 'accepted';
  static const String rideStatusInProgress = 'in_progress';
  static const String rideStatusParcelCollected = 'parcel_collected';
  static const String rideStatusCompleted = 'completed';
  static const String rideStatusCancelled = 'cancelled';

  // User Roles (Firestore / [UserModel.role] — UI may say "Sender" / "Transporter")
  static const String rolePassenger = 'Passenger';
  static const String roleDriver = 'Driver';

  /// Use this instead of ad-hoc string checks. Accepts any casing/spacing from Firestore.
  /// Also treats `transporter` as driver if old documents used the UI label by mistake.
  ///
  /// **Canonical Firestore values** from signup are [roleDriver] / [rolePassenger] (`Driver` / `Passenger`).
  /// Never compare with `== 'driver'` alone — use this helper so `transporter` and casing stay aligned.
  static bool isDriverRole(String? role) {
    final r = role?.trim().toLowerCase() ?? '';
    return r == 'driver' || r == 'transporter';
  }

  /// Sender / customer shell. Empty role is treated as passenger for legacy documents.
  static bool isPassengerRole(String? role) {
    final r = role?.trim().toLowerCase() ?? '';
    return r == 'passenger' || r.isEmpty;
  }

  // Image Settings
  static const double maxImageSizeMB = 10.0;
  static const int maxImageSizeBytes = 10 * 1024 * 1024; // 10MB
  static const int imageCompressionQuality = 85;
  static const int imageMaxWidth = 1920;
  static const int imageMaxHeight = 1920;

  // Pagination
  static const int defaultPageSize = 20;
  static const int maxPageSize = 50;
  static const int rideHistoryLimit = 50;

  // Pricing
  static const double driverFeePercentage = 0.02; // 2%
  static const double localRouteThresholdKm = 30.0;

  // Location
  static const double defaultRadiusKm = 10.0;
  static const int viewerOnlineTimeoutSeconds = 30;

  // Validation
  static const int minPasswordLength = 6;
  static const int maxNameLength = 100;
  static const int maxDescriptionLength = 500;

  // Network
  static const int connectionTimeoutSeconds = 30;
  static const int maxRetryAttempts = 3;
  static const int retryDelaySeconds = 2;

  // Firebase Storage paths - organized by signup email for easy sorting
  // drivers/{emailKey}/ - transporter documents (car book, license, selfie)
  // senders/{emailKey}/ - client documents (profile, ID, etc.)
  /// Sanitizes email for use in storage path (e.g. admin@boltlog.org -> admin_at_boltlog_org)
  /// Must match Firebase rules: split('@').join('_at_').split('.').join('_')
  static String sanitizeEmailForStorage(String email) {
    return email.trim().replaceAll('@', '_at_').replaceAll('.', '_');
  }
  /// Path key from user. Uses uid_xxx for reliability - auth token email may not
  /// be ready immediately after signup, causing "object not found" on upload.
  static String storagePathKey(String? email, String uid) {
    return 'uid_$uid';
  }
  static String storageDriverPath(String pathKey, String fileName) => 'drivers/$pathKey/$fileName';
  static String storageSenderPath(String pathKey, String fileName) => 'senders/$pathKey/$fileName';

  // App Info
  static const String appName = 'Boltlog';
  static const String appVersion = '2.4.0';
  static const String supportEmail = 'support@boltlog.com';
  static const String supportPhone = '+263 77 123 4567';
}

/// Compile-time switches for **internal / QA builds**.
///
/// **Before production:** set `relaxTransporterVerification`, `useQaFallbackDriverBaseLocation`,
/// `allowMapTapSimulateDriverGps`, and `showInternalQaBanner` to `false`; tune
/// `enableAcceptanceFeeDeduction` to match your go-live policy; restore a modest
/// default driver wallet in [UserModel.fromFirebaseUser] by turning relax off.
class TestingFlags {
  /// When true, verification UI is relaxed: transporters can negotiate and switch
  /// roles without full document checks; dashboard treats profile as complete.
  static const bool relaxTransporterVerification = true;

  /// When true, deducts [PricingService.platformFeePercentage] from the
  /// transporter wallet atomically when they accept a job (see [RideService.acceptRide]).
  /// Keep OFF in QA when you want accept -> live map without wallet gating.
  static const bool enableAcceptanceFeeDeduction = false;

  /// When true and [relaxTransporterVerification] is on, driver onboarding can
  /// skip document photo capture (rate + vehicle type only).
  static bool get skipDriverDocumentUpload => relaxTransporterVerification;

  /// Assigned transporters can tap the live map to push a simulated GPS point
  /// (Firestore `driverLiveLat`/`driverLiveLng`) when GPS is unavailable in QA.
  static const bool allowMapTapSimulateDriverGps = true;

  /// Show Flutter’s debug banner (top-right) in debug builds so QA can spot
  /// non-release configuration at a glance.
  static const bool showInternalQaBanner = true;

  /// When true (and in debug mode), the app opens on the role flow overview so you can
  /// see sender vs transporter shells and the routing story before continuing.
  /// Set to `false` for release-like runs or when you want splash-first.
  static const bool showRoleFlowOverview = true;

  /// **Debug only.** Skips permissions, flow overview, and email/password login; uses
  /// Firebase **anonymous** sign-in and jumps straight to a shell so you can test UI logic.
  /// Requires Anonymous sign-in enabled in Firebase Console → Authentication → Sign-in method.
  /// Set to `false` to use the normal splash → auth flow.
  static const bool skipPermissionsLoginForQa = true;

  /// When [skipPermissionsLoginForQa] is active: `false` = sender [MainNavigation],
  /// `true` = transporter [TransporterNavigation].
  static const bool qaBypassLaunchAsDriver = false;

  /// User-visible label for snackbars and short copy (keep in sync with flags above).
  static const String buildLabel = 'Test build';

  /// New drivers get this wallet balance in QA so platform fees on accept rarely block flows.
  static const double qaDefaultDriverWallet = 1000.0;

  /// When true and GPS is unavailable, transporter discovery uses [qaFallbackDriverBaseLat]/[qaFallbackDriverBaseLng].
  static const bool useQaFallbackDriverBaseLocation = true;

  /// Default base (Harare CBD) for QA when simulators or permissions block real GPS.
  static const double qaFallbackDriverBaseLat = -17.8252;
  static const double qaFallbackDriverBaseLng = 31.0335;
}

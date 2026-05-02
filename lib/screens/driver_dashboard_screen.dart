import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/ride_model.dart';
import '../models/user_model.dart';
import '../services/ride_service.dart';
import '../services/user_service.dart';
import '../constants/app_constants.dart';
import '../config/testing_flags.dart';
import 'transporter_dashboard_screen.dart';
import 'active_deliveries_screen.dart';
import '../widgets/active_deliveries_map.dart';
import 'request_detail_screen.dart';
import 'driver_account_edit_screen.dart';
import 'main_navigation.dart';
import 'wallet_topup_screen.dart';
import '../widgets/storage_image.dart';
import '../utils/ride_distance_utils.dart';
import '../utils/transporter_accept_nav.dart';
import '../theme/app_theme.dart';

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  final RideService _rideService = RideService();
  final UserService _userService = UserService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  Timer? _autoRefreshTimer;
  /// Home preview card: accept → map in progress.
  String? _busyPreviewRideId;

  @override
  void initState() {
    super.initState();
    // Auto-refresh the dashboard every 5 seconds so "Current Requests" stays up to date
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      setState(() {
        // No-op: just trigger a rebuild; data comes from live Firestore streams
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_syncTransporterGpsToProfile());
    });
  }

  /// Writes live GPS to Firestore so the home map and nearby filters use real coordinates.
  Future<void> _syncTransporterGpsToProfile() async {
    final user = _auth.currentUser;
    if (user == null || !mounted) return;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      await _userService.updateDriverProfile(
        uid: user.uid,
        currentLat: pos.latitude,
        currentLng: pos.longitude,
      );
    } catch (_) {
      // Map still works with myLocationEnabled when permission is granted.
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in')),
      );
    }

    return StreamBuilder<UserModel?>(
      stream: _userService.streamUser(user.uid),
      builder: (context, userSnapshot) {
        final userModel = userSnapshot.data;
        final walletBalance = userModel?.driverWalletBalance ?? 0.0;
        final verificationStatus =
            (userModel?.verificationStatus ?? 'pending').toLowerCase();
        final isVerified = verificationStatus == 'auto_verified' ||
            verificationStatus == 'verified';

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Transporter Home',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1E40AF),
                    letterSpacing: -0.25,
                  ),
                ),
              ],
            ),
            actions: [
              PopupMenuButton<String>(
                tooltip: 'More options',
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: AppColors.primaryDark,
                ),
                color: AppColors.cardBackground,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                onSelected: (value) {
                  switch (value) {
                    case 'requests':
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TransporterDashboardScreen(),
                        ),
                      );
                      break;
                    case 'active':
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ActiveDeliveriesScreen(),
                        ),
                      );
                      break;
                    case 'wallet':
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const WalletTopUpScreen(),
                        ),
                      );
                      break;
                    case 'account':
                      if (userModel == null) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              DriverAccountEditScreen(user: userModel),
                        ),
                      );
                      break;
                    case 'home':
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MainNavigation(
                            initialTabIndex: 0,
                          ),
                        ),
                        (route) => false,
                      );
                      break;
                    case 'report':
                      _showReportIssueDialog(context);
                      break;
                    case 'help':
                      _showHelpDialog(context);
                      break;
                    case 'support':
                      _showContactSupportDialog(context);
                      break;
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'requests',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.dashboard_outlined),
                      title: Text('Current requests'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'active',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.local_shipping_outlined),
                      title: Text('Active deliveries'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'wallet',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.account_balance_wallet_outlined),
                      title: Text('Wallet top up'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'account',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.person_outline_rounded),
                      title: Text('Account details'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'home',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.home_outlined),
                      title: Text('Go to home'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'report',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.report_problem_outlined),
                      title: Text('Report an issue'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'help',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.help_outline),
                      title: Text('Help & FAQ'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'support',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.contact_support_outlined),
                      title: Text('Contact support'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: SafeArea(
            child: StreamBuilder<List<RideModel>>(
              stream: _rideService.streamTransporterActiveItems(user.uid),
              builder: (context, deliveriesSnapshot) {
                return StreamBuilder<List<RideModel>>(
                  stream: _rideService.streamTransporterCompletedDeliveries(user.uid),
                  builder: (context, completedDeliveriesSnapshot) {
                    return StreamBuilder<List<RideModel>>(
                      stream: _rideService.streamTransporterRequestInbox(user.uid),
                      builder: (context, availableRidesSnapshot) {
                        // Calculate statistics
                        final deliveries = deliveriesSnapshot.data ?? [];
                        final completedRides = completedDeliveriesSnapshot.data ?? [];

                        // Vehicle match for inbox; map shows all of these (pins at real pickup/dropoff).
                        // List-style "nearby only" uses radius; map must not hide farther requests.
                        final allAvailableRides = availableRidesSnapshot.data ?? [];
                        final availableRidesMatching = allAvailableRides
                            .where((ride) {
                              final orderType = ride.transportType;
                              final driverTruckType = userModel?.truckType;
                              if (orderType == null || orderType.isEmpty) {
                                return true;
                              }
                              return driverTruckType != null &&
                                  driverTruckType.isNotEmpty &&
                                  orderType == driverTruckType;
                            })
                            .toList();
                        final availableRidesForMap =
                            filterAndSortRidesByDistance(
                          List<RideModel>.from(availableRidesMatching),
                          driverLat: userModel?.currentLat,
                          driverLng: userModel?.currentLng,
                          applyRadiusFilter: false,
                        );

                        // Calculate earnings from completed rides
                        final totalEarnings = completedRides.fold<double>(
                          0.0,
                          (sum, ride) => sum + (ride.price ?? 0.0),
                        );
                        
                        final activeDeliveriesCount = deliveries.length;
                        final completedDeliveriesCount = completedRides.length;
                        final rating = userModel?.rating ?? 0.0;
                        final isAvailable = userModel?.isAvailable ?? true;

                        return RefreshIndicator(
                          onRefresh: () async {
                            // Refresh is handled by streams
                          },
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.cardBackground,
                                borderRadius: BorderRadius.circular(AppRadii.md),
                                border: Border.all(
                                  color: AppColors.primary.withOpacity(0.2),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.account_balance_wallet_rounded,
                                    color: AppColors.primary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Wallet',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '\$${walletBalance.toStringAsFixed(2)}',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primaryDark,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildSectionHeader('Open Requests Map'),
                            const SizedBox(height: 10),
                            Container(
                              height: MediaQuery.of(context).size.height * 0.5,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(AppRadii.lg),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.08),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(AppRadii.lg),
                                child: ActiveDeliveriesMapWidget(
                                  deliveries: availableRidesForMap,
                                  height:
                                      MediaQuery.of(context).size.height * 0.5,
                                  currentLat: userModel?.currentLat,
                                  currentLng: userModel?.currentLng,
                                  showPickupGuidesFromCurrent: true,
                                  quickLoad: true,
                                  onRequestTap: (ride) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            RequestDetailScreen(ride: ride),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'Pins show every open request that matches your vehicle type (by pickup location). Tap a blue pickup marker for details.',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
      },
    );
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  String _buildVerificationBannerText(
      String verificationStatus, String? verificationNotes) {
    final normalized = verificationStatus.toLowerCase();

    if (verificationNotes != null && verificationNotes.isNotEmpty) {
      return verificationNotes;
    }

    switch (normalized) {
      case 'needs_review':
        return 'Your documents need a quick manual review. Please check your Account Details card for any notes and re-upload clearer photos if requested.';
      case 'rejected':
        return 'Your documents were rejected. Please open Account Details to see the reason and upload clearer photos.';
      case 'pending':
      default:
        return 'Your documents are being verified. You will be able to accept and negotiate on requests once verification is complete.';
    }
  }

  /// Returns 0.0..1.0 for transporter profile completion (same 5 steps as profile screen).
  double _driverProfileProgressValue(UserModel? userModel) {
    // In testing mode, treat profile as fully complete so percentage shows 100%.
    if (TestingFlags.relaxTransporterVerification) return 1.0;
    if (userModel == null) return 0.0;
    const int totalSteps = 5;
    int completedSteps = 0;
    if ((userModel.displayName ?? '').isNotEmpty &&
        (userModel.phoneNumber ?? '').isNotEmpty) completedSteps++;
    if ((userModel.truckType ?? '').isNotEmpty &&
        (userModel.vehicleNumber ?? '').isNotEmpty) completedSteps++;
    if ((userModel.carBookImageUrl ?? '').isNotEmpty &&
        (userModel.truckSideImageUrl ?? '').isNotEmpty) completedSteps++;
    if ((userModel.driverLicenseImageUrl ?? '').isNotEmpty &&
        (userModel.selfieImageUrl ?? '').isNotEmpty) completedSteps++;
    final verificationStatus =
        (userModel.verificationStatus ?? 'pending').toLowerCase();
    if (verificationStatus == 'auto_verified' ||
        verificationStatus == 'verified') completedSteps++;
    return (completedSteps / totalSteps).clamp(0.0, 1.0).toDouble();
  }

  Widget _buildProfileProgress(UserModel? userModel) {
    if (userModel == null) {
      return const SizedBox.shrink();
    }

    final double progress = _driverProfileProgressValue(userModel);
    final int percentage = (progress * 100).round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Account setup',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1E40AF),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$percentage% complete',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Complete your profile and upload all documents to start accepting more deliveries.',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailabilityToggle(String uid, bool isAvailable) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAvailable
              ? Colors.green.withOpacity(0.25)
              : Colors.grey.shade300,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Driver Status',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1E40AF),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isAvailable ? 'Available for deliveries' : 'Currently offline',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: isAvailable ? Colors.green.shade700 : Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Switch(
            value: isAvailable,
            onChanged: (value) async {
              try {
                await _userService.updateDriverProfile(
                  uid: uid,
                  isAvailable: value,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        value ? 'You are now available' : 'You are now offline',
                      ),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error updating status: ${e.toString()}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            activeColor: const Color(0xFF2563EB),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection({
    required double totalEarnings,
    required int activeDeliveries,
    required int completedDeliveries,
    required double rating,
    required int availableRides,
  }) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: Icons.attach_money,
            iconColor: Colors.green,
            title: 'Total Earnings',
            value: '\$${totalEarnings.toStringAsFixed(2)}',
            subtitle: 'From deliveries',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.local_shipping,
            iconColor: const Color(0xFF2563EB),
            title: 'Active',
            value: activeDeliveries.toString(),
            subtitle: 'Live trip or accepted',
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: 10,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Quick Actions'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildQuickActionCard(
                icon: Icons.dashboard,
                title: 'Current Requests',
                subtitle: 'View requests',
                color: const Color(0xFF2563EB),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const TransporterDashboardScreen(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildQuickActionCard(
                icon: Icons.local_shipping,
                title: 'Active',
                subtitle: 'Deliveries',
                color: Colors.orange,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ActiveDeliveriesScreen(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildQuickActionCard(
          icon: Icons.account_balance_wallet,
          title: 'Top Up Wallet',
          subtitle: 'Add funds to accept more deliveries',
          color: Colors.green,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const WalletTopUpScreen(),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildQuickActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.25), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1E40AF),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: _buildSectionHeaderTextStyle(),
    );
  }

  TextStyle _buildSectionHeaderTextStyle() {
    return GoogleFonts.inter(
      fontSize: 18,
      fontWeight: FontWeight.bold,
      color: const Color(0xFF1E40AF),
    );
  }

  Widget _buildDeliveryPreviewCard(
    BuildContext context,
    RideModel ride,
    String transporterId, {
    double? driverLat,
    double? driverLng,
    required bool canActAsTransporter,
  }) {
    final distanceKm = (driverLat != null && driverLng != null)
        ? distanceToPickupKm(ride, driverLat, driverLng)
        : null;
    final legKm = pickupToDropoffKm(ride);
    final waitingForSender = ride.awaitingSenderToConfirmTransporter &&
        ride.awaitingSenderConfirmDriverId?.trim() == transporterId &&
        !(ride.priceStatus == 'pending' &&
            ride.lastCounterOfferBy == 'sender');

    final showTransporterActions = !waitingForSender &&
        (ride.status == 'open' ||
            (ride.status == 'pending' && ride.isDriverSlotOpen));
    final lockedToOtherNegotiator =
        ride.negotiatingTransporterId != null &&
            ride.negotiatingTransporterId!.isNotEmpty &&
            ride.negotiatingTransporterId != transporterId;
    final committedToOther = ride.acceptedTransporterId != null &&
        ride.acceptedTransporterId!.isNotEmpty &&
        ride.acceptedTransporterId != transporterId;
    final canInteract = showTransporterActions &&
        canActAsTransporter &&
        !lockedToOtherNegotiator &&
        !committedToOther;
    final busy = _busyPreviewRideId == ride.id;
    final acceptLabel =
        ride.priceStatus == 'accepted' ? 'Accept delivery' : 'Accept';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (ride.packageDescription != null) ...[
                        Text(
                          ride.packageDescription!,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1E40AF),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (ride.packageType != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            ride.packageType!.toUpperCase(),
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF2563EB),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (ride.price != null)
                  Text(
                    '\$${ride.price!.toStringAsFixed(2)}',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF2563EB),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    legKm != null
                        ? 'About ${legKm.toStringAsFixed(1)} km pickup → drop-off (straight line).'
                        : 'Open details for route and addresses.',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      height: 1.35,
                      color: const Color(0xFF1E40AF),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    distanceKm != null
                        ? 'About ${distanceKm.toStringAsFixed(1)} km from you to pickup.'
                        : 'Turn on location to see distance to pickup.',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      height: 1.35,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
              ),
            ),
            if (waitingForSender) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.indigo.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.mark_chat_unread_outlined,
                        color: Colors.indigo.shade800, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Waiting for sender\'s reply. When they confirm, you\'ll go to the live map.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.indigo.shade900,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (showTransporterActions && canInteract) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: busy
                      ? null
                      : () async {
                          setState(() => _busyPreviewRideId = ride.id);
                          try {
                            await transporterAcceptRideOpenMap(
                              context,
                              ride,
                              transporterId,
                              usePushReplacement: false,
                            );
                          } finally {
                            if (mounted) {
                              setState(() => _busyPreviewRideId = null);
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          acceptLabel,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                ),
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        if (canInteract &&
                            ride.priceStatus == 'accepted' &&
                            ride.isDriverSlotOpen &&
                            (ride.status == 'open' ||
                                ride.status == 'pending')) {
                          setState(() => _busyPreviewRideId = ride.id);
                          try {
                            await transporterAcceptRideOpenMap(
                              context,
                              ride,
                              transporterId,
                              usePushReplacement: false,
                            );
                          } finally {
                            if (mounted) {
                              setState(() => _busyPreviewRideId = null);
                            }
                          }
                          return;
                        }
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RequestDetailScreen(ride: ride),
                          ),
                        );
                      },
                icon: const Icon(Icons.chevron_right, size: 20),
                label: Text(
                  'View details',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF2563EB),
                  padding: const EdgeInsets.only(top: 8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveDeliveryCard(BuildContext context, RideModel delivery) {
    final statusColor = _getStatusColor(delivery.status);
    final statusLabel = _getStatusLabel(delivery.status);
    final negotiatedAmount = delivery.finalPrice ??
        delivery.counterOffer ??
        delivery.price;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 2,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ActiveDeliveriesScreen(),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      statusLabel,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                  if (negotiatedAmount != null)
                    Text(
                      '\$${negotiatedAmount.toStringAsFixed(2)}',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E40AF),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (delivery.packageDescription != null) ...[
                Text(
                  delivery.packageDescription!,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1E40AF),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Icon(Icons.location_on, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      delivery.pickupLocation,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(
            Icons.local_shipping,
            size: 48,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.amber;
      case 'accepted':
        return Colors.orange;
      case 'in_progress':
        return Colors.blue;
      case 'parcel_collected':
        return Colors.purple;
      case 'completed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'NEGOTIATING';
      case 'accepted':
        return 'ACCEPTED';
      case 'in_progress':
        return 'IN TRANSIT';
      case 'parcel_collected':
        return 'PARCEL COLLECTED';
      case 'completed':
        return 'DELIVERED';
      default:
        return status.toUpperCase();
    }
  }

  Widget _buildAccountCard(BuildContext context, UserModel? userModel) {
    if (userModel == null) {
      return const SizedBox.shrink();
    }

    String getVehicleTypeLabel(String? truckType) {
      switch (truckType) {
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
        default:
          return truckType ?? 'Not set';
      }
    }

    String _verificationStatusLabel(String? status) {
      switch ((status ?? 'pending').toLowerCase()) {
        case 'auto_verified':
        case 'verified':
          return 'Verified';
        case 'needs_review':
          return 'Needs review';
        default:
          return 'Pending';
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  // Profile Picture (Selfie)
                  StorageAvatar(
                    pathOrUrl: userModel.selfieImageUrl,
                    radius: 24,
                    backgroundColor: const Color(0xFF2563EB).withOpacity(0.1),
                    child: userModel.selfieImageUrl == null || userModel.selfieImageUrl!.isEmpty
                        ? const Icon(
                            Icons.account_circle,
                            color: Color(0xFF2563EB),
                            size: 32,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Account Details',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E40AF),
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.edit, color: Color(0xFF2563EB)),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DriverAccountEditScreen(user: userModel),
                    ),
                  );
                },
                tooltip: 'Edit Account',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.grey.shade200),
          const SizedBox(height: 16),
          
          // Personal Information
          _buildAccountDetailRow(
            Icons.person,
            'Full Name',
            userModel.displayName ?? 'Not set',
          ),
          const SizedBox(height: 12),
          _buildAccountDetailRow(
            Icons.email,
            'Email',
            userModel.email ?? 'Not set',
          ),
          const SizedBox(height: 12),
          _buildAccountDetailRow(
            Icons.phone,
            'Phone Number',
            userModel.phoneNumber ?? 'Not set',
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.grey.shade200),
          const SizedBox(height: 16),
          
          // Driver Information
          _buildAccountDetailRow(
            Icons.local_shipping,
            'Vehicle Type',
            getVehicleTypeLabel(userModel.truckType),
          ),
          if (userModel.ratePer10Km != null && userModel.ratePer10Km! > 0) ...[
            const SizedBox(height: 12),
            _buildAccountDetailRow(
              Icons.attach_money,
              'Rate per 10 km',
              '\$${userModel.ratePer10Km!.toStringAsFixed(2)}',
            ),
          ],
          if (userModel.vehicleNumber != null && userModel.vehicleNumber!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildAccountDetailRow(
              Icons.confirmation_number,
              'Vehicle Number',
              userModel.vehicleNumber!,
            ),
          ],
          if (userModel.rating != null && userModel.rating! > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.star, size: 20, color: Colors.grey.shade600),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Rating',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            userModel.rating!.toStringAsFixed(1),
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1E40AF),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.star,
                            size: 16,
                            color: Colors.amber,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          _buildAccountDetailRow(
            Icons.verified_user,
            'Verification',
            _verificationStatusLabel(userModel.verificationStatus),
          ),
          if (userModel.verificationNotes != null && userModel.verificationNotes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Text(
                userModel.verificationNotes!,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Divider(color: Colors.grey.shade200),
          const SizedBox(height: 16),
          
          // Documents Status
          Text(
            'Documents',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          _buildDocumentStatus(
            'Car Book',
            userModel.carBookImageUrl != null && userModel.carBookImageUrl!.isNotEmpty,
          ),
          const SizedBox(height: 8),
          _buildDocumentStatus(
            'Truck Side View',
            userModel.truckSideImageUrl != null && userModel.truckSideImageUrl!.isNotEmpty,
          ),
          const SizedBox(height: 8),
          _buildDocumentStatus(
            'Driver License',
            userModel.driverLicenseImageUrl != null && userModel.driverLicenseImageUrl!.isNotEmpty,
          ),
          const SizedBox(height: 8),
          _buildDocumentStatus(
            'Selfie',
            userModel.selfieImageUrl != null && userModel.selfieImageUrl!.isNotEmpty,
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.grey.shade200),
          const SizedBox(height: 16),
          
        ],
      ),
    );
  }
  

  Widget _buildAccountDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade600),
        const SizedBox(width: 12),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              Flexible(
                child: Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1E40AF),
                  ),
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDocumentStatus(String documentName, bool isUploaded) {
    return Row(
      children: [
        Icon(
          isUploaded ? Icons.check_circle : Icons.cancel,
          size: 18,
          color: isUploaded ? Colors.green : Colors.grey.shade400,
        ),
        const SizedBox(width: 8),
        Text(
          documentName,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: isUploaded ? Colors.grey.shade700 : Colors.grey.shade500,
            decoration: isUploaded ? null : TextDecoration.lineThrough,
          ),
        ),
        const Spacer(),
        Text(
          isUploaded ? 'Uploaded' : 'Not uploaded',
          style: GoogleFonts.inter(
            fontSize: 12,
            color: isUploaded ? Colors.green : Colors.grey.shade500,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildSupportCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.support_agent,
                  color: Colors.orange,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Support & Help',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E40AF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.grey.shade200),
          const SizedBox(height: 12),
          _buildSupportOption(
            context,
            icon: Icons.report_problem,
            title: 'Report an Issue',
            subtitle: 'Report problems or bugs',
            color: Colors.red,
            onTap: () {
              _showReportIssueDialog(context);
            },
          ),
          const SizedBox(height: 12),
          _buildSupportOption(
            context,
            icon: Icons.help_outline,
            title: 'Help & FAQ',
            subtitle: 'Get answers to common questions',
            color: const Color(0xFF2563EB),
            onTap: () {
              _showHelpDialog(context);
            },
          ),
          const SizedBox(height: 12),
          _buildSupportOption(
            context,
            icon: Icons.contact_support,
            title: 'Contact Support',
            subtitle: 'Get in touch with our support team',
            color: Colors.green,
            onTap: () {
              _showContactSupportDialog(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSupportOption(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1E40AF),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  void _showReportIssueDialog(BuildContext context) {
    final TextEditingController issueController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(Icons.report_problem, color: Colors.red),
                  const SizedBox(width: 8),
                  Text(
                    'Report an Issue',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E40AF),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Please describe the issue you encountered:',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: issueController,
                      maxLines: 5,
                      decoration: InputDecoration(
                        hintText: 'Describe the issue in detail...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFF2563EB),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          issueController.dispose();
                        },
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.inter(
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (issueController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please describe the issue'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          setState(() {
                            isSubmitting = true;
                          });

                          // Simulate submission (in production, send to backend)
                          await Future.delayed(const Duration(seconds: 1));

                          if (context.mounted) {
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Issue reported successfully! We will look into it.'),
                                backgroundColor: Colors.green,
                                duration: Duration(seconds: 3),
                              ),
                            );
                            issueController.dispose();
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          'Submit',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.help_outline, color: Color(0xFF2563EB)),
              const SizedBox(width: 8),
              Text(
                'Help & FAQ',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E40AF),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFAQItem(
                  'How do I accept a delivery request?',
                  'Tap on any request card to view details, then tap "Accept Request" to accept it.',
                ),
                const SizedBox(height: 16),
                _buildFAQItem(
                  'How do I mark a delivery as complete?',
                  'Go to Active Deliveries, find your delivery, and tap "Mark as Delivered" when you\'ve completed it.',
                ),
                const SizedBox(height: 16),
                _buildFAQItem(
                  'How do I update my availability?',
                  'Use the toggle switch at the top of the dashboard to go online or offline.',
                ),
                const SizedBox(height: 16),
                _buildFAQItem(
                  'How do I edit my account details?',
                  'Tap the edit icon on the Account Details card to update your information.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Close',
                style: GoogleFonts.inter(
                  color: const Color(0xFF2563EB),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showContactSupportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.contact_support, color: Colors.green),
              const SizedBox(width: 8),
              Text(
                'Contact Support',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E40AF),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Get in touch with our support team:',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 16),
              _buildContactOption(
                Icons.email,
                'Email',
                'support@boltlog.com',
                () {
                  // Open email client
                },
              ),
              const SizedBox(height: 12),
              _buildContactOption(
                Icons.phone,
                'Phone',
                '+263 774 219 900',
                () {
                  // Make phone call
                },
              ),
              const SizedBox(height: 12),
              _buildContactOption(
                Icons.chat,
                'Live Chat',
                'Available 24/7',
                () {
                  // Open chat
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Close',
                style: GoogleFonts.inter(
                  color: const Color(0xFF2563EB),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFAQItem(String question, String answer) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1E40AF),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          answer,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: Colors.grey.shade700,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildContactOption(IconData icon, String label, String value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF2563EB), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Text(
                    value,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1E40AF),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/app_resume_service.dart';
import '../services/user_service.dart';
import '../models/user_model.dart';
import '../services/ride_service.dart';
import '../models/ride_model.dart';
import '../utils/ride_distance_utils.dart';
import '../theme/app_theme.dart';
import 'ride_booking_screen.dart';
import 'ride_history_screen.dart';
import 'nearby_drivers_screen.dart';
import 'auth_entry_screen.dart';
import 'request_detail_screen.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart';
import 'support_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final UserService _userService = UserService();
  final RideService _rideService = RideService();
  List<RideModel>? _cachedUserRides;

  /// Avoid flicker / empty flashes: never replace a non-empty cache with a transient [].
  void _applyUserRidesCache(List<RideModel>? data) {
    if (data == null) return;
    if (data.isNotEmpty) {
      _cachedUserRides = data;
      return;
    }
    if (_cachedUserRides == null) {
      _cachedUserRides = data;
    }
  }

  Widget _buildSenderProfileProgress(UserModel? userModel) {
    if (userModel == null) return const SizedBox.shrink();

    const int totalSteps = 3;
    int completed = 0;
    if ((userModel.displayName ?? '').trim().isNotEmpty) completed++;
    if ((userModel.phoneNumber ?? '').trim().isNotEmpty) completed++;
    if ((userModel.email ?? '').trim().isNotEmpty) completed++;

    final double progress = (completed / totalSteps).clamp(0.0, 1.0);
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
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Add your name, phone and email in Profile to complete your account.',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'completed':
        return 'DELIVERED';
      case 'parcel_collected':
        return 'PARCEL COLLECTED';
      case 'in_progress':
        return 'IN TRANSIT';
      case 'pending':
        return 'NEGOTIATING';
      case 'open':
        return 'WAITING FOR TRANSPORTERS';
      case 'cancelled':
        return 'CANCELLED';
      default:
        return status.toUpperCase();
    }
  }

  String _activeOrderDistanceSubtitle(RideModel ride) {
    final km = pickupToDropoffKm(ride);
    if (km == null) {
      return 'Distance unavailable';
    }
    if (km >= 100) {
      return '${km.toStringAsFixed(0)} km trip';
    }
    return '${km.toStringAsFixed(1)} km trip';
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'parcel_collected':
        return Colors.purple;
      case 'in_progress':
        return Colors.blue;
      case 'pending':
        return Colors.amber;
      case 'open':
        return Colors.orange;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'open':
        return Icons.access_time;
      case 'pending':
        return Icons.handshake;
      case 'in_progress':
        return Icons.local_shipping;
      case 'parcel_collected':
        return Icons.inventory_2;
      case 'completed':
        return Icons.check_circle;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final User? firebaseUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Text(
              'Boltlog',
              style: GoogleFonts.inter(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E40AF), // Blue-700
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB).withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: const Color(0xFF2563EB).withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Text(
                'SENDER',
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF2563EB),
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: Color(0xFF1E40AF)), // Blue-700
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NotificationsScreen(),
                ),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Color(0xFF1E40AF)), // Blue-700
            onSelected: (value) async {
              if (value == 'profile') {
                // Profile is handled by bottom navigation
              } else if (value == 'settings') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SettingsScreen(),
                  ),
                );
              } else if (value == 'logout') {
                final user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  try {
                    final model = await _userService.getUser(user.uid);
                    if ((model?.role ?? '').toLowerCase() == 'passenger') {
                      await _rideService.cleanupSenderRidesBeforeLogout(user.uid);
                    }
                  } catch (_) {}
                }
                await AppResumeService.instance.clear();
                await FirebaseAuth.instance.signOut();
                if (mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const AuthEntryScreen()),
                    (route) => false,
                  );
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'profile',
                child: Text('Profile'),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Text('Settings'),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Text('Logout'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Active Orders – persistent: cache last list, show loading placeholder when waiting
              if (firebaseUser != null)
                StreamBuilder<List<RideModel>>(
                  stream: _rideService.streamUserRides(firebaseUser.uid),
                  builder: (context, snapshot) {
                    _applyUserRidesCache(snapshot.data);
                    final allRides = snapshot.data ?? _cachedUserRides ?? [];
                    final activeRides = allRides
                        .where((ride) =>
                            ride.status != 'completed' && ride.status != 'cancelled')
                        .toList();

                    if (snapshot.connectionState == ConnectionState.waiting &&
                        activeRides.isEmpty) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Active transport requests',
                            style: GoogleFonts.inter(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1E40AF),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: const Color(0xFF2563EB),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Loading orders…',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }

                    // Always show this block on the sender home dashboard (not only when non-empty).
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Active transport requests',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1E40AF), // Blue-700
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (activeRides.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Text(
                              'No active deliveries right now. Use Request Transport below when you need a trip.',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: Colors.grey.shade700,
                                height: 1.35,
                              ),
                            ),
                          )
                        else
                          ...activeRides.map<Widget>((ride) {
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => RequestDetailScreen(ride: ride),
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
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: _getStatusColor(ride.status).withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Icon(
                                            _getStatusIcon(ride.status),
                                            color: _getStatusColor(ride.status),
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                ride.packageDescription ?? 'Transport Request',
                                                style: GoogleFonts.inter(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                  color: const Color(0xFF1E40AF),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                _activeOrderDistanceSubtitle(ride),
                                                style: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade600,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _getStatusColor(ride.status).withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            _getStatusLabel(ride.status),
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: _getStatusColor(ride.status),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (ride.price != null) ...[
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Price:',
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                          Text(
                                            '\$${ride.price!.toStringAsFixed(2)}',
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: const Color(0xFF2563EB),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 24),
                      ],
                    );
                  },
                ),
              // Sender account setup progress
              if (firebaseUser != null)
                StreamBuilder<UserModel?>(
                  stream: _userService.streamUser(firebaseUser.uid),
                  builder: (context, userSnapshot) {
                    final userModel = userSnapshot.data;
                    if (userModel == null) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSenderProfileProgress(userModel),
                        const SizedBox(height: 20),
                      ],
                    );
                  },
                ),
              // Welcome section
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.12),
                      AppColors.primaryDark.withOpacity(0.06),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primary.withOpacity(0.18)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome back!',
                      style: GoogleFonts.inter(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E40AF), // Blue-700
                      ),
                    ),
                    const SizedBox(height: 8),
                    StreamBuilder<UserModel?>(
                      stream: firebaseUser != null
                          ? _userService.streamUser(firebaseUser.uid)
                          : null,
                      builder: (context, snapshot) {
                        final userModel = snapshot.data;
                        return Text(
                          userModel?.displayName ?? firebaseUser?.displayName ?? firebaseUser?.email ?? 'User',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Quick actions
              Text(
                'Quick Actions',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E40AF), // Blue-700
                ),
              ),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.5,
                children: [
                  _buildActionCard(
                    context,
                    'Request Transport',
                    Icons.local_shipping,
                    () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const RideBookingScreen(),
                        ),
                      );
                    },
                  ),
                  _buildActionCard(
                    context,
                    'Nearby Drivers',
                    Icons.person_search,
                    () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const NearbyDriversScreen(),
                        ),
                      );
                    },
                  ),
                  _buildActionCard(
                    context,
                    'Delivery History',
                    Icons.history,
                    () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const RideHistoryScreen(),
                        ),
                      );
                    },
                  ),
                  _buildActionCard(
                    context,
                    'Support',
                    Icons.help_outline,
                    () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SupportScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Recent deliveries
              Text(
                'Recent Deliveries',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E40AF), // Blue-700
                ),
              ),
              const SizedBox(height: 16),
              StreamBuilder<List<RideModel>>(
                stream: firebaseUser != null
                    ? _rideService.streamUserRides(firebaseUser.uid)
                    : null,
                builder: (context, snapshot) {
                  _applyUserRidesCache(snapshot.data);
                  final rides = snapshot.data ?? _cachedUserRides ?? [];
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      rides.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: const Color(0xFF2563EB),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Loading recent deliveries…',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  if (rides.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          'No recent activity',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    );
                  }

                  return Column(
                    children: rides.take(3).map((ride) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => RequestDetailScreen(ride: ride),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: ListTile(
                            leading: Icon(
                              Icons.local_shipping,
                              color: const Color(0xFF2563EB), // Blue-600
                            ),
                            title: Text(
                              ride.pickupLocation,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              ride.dropoffLocation,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _getStatusLabel(ride.status),
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: ride.status == 'completed'
                                        ? Colors.green
                                        : ride.status == 'cancelled'
                                            ? Colors.red
                                            : ride.status == 'parcel_collected'
                                                ? Colors.purple
                                                : ride.status == 'pending'
                                                    ? Colors.amber
                                                    : ride.status == 'open'
                                                        ? Colors.orange
                                                        : Colors.blue,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.chevron_right,
                                  size: 16,
                                  color: Colors.grey.shade400,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  'Developed by Fidinsky Tech Solutions',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade500,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 22, color: AppColors.primary),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


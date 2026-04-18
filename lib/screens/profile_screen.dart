import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/user_service.dart';
import '../services/ride_service.dart';
import '../services/app_resume_service.dart';
import '../models/user_model.dart';
import 'auth_entry_screen.dart';
import 'driver_completion_screen.dart';
import 'main_navigation.dart';
import 'transporter_navigation.dart';
import 'notifications_screen.dart';
import 'payment_methods_screen.dart';
import 'support_screen.dart';
import 'driver_account_edit_screen.dart';
import '../widgets/storage_image.dart';
import '../constants/app_constants.dart';
import '../config/testing_flags.dart';
import '../utils/qa_driver_location.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final UserService _userService = UserService();
  bool _isSwitching = false; // Prevent multiple switch attempts

  Future<void> _handleLogout() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final model = await _userService.getUser(user.uid);
        if ((model?.role ?? '').toLowerCase() == 'passenger') {
          await RideService().cleanupSenderRidesBeforeLogout(user.uid);
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

  Widget _buildProfileIncompleteNotification() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.amber.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              color: Colors.amber.shade800, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Your profile is incomplete. Complete it to start accepting deliveries.',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.amber.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Returns 0.0..1.0 for transporter profile completion (same 5 steps as dashboard).
  static double _driverProfileProgressValue(UserModel? userModel) {
    // In testing mode, treat driver profile as fully complete.
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

  Widget _buildDriverProfileProgress(UserModel? userModel) {
    if (userModel == null) return const SizedBox.shrink();

    final double progress = _driverProfileProgressValue(userModel);
    final int percentage = (progress * 100).round();

    return Container(
      width: double.infinity,
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
              Text(
                'Transporter account setup',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1E40AF),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: progress >= 1.0
                      ? Colors.green.withOpacity(0.1)
                      : Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  progress >= 1.0 ? '100% COMPLETE' : '$percentage% COMPLETE',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: progress >= 1.0
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                progress >= 1.0 ? Colors.green : const Color(0xFF2563EB),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            progress >= 1.0
                ? 'Your transporter profile is fully set up and ready to use.'
                : 'Complete your transporter profile to start accepting more deliveries.',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSwitchToDriver(UserModel user) async {
    // In testing mode, skip profile completeness checks and go straight to completion/switch.
    if (TestingFlags.relaxTransporterVerification) {
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DriverCompletionScreen(currentUser: user),
          ),
        );
      }
      return;
    }

    // Check if driver profile is complete (production rules)
    final hasTruckType = user.truckType != null && user.truckType!.isNotEmpty;
    final hasRatePer10Km = user.ratePer10Km != null && user.ratePer10Km! > 0;
    final hasCarBook = user.carBookImageUrl != null && user.carBookImageUrl!.isNotEmpty;
    final hasTruckSide = user.truckSideImageUrl != null && user.truckSideImageUrl!.isNotEmpty;
    final hasLicense = user.driverLicenseImageUrl != null && user.driverLicenseImageUrl!.isNotEmpty;
    final hasSelfie = user.selfieImageUrl != null && user.selfieImageUrl!.isNotEmpty;

    if (!hasTruckType || !hasRatePer10Km || !hasCarBook || !hasTruckSide || !hasLicense || !hasSelfie) {
      // Navigate to driver completion screen
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DriverCompletionScreen(currentUser: user),
          ),
        );
      }
      return;
    }

    // If profile is complete, switch directly
    await _handleRoleSwitch(user, true);
  }

  Future<void> _handleRoleSwitch(UserModel user, bool switchToDriver) async {
    // Prevent multiple simultaneous switch attempts
    if (_isSwitching) return;
    
    setState(() {
      _isSwitching = true;
    });

    if (switchToDriver) {
      // In testing mode, bypass all document requirements when switching to driver.
      if (TestingFlags.relaxTransporterVerification) {
        try {
          final loc = await QaDriverLocation.resolve();
          final seedWallet =
              (user.driverWalletBalance == null || user.driverWalletBalance! <= 0)
                  ? TestingFlags.qaDefaultDriverWallet
                  : null;
          await _userService.updateDriverProfile(
            uid: user.uid,
            role: 'Driver',
            isAvailable: true,
            verificationStatus: 'auto_verified',
            currentLat: loc?.lat,
            currentLng: loc?.lng,
            driverWalletBalance: seedWallet,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Switched to Driver (${TestingFlags.buildLabel}: verification relaxed).',
                ),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const TransporterNavigation()),
              (route) => false,
            );
          }
        } finally {
          if (mounted) {
            setState(() {
              _isSwitching = false;
            });
          }
        }
        return;
      }

      // Switching to Driver - MUST check if driver profile is complete
      final hasTruckType = user.truckType != null && user.truckType!.isNotEmpty;
      final hasRatePer10Km = user.ratePer10Km != null && user.ratePer10Km! > 0;
      final hasCarBook = user.carBookImageUrl != null && user.carBookImageUrl!.isNotEmpty;
      final hasTruckSide = user.truckSideImageUrl != null && user.truckSideImageUrl!.isNotEmpty;
      final hasLicense = user.driverLicenseImageUrl != null && user.driverLicenseImageUrl!.isNotEmpty;
      final hasSelfie = user.selfieImageUrl != null && user.selfieImageUrl!.isNotEmpty;

      if (!hasTruckType || !hasRatePer10Km || !hasCarBook || !hasTruckSide || !hasLicense || !hasSelfie) {
        // Requirements not met - show message and navigate to completion screen
        if (mounted) {
          setState(() {
            _isSwitching = false;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please complete your driver profile first. Required: Vehicle Type, Rate per 10 km, Car Book, Truck Side View, Driver License, and Selfie.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
          
          // Navigate to driver completion screen
          final result = await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DriverCompletionScreen(currentUser: user),
            ),
          );
          
          // If user completed the profile, the screen will navigate automatically
          // If they cancelled, we just return (switch stays off)
          return;
        }
        return;
      }
    }

    // Switch role only if:
    // - Switching to Sender (no requirements needed)
    // - Switching to Driver AND all requirements are met (checked above)
    try {
      await _userService.updateDriverProfile(
        uid: user.uid,
        role: switchToDriver ? 'Driver' : 'Passenger',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Switched to ${switchToDriver ? 'Driver' : 'Sender'} profile'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );

        // Navigate to appropriate screen based on new role
        if (switchToDriver) {
          // Switched to Driver - go to Driver Dashboard
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const TransporterNavigation()),
            (route) => false,
          );
        } else {
          // Switched to Sender - go to Sender Dashboard
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const MainNavigation()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSwitching = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error switching profile: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    return StreamBuilder<UserModel?>(
      stream: firebaseUser != null
          ? _userService.streamUser(firebaseUser.uid)
          : null,
      builder: (context, snapshot) {
        final _user = snapshot.data;
        
        return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Profile',
          style: GoogleFonts.inter(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E40AF), // Blue-700
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: Color(0xFF1E40AF)), // Blue-700
            onPressed: () {
              // For drivers, navigate to driver account edit screen
              if (AppConstants.isDriverRole(_user?.role)) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DriverAccountEditScreen(user: _user!),
                  ),
                );
              } else {
                // For regular users, show edit dialog or navigate to edit screen
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Profile editing coming soon'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Profile incomplete notification (transporter only)
              if (AppConstants.isDriverRole(_user?.role) &&
                  _driverProfileProgressValue(_user) < 1.0)
                _buildProfileIncompleteNotification(),
              if (AppConstants.isDriverRole(_user?.role) &&
                  _driverProfileProgressValue(_user) < 1.0)
                const SizedBox(height: 16),
              // Profile header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withOpacity(0.1), // Blue-600
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    // Profile picture: for drivers, use truck side view; otherwise fall back to selfie / Google photo / initial
                    (AppConstants.isDriverRole(_user?.role) &&
                            _user?.truckSideImageUrl != null &&
                            _user!.truckSideImageUrl!.isNotEmpty)
                        ? StorageAvatar(
                            pathOrUrl: _user!.truckSideImageUrl,
                            radius: 50,
                            backgroundColor: const Color(0xFF2563EB),
                            child: null,
                          )
                        : (AppConstants.isDriverRole(_user?.role) &&
                                _user?.selfieImageUrl != null &&
                                _user!.selfieImageUrl!.isNotEmpty)
                            ? StorageAvatar(
                                pathOrUrl: _user!.selfieImageUrl,
                                radius: 50,
                                backgroundColor: const Color(0xFF2563EB),
                                child: Text(
                                  (_user.displayName ?? firebaseUser?.displayName ?? 'U')
                                      .substring(0, 1)
                                      .toUpperCase(),
                                  style: GoogleFonts.inter(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              )
                            : CircleAvatar(
                                radius: 50,
                                backgroundColor: const Color(0xFF2563EB), // Blue-600
                                child: firebaseUser?.photoURL != null
                                    ? ClipOval(
                                        child: Image.network(
                                          firebaseUser!.photoURL!,
                                          width: 100,
                                          height: 100,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : Text(
                                        (_user?.displayName ?? firebaseUser?.displayName ?? 'U')
                                            .substring(0, 1)
                                            .toUpperCase(),
                                        style: GoogleFonts.inter(
                                          fontSize: 32,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                              ),
                    const SizedBox(height: 16),
                    Text(
                      _user?.displayName ?? firebaseUser?.displayName ?? 'User',
                      style: GoogleFonts.inter(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E40AF), // Blue-700
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _user?.email ?? firebaseUser?.email ?? '',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB), // Blue-600
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        AppConstants.isDriverRole(_user?.role)
                            ? 'Transporter'
                            : (AppConstants.isPassengerRole(_user?.role)
                                ? 'Sender'
                                : _user?.role ?? 'Sender'),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Transporter account setup progress (shown under profile header for drivers)
              if (AppConstants.isDriverRole(_user?.role))
                _buildDriverProfileProgress(_user),
              if (AppConstants.isDriverRole(_user?.role))
                const SizedBox(height: 24),
              // Profile details
              _buildProfileItem(
                Icons.phone,
                'Phone',
                _user?.phoneNumber ?? firebaseUser?.phoneNumber ?? 'Not set',
                _user,
              ),
              _buildProfileItem(
                Icons.email,
                'Email',
                _user?.email ?? firebaseUser?.email ?? 'Not set',
                _user,
              ),
              _buildProfileItem(
                Icons.calendar_today,
                'Member Since',
                _user != null
                    ? '${_user!.createdAt.day}/${_user!.createdAt.month}/${_user!.createdAt.year}'
                    : 'N/A',
                _user,
              ),
              const SizedBox(height: 24),
              // Settings section
              Text(
                'Settings',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E40AF), // Blue-700
                ),
              ),
              const SizedBox(height: 12),
              _buildSettingsItem(
                Icons.notifications_outlined,
                'Notifications',
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NotificationsScreen(),
                    ),
                  );
                },
              ),
              _buildSettingsItem(
                Icons.payment,
                'Payment Methods',
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PaymentMethodsScreen(),
                    ),
                  );
                },
              ),
              _buildSettingsItem(
                Icons.help_outline,
                'Help & Support',
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SupportScreen(),
                    ),
                  );
                },
              ),
              _buildSettingsItem(
                Icons.info_outline,
                'About',
                () {
                  _showAboutDialog(context);
                },
              ),
              const SizedBox(height: 24),
              // Logout button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  onPressed: _handleLogout,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red, width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Logout',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.red,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Delete account
              SizedBox(
                width: double.infinity,
                height: 48,
                child: TextButton(
                  onPressed: () => _showDeleteAccountDialog(context),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                  child: Text(
                    'Delete Account',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.red,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
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
      },
    );
  }

  Widget _buildProfileItem(IconData icon, String label, String value, UserModel? user) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.shade200,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF2563EB), size: 24), // Blue-600
          const SizedBox(width: 16),
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
                const SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF1E40AF), // Blue-700
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsItem(IconData icon, String title, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.shade200,
          width: 1,
        ),
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF2563EB)), // Blue-600
        title: Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF1E40AF), // Blue-700
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Boltlog',
      applicationVersion: '2.4.0',
      applicationIcon: const Icon(
        Icons.local_shipping,
        size: 48,
        color: Color(0xFF2563EB),
      ),
      applicationLegalese: '© 2024 Boltlog. All rights reserved.',
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            'Boltlog is a goods transportation marketplace app where users can request transport for goods and transporters can accept delivery requests.',
            style: GoogleFonts.inter(),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Delete Account',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete your account? This action cannot be undone.',
          style: GoogleFonts.inter(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: GoogleFonts.inter()),
          ),
          TextButton(
            onPressed: () {
              _deleteAccount(ctx);
            },
            child: Text(
              'Delete',
              style: GoogleFonts.inter(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No user is currently logged in.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final uid = user.uid;

      // Delete Firestore user document
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();

      // Delete Firebase Auth user
      await user.delete();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthEntryScreen()),
          (route) => false,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your account has been deleted.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Failed to delete account. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete account: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}


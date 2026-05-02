import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shown after installation / first launch to request all required permissions.
class PermissionsScreen extends StatefulWidget {
  final Widget child;

  const PermissionsScreen({super.key, required this.child});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  bool _isRequesting = false;
  String? _statusMessage;

  static const _permissionsKey = 'permissions_requested_v1';

  Future<bool> _hasRequestedBefore() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_permissionsKey) ?? false;
  }

  Future<void> _markAsRequested() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_permissionsKey, true);
  }

  List<Permission> _getRequiredPermissions() {
    final perms = <Permission>[
      Permission.locationWhenInUse,
      Permission.camera,
      Permission.notification,
    ];
    if (!kIsWeb && Platform.isAndroid) {
      // Android 13+ uses photos, older uses storage
      perms.add(Permission.photos);
      perms.add(Permission.storage);
    }
    return perms;
  }

  Future<void> _requestAllPermissions() async {
    setState(() {
      _isRequesting = true;
      _statusMessage = 'Requesting permissions...';
    });

    final perms = _getRequiredPermissions();
    final results = <Permission, PermissionStatus>{};

    for (final p in perms) {
      if (!mounted) return;
      final status = await p.status;
      if (status.isDenied || status.isPermanentlyDenied) {
        final newStatus = await p.request();
        results[p] = newStatus;
      } else {
        results[p] = status;
      }
    }

    // Only core permissions are strictly required for app use.
    // Others (photos/storage/notifications) are requested but not blocking.
    final requiredPerms = <Permission>[
      Permission.locationWhenInUse,
      Permission.camera,
    ];

    final allGranted = requiredPerms.every((p) {
      final status = results[p];
      if (status == null) return false;
      return status.isGranted || status.isLimited;
    });

    if (!mounted) return;
    setState(() {
      _isRequesting = false;
      _statusMessage = allGranted
          ? 'All permissions granted. Loading app...'
          : 'You must grant all permissions to use Boltlog. Please enable them in Settings and try again.';
    });

    if (allGranted) {
      await _markAsRequested();

      // Navigate to child after a brief delay
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => widget.child),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(
                Icons.security,
                size: 80,
                color: const Color(0xFF2563EB),
              ),
              const SizedBox(height: 24),
              Text(
                'Permissions Required',
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E40AF),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Boltlog needs these permissions to work properly:',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: Colors.grey.shade700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              _buildPermissionRow(Icons.location_on, 'Location', 'Find nearby drivers and track deliveries'),
              _buildPermissionRow(Icons.camera_alt, 'Camera', 'Take photos of documents and parcels'),
              _buildPermissionRow(
                Icons.photo_library,
                'Photos',
                'Select images from your gallery, Google Photos or Drive',
              ),
              _buildPermissionRow(Icons.notifications, 'Notifications', 'Get ride updates and messages'),
              const SizedBox(height: 24),
              if (_statusMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _statusMessage!,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: const Color(0xFF2563EB),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isRequesting ? null : _requestAllPermissions,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isRequesting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          'Grant All Permissions',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _isRequesting ? null : openAppSettings,
                  child: Text(
                    'Open App Settings',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: const Color(0xFF2563EB),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionRow(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF2563EB), size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1E40AF),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

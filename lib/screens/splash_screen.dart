import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/app_constants.dart';
import '../services/user_service.dart';
import '../services/app_resume_service.dart';
import '../models/user_model.dart';
import 'auth_entry_screen.dart';
import 'main_navigation.dart';
import 'transporter_navigation.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    // Set edge-to-edge mode with transparent system bars for fullscreen effect
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
    );
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
    // Check auth state and navigate - start checking immediately, show splash for at least 2 seconds
    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    // Track start time for minimum display duration
    final startTime = DateTime.now();
    
    // Start checking immediately - don't wait for splash animation
    // Check auth state first (this is instant)
    final User? user = FirebaseAuth.instance.currentUser;
    
    if (user == null) {
      // User not logged in - show splash briefly then go to auth entry
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AuthEntryScreen()),
      );
      return;
    }
    
    // User is logged in - get their role from Firestore
    // Try cache first for faster loading, then server if needed
    final userService = UserService();
    UserModel? userModel;
    
    try {
      // Try cache first for instant loading, then server if cache miss
      // This makes app reopening much faster
      try {
        userModel = await userService.getUser(user.uid, source: Source.cache)
            .timeout(
              const Duration(milliseconds: 500),
              onTimeout: () => null,
            );
      } catch (cacheError) {
        // Cache miss or error, try server
        debugPrint('Cache miss, trying server: $cacheError');
      }
      
      // If cache didn't work, try server
      if (userModel == null) {
        userModel = await userService.getUser(user.uid, source: Source.server)
            .timeout(
              const Duration(seconds: 3),
              onTimeout: () {
                debugPrint('Timeout getting user data from Firestore for user: ${user.uid}');
                return null;
              },
            );
      }
      
      debugPrint('Retrieved user role: ${userModel?.role ?? "null"}');
    } catch (e) {
      debugPrint('Error getting user data: $e');
      // Continue with null userModel - will use fallback navigation
    }
    
    // Ensure minimum splash screen display time (1 second) to prevent flickering
    final elapsed = DateTime.now().difference(startTime);
    final minDisplayTime = const Duration(milliseconds: 1000);
    if (elapsed < minDisplayTime) {
      await Future.delayed(minDisplayTime - elapsed);
    }
    
    if (!mounted) return;

    AppResumeSnapshot? resume;
    if (user != null) {
      resume = await AppResumeService.instance.readSnapshotForUser(
        user.uid,
        userModel,
      );
    }
    final int initialTab = resume?.mainTabIndex ?? 0;
    final AppResumeSnapshot? deepResume =
        (resume != null && resume.hasDeepScreen) ? resume : null;

    // Navigate based on role
    // Driver accounts go to TransporterNavigation (Driver Dashboard)
    // Passenger/Sender accounts go to MainNavigation (Sender Dashboard)
    final userRole = userModel?.role?.trim() ?? '';
    debugPrint('User role after trim: "$userRole"');
    debugPrint(
      'Role comparison - isDriver (transporter shell): ${AppConstants.isDriverRole(userModel?.role)}',
    );

    if (AppConstants.isDriverRole(userModel?.role)) {
      debugPrint('Navigating to TransporterNavigation (Driver Dashboard)');
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => TransporterNavigation(
              initialTabIndex: initialTab,
              resumeSnapshot: deepResume,
            ),
          ),
          (route) => false,
        );
      }
    } else {
      debugPrint(
          'Navigating to MainNavigation (Sender Dashboard) - Role: "$userRole"');
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => MainNavigation(
              initialTabIndex: initialTab,
              resumeSnapshot: deepResume,
            ),
          ),
          (route) => false,
        );
      }
    }
  }

  @override
  void dispose() {
    // Restore system UI when screen is disposed
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final padding = mediaQuery.padding;
    
    return Scaffold(
      backgroundColor: Colors.white,
      extendBodyBehindAppBar: true,
      body: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.white,
          child: SafeArea(
            top: false,
            bottom: false,
            child: Column(
              children: [
                // Add top padding for status bar/notch
                SizedBox(height: padding.top),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Top spacer
                      const Spacer(),
                      // Central branding area
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 800),
                        curve: Curves.easeOut,
                        builder: (context, value, child) {
                          return Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(0, 20 * (1 - value)),
                              child: child,
                            ),
                          );
                        },
                        child: Column(
                          children: [
                            // Central picture
                            Image.asset(
                              'assets/images/splash_logo.png',
                              width: 140,
                              height: 140,
                              fit: BoxFit.contain,
                            ),
                            const SizedBox(height: 24),
                            // Brand name
                            Text(
                              'Boltlog',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 40,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1E40AF), // Blue-700
                                letterSpacing: -0.5,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Tagline
                            Text(
                              'Offer Your Price',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF2563EB), // Blue-600
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Bottom area
                      const Spacer(),
                      Padding(
                        padding: EdgeInsets.only(bottom: padding.bottom > 0 ? padding.bottom + 16 : 48),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Loading indicator
                            SizedBox(
                              width: 200,
                              child: Column(
                                children: [
                                  Container(
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFCFE7D7),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: TweenAnimationBuilder<double>(
                                      tween: Tween(begin: 0.0, end: 0.33),
                                      duration: const Duration(milliseconds: 1500),
                                      curve: Curves.easeInOut,
                                      builder: (context, value, child) {
                                        return Align(
                                          alignment: Alignment.centerLeft,
                                          child: Container(
                                            width: 200 * value,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF2563EB), // Blue-600
                                              borderRadius: BorderRadius.circular(3),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Loading resources...',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: const Color(0xFF2563EB), // Blue-600
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Version
                            Text(
                              'v 2.4.0 (Build 302)',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: const Color(0xFF8BA896),
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Credit
                            Text(
                              'Developed by Fidinsky Tech Solutions',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF8BA896),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


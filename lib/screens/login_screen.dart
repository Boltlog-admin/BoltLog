import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../constants/app_constants.dart';
import '../config/testing_flags.dart';
import '../services/app_resume_service.dart';
import '../services/user_service.dart';
import '../models/user_model.dart';
import 'main_navigation.dart';
import 'transporter_navigation.dart';
import 'forgot_password_screen.dart';
import 'signup_screen.dart';
import 'driver_completion_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController phoneEmailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: _kGoogleWebClientId.isEmpty ? null : _kGoogleWebClientId,
    scopes: ['email', 'profile'],
  );
  final UserService _userService = UserService();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isLoggingIn = false; // Prevent multiple simultaneous login attempts
  bool _isGoogleLoading = false;
  String _selectedRole = 'Passenger';
  bool _isPhoneNumber = false;

  /// Optional: set from Firebase Console → Project Settings → Your apps → Web app
  /// (OAuth 2.0 Web client ID from Google Cloud Console). Improves Google Sign-In on Android.
  static const String _kGoogleWebClientId = '';

  @override
  void dispose() {
    phoneEmailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    // Prevent multiple simultaneous login attempts
    if (_isLoggingIn || _isLoading) {
      debugPrint('Login already in progress, ignoring duplicate request');
      return;
    }

    if (phoneEmailController.text.isEmpty || passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all fields'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _isLoggingIn = true;
    });

    try {
      // Check if Firebase is initialized
      if (Firebase.apps.isEmpty) {
        throw Exception('Firebase is not initialized. Please restart the app.');
      }

      String email = phoneEmailController.text.trim();

      // Only allow email login now
      if (!email.contains('@')) {
        throw Exception('Please log in using your email address (phone login has been disabled).');
      }

      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: passwordController.text,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw FirebaseAuthException(
            code: 'timeout',
            message: 'Login request timed out. Please check your internet connection and try again.',
          );
        },
      );

      if (mounted) {
        // Check user role first
        final userService = UserService();
        UserModel? userModel;
        try {
          userModel = await userService.getUser(userCredential.user!.uid)
              .timeout(
                const Duration(seconds: 10),
                onTimeout: () {
                  debugPrint('Timeout getting user data from Firestore');
                  return null;
                },
              );
        } catch (e) {
          debugPrint('Error getting user: $e');
          // Continue with null userModel - will default to sender navigation
        }
        
        // Show success message
        final userRole = userModel?.role?.trim() ?? '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppConstants.isDriverRole(userRole) 
                ? 'Successfully signed in as Transporter!'
                : 'Successfully signed in!'
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        
        // Wait a moment for user to see the message, then navigate
        await Future.delayed(const Duration(milliseconds: 1500));
        
        if (mounted) {
          final userRole = userModel?.role?.trim() ?? '';
          if (AppConstants.isDriverRole(userRole)) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const TransporterNavigation()),
              (route) => false,
            );
          } else {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const MainNavigation()),
              (route) => false,
            );
          }
        }
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        String errorMessage;
        switch (e.code) {
          case 'user-not-found':
            errorMessage = 'No account found. Please sign up first.';
            break;
          case 'wrong-password':
            errorMessage = 'Incorrect password. Please try again.';
            break;
          case 'invalid-credential':
          case 'invalid-login-credentials':
            errorMessage = 'Invalid email or password. Please check your credentials and try again.';
            break;
          case 'invalid-email':
            errorMessage = 'Invalid email address. Please check and try again.';
            break;
          case 'user-disabled':
            errorMessage = 'This account has been disabled. Please contact support.';
            break;
          case 'too-many-requests':
            errorMessage = 'Too many failed attempts. Please try again later.';
            break;
          case 'operation-not-allowed':
            errorMessage = 'Email/Password authentication is not enabled. Please contact support.';
            break;
          case 'network-request-failed':
            errorMessage = 'Network error. Please check your internet connection.';
            break;
          case 'internal-error':
            errorMessage = 'Internal error. Please try again or contact support.';
            break;
          case 'timeout':
            errorMessage = 'Connection timeout. Please check your internet and try again.';
            break;
          case 'too-many-requests':
            errorMessage = 'Too many login attempts. Please wait a few minutes and try again.';
            break;
          default:
            if (e.message != null && e.message!.isNotEmpty) {
              errorMessage = e.message!;
            } else {
              errorMessage = 'Login failed (${e.code}). Please check your credentials and try again.';
            }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Login error: $e');
      if (mounted) {
        String errorMessage;
        if (e is FirebaseAuthException) {
          // This should have been caught above, but handle it anyway
          errorMessage = e.message ?? 'Login failed. Please try again.';
        } else if (e.toString().contains('timeout') || e.toString().contains('Timeout')) {
          errorMessage = 'Connection timeout. Please check your internet connection and try again.';
        } else if (e.toString().contains('network') || e.toString().contains('Network')) {
          errorMessage = 'Network error. Please check your internet connection.';
        } else {
          errorMessage = e.toString().replaceAll('Exception: ', '').replaceAll('Error: ', '');
          if (errorMessage.isEmpty || errorMessage.length > 100) {
            errorMessage = 'Login failed. Please try again.';
          }
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoggingIn = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Color(0xFF1E40AF), // Blue-700
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Log In',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1E40AF),
                    ),
                  ),
                ],
              ),
            ),
            // Main content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    // Branding
                    Column(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB).withOpacity(0.2), // Blue-600
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: Image.asset(
                              'assets/images/boltlogicon.png',
                              width: 48,
                              height: 48,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Log in to your account',
                          style: GoogleFonts.inter(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1E40AF), // Blue-700
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Use the same email whether you signed up as a Sender or Transporter. We will take you to the right dashboard automatically.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    // Login form
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Email field
                        Text(
                          'Email',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF1E40AF), // Blue-700
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.grey.shade200,
                              width: 1,
                            ),
                          ),
                          child: TextField(
                            controller: phoneEmailController,
                            keyboardType: TextInputType.emailAddress,
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              color: const Color(0xFF1E40AF), // Blue-700
                            ),
                            decoration: InputDecoration(
                              hintText: 'example@email.com',
                              hintStyle: GoogleFonts.inter(
                                color: Colors.grey.shade400,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                              suffixIcon: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Icon(
                                  Icons.email,
                                  size: 20,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Password field
                        Text(
                          'Password',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF1E40AF), // Blue-700
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.grey.shade200,
                              width: 1,
                            ),
                          ),
                          child: TextField(
                            controller: passwordController,
                            obscureText: _obscurePassword,
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              color: const Color(0xFF1E40AF), // Blue-700
                            ),
                            decoration: InputDecoration(
                              hintText: '•••••••••',
                              hintStyle: GoogleFonts.inter(
                                color: Colors.grey.shade400,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                  color: const Color(0xFF2563EB), // Blue-600
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const ForgotPasswordScreen(),
                                ),
                              );
                            },
                            child: Text(
                              'Forgot Password?',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF2563EB), // Blue-600
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Login button
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB), // Blue-600
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Log In',
                                        style: GoogleFonts.inter(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.arrow_forward, size: 20),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    // Social login divider
                    Row(
                      children: [
                        Expanded(
                          child: Divider(
                            color: Colors.grey.shade300,
                            thickness: 1,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'Or continue with',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                            color: Colors.grey.shade300,
                            thickness: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Social login button (Google/Gmail)
                    _buildGoogleSignInButton(context),
                    const SizedBox(height: 32),
                    // Signup link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Don't have an account? ",
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => SignupScreen(selectedRole: _selectedRole),
                              ),
                            );
                          },
                          child: Text(
                            'Sign Up',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF13EC5B),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildGoogleSignInButton(BuildContext context) {
    final loading = _isGoogleLoading || _isLoading;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton.icon(
        onPressed: loading ? null : () => _signInWithGoogle(context),
        icon: loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Image.asset(
                'assets/images/google_logo.png',
                height: 24,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.g_mobiledata, size: 24),
              ),
        label: Text(
          loading ? 'Signing in…' : 'Continue with Google',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: loading ? Colors.grey : const Color(0xFF1E40AF),
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.grey.shade200),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Future<void> _signInWithGoogle(BuildContext context) async {
    if (_isGoogleLoading || _isLoading) return;
    setState(() => _isGoogleLoading = true);

    try {
      // Sign out first so the user can pick which Gmail account to use
      await _googleSignIn.signOut();

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        if (mounted) setState(() => _isGoogleLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      if (googleAuth.idToken == null) {
        if (mounted) {
          setState(() => _isGoogleLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Could not get Google account info. Ensure Google sign-in is enabled in Firebase Console.',
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential =
          await _auth.signInWithCredential(credential);
      final User? user = userCredential.user;

      if (user != null) {
        // Check if this Google account already has a user profile
        UserModel? existingUser = await _userService.getUser(user.uid);
        String role;

        if (existingUser != null) {
          // Use the existing role - do NOT change it from the login screen
          role = existingUser.role.trim().isEmpty
              ? 'Passenger'
              : existingUser.role;
        } else {
          // New user via Google: ask whether they are Sender or Transporter
          final chosenRole = await _showRoleSelectionDialog(context);
          if (chosenRole == null) {
            // User cancelled the role dialog; stop sign-in
            if (mounted) setState(() => _isGoogleLoading = false);
            await AppResumeService.instance.clear();
            await _auth.signOut();
            await _googleSignIn.signOut();
            return;
          }
          role = chosenRole;

          final newUser = UserModel.fromFirebaseUser(
            uid: user.uid,
            email: user.email,
            displayName: user.displayName,
            phoneNumber: user.phoneNumber,
            role: role,
            photoUrl: user.photoURL,
          );
          await _userService.createOrUpdateUser(newUser);
          existingUser = newUser;

          final isNewUser =
              userCredential.additionalUserInfo?.isNewUser ?? true;
          if (isNewUser && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Account created with Google'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }

        if (!mounted) {
          setState(() => _isGoogleLoading = false);
          return;
        }

        setState(() => _isGoogleLoading = false);

        final isDriver = AppConstants.isDriverRole(role);
        if (isDriver) {
          // For drivers, ensure profile completion
          final savedUser = existingUser ?? await _userService.getUser(user.uid);
          final docsComplete = savedUser != null &&
              savedUser.carBookImageUrl != null &&
              savedUser.carBookImageUrl!.isNotEmpty &&
              savedUser.truckSideImageUrl != null &&
              savedUser.truckSideImageUrl!.isNotEmpty &&
              savedUser.driverLicenseImageUrl != null &&
              savedUser.driverLicenseImageUrl!.isNotEmpty &&
              savedUser.selfieImageUrl != null &&
              savedUser.selfieImageUrl!.isNotEmpty;
          final hasCompleteProfile = savedUser != null &&
              savedUser.truckType != null &&
              savedUser.truckType!.isNotEmpty &&
              savedUser.ratePer10Km != null &&
              savedUser.ratePer10Km! > 0 &&
              (docsComplete || TestingFlags.relaxTransporterVerification);

          if (hasCompleteProfile) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                  builder: (_) => const TransporterNavigation()),
              (route) => false,
            );
          } else {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) =>
                    DriverCompletionScreen(currentUser: existingUser!),
              ),
              (route) => false,
            );
          }
        } else {
          // Sender: go to main navigation
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const MainNavigation()),
            (route) => false,
          );
        }
      } else {
        if (mounted) setState(() => _isGoogleLoading = false);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _isGoogleLoading = false);
        String msg = 'Google sign-in failed. Try again.';
        if (e.code == 'account-exists-with-different-credential') {
          msg =
              'This email is already used with another sign-in method. Use that method or sign in with email.';
        } else if (e.code == 'invalid-credential' ||
            e.code == 'operation-not-allowed') {
          msg =
              'Google sign-in is not set up. Enable it in Firebase Console → Authentication → Sign-in method.';
        } else if (e.message != null && e.message!.isNotEmpty) {
          msg = e.message!;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, st) {
      debugPrint('Google sign-in error: $e $st');
      if (mounted) {
        setState(() => _isGoogleLoading = false);
        String msg = 'Could not sign in with Google. Try again.';
        final s = e.toString().toLowerCase();
        if (s.contains('sign_in_failed') ||
            s.contains('network') ||
            s.contains('socket')) {
          msg = 'Network error. Check your connection and try again.';
        } else if (s.contains('cancel')) {
          return;
        } else if (s.contains('api_not_enabled') ||
            s.contains('developer_error')) {
          msg =
              'Google sign-in not configured. Add SHA-1 in Firebase and enable Google sign-in.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Show a simple dialog to choose whether this new Google account is Sender or Transporter.
  Future<String?> _showRoleSelectionDialog(BuildContext context) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            'Choose account type',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Is this account for a Sender or a Transporter? This choice is fixed for this account.',
            style: GoogleFonts.inter(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('Passenger'),
              child: Text(
                'Sender',
                style: GoogleFonts.inter(color: const Color(0xFF2563EB)),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop('Driver'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
              ),
              child: Text(
                'Transporter',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }

}

// Extension to capitalize first letter
extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
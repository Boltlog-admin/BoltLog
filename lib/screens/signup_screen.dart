import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/qa_driver_location.dart';
import '../services/user_service.dart';
import '../services/image_service.dart';
import '../services/storage_service.dart';
import '../models/user_model.dart';
import '../constants/app_constants.dart';
import '../config/testing_flags.dart';
import 'main_navigation.dart';
import 'transporter_navigation.dart';

class SignupScreen extends StatefulWidget {
  final String selectedRole;
  
  const SignupScreen({super.key, this.selectedRole = 'Passenger'});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UserService _userService = UserService();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  String _selectedRole = 'Passenger';
  String? _selectedTruckType; // For drivers: 'bike', 'sedan', 'pickup', 'closed_pickup', 'lorry'
  final TextEditingController _ratePer10KmController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  File? _carBookImage;
  File? _truckSideImage;
  File? _driverLicenseImage;
  File? _selfieImage;
  // Store image bytes for reliable upload (avoid file read issues)
  Uint8List? _carBookImageBytes;
  Uint8List? _truckSideImageBytes;
  Uint8List? _driverLicenseImageBytes;
  Uint8List? _selfieImageBytes;
  bool _isUploadingImages = false;

  /// Seeds [UserModel.currentLat] / [currentLng] so nearby matching can rank transporters.
  double? _driverDefaultLat;
  double? _driverDefaultLng;
  bool _driverLocationLoading = false;
  String? _driverLocationError;
  bool _driverUsingQaFallback = false;

  @override
  void initState() {
    super.initState();
    _selectedRole = widget.selectedRole;
    if (_selectedRole == 'Driver') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _resolveDriverDefaultLocation();
      });
    }
  }

  void _scheduleResolveDriverDefaultLocation() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolveDriverDefaultLocation();
    });
  }

  Future<void> _resolveDriverDefaultLocation() async {
    if (_selectedRole != 'Driver' || !mounted) return;
    setState(() {
      _driverLocationLoading = true;
      _driverLocationError = null;
    });
    final pair = await QaDriverLocation.resolve();
    if (!mounted) return;
    if (pair != null) {
      final isFb = TestingFlags.useQaFallbackDriverBaseLocation &&
          (pair.lat - TestingFlags.qaFallbackDriverBaseLat).abs() < 0.0001 &&
          (pair.lng - TestingFlags.qaFallbackDriverBaseLng).abs() < 0.0001;
      setState(() {
        _driverDefaultLat = pair.lat;
        _driverDefaultLng = pair.lng;
        _driverLocationLoading = false;
        _driverLocationError = null;
        _driverUsingQaFallback = isFb;
      });
    } else {
      setState(() {
        _driverLocationLoading = false;
        _driverUsingQaFallback = false;
        _driverLocationError =
            'Could not resolve location. Enable GPS and permission, then tap “Use current location”.';
      });
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    _ratePer10KmController.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    // Validation
    if (nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your full name'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (emailController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your email address'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Email validation
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(emailController.text.trim())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email address'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your phone number'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a password'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (passwordController.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password must be at least 6 characters'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (passwordController.text != confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passwords do not match'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validate truck type for drivers
    if (_selectedRole == 'Driver' && _selectedTruckType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select your vehicle type'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validate rate per 10 km and default service location for drivers
    double? ratePer10Km;
    if (_selectedRole == 'Driver') {
      if (_driverDefaultLat == null || _driverDefaultLng == null) {
        await _resolveDriverDefaultLocation();
      }
      if (_driverDefaultLat == null || _driverDefaultLng == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _driverLocationError ??
                    'Allow location access and tap “Use current location” to set your default service area.',
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      ratePer10Km = double.tryParse(_ratePer10KmController.text.trim());
      if (ratePer10Km == null || ratePer10Km <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter your rate per 10 km (e.g. 15 for \$15 per 10 km)'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    // Validate images for drivers (skip when relax flag is enabled)
    if (_selectedRole == 'Driver' && !TestingFlags.relaxTransporterVerification) {
      if (_carBookImage == null || _carBookImageBytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please take a picture of your car book'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      if (_driverLicenseImage == null || _driverLicenseImageBytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please take a picture of your driver license'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      if (_selfieImage == null || _selfieImageBytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please take a selfie'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Create user with email and password
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
      );

      // Update display name in background (non-blocking for faster signup)
      userCredential.user?.updateDisplayName(nameController.text.trim()).catchError(
        (e) => debugPrint('Failed to update display name: $e'),
      );

      // Normalize phone number - ensure it has +263 prefix
      String phoneNumber = phoneController.text.trim();
      // Remove +263 prefix if already present
      phoneNumber = phoneNumber.replaceAll(RegExp(r'^\+263\s*'), '').trim();
      // Remove spaces
      phoneNumber = phoneNumber.replaceAll(RegExp(r'\s+'), '');
      // Add +263 prefix
      phoneNumber = '+263$phoneNumber';
      
      // Upload images for drivers
      String? carBookImageUrl;
      String? truckSideImageUrl;
      String? driverLicenseImageUrl;
      String? selfieImageUrl;
      
      if (_selectedRole == 'Driver' && !TestingFlags.relaxTransporterVerification) {
        setState(() {
          _isUploadingImages = true;
        });
        
        try {
          final userId = userCredential.user!.uid;
          if (userId.isEmpty) {
            throw Exception('User ID is invalid. Please try signing up again.');
          }
          
          // Refresh auth token and wait for Storage to recognize the user
          try {
            await userCredential.user?.getIdToken(true);
            await Future.delayed(const Duration(seconds: 8));
          } catch (_) {}
          
          if (_carBookImage == null || _carBookImageBytes == null ||
              _truckSideImage == null || _truckSideImageBytes == null ||
              _driverLicenseImage == null || _driverLicenseImageBytes == null ||
              _selfieImage == null || _selfieImageBytes == null) {
            throw Exception('Image files not found. Please take the pictures again.');
          }
          
          final pathKey = AppConstants.storagePathKey(userCredential.user!.email, userId);
          final metadata = SettableMetadata(
            contentType: 'image/jpeg',
            customMetadata: {'uploadedBy': userId},
          );
          
          // Compress images
          final compressed = await Future.wait([
            ImageService.compressImage(_carBookImageBytes!),
            ImageService.compressImage(_truckSideImageBytes!),
            ImageService.compressImage(_driverLicenseImageBytes!),
            ImageService.compressImage(_selfieImageBytes!),
          ]);
          final carBookBytes = compressed[0].isEmpty ? _carBookImageBytes! : compressed[0];
          final truckSideBytes = compressed[1].isEmpty ? _truckSideImageBytes! : compressed[1];
          final licenseBytes = compressed[2].isEmpty ? _driverLicenseImageBytes! : compressed[2];
          final selfieBytes = compressed[3].isEmpty ? _selfieImageBytes! : compressed[3];
          
          // Upload path-only (skips getDownloadURL - fetch URL when displaying)
          final carBookPath = AppConstants.storageDriverPath(pathKey, 'car_book.jpg');
          final truckSidePath = AppConstants.storageDriverPath(pathKey, 'truck_side.jpg');
          final licensePath = AppConstants.storageDriverPath(pathKey, 'driver_license.jpg');
          final selfiePath = AppConstants.storageDriverPath(pathKey, 'selfie.jpg');
          await StorageService.putDataReturnPath(path: carBookPath, data: carBookBytes, metadata: metadata, user: userCredential.user);
          carBookImageUrl = carBookPath;
          await StorageService.putDataReturnPath(path: truckSidePath, data: truckSideBytes, metadata: metadata, user: userCredential.user);
          truckSideImageUrl = truckSidePath;
          await StorageService.putDataReturnPath(path: licensePath, data: licenseBytes, metadata: metadata, user: userCredential.user);
          driverLicenseImageUrl = licensePath;
          await StorageService.putDataReturnPath(path: selfiePath, data: selfieBytes, metadata: metadata, user: userCredential.user);
          selfieImageUrl = selfiePath;
          debugPrint('All images uploaded successfully');
        } catch (e) {
          debugPrint('Error uploading images: $e');
          if (mounted) {
            setState(() {
              _isUploadingImages = false;
            });
            
            // Show specific error - include full details for debugging
            String errorMessage = 'Error uploading images. ';
            final errStr = e.toString().toLowerCase();
            if (errStr.contains('401') || errStr.contains('unauthenticated')) {
              errorMessage += 'Auth expired. Try again.';
            } else if (errStr.contains('412') || errStr.contains('service account') || errStr.contains('missing necessary permissions') || errStr.contains('not-found')) {
              errorMessage += 'Storage 412: Link billing to project Boltlog, then run: npx firebase-tools deploy --only functions';
            } else if (errStr.contains('403') || errStr.contains('unauthorized') || errStr.contains('permission')) {
              errorMessage += 'Permission denied. Deploy: npx firebase-tools deploy --only storage';
            } else if (errStr.contains('network') || errStr.contains('connection') || errStr.contains('socket')) {
              errorMessage += 'Network error. Check connection.';
            } else {
              errorMessage += 'Please try again.';
            }
            errorMessage += '\n\nFull error: ${e.toString()}';
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: SingleChildScrollView(
                  child: Text(errorMessage),
                ),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 8),
                behavior: SnackBarBehavior.floating,
                action: SnackBarAction(
                  label: 'Settings',
                  textColor: Colors.white,
                  onPressed: () => openAppSettings(),
                ),
              ),
            );
            
            // Delete the created user account since image upload failed
            try {
              await userCredential.user?.delete();
              debugPrint('Deleted user account due to image upload failure');
            } catch (deleteError) {
              debugPrint('Error deleting user account: $deleteError');
            }
          }
          return;
        }
        
        setState(() {
          _isUploadingImages = false;
        });
      }
      
      // Create user in Firestore
      final userModel = UserModel.fromFirebaseUser(
        uid: userCredential.user!.uid,
        email: emailController.text.trim(),
        displayName: nameController.text.trim(),
        phoneNumber: phoneNumber,
        role: _selectedRole,
        truckType:  _selectedRole == 'Driver' ? _selectedTruckType : null,
        ratePer10Km: _selectedRole == 'Driver' ? ratePer10Km : null,
        currentLat: _selectedRole == 'Driver' ? _driverDefaultLat : null,
        currentLng: _selectedRole == 'Driver' ? _driverDefaultLng : null,
        carBookImageUrl: carBookImageUrl,
        truckSideImageUrl: truckSideImageUrl,
        driverLicenseImageUrl: driverLicenseImageUrl,
        selfieImageUrl: selfieImageUrl,
      );
      await _userService.createOrUpdateUser(userModel);

      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
        if (_selectedRole == 'Driver') {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => const TransporterNavigation(showWelcomeMessage: false),
            ),
            (route) => false,
          );
        } else {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => const MainNavigation(showWelcomeMessage: false),
            ),
            (route) => false,
          );
        }
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Signup failed. Please try again.';
      
      switch (e.code) {
        case 'weak-password':
          errorMessage = 'The password provided is too weak.';
          break;
        case 'email-already-in-use':
          errorMessage = 'An account already exists with this email address.';
          break;
        case 'invalid-email':
          errorMessage = 'The email address is invalid.';
          break;
        case 'operation-not-allowed':
          errorMessage = 'Email/password accounts are not enabled.';
          break;
        case 'network-request-failed':
          errorMessage = 'Network error. Please check your internet connection.';
          break;
        default:
          errorMessage = 'Signup failed: ${e.message ?? e.code}';
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('An error occurred: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: const Color(0xFF1E40AF), // Blue-700
                    ),
                  ),
                  // Role toggle
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedRole = 'Passenger';
                              _selectedTruckType = null;
                              _driverDefaultLat = null;
                              _driverDefaultLng = null;
                              _driverLocationError = null;
                              _driverUsingQaFallback = false;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _selectedRole == 'Passenger'
                                  ? const Color(0xFF2563EB) // Blue-600
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Sender',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _selectedRole == 'Passenger'
                                    ? Colors.white
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            final wasPassenger = _selectedRole == 'Passenger';
                            setState(() {
                              _selectedRole = 'Driver';
                              if (wasPassenger) {
                                _selectedTruckType = null;
                              }
                            });
                            _scheduleResolveDriverDefaultLocation();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _selectedRole == 'Driver'
                                  ? const Color(0xFF2563EB) // Blue-600
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Transporter',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: _selectedRole == 'Driver'
                                    ? Colors.white
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ),
                      ],
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
                          'Create Account',
                          style: GoogleFonts.inter(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1E40AF), // Blue-700
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sign up to get started',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    // Signup form
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name field
                        Text(
                          'Full Name',
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
                            controller: nameController,
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              color: const Color(0xFF1E40AF), // Blue-700
                            ),
                            decoration: InputDecoration(
                              hintText: 'Enter your full name',
                              hintStyle: GoogleFonts.inter(
                                color: Colors.grey.shade400,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
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
                            controller: emailController,
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
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Phone field
                        Text(
                          'Phone Number',
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
                            controller: phoneController,
                            keyboardType: TextInputType.phone,
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              color: const Color(0xFF1E40AF), // Blue-700
                            ),
                            decoration: InputDecoration(
                              hintText: 'Enter phone number',
                              hintStyle: GoogleFonts.inter(
                                color: Colors.grey.shade400,
                              ),
                              prefixText: '+263 ',
                              prefixStyle: GoogleFonts.inter(
                                fontSize: 16,
                                color: const Color(0xFF1E40AF), // Blue-700
                                fontWeight: FontWeight.w500,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
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
                        const SizedBox(height: 20),
                        // Confirm Password field
                        Text(
                          'Confirm Password',
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
                            controller: confirmPasswordController,
                            obscureText: _obscureConfirmPassword,
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
                                  _obscureConfirmPassword
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                  color: const Color(0xFF2563EB), // Blue-600
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscureConfirmPassword = !_obscureConfirmPassword;
                                  });
                                },
                              ),
                            ),
                          ),
                        ),
                        // Car Type Selection (only for drivers)
                        if (_selectedRole == 'Driver') ...[
                          const SizedBox(height: 20),
                          Text(
                            'Vehicle Type *',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF1E40AF), // Blue-700
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildTruckTypeOption('bike_express', 'Bike Express', Icons.two_wheeler),
                                _buildTruckTypeOption('runner', 'Runner', Icons.airport_shuttle),
                                _buildTruckTypeOption('pickup', 'Pickup', Icons.local_shipping, mass: '1.2t'),
                                _buildTruckTypeOption('truck_5t', 'Truck', Icons.fire_truck, mass: '5t'),
                                _buildTruckTypeOption('truck_10t', 'Truck', Icons.fire_truck, mass: '10t'),
                                _buildTruckTypeOption('truck_20t', 'Truck', Icons.fire_truck, mass: '20t'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Default service location *',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF1E40AF),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'We save your current position as a base so senders can see transporters near their pickup. Live location still updates when you use the app.',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blue.shade100),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_driverLocationLoading)
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.blue.shade700,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Getting your location…',
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            color: Colors.blue.shade900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                else if (_driverDefaultLat != null &&
                                    _driverDefaultLng != null)
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.check_circle,
                                          color: Colors.green.shade700, size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Base set: ${_driverDefaultLat!.toStringAsFixed(4)}, ${_driverDefaultLng!.toStringAsFixed(4)}',
                                              style: GoogleFonts.inter(
                                                fontSize: 13,
                                                color: const Color(0xFF1E40AF),
                                              ),
                                            ),
                                            if (_driverUsingQaFallback) ...[
                                              const SizedBox(height: 6),
                                              Text(
                                                'Using test default coordinates (${TestingFlags.buildLabel}).',
                                                style: GoogleFonts.inter(
                                                  fontSize: 11,
                                                  color: Colors.orange.shade900,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  )
                                else
                                  Text(
                                    _driverLocationError ??
                                        'Location not set yet.',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: Colors.orange.shade900,
                                    ),
                                  ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: _driverLocationLoading
                                        ? null
                                        : () {
                                            _resolveDriverDefaultLocation();
                                          },
                                    icon: const Icon(Icons.my_location, size: 18),
                                    label: Text(
                                      'Use current location',
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF2563EB),
                                      side: const BorderSide(
                                          color: Color(0xFF2563EB)),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          // Rate per 10 km
                          Text(
                            'Your rate per 10 km (\$) *',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF1E40AF), // Blue-700
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _ratePer10KmController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              hintText: 'e.g. 15',
                              hintStyle: GoogleFonts.inter(color: Colors.grey.shade500),
                              prefixText: '\$ ',
                              prefixStyle: GoogleFonts.inter(fontSize: 16, color: const Color(0xFF1E40AF)),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            ),
                            style: GoogleFonts.inter(fontSize: 16, color: const Color(0xFF1E40AF)),
                          ),
                          const SizedBox(height: 20),
                          // Car Book Image
                          Text(
                            'Car Book Picture *',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF1E40AF), // Blue-700
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildImagePicker(
                            'Car Book',
                            _carBookImage,
                            (image, bytes) => setState(() {
                              _carBookImage = image;
                              _carBookImageBytes = bytes;
                            }),
                            Icons.description,
                          ),
                          const SizedBox(height: 20),
                          // Truck Side View Image
                          Text(
                            'Truck Side View Picture *',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF1E40AF), // Blue-700
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildImagePicker(
                            'Truck Side View',
                            _truckSideImage,
                            (image, bytes) => setState(() {
                              _truckSideImage = image;
                              _truckSideImageBytes = bytes;
                            }),
                            Icons.local_shipping,
                          ),
                          const SizedBox(height: 20),
                          // Driver License Image
                          Text(
                            'Driver License Picture *',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF1E40AF), // Blue-700
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildImagePicker(
                            'Driver License',
                            _driverLicenseImage,
                            (image, bytes) => setState(() {
                              _driverLicenseImage = image;
                              _driverLicenseImageBytes = bytes;
                            }),
                            Icons.credit_card,
                          ),
                          const SizedBox(height: 20),
                          // Selfie Image
                          Text(
                            'Selfie Picture *',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF1E40AF), // Blue-700
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildImagePicker(
                            'Selfie',
                            _selfieImage,
                            (image, bytes) => setState(() {
                              _selfieImage = image;
                              _selfieImageBytes = bytes;
                            }),
                            Icons.face,
                          ),
                        ],
                        const SizedBox(height: 32),
                        // Signup button
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: (_isLoading || _isUploadingImages) ? null : _handleSignup,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB), // Blue-600
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: (_isLoading || _isUploadingImages)
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
                                : Text(
                                    _isUploadingImages ? 'Uploading Images...' : 'Sign Up',
                                    style: GoogleFonts.inter(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Login link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Already have an account? ',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          child: Text(
                            'Log In',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF2563EB), // Blue-600
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

  Widget _buildTruckTypeOption(String value, String label, IconData icon, {String? mass}) {
    final isSelected = _selectedTruckType == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTruckType = isSelected ? null : value;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2563EB) : Colors.white, // Blue-600
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFF2563EB) : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected ? Colors.white : const Color(0xFF1E40AF),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : const Color(0xFF1E40AF), // Blue-700
                  ),
                ),
              ],
            ),
            if (mass != null) ...[
              const SizedBox(height: 2),
              Text(
                mass,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? Colors.white70 : Colors.grey.shade600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImagePicker(String label, File? image, void Function(File?, Uint8List?) onImageSelected, IconData icon) {
    return GestureDetector(
      onTap: () => _showImageSourceDialog(label, onImageSelected),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: image != null ? const Color(0xFF2563EB) : Colors.grey.shade300,
            width: image != null ? 2 : 1,
          ),
        ),
        child: image != null
            ? Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.file(
                      image,
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => onImageSelected(null, null),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                        padding: const EdgeInsets.all(4),
                        minimumSize: const Size(24, 24),
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 32,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap to take $label picture',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _showImageSourceDialog(String label, void Function(File?, Uint8List?) onImageSelected) async {
    // Capture the parent context so SnackBars are shown on the main Scaffold,
    // not the (soon-to-be-dismissed) bottom sheet context.
    final parentContext = context;
    final imageLabel = label; // Capture label for use in callbacks

    showModalBottomSheet(
      context: parentContext,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take Photo'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  try {
                    final XFile? image = await _imagePicker.pickImage(
                      source: ImageSource.camera,
                      imageQuality: 45, // smaller file for mobile data
                      maxWidth: 1280,
                      maxHeight: 960,
                      preferredCameraDevice: CameraDevice.rear,
                    ).timeout(
                      const Duration(seconds: 30),
                      onTimeout: () {
                        throw Exception('Camera timeout. Please try again.');
                      },
                    );
                    
                    if (image != null && mounted) {
                      // Read bytes immediately and save to a reliable location
                      try {
                        final bytes = await image.readAsBytes();
                        if (bytes.isEmpty) {
                          throw Exception('No image data could be read. Please try again.');
                        }
                        final tempDir = await getTemporaryDirectory();
                        final timestamp = DateTime.now().millisecondsSinceEpoch;
                        final fileName = '${imageLabel.toLowerCase().replaceAll(' ', '_')}_$timestamp.jpg';
                        final savedFile = File('${tempDir.path}/$fileName');
                        await savedFile.writeAsBytes(bytes);
                        if (!await savedFile.exists()) {
                          throw Exception('Failed to save image. Please try again.');
                        }
                        debugPrint('DEBUG: Camera image saved. Label: "$imageLabel", bytes: ${bytes.length}');
                        onImageSelected(savedFile, bytes);
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(parentContext).showSnackBar(
                            SnackBar(
                              content: Text('Error saving image: ${e.toString()}'),
                              backgroundColor: Colors.red,
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }
                      }
                    } else if (mounted) {
                      // User cancelled or no image selected - no error needed
                      debugPrint('Camera cancelled or no image selected');
                    }
                  } catch (e) {
                    debugPrint('Camera error: $e');
                    if (mounted) {
                      String errorMessage = 'Could not open camera. ';
                      final errorStr = e.toString().toLowerCase();
                      if (errorStr.contains('permission')) {
                        errorMessage += 'Please grant camera permission in app settings.';
                      } else if (errorStr.contains('timeout')) {
                        errorMessage += 'Camera took too long. Please try again.';
                      } else if (errorStr.contains('not available') || errorStr.contains('no camera')) {
                        errorMessage += 'Camera is not available on this device.';
                      } else {
                        errorMessage += 'Please try again or use gallery instead.';
                      }
                      
                      ScaffoldMessenger.of(parentContext).showSnackBar(
                        SnackBar(
                          content: Text(errorMessage),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 4),
                          action: SnackBarAction(
                            label: 'OK',
                            textColor: Colors.white,
                            onPressed: () {},
                          ),
                        ),
                      );
                    }
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  try {
                    final XFile? image = await _imagePicker.pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 45, // smaller file for mobile data
                      maxWidth: 1280,
                      maxHeight: 960,
                    );
                    if (image != null) {
                      // Read bytes immediately and save to a reliable location
                      try {
                        final bytes = await image.readAsBytes();
                        if (bytes.isEmpty) {
                          throw Exception('No image data could be read. Try taking a photo instead.');
                        }
                        final tempDir = await getTemporaryDirectory();
                        final timestamp = DateTime.now().millisecondsSinceEpoch;
                        final fileName = '${imageLabel.toLowerCase().replaceAll(' ', '_')}_$timestamp.jpg';
                        final savedFile = File('${tempDir.path}/$fileName');
                        await savedFile.writeAsBytes(bytes);
                        if (!await savedFile.exists()) {
                          throw Exception('Failed to save image. Please try again.');
                        }
                        debugPrint('DEBUG: Gallery image saved. Size: ${bytes.length}');
                        onImageSelected(savedFile, bytes);
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(parentContext).showSnackBar(
                            SnackBar(
                              content: Text('Error saving image: ${e.toString()}'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(parentContext).showSnackBar(
                        SnackBar(
                          content: Text('Could not open gallery: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}


import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:firebase_storage/firebase_storage.dart';
import '../services/image_service.dart';
import '../services/storage_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import '../services/user_service.dart';
import '../models/user_model.dart';
import '../constants/app_constants.dart';
import '../config/testing_flags.dart';
import '../utils/qa_driver_location.dart';
import 'transporter_navigation.dart';

class DriverCompletionScreen extends StatefulWidget {
  final UserModel currentUser;
  
  const DriverCompletionScreen({super.key, required this.currentUser});

  @override
  State<DriverCompletionScreen> createState() => _DriverCompletionScreenState();
}

class _DriverCompletionScreenState extends State<DriverCompletionScreen> {
  final UserService _userService = UserService();
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _ratePer10KmController = TextEditingController();

  String? _selectedTruckType;
  File? _carBookImage;
  File? _truckSideImage;
  File? _driverLicenseImage;
  File? _selfieImage;
  Uint8List? _carBookImageBytes;
  Uint8List? _truckSideImageBytes;
  Uint8List? _driverLicenseImageBytes;
  Uint8List? _selfieImageBytes;
  bool _isLoading = false;
  bool _isUploadingImages = false;

  @override
  void initState() {
    super.initState();
    if (widget.currentUser.ratePer10Km != null && widget.currentUser.ratePer10Km! > 0) {
      _ratePer10KmController.text = widget.currentUser.ratePer10Km!.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _ratePer10KmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Complete Driver Profile',
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E40AF),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'To switch to driver profile, please complete the following information:',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 24),
              // Vehicle Type
              Text(
                'Vehicle Type *',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF1E40AF),
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
              // Rate per 10 km
              Text(
                'Your rate per 10 km (\$) *',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF1E40AF),
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
                  color: const Color(0xFF1E40AF),
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
                  color: const Color(0xFF1E40AF),
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
                  color: const Color(0xFF1E40AF),
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
                  color: const Color(0xFF1E40AF),
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
              const SizedBox(height: 32),
              // Submit button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: (_isLoading || _isUploadingImages) ? null : _completeProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
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
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          _isUploadingImages ? 'Uploading Images...' : 'Complete Profile',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
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
          color: isSelected ? const Color(0xFF2563EB) : Colors.white,
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
                    color: isSelected ? Colors.white : const Color(0xFF1E40AF),
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
                  Icon(icon, size: 32, color: Colors.grey.shade400),
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
    // Capture the parent context so we can safely show SnackBars even after the
    // bottom sheet is dismissed.
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
                      imageQuality: 85,
                    );
                    if (image != null) {
                      try {
                        final bytes = await image.readAsBytes();
                        if (bytes.isEmpty) throw Exception('No image data could be read.');
                        final tempDir = await getTemporaryDirectory();
                        final timestamp = DateTime.now().millisecondsSinceEpoch;
                        final fileName = '${imageLabel.toLowerCase().replaceAll(' ', '_')}_$timestamp.jpg';
                        final savedFile = File('${tempDir.path}/$fileName');
                        await savedFile.writeAsBytes(bytes);
                        onImageSelected(savedFile, bytes);
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(parentContext).showSnackBar(
                            SnackBar(
                              content: Text('Error: ${e.toString()}'),
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
                          content: Text('Could not open camera: $e'),
                          backgroundColor: Colors.red,
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
                      imageQuality: 85,
                    );
                    if (image != null) {
                      try {
                        final bytes = await image.readAsBytes();
                        if (bytes.isEmpty) throw Exception('No image data could be read. Try taking a photo instead.');
                        final tempDir = await getTemporaryDirectory();
                        final timestamp = DateTime.now().millisecondsSinceEpoch;
                        final fileName = '${imageLabel.toLowerCase().replaceAll(' ', '_')}_$timestamp.jpg';
                        final savedFile = File('${tempDir.path}/$fileName');
                        await savedFile.writeAsBytes(bytes);
                        onImageSelected(savedFile, bytes);
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(parentContext).showSnackBar(
                            SnackBar(
                              content: Text('Error: ${e.toString()}'),
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

  Future<void> _completeProfile() async {
    // Validation
    if (_selectedTruckType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select your vehicle type'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final ratePer10Km = double.tryParse(_ratePer10KmController.text.trim());
    if (ratePer10Km == null || ratePer10Km <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your rate per 10 km (e.g. 15 for \$15 per 10 km)'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // QA: skip document uploads when [TestingFlags.skipDriverDocumentUpload].
    if (TestingFlags.skipDriverDocumentUpload) {
      setState(() {
        _isLoading = true;
      });
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          throw Exception('User not logged in');
        }
        final loc = await QaDriverLocation.resolve();
        await _userService.updateDriverProfile(
          uid: user.uid,
          role: 'Driver',
          truckType: _selectedTruckType,
          ratePer10Km: ratePer10Km,
          isAvailable: true,
          verificationStatus: 'auto_verified',
          currentLat: loc?.lat,
          currentLng: loc?.lng,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Driver profile saved. Documents skipped (${TestingFlags.buildLabel}).',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const TransporterNavigation()),
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${e.toString()}'),
              backgroundColor: Colors.red,
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
      return;
    }

    if (_carBookImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please take a picture of your car book'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_truckSideImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please take a side view picture of your truck'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_driverLicenseImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please take a picture of your driver license'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selfieImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please take a selfie'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }

      // Refresh auth token and wait for Storage to recognize the user
      try {
        await user.getIdToken(true);
        await Future.delayed(const Duration(seconds: 8));
      } catch (_) {}

      // Upload images
      setState(() {
        _isUploadingImages = true;
      });

      String? carBookImageUrl;
      String? truckSideImageUrl;
      String? driverLicenseImageUrl;
      String? selfieImageUrl;

      // Get bytes: use stored bytes when available (more reliable than re-reading file)
      Uint8List carBookBytes;
      Uint8List truckSideBytes;
      Uint8List licenseBytes;
      Uint8List selfieBytes;
      try {
        carBookBytes = _carBookImageBytes ?? await _carBookImage!.readAsBytes();
        truckSideBytes = _truckSideImageBytes ?? await _truckSideImage!.readAsBytes();
        licenseBytes = _driverLicenseImageBytes ?? await _driverLicenseImage!.readAsBytes();
        selfieBytes = _selfieImageBytes ?? await _selfieImage!.readAsBytes();
      } catch (e) {
        throw Exception('Could not read one of the images. Please take the pictures again.');
      }

      // Compress and upload all 3 in parallel for faster completion
      final pathKey = AppConstants.storagePathKey(user.email, user.uid);
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {'uploadedBy': user.uid},
      );
      
      final compressed = await Future.wait([
        ImageService.compressImage(carBookBytes),
        ImageService.compressImage(truckSideBytes),
        ImageService.compressImage(licenseBytes),
        ImageService.compressImage(selfieBytes),
      ]);
      final compressedCarBook = compressed[0].isEmpty ? carBookBytes : compressed[0];
      final compressedTruckSide = compressed[1].isEmpty ? truckSideBytes : compressed[1];
      final compressedLicense = compressed[2].isEmpty ? licenseBytes : compressed[2];
      final compressedSelfie = compressed[3].isEmpty ? selfieBytes : compressed[3];

      // Upload using path-only (skips getDownloadURL - fetch URL when displaying)
      final carBookPath = AppConstants.storageDriverPath(pathKey, 'car_book.jpg');
      final truckSidePath = AppConstants.storageDriverPath(pathKey, 'truck_side.jpg');
      final licensePath = AppConstants.storageDriverPath(pathKey, 'driver_license.jpg');
      final selfiePath = AppConstants.storageDriverPath(pathKey, 'selfie.jpg');
      await StorageService.putDataReturnPath(path: carBookPath, data: compressedCarBook, metadata: metadata, user: user);
      carBookImageUrl = carBookPath;
      await StorageService.putDataReturnPath(path: truckSidePath, data: compressedTruckSide, metadata: metadata, user: user);
      truckSideImageUrl = truckSidePath;
      await StorageService.putDataReturnPath(path: licensePath, data: compressedLicense, metadata: metadata, user: user);
      driverLicenseImageUrl = licensePath;
      await StorageService.putDataReturnPath(path: selfiePath, data: compressedSelfie, metadata: metadata, user: user);
      selfieImageUrl = selfiePath;

      final loc = await QaDriverLocation.resolve();
      // Update driver-specific fields and role
      await _userService.updateDriverProfile(
        uid: user.uid,
        role: 'Driver',
        truckType: _selectedTruckType,
        ratePer10Km: ratePer10Km,
        carBookImageUrl: carBookImageUrl,
        truckSideImageUrl: truckSideImageUrl,
        driverLicenseImageUrl: driverLicenseImageUrl,
        selfieImageUrl: selfieImageUrl,
        isAvailable: true,
        currentLat: loc?.lat,
        currentLng: loc?.lng,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
        
        // Navigate to transporter navigation
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const TransporterNavigation()),
          (route) => false,
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Driver profile image upload error: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        String message;
        if (e is FirebaseException) {
          final code = e.code.toLowerCase();
          if (code.contains('permission') || code.contains('unauthorized') || code.contains('denied')) {
            message = 'Upload denied. Sign out, sign in again, and retry. Check Firebase Storage rules.';
          } else if (code.contains('unauthenticated')) {
            message = 'Please sign in again and try uploading.';
          } else if (code.contains('canceled') || code.contains('cancelled')) {
            message = 'Upload was cancelled. Please try again.';
          } else {
            message = 'Upload failed (${e.code}). Check your connection and try again.';
          }
          message += '\n\nDetails: ${e.message ?? e.code}';
        } else {
          message = 'Unable to upload images. Check your internet connection and try again.';
          message += '\n\nDetails: ${e.toString()}';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: SingleChildScrollView(
              child: Text(message),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 8),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isUploadingImages = false;
        });
      }
    }
  }
}

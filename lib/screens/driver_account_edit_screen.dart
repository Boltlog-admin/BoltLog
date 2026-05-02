import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import '../models/user_model.dart';
import '../services/user_service.dart';
import '../services/storage_service.dart';
import '../services/image_service.dart';
import '../constants/app_constants.dart';
import '../widgets/storage_image.dart';

class DriverAccountEditScreen extends StatefulWidget {
  final UserModel user;

  const DriverAccountEditScreen({super.key, required this.user});

  @override
  State<DriverAccountEditScreen> createState() => _DriverAccountEditScreenState();
}

class _DriverAccountEditScreenState extends State<DriverAccountEditScreen> {
  final UserService _userService = UserService();
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _vehicleNumberController = TextEditingController();
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
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.user.displayName ?? '';
    _phoneController.text = widget.user.phoneNumber ?? '';
    _vehicleNumberController.text = widget.user.vehicleNumber ?? '';
    if (widget.user.ratePer10Km != null && widget.user.ratePer10Km! > 0) {
      _ratePer10KmController.text = widget.user.ratePer10Km!.toStringAsFixed(0);
    }
    _selectedTruckType = widget.user.truckType;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _vehicleNumberController.dispose();
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1E40AF)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Edit Account',
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
              // Personal Information Section
              Text(
                'Personal Information',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E40AF),
                ),
              ),
              const SizedBox(height: 16),
              
              // Full Name
              _buildTextField(
                label: 'Full Name',
                controller: _nameController,
                icon: Icons.person,
              ),
              const SizedBox(height: 16),
              
              // Phone Number
              _buildTextField(
                label: 'Phone Number',
                controller: _phoneController,
                icon: Icons.phone,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 24),
              
              // Vehicle Information Section
              Text(
                'Vehicle Information',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E40AF),
                ),
              ),
              const SizedBox(height: 16),
              
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
              const SizedBox(height: 16),
              
              // Vehicle Number
              _buildTextField(
                label: 'Vehicle Number (Optional)',
                controller: _vehicleNumberController,
                icon: Icons.confirmation_number,
              ),
              const SizedBox(height: 16),
              // Rate per 10 km
              Text(
                'Your rate per 10 km (\$)',
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
              const SizedBox(height: 24),
              
              // Documents Section
              Text(
                'Documents',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E40AF),
                ),
              ),
              const SizedBox(height: 16),
              
              // Car Book Image
              Text(
                'Car Book Picture',
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
                widget.user.carBookImageUrl,
                (file, bytes) => setState(() {
                  _carBookImage = file;
                  _carBookImageBytes = bytes;
                }),
                Icons.description,
              ),
              const SizedBox(height: 16),
              // Truck Side View Image
              Text(
                'Truck Side View Picture',
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
                widget.user.truckSideImageUrl,
                (file, bytes) => setState(() {
                  _truckSideImage = file;
                  _truckSideImageBytes = bytes;
                }),
                Icons.local_shipping,
              ),
              const SizedBox(height: 16),
              
              // Driver License Image
              Text(
                'Driver License Picture',
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
                widget.user.driverLicenseImageUrl,
                (file, bytes) => setState(() {
                  _driverLicenseImage = file;
                  _driverLicenseImageBytes = bytes;
                }),
                Icons.credit_card,
              ),
              const SizedBox(height: 16),
              
              // Selfie Image
              Text(
                'Selfie Picture',
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
                widget.user.selfieImageUrl,
                (file, bytes) => setState(() {
                  _selfieImage = file;
                  _selfieImageBytes = bytes;
                }),
                Icons.face,
              ),
              const SizedBox(height: 32),
              
              // Save Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: (_isLoading || _isUploading) ? null : _saveChanges,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: (_isLoading || _isUploading)
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          _isUploading ? 'Uploading...' : 'Save Changes',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: GoogleFonts.inter(
          fontSize: 16,
          color: const Color(0xFF1E40AF),
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.inter(
            color: Colors.grey.shade600,
          ),
          prefixIcon: Icon(icon, color: const Color(0xFF2563EB)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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

  Widget _buildImagePicker(
    String label,
    File? newImage,
    String? existingImageUrl,
    void Function(File?, Uint8List?) onImageSelected,
    IconData icon,
  ) {
    final hasImage = newImage != null || (existingImageUrl != null && existingImageUrl!.isNotEmpty);

    return GestureDetector(
      onTap: () => _showImageSourceDialog(label, onImageSelected),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasImage ? const Color(0xFF2563EB) : Colors.grey.shade300,
            width: hasImage ? 2 : 1,
          ),
        ),
        child: newImage != null
            ? Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.file(
                      newImage,
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
            : existingImageUrl != null && existingImageUrl.isNotEmpty
                ? Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: StorageImage(
                          pathOrUrl: existingImageUrl,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(icon, size: 32, color: Colors.grey.shade400),
                                const SizedBox(height: 8),
                                Text(
                                  'Tap to change $label picture',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: IconButton(
                          icon: const Icon(Icons.edit, color: Colors.white),
                          onPressed: () => _showImageSourceDialog(label, onImageSelected),
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
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take Photo'),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    final XFile? image = await _imagePicker.pickImage(
                      source: ImageSource.camera,
                      imageQuality: 85,
                    );
                    if (image != null && mounted) {
                      final bytes = await image.readAsBytes();
                      if (bytes.isEmpty) throw Exception('No image data could be read.');
                      final tempDir = await getTemporaryDirectory();
                      final file = File('${tempDir.path}/img_${DateTime.now().millisecondsSinceEpoch}.jpg');
                      await file.writeAsBytes(bytes);
                      onImageSelected(file, bytes);
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error: Could not open camera. ${e.toString()}'),
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
                  Navigator.pop(context);
                  try {
                    final XFile? image = await _imagePicker.pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 85,
                    );
                    if (image != null && mounted) {
                      final bytes = await image.readAsBytes();
                      if (bytes.isEmpty) throw Exception('No image data could be read.');
                      final tempDir = await getTemporaryDirectory();
                      final file = File('${tempDir.path}/img_${DateTime.now().millisecondsSinceEpoch}.jpg');
                      await file.writeAsBytes(bytes);
                      onImageSelected(file, bytes);
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error: Could not open gallery. ${e.toString()}'),
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

  Future<void> _saveChanges() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your full name'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedTruckType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select your vehicle type'),
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

      // Refresh auth token and wait for Storage to see current user
      try {
        await user.getIdToken(true);
        await Future.delayed(const Duration(seconds: 1));
      } catch (_) {}

      // Upload new images if selected
      setState(() {
        _isUploading = true;
      });

      final imageMetadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {'uploadedBy': user.uid},
      );
      String? carBookImageUrl = widget.user.carBookImageUrl;
      String? truckSideImageUrl = widget.user.truckSideImageUrl;
      String? driverLicenseImageUrl = widget.user.driverLicenseImageUrl;
      String? selfieImageUrl = widget.user.selfieImageUrl;

      if (_carBookImage != null) {
        final bytes = _carBookImageBytes ?? await _carBookImage!.readAsBytes();
        final compressed = await ImageService.compressImage(bytes);
        if (compressed.isNotEmpty) {
          carBookImageUrl = await StorageService.putDataReturnPath(
            path: AppConstants.storageDriverPath(AppConstants.storagePathKey(user.email, user.uid), 'car_book.jpg'),
            data: compressed,
            metadata: imageMetadata,
            user: user,
          );
        }
      }

      if (_truckSideImage != null) {
        final bytes = _truckSideImageBytes ?? await _truckSideImage!.readAsBytes();
        final compressed = await ImageService.compressImage(bytes);
        if (compressed.isNotEmpty) {
          truckSideImageUrl = await StorageService.putDataReturnPath(
            path: AppConstants.storageDriverPath(AppConstants.storagePathKey(user.email, user.uid), 'truck_side.jpg'),
            data: compressed,
            metadata: imageMetadata,
            user: user,
          );
        }
      }

      if (_driverLicenseImage != null) {
        final bytes = _driverLicenseImageBytes ?? await _driverLicenseImage!.readAsBytes();
        final compressed = await ImageService.compressImage(bytes);
        if (compressed.isNotEmpty) {
          driverLicenseImageUrl = await StorageService.putDataReturnPath(
            path: AppConstants.storageDriverPath(AppConstants.storagePathKey(user.email, user.uid), 'driver_license.jpg'),
            data: compressed,
            metadata: imageMetadata,
            user: user,
          );
        }
      }

      if (_selfieImage != null) {
        final bytes = _selfieImageBytes ?? await _selfieImage!.readAsBytes();
        final compressed = await ImageService.compressImage(bytes);
        if (compressed.isNotEmpty) {
          selfieImageUrl = await StorageService.putDataReturnPath(
            path: AppConstants.storageDriverPath(AppConstants.storagePathKey(user.email, user.uid), 'selfie.jpg'),
            data: compressed,
            metadata: imageMetadata,
            user: user,
          );
        }
      }

      setState(() {
        _isUploading = false;
      });

      // Normalize phone number
      String phoneNumber = _phoneController.text.trim();
      if (phoneNumber.isNotEmpty && !phoneNumber.startsWith('+263')) {
        phoneNumber = phoneNumber.replaceAll(RegExp(r'^\+263\s*'), '').trim();
        phoneNumber = phoneNumber.replaceAll(RegExp(r'\s+'), '');
        phoneNumber = '+263$phoneNumber';
      }

      // Update user profile
      await _userService.updateUserProfile(
        uid: user.uid,
        displayName: _nameController.text.trim(),
        phoneNumber: phoneNumber.isNotEmpty ? phoneNumber : widget.user.phoneNumber,
      );

      // Update driver-specific fields
      await _userService.updateDriverProfile(
        uid: user.uid,
        truckType: _selectedTruckType,
        ratePer10Km: () {
          final v = double.tryParse(_ratePer10KmController.text.trim());
          return (v != null && v > 0) ? v : null;
        }(),
        carBookImageUrl: carBookImageUrl,
        truckSideImageUrl: truckSideImageUrl,
        driverLicenseImageUrl: driverLicenseImageUrl,
        selfieImageUrl: selfieImageUrl,
        vehicleNumber: _vehicleNumberController.text.trim().isNotEmpty
            ? _vehicleNumberController.text.trim()
            : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: SingleChildScrollView(
              child: Text('Error uploading images.\n\nDetails: ${e.toString()}'),
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
          _isUploading = false;
        });
      }
    }
  }
}

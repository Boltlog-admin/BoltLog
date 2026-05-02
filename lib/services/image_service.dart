import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../constants/app_constants.dart';

class ImageService {
  // Compress image before upload
  static Future<Uint8List> compressImage(
    Uint8List imageBytes, {
    int quality = AppConstants.imageCompressionQuality,
    int maxWidth = AppConstants.imageMaxWidth,
    int maxHeight = AppConstants.imageMaxHeight,
  }) async {
    try {
      // Compress image
      final compressedBytes = await FlutterImageCompress.compressWithList(
        imageBytes,
        minHeight: maxHeight,
        minWidth: maxWidth,
        quality: quality,
        format: CompressFormat.jpeg,
      );

      // Check if compressed size is acceptable
      if (compressedBytes.length > AppConstants.maxImageSizeBytes) {
        // If still too large, compress more aggressively
        return await compressImage(
          compressedBytes,
          quality: (quality * 0.7).round(),
          maxWidth: (maxWidth * 0.8).round(),
          maxHeight: (maxHeight * 0.8).round(),
        );
      }

      return compressedBytes;
    } catch (e) {
      // If compression fails, return original (but log warning)
      return imageBytes;
    }
  }

  // Compress image from file
  static Future<Uint8List> compressImageFile(
    File imageFile, {
    int quality = AppConstants.imageCompressionQuality,
    int maxWidth = AppConstants.imageMaxWidth,
    int maxHeight = AppConstants.imageMaxHeight,
  }) async {
    final imageBytes = await imageFile.readAsBytes();
    return await compressImage(
      imageBytes,
      quality: quality,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
  }

  // Validate image size
  static bool isValidImageSize(Uint8List imageBytes) {
    return imageBytes.length <= AppConstants.maxImageSizeBytes;
  }

  // Get image size in MB
  static double getImageSizeMB(Uint8List imageBytes) {
    return imageBytes.length / (1024 * 1024);
  }
}

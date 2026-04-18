import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/storage_service.dart';

/// Displays an image from Firebase Storage. Handles both full URLs and storage paths.
/// When path is stored (no getDownloadURL during upload), fetches URL on display.
class StorageImage extends StatelessWidget {
  final String? pathOrUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;
  final Widget? placeholder;

  const StorageImage({
    super.key,
    required this.pathOrUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorBuilder,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    if (pathOrUrl == null || pathOrUrl!.isEmpty) {
      return _buildPlaceholder(context);
    }
    if (!StorageService.isStoragePath(pathOrUrl)) {
      return Image.network(
        pathOrUrl!,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: errorBuilder ?? _defaultErrorBuilder,
      );
    }
    return FutureBuilder<String>(
      future: StorageService.getDownloadUrlFromPath(pathOrUrl!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return placeholder ?? _buildPlaceholder(context);
        }
        if (snapshot.hasError || !snapshot.hasData) {
          debugPrint('StorageImage getDownloadUrl failed pathOrUrl=$pathOrUrl error=${snapshot.error}');
          return errorBuilder?.call(context, snapshot.error ?? Object(), snapshot.stackTrace) ??
              _defaultErrorBuilder(context, snapshot.error ?? Object(), snapshot.stackTrace);
        }
        return Image.network(
          snapshot.data!,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: errorBuilder ?? _defaultErrorBuilder,
        );
      },
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return placeholder ??
        Container(
          width: width,
          height: height,
          color: Colors.grey.shade200,
          child: const Center(child: Icon(Icons.image, color: Colors.grey)),
        );
  }

  Widget _defaultErrorBuilder(BuildContext context, Object error, StackTrace? stackTrace) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey.shade200,
      child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
    );
  }
}

/// CircleAvatar that supports both Firebase Storage URLs and paths.
class StorageAvatar extends StatelessWidget {
  final String? pathOrUrl;
  final double radius;
  final Color? backgroundColor;
  final Widget? child;

  const StorageAvatar({
    super.key,
    required this.pathOrUrl,
    this.radius = 24,
    this.backgroundColor,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (pathOrUrl == null || pathOrUrl!.isEmpty) {
      return CircleAvatar(radius: radius, backgroundColor: backgroundColor, child: child);
    }
    if (!StorageService.isStoragePath(pathOrUrl)) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        backgroundImage: NetworkImage(pathOrUrl!),
        child: child,
      );
    }
    return FutureBuilder<String>(
      future: StorageService.getDownloadUrlFromPath(pathOrUrl!),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return CircleAvatar(
            radius: radius,
            backgroundColor: backgroundColor,
            backgroundImage: NetworkImage(snapshot.data!),
          );
        }
        if (snapshot.hasError) {
          debugPrint('StorageAvatar getDownloadUrl failed pathOrUrl=$pathOrUrl error=${snapshot.error}');
        }
        return CircleAvatar(
          radius: radius,
          backgroundColor: backgroundColor,
          child: child ?? (snapshot.connectionState == ConnectionState.waiting
              ? SizedBox(width: radius * 1.2, height: radius * 1.2, child: const CircularProgressIndicator(strokeWidth: 2))
              : null),
        );
      },
    );
  }
}

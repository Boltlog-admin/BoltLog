import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the device dialer with [phoneNumber], or returns false if invalid.
Future<bool> launchTel(String? phoneNumber) async {
  if (phoneNumber == null || phoneNumber.trim().isEmpty) {
    return false;
  }
  final trimmed = phoneNumber.trim();
  final digits = trimmed.replaceAll(RegExp(r'[\s\-()]'), '');
  if (digits.isEmpty) return false;
  final uri = Uri(scheme: 'tel', path: digits);
  try {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return true;
    }
  } catch (e, st) {
    debugPrint('launchTel: $e\n$st');
  }
  return false;
}

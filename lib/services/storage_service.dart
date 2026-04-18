import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show Firebase, FirebaseException;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:http/http.dart' as http;
import '../firebase_options.dart';

/// Exception with Firebase Storage error code for clearer user feedback.
class StorageUploadException implements Exception {
  final String code;
  final String message;
  StorageUploadException({required this.code, required this.message});
  @override
  String toString() => '[$code] $message';
}

/// Handles Firebase Storage uploads with retry on permission errors.
class StorageService {
  /// Use bucket from firebase_options so Storage always matches deployed rules.
  static FirebaseStorage get _storage {
    final bucket = DefaultFirebaseOptions.currentPlatform.storageBucket;
    if (bucket != null && bucket.isNotEmpty) {
      return FirebaseStorage.instanceFor(app: Firebase.app(), bucket: bucket);
    }
    return FirebaseStorage.instance;
  }

  /// Returns true if value is a storage path (not a full URL).
  static bool isStoragePath(String? value) =>
      value != null && value.isNotEmpty && !value.startsWith('http');

  /// Get download URL from path. Use when displaying - object has time to propagate.
  /// Trims path and retries on object-not-found (propagation delay).
  static Future<String> getDownloadUrlFromPath(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) throw ArgumentError('Storage path is empty');
    final ref = _storage.ref().child(trimmed);
    const maxAttempts = 3;
    const delays = [0, 1, 2]; // seconds
    Object? lastError;
    for (var i = 0; i < maxAttempts; i++) {
      try {
        if (i > 0) await Future.delayed(Duration(seconds: delays[i]));
        final url = await ref.getDownloadURL();
        return url;
      } catch (e) {
        lastError = e;
        final errStr = e.toString().toLowerCase();
        final isRetryable = errStr.contains('object-not-found') ||
            errStr.contains('object not found') ||
            errStr.contains('no object') ||
            errStr.contains('desired reference');
        debugPrint('StorageService getDownloadUrlFromPath path=$trimmed attempt=${i + 1}/$maxAttempts: $e');
        if (!isRetryable || i == maxAttempts - 1) rethrow;
      }
    }
    if (lastError != null) throw lastError;
    throw StateError('getDownloadUrlFromPath failed');
  }

  /// Upload and return path only. Tries Cloud Function first (avoids 412), then REST, then SDK.
  static Future<String> putDataReturnPath({
    required String path,
    required Uint8List data,
    required SettableMetadata metadata,
    User? user,
  }) async {
    Object? lastError;

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        if (user != null) {
          return await _uploadViaRestApi(path: path, data: data, user: user);
        }
        break;
      } catch (e) {
        lastError = e;
        debugPrint('StorageService REST attempt ${attempt + 1}/3 path=$path: $e');
        if (attempt < 2 && user != null) {
          await Future.delayed(Duration(seconds: attempt + 2));
          try { await user.getIdToken(true); } catch (_) {}
          continue;
        }
        break;
      }
    }

    final ref = _storage.ref().child(path);
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        if (!kIsWeb && Platform.isAndroid) {
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/upload_${DateTime.now().millisecondsSinceEpoch}.jpg');
          await tempFile.writeAsBytes(data);
          try {
            await ref.putFile(tempFile, metadata);
          } finally {
            if (await tempFile.exists()) await tempFile.delete();
          }
        } else {
          await ref.putData(data, metadata);
        }
        return path;
      } catch (e) {
        lastError = e;
        debugPrint('StorageService SDK attempt ${attempt + 1}/3 path=$path: $e');
        if (attempt < 2 && _shouldRetry(e) && user != null) {
          await Future.delayed(Duration(seconds: attempt + 2));
          try { await user.getIdToken(true); } catch (_) {}
          continue;
        }
        break;
      }
    }

    if (lastError != null) {
      try {
        return await _uploadViaCloudFunction(path: path, data: data, user: user);
      } catch (e) {
        debugPrint('StorageService Cloud Function fallback failed: $e');
      }
      if (lastError is FirebaseException) {
        throw StorageUploadException(
          code: lastError.code,
          message: lastError.message ?? lastError.code,
        );
      }
      throw lastError;
    }
    throw StateError('Upload failed after retries');
  }

  /// Cloud Function upload - uses Admin SDK server-side. Bypasses client auth issues.
  static Future<String> _uploadViaCloudFunction({
    required String path,
    required Uint8List data,
    User? user,
  }) async {
    if (user == null) throw Exception('User required for Cloud Function upload');
    final callable = FirebaseFunctions.instance.httpsCallable(
      'uploadDriverImage',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
    );
    final imageBase64 = base64Encode(data);
    final result = await callable.call({
      'path': path,
      'imageBase64': imageBase64,
    });
    final resultData = result.data as Map<String, dynamic>?;
    final resultPath = resultData?['path'] as String?;
    if (resultPath != null) {
      debugPrint('StorageService Cloud Function upload succeeded: $path');
      return resultPath;
    }
    throw Exception('Cloud Function returned no path');
  }

  /// REST API upload - explicitly sends auth token. Primary method when SDK has issues.
  static Future<String> _uploadViaRestApi({
    required String path,
    required Uint8List data,
    User? user,
  }) async {
    if (user == null) throw Exception('User required for REST upload');
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) throw Exception('No auth token');
    final bucket = DefaultFirebaseOptions.currentPlatform.storageBucket;
    final encodedPath = Uri.encodeComponent(path);
    final url = Uri.parse(
      'https://firebasestorage.googleapis.com/v0/b/$bucket/o?uploadType=media&name=$encodedPath',
    );
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'image/jpeg',
      },
      body: data,
    ).timeout(const Duration(seconds: 60));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      debugPrint('StorageService REST upload succeeded: $path');
      return path;
    }
    throw Exception('REST upload failed: ${response.statusCode} ${response.body}');
  }

  static bool _shouldRetry(Object e) {
    final errStr = e.toString().toLowerCase();
    return errStr.contains('permission') ||
        errStr.contains('403') ||
        errStr.contains('unauthorized') ||
        errStr.contains('denied') ||
        errStr.contains('unauthenticated') ||
        errStr.contains('unknown') ||
        errStr.contains('firebase_storage') ||
        errStr.contains('storage/') ||
        errStr.contains('object-not-found') ||
        errStr.contains('object not found') ||
        errStr.contains('desired reference');
  }

  /// Get download URL with retry. Firebase needs time to finalize after upload.
  static Future<String> _getDownloadUrlWithRetry(Reference ref) async {
    const maxAttempts = 8;
    const delays = [3, 5, 7, 10, 12, 15, 20]; // seconds before each attempt
    for (var i = 0; i < maxAttempts; i++) {
      try {
        await Future.delayed(Duration(seconds: i == 0 ? 5 : delays[i - 1]));
        return await ref.getDownloadURL();
      } catch (e) {
        final errStr = e.toString().toLowerCase();
        final isObjectNotFound = errStr.contains('object-not-found') ||
            errStr.contains('object not found') ||
            errStr.contains('desired reference') ||
            errStr.contains('no object exists');
        if (isObjectNotFound && i < maxAttempts - 1) {
          debugPrint('StorageService getDownloadURL attempt ${i + 1}/$maxAttempts failed, retrying in ${i < delays.length ? delays[i] : 10}s...');
          continue;
        }
        rethrow;
      }
    }
    throw StateError('getDownloadURL failed after retries');
  }

  /// Upload bytes with retry. Uses putFile (more reliable on Android than putData).
  static Future<String> putDataWithRetry({
    required String path,
    required Uint8List data,
    required SettableMetadata metadata,
    User? user,
  }) async {
    final ref = _storage.ref().child(path);
    Object? lastError;

    Future<String> doPutFile() async {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/upload_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(data);
      try {
        final snapshot = await ref.putFile(tempFile, metadata);
        return await _getDownloadUrlWithRetry(snapshot.ref);
      } finally {
        if (await tempFile.exists()) await tempFile.delete();
      }
    }

    Future<String> doPutData() async {
      final snapshot = await ref.putData(data, metadata);
      return await _getDownloadUrlWithRetry(snapshot.ref);
    }

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        if (!kIsWeb && Platform.isAndroid) {
          return await doPutFile();
        }
        return await doPutData();
      } catch (e) {
        lastError = e;
        debugPrint('StorageService upload attempt ${attempt + 1}/3 path=$path: $e');
        if (attempt < 2 && _shouldRetry(e) && user != null) {
          await Future.delayed(Duration(seconds: attempt + 2));
          try { await user.getIdToken(true); } catch (_) {}
          continue;
        }
        break;
      }
    }

    if (lastError != null) {
      try {
        return await (kIsWeb || !Platform.isAndroid ? doPutData() : doPutFile());
      } catch (e) {
        debugPrint('StorageService fallback failed: $e');
      }
      if (lastError is FirebaseException) {
        throw StorageUploadException(
          code: lastError.code,
          message: lastError.message ?? lastError.code,
        );
      }
      throw lastError;
    }
    throw StateError('Upload failed after retries');
  }

  /// Upload file with retry on auth/storage errors.
  static Future<String> putFileWithRetry({
    required String path,
    required File file,
    required SettableMetadata metadata,
    User? user,
  }) async {
    final ref = _storage.ref().child(path);

    Future<String> doUpload() async {
      final snapshot = await ref.putFile(file, metadata);
      return await _getDownloadUrlWithRetry(snapshot.ref);
    }

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await doUpload();
      } catch (e) {
        if (attempt < 2 && _shouldRetry(e) && user != null) {
          await Future.delayed(Duration(seconds: attempt + 1));
          try {
            await user.getIdToken(true);
          } catch (_) {}
          continue;
        }
        rethrow;
      }
    }
    throw StateError('Upload failed after retries');
  }
}

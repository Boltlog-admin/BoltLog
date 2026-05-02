import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';

class ErrorHandlerService {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      printTime: true,
    ),
  );

  // Handle and display errors to user
  static void handleError(BuildContext context, dynamic error, {String? customMessage}) {
    String userMessage = customMessage ?? _getUserFriendlyMessage(error);
    
    // Log error for debugging
    _logError(error);
    
    // Show error to user
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Dismiss',
            textColor: Colors.white,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );
    }
  }

  /// Same wording as [handleError], for SnackBars or dialogs without logging.
  static String messageForDisplay(dynamic error) => _getUserFriendlyMessage(error);

  // Get user-friendly error message
  static String _getUserFriendlyMessage(dynamic error) {
    if (error is FirebaseAuthException) {
      return _getAuthErrorMessage(error);
    }
    
    if (error is FirebaseException) {
      return _getFirestoreErrorMessage(error);
    }
    
    if (error is Exception) {
      final message = error.toString();
      
      // Network errors
      if (message.contains('network') || message.contains('Network') || message.contains('SocketException')) {
        return 'Network error. Please check your internet connection and try again.';
      }
      
      // Timeout errors
      if (message.contains('timeout') || message.contains('Timeout')) {
        return 'Request timed out. Please try again.';
      }
      
      // Generic error
      return message.replaceAll('Exception: ', '').replaceAll('Error: ', '');
    }
    
    return 'An unexpected error occurred. Please try again.';
  }

  // Get Firebase Auth error messages
  static String _getAuthErrorMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'user-not-found':
        return 'No account found with this email. Please sign up first.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'email-already-in-use':
        return 'An account already exists with this email address.';
      case 'invalid-email':
        return 'Invalid email address. Please check and try again.';
      case 'weak-password':
        return 'Password is too weak. Please use a stronger password.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please wait a few minutes and try again.';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled. Please contact support.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';
      case 'requires-recent-login':
        return 'Please log out and log in again to perform this action.';
      case 'invalid-credential':
        return 'Invalid credentials. Please check your email and password.';
      default:
        return error.message ?? 'Authentication failed. Please try again.';
    }
  }

  // Get Firestore error messages
  static String _getFirestoreErrorMessage(FirebaseException error) {
    switch (error.code) {
      case 'permission-denied':
        return 'Permission denied. Deploy the latest firestore.rules to this Firebase project, '
            'or ask your admin to run: firebase deploy --only firestore:rules';
      case 'not-found':
        return 'The requested data was not found.';
      case 'unavailable':
        return 'Service is temporarily unavailable. Please try again later.';
      case 'deadline-exceeded':
        return 'Request timed out. Please try again.';
      case 'resource-exhausted':
        return 'Too many requests. Please try again later.';
      case 'failed-precondition':
        return 'Operation cannot be completed. Please try again.';
      case 'aborted':
        return 'Operation was cancelled. Please try again.';
      case 'out-of-range':
        return 'Invalid data provided. Please check your input.';
      case 'unimplemented':
        return 'This feature is not available yet.';
      case 'internal':
        return 'An internal error occurred. Please try again.';
      case 'unauthenticated':
        return 'Please log in to continue.';
      default:
        return error.message ?? 'An error occurred. Please try again.';
    }
  }

  // Log error for debugging
  static void _logError(dynamic error, [StackTrace? stackTrace]) {
    if (error is FirebaseAuthException) {
      _logger.e('Firebase Auth Error', error: error, stackTrace: stackTrace);
    } else if (error is FirebaseException) {
      _logger.e('Firebase Error', error: error, stackTrace: stackTrace);
    } else {
      _logger.e('Error', error: error, stackTrace: stackTrace);
    }
  }

  // Show success message
  static void showSuccess(BuildContext context, String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // Show info message
  static void showInfo(BuildContext context, String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // Show warning message
  static void showWarning(BuildContext context, String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }
}

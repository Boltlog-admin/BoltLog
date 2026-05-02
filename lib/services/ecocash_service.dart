import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import '../models/payment_model.dart';
import '../models/payment_method_model.dart';
import '../constants/app_constants.dart';

/// EcoCash Payment Service
/// 
/// EcoCash offers multiple integration methods:
/// 1. USSD Push (Recommended) - User receives USSD prompt on their phone
/// 2. Direct API Integration - Requires merchant account with EcoCash
/// 3. Payment Gateway (Paynow, etc.) - Third-party aggregator
/// 
/// This service implements the USSD Push method which is the most user-friendly
class EcoCashService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // EcoCash API Configuration
  // NOTE: Replace with actual EcoCash merchant credentials
  static const String _merchantCode = 'YOUR_MERCHANT_CODE';
  static const String _merchantKey = 'YOUR_MERCHANT_KEY';
  static const String _apiBaseUrl = 'https://api.ecocash.co.zw'; // Example URL
  
  // For testing, you can use Paynow (aggregator) which supports EcoCash
  static const String _paynowIntegrationId = 'YOUR_PAYNOW_ID';
  static const String _paynowIntegrationKey = 'YOUR_PAYNOW_KEY';
  static const String _paynowApiUrl = 'https://www.paynow.co.zw/interface/initiatetransaction';

  /// Initiate EcoCash payment via USSD Push
  /// 
  /// This method sends a payment request to the user's phone.
  /// User receives a USSD prompt to confirm payment.
  /// 
  /// Flow:
  /// 1. App initiates payment request
  /// 2. User receives USSD prompt on phone
  /// 3. User enters EcoCash PIN to confirm
  /// 4. Payment is processed
  /// 5. App polls for payment status
  Future<EcoCashPaymentResult> initiatePayment({
    required String phoneNumber, // Format: 0771234567 or +263771234567
    required double amount,
    required String reference, // Unique reference for this transaction
    String? description,
  }) async {
    try {
      // Normalize phone number
      String normalizedPhone = _normalizePhoneNumber(phoneNumber);
      
      // Validate phone number is EcoCash registered
      if (!_isValidEcoCashNumber(normalizedPhone)) {
        throw Exception('Invalid EcoCash number. Must be a NetOne/Econet number.');
      }

      // Method 1: Direct EcoCash API (if you have merchant account)
      // Uncomment and configure when you have credentials
      /*
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/api/payment/initiate'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_merchantKey',
        },
        body: json.encode({
          'merchantCode': _merchantCode,
          'phoneNumber': normalizedPhone,
          'amount': amount,
          'reference': reference,
          'description': description ?? 'Boltlog Delivery Payment',
          'callbackUrl': 'https://your-backend.com/ecocash/callback',
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return EcoCashPaymentResult(
          success: true,
          pollUrl: data['pollUrl'],
          reference: reference,
          message: 'Payment request sent. Please check your phone for USSD prompt.',
        );
      } else {
        throw Exception('Failed to initiate payment: ${response.body}');
      }
      */

      // Method 2: Using Paynow (Easier integration, supports multiple providers)
      // This is recommended for easier setup
      final paynowResult = await _initiatePaynowPayment(
        phoneNumber: normalizedPhone,
        amount: amount,
        reference: reference,
        description: description,
      );

      return paynowResult;

    } catch (e) {
      return EcoCashPaymentResult(
        success: false,
        reference: reference,
        message: 'Error initiating payment: ${e.toString()}',
      );
    }
  }

  /// Initiate payment via Paynow (aggregator that supports EcoCash)
  Future<EcoCashPaymentResult> _initiatePaynowPayment({
    required String phoneNumber,
    required double amount,
    required String reference,
    String? description,
  }) async {
    try {
      // Create payment hash for security
      final hashString = '$_paynowIntegrationId$reference${amount.toStringAsFixed(2)}$_paynowIntegrationKey';
      final hash = _createHash(hashString);

      final response = await http.post(
        Uri.parse(_paynowApiUrl),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'resulturl': 'https://your-backend.com/paynow/result', // Your callback URL
          'returnurl': 'boltlog://payment/return', // Deep link back to app
          'reference': reference,
          'amount': amount.toStringAsFixed(2),
          'id': _paynowIntegrationId,
          'additionalinfo': description ?? 'Boltlog Delivery Payment',
          'authemail': 'your-email@example.com', // Your merchant email
          'status': 'Message',
          'hash': hash,
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final responseData = _parsePaynowResponse(response.body);
        
        if (responseData['status'] == 'Ok') {
          // Extract poll URL for status checking
          final pollUrl = responseData['pollurl'];
          
          return EcoCashPaymentResult(
            success: true,
            pollUrl: pollUrl,
            reference: reference,
            message: 'Payment request sent. Please check your phone for USSD prompt.',
            paymentUrl: responseData['browserurl'], // For web-based payment
          );
        } else {
          throw Exception(responseData['error'] ?? 'Payment initiation failed');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      return EcoCashPaymentResult(
        success: false,
        reference: reference,
        message: 'Error: ${e.toString()}',
      );
    }
  }

  /// Poll payment status
  /// 
  /// After initiating payment, poll this endpoint to check if payment was completed
  Future<EcoCashPaymentStatus> checkPaymentStatus(String pollUrl) async {
    try {
      final response = await http.get(
        Uri.parse(pollUrl),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = _parsePaynowResponse(response.body);
        
        if (data['status'] == 'Paid') {
          return EcoCashPaymentStatus(
            status: PaymentStatus.completed,
            transactionId: data['paynowreference'],
            message: 'Payment completed successfully',
          );
        } else if (data['status'] == 'Cancelled') {
          return EcoCashPaymentStatus(
            status: PaymentStatus.cancelled,
            message: 'Payment was cancelled',
          );
        } else {
          return EcoCashPaymentStatus(
            status: PaymentStatus.pending,
            message: 'Payment is pending. Please complete on your phone.',
          );
        }
      } else {
        return EcoCashPaymentStatus(
          status: PaymentStatus.pending,
          message: 'Unable to check payment status',
        );
      }
    } catch (e) {
      return EcoCashPaymentStatus(
        status: PaymentStatus.pending,
        message: 'Error checking status: ${e.toString()}',
      );
    }
  }

  /// Process EcoCash payment for a ride
  /// 
  /// This integrates with the existing payment service
  Future<PaymentModel> processEcoCashPayment({
    required String rideId,
    required double amount,
    required String phoneNumber,
    String? paymentMethodId,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Generate unique reference
      final reference = 'BOLTLOG_${DateTime.now().millisecondsSinceEpoch}';

      // Create payment record first
      final payment = PaymentModel(
        userId: user.uid,
        rideId: rideId,
        amount: amount,
        paymentMethod: PaymentMethodType.mobileMoney,
        status: PaymentStatus.pending,
        createdAt: DateTime.now(),
      );

      final paymentRef = await _firestore.collection('payments').add(payment.toMap());
      final paymentId = paymentRef.id;

      // Initiate EcoCash payment
      final result = await initiatePayment(
        phoneNumber: phoneNumber,
        amount: amount,
        reference: reference,
        description: 'Boltlog Delivery - Ride $rideId',
      );

      if (!result.success) {
        // Update payment as failed
        await paymentRef.update({
          'status': PaymentStatus.failed.toString().split('.').last,
          'failureReason': result.message,
        });

        throw Exception(result.message);
      }

      // Update payment with poll URL for status checking
      await paymentRef.update({
        'transactionId': reference,
        'pollUrl': result.pollUrl,
        'status': PaymentStatus.processing.toString().split('.').last,
      });

      // Start polling for payment status (in background)
      _pollPaymentStatus(paymentId, result.pollUrl!);

      // Update ride with payment info
      await _firestore.collection('rides').doc(rideId).update({
        'paymentId': paymentId,
        'paymentStatus': PaymentStatus.processing.toString().split('.').last,
        'paymentMethod': 'mobileMoney',
        'ecocashReference': reference,
      });

      return PaymentModel(
        id: paymentId,
        userId: user.uid,
        rideId: rideId,
        amount: amount,
        paymentMethod: PaymentMethodType.mobileMoney,
        status: PaymentStatus.processing,
        transactionId: reference,
        createdAt: payment.createdAt,
      );
    } catch (e) {
      throw Exception('Error processing EcoCash payment: $e');
    }
  }

  /// Poll payment status in background
  Future<void> _pollPaymentStatus(String paymentId, String pollUrl) async {
    int attempts = 0;
    const maxAttempts = 60; // Poll for 5 minutes (5 second intervals)

    while (attempts < maxAttempts) {
      await Future.delayed(const Duration(seconds: 5));

      try {
        final status = await checkPaymentStatus(pollUrl);

        final paymentRef = _firestore.collection('payments').doc(paymentId);
        
        if (status.status == PaymentStatus.completed) {
          await paymentRef.update({
            'status': PaymentStatus.completed.toString().split('.').last,
            'completedAt': DateTime.now().toIso8601String(),
            'transactionId': status.transactionId,
          });

          // Update ride payment status
          final paymentDoc = await paymentRef.get();
          final rideId = paymentDoc.data()?['rideId'] as String?;
          if (rideId != null) {
            await _firestore.collection('rides').doc(rideId).update({
              'paymentStatus': PaymentStatus.completed.toString().split('.').last,
            });
          }

          break; // Stop polling
        } else if (status.status == PaymentStatus.cancelled) {
          await paymentRef.update({
            'status': PaymentStatus.cancelled.toString().split('.').last,
            'failureReason': status.message,
          });
          break; // Stop polling
        }

        attempts++;
      } catch (e) {
        // Continue polling on error
        attempts++;
      }
    }

    // If max attempts reached and still pending, mark as timeout
    if (attempts >= maxAttempts) {
      final paymentRef = _firestore.collection('payments').doc(paymentId);
      final paymentDoc = await paymentRef.get();
      if (paymentDoc.exists) {
        final currentStatus = paymentDoc.data()?['status'] as String?;
        if (currentStatus == PaymentStatus.processing.toString().split('.').last) {
          await paymentRef.update({
            'status': PaymentStatus.failed.toString().split('.').last,
            'failureReason': 'Payment timeout - no response received',
          });
        }
      }
    }
  }

  /// Normalize phone number to EcoCash format
  String _normalizePhoneNumber(String phone) {
    String normalized = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    
    if (normalized.startsWith('+263')) {
      normalized = normalized.substring(4);
    } else if (normalized.startsWith('263')) {
      normalized = normalized.substring(3);
    } else if (normalized.startsWith('0')) {
      normalized = normalized.substring(1);
    }
    
    return normalized;
  }

  /// Validate if number is EcoCash compatible
  /// EcoCash works on NetOne and Econet networks
  bool _isValidEcoCashNumber(String phone) {
    // EcoCash numbers start with 071, 073, 077 (Econet) or 078 (NetOne)
    final ecoCashPattern = RegExp(r'^(071|073|077|078)\d{7}$');
    return ecoCashPattern.hasMatch(phone);
  }

  /// Create MD5 hash for Paynow
  String _createHash(String input) {
    final bytes = utf8.encode(input);
    final digest = md5.convert(bytes);
    return digest.toString().toUpperCase();
  }

  /// Parse Paynow response
  Map<String, String> _parsePaynowResponse(String response) {
    final Map<String, String> result = {};
    final lines = response.split('\n');
    
    for (var line in lines) {
      final parts = line.split('=');
      if (parts.length == 2) {
        result[parts[0].trim()] = Uri.decodeComponent(parts[1].trim());
      }
    }
    
    return result;
  }
}

/// EcoCash Payment Result
class EcoCashPaymentResult {
  final bool success;
  final String? pollUrl; // URL to poll for payment status
  final String reference;
  final String message;
  final String? paymentUrl; // For web-based payment redirect

  EcoCashPaymentResult({
    required this.success,
    this.pollUrl,
    required this.reference,
    required this.message,
    this.paymentUrl,
  });
}

/// EcoCash Payment Status
class EcoCashPaymentStatus {
  final PaymentStatus status;
  final String? transactionId;
  final String message;

  EcoCashPaymentStatus({
    required this.status,
    this.transactionId,
    required this.message,
  });
}

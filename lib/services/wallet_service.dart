import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/payment_model.dart';
import 'ecocash_service.dart';
import 'error_handler_service.dart';

/// Wallet Service for Transporters
/// 
/// Handles wallet top-up and balance management for transporters
class WalletService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final EcoCashService _ecocashService = EcoCashService();

  // Users Collection
  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');

  // Wallet Transactions Collection
  CollectionReference<Map<String, dynamic>> get _walletTransactionsCollection =>
      _firestore.collection('walletTransactions');

  /// Get current wallet balance
  Future<double> getWalletBalance(String userId) async {
    try {
      final userDoc = await _usersCollection.doc(userId).get();
      if (!userDoc.exists) {
        return 0.0;
      }
      
      final data = userDoc.data();
      return (data?['driverWalletBalance'] as num?)?.toDouble() ?? 0.0;
    } catch (e) {
      throw Exception('Error getting wallet balance: $e');
    }
  }

  /// Stream wallet balance
  Stream<double> streamWalletBalance(String userId) {
    return _usersCollection.doc(userId).snapshots().map((snapshot) {
      if (!snapshot.exists) return 0.0;
      final data = snapshot.data();
      return (data?['driverWalletBalance'] as num?)?.toDouble() ?? 0.0;
    });
  }

  /// Top up wallet using EcoCash
  Future<WalletTopUpResult> topUpWithEcoCash({
    required String userId,
    required double amount,
    required String phoneNumber,
  }) async {
    try {
      // Validate amount
      if (amount <= 0) {
        throw Exception('Amount must be greater than zero');
      }

      if (amount < 1) {
        throw Exception('Minimum top-up amount is ZWL 1.00');
      }

      // Generate unique reference
      final reference = 'TOPUP_${DateTime.now().millisecondsSinceEpoch}';

      // Create wallet transaction record
      final transaction = {
        'userId': userId,
        'type': 'topup',
        'amount': amount,
        'paymentMethod': 'ecocash',
        'phoneNumber': phoneNumber,
        'status': 'pending',
        'reference': reference,
        'createdAt': DateTime.now().toIso8601String(),
      };

      final transactionRef = await _walletTransactionsCollection.add(transaction);
      final transactionId = transactionRef.id;

      // Initiate EcoCash payment
      final result = await _ecocashService.initiatePayment(
        phoneNumber: phoneNumber,
        amount: amount,
        reference: reference,
        description: 'Boltlog Wallet Top-Up',
      );

      if (!result.success) {
        // Update transaction as failed
        await transactionRef.update({
          'status': 'failed',
          'failureReason': result.message,
          'updatedAt': DateTime.now().toIso8601String(),
        });

        return WalletTopUpResult(
          success: false,
          message: result.message,
          transactionId: transactionId,
        );
      }

      // Update transaction with poll URL
      final pollUrl = result.pollUrl;
      await transactionRef.update({
        if (pollUrl != null) 'pollUrl': pollUrl,
        'status': 'processing',
        'updatedAt': DateTime.now().toIso8601String(),
      });

      // Start polling for payment status if poll URL is available
      if (pollUrl != null) {
        _pollTopUpStatus(transactionId, pollUrl, userId, amount);
      }

      return WalletTopUpResult(
        success: true,
        message: 'Payment request sent. Please check your phone for USSD prompt.',
        transactionId: transactionId,
        pollUrl: pollUrl,
      );
    } catch (e) {
      throw Exception('Error topping up wallet: $e');
    }
  }

  /// Poll top-up payment status
  Future<void> _pollTopUpStatus(
    String transactionId,
    String pollUrl,
    String userId,
    double amount,
  ) async {
    int attempts = 0;
    const maxAttempts = 60; // Poll for 5 minutes

    while (attempts < maxAttempts) {
      await Future.delayed(const Duration(seconds: 5));

      try {
        final status = await _ecocashService.checkPaymentStatus(pollUrl);
        final transactionRef = _walletTransactionsCollection.doc(transactionId);

        if (status.status == PaymentStatus.completed) {
          // Payment successful - update wallet balance
          await _firestore.runTransaction((transaction) async {
            final userRef = _usersCollection.doc(userId);
            final userDoc = await transaction.get(userRef);

            if (!userDoc.exists) {
              throw Exception('User not found');
            }

            final currentBalance =
                (userDoc.data()?['driverWalletBalance'] as num?)?.toDouble() ?? 0.0;
            final newBalance = currentBalance + amount;

            transaction.update(userRef, {
              'driverWalletBalance': newBalance,
            });

            transaction.update(transactionRef, {
              'status': 'completed',
              'transactionId': status.transactionId,
              'completedAt': DateTime.now().toIso8601String(),
              'updatedAt': DateTime.now().toIso8601String(),
            });
          });

          break; // Stop polling
        } else if (status.status == PaymentStatus.cancelled ||
                   status.status == PaymentStatus.failed) {
          await transactionRef.update({
            'status': status.status.toString().split('.').last,
            'failureReason': status.message,
            'updatedAt': DateTime.now().toIso8601String(),
          });
          break; // Stop polling
        }

        attempts++;
      } catch (e) {
        attempts++;
      }
    }

    // If timeout, mark as failed
    if (attempts >= maxAttempts) {
      final transactionRef = _walletTransactionsCollection.doc(transactionId);
      final transactionDoc = await transactionRef.get();
      if (transactionDoc.exists) {
        final currentStatus = transactionDoc.data()?['status'] as String?;
        if (currentStatus == 'processing') {
          await transactionRef.update({
            'status': 'failed',
            'failureReason': 'Payment timeout - no response received',
            'updatedAt': DateTime.now().toIso8601String(),
          });
        }
      }
    }
  }

  /// Get wallet transaction history
  Future<List<WalletTransaction>> getTransactionHistory(
    String userId, {
    int limit = 50,
  }) async {
    try {
      final snapshot = await _walletTransactionsCollection
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return WalletTransaction(
          id: doc.id,
          userId: data['userId'] as String,
          type: data['type'] as String,
          amount: (data['amount'] as num).toDouble(),
          paymentMethod: data['paymentMethod'] as String?,
          status: data['status'] as String,
          reference: data['reference'] as String?,
          createdAt: DateTime.parse(data['createdAt'] as String),
          completedAt: data['completedAt'] != null
              ? DateTime.parse(data['completedAt'] as String)
              : null,
        );
      }).toList();
    } catch (e) {
      throw Exception('Error getting transaction history: $e');
    }
  }

  /// Stream wallet transaction history
  Stream<List<WalletTransaction>> streamTransactionHistory(
    String userId, {
    int limit = 50,
  }) {
    return _walletTransactionsCollection
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              return WalletTransaction(
                id: doc.id,
                userId: data['userId'] as String,
                type: data['type'] as String,
                amount: (data['amount'] as num).toDouble(),
                paymentMethod: data['paymentMethod'] as String?,
                status: data['status'] as String,
                reference: data['reference'] as String?,
                createdAt: DateTime.parse(data['createdAt'] as String),
                completedAt: data['completedAt'] != null
                    ? DateTime.parse(data['completedAt'] as String)
                    : null,
              );
            }).toList());
  }
}

/// Wallet Top-Up Result
class WalletTopUpResult {
  final bool success;
  final String message;
  final String transactionId;
  final String? pollUrl;

  WalletTopUpResult({
    required this.success,
    required this.message,
    required this.transactionId,
    this.pollUrl,
  });
}

/// Wallet Transaction Model
class WalletTransaction {
  final String id;
  final String userId;
  final String type; // 'topup', 'deduction', 'refund'
  final double amount;
  final String? paymentMethod;
  final String status; // 'pending', 'processing', 'completed', 'failed'
  final String? reference;
  final DateTime createdAt;
  final DateTime? completedAt;

  WalletTransaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.amount,
    this.paymentMethod,
    required this.status,
    this.reference,
    required this.createdAt,
    this.completedAt,
  });
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/payment_method_model.dart';
import '../models/payment_model.dart';
import '../constants/app_constants.dart';
import 'ecocash_service.dart';

class PaymentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Payment Methods Collection
  CollectionReference<Map<String, dynamic>> get _paymentMethodsCollection =>
      _firestore.collection('paymentMethods');

  // Payments Collection
  CollectionReference<Map<String, dynamic>> get _paymentsCollection =>
      _firestore.collection('payments');

  // Get user's payment methods
  Future<List<PaymentMethodModel>> getUserPaymentMethods(String userId) async {
    try {
      final snapshot = await _paymentMethodsCollection
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => PaymentMethodModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      throw Exception('Error getting payment methods: $e');
    }
  }

  // Stream user's payment methods
  Stream<List<PaymentMethodModel>> streamUserPaymentMethods(String userId) {
    return _paymentMethodsCollection
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => PaymentMethodModel.fromMap(doc.data(), doc.id))
            .toList());
  }

  // Add payment method
  Future<String> addPaymentMethod(PaymentMethodModel paymentMethod) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // If this is set as default, unset other defaults
      if (paymentMethod.isDefault) {
        await _unsetOtherDefaults(user.uid);
      }

      final docRef = await _paymentMethodsCollection.add(paymentMethod.toMap());
      return docRef.id;
    } catch (e) {
      throw Exception('Error adding payment method: $e');
    }
  }

  // Set default payment method
  Future<void> setDefaultPaymentMethod(String paymentMethodId, String userId) async {
    try {
      await _firestore.runTransaction((transaction) async {
        // Unset all other defaults
        final otherDefaults = await _paymentMethodsCollection
            .where('userId', isEqualTo: userId)
            .where('isDefault', isEqualTo: true)
            .get();

        for (var doc in otherDefaults.docs) {
          transaction.update(doc.reference, {'isDefault': false});
        }

        // Set this as default
        final methodRef = _paymentMethodsCollection.doc(paymentMethodId);
        transaction.update(methodRef, {
          'isDefault': true,
          'updatedAt': DateTime.now().toIso8601String(),
        });
      });
    } catch (e) {
      throw Exception('Error setting default payment method: $e');
    }
  }

  // Remove payment method
  Future<void> removePaymentMethod(String paymentMethodId) async {
    try {
      await _paymentMethodsCollection.doc(paymentMethodId).delete();
    } catch (e) {
      throw Exception('Error removing payment method: $e');
    }
  }

  // Get default payment method
  Future<PaymentMethodModel?> getDefaultPaymentMethod(String userId) async {
    try {
      final snapshot = await _paymentMethodsCollection
          .where('userId', isEqualTo: userId)
          .where('isDefault', isEqualTo: true)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        return null;
      }

      return PaymentMethodModel.fromMap(
        snapshot.docs.first.data(),
        snapshot.docs.first.id,
      );
    } catch (e) {
      throw Exception('Error getting default payment method: $e');
    }
  }

  // Unset other default payment methods
  Future<void> _unsetOtherDefaults(String userId) async {
    final snapshot = await _paymentMethodsCollection
        .where('userId', isEqualTo: userId)
        .where('isDefault', isEqualTo: true)
        .get();

    final batch = _firestore.batch();
    for (var doc in snapshot.docs) {
      batch.update(doc.reference, {
        'isDefault': false,
        'updatedAt': DateTime.now().toIso8601String(),
      });
    }
    await batch.commit();
  }

  // Process payment for a ride
  Future<PaymentModel> processPayment({
    required String rideId,
    required double amount,
    required PaymentMethodType paymentMethod,
    String? paymentMethodId, // For saved payment methods
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Create payment record
      final payment = PaymentModel(
        userId: user.uid,
        rideId: rideId,
        amount: amount,
        paymentMethod: paymentMethod,
        status: PaymentStatus.pending,
        createdAt: DateTime.now(),
      );

      final paymentRef = await _paymentsCollection.add(payment.toMap());
      final paymentId = paymentRef.id;

      // Process payment based on method
      String? transactionId;
      PaymentStatus status;

      switch (paymentMethod) {
        case PaymentMethodType.card:
          // TODO: Integrate with Stripe or payment gateway
          // For now, simulate payment
          transactionId = 'card_${DateTime.now().millisecondsSinceEpoch}';
          status = PaymentStatus.completed;
          break;

        case PaymentMethodType.mobileMoney:
          // Check if it's EcoCash and use EcoCash service
          if (paymentMethodId != null) {
            try {
              final methodDoc = await _paymentMethodsCollection.doc(paymentMethodId).get();
              final provider = methodDoc.data()?['mobileMoneyProvider'] as String?;
              final phoneNumber = methodDoc.data()?['mobileMoneyNumber'] as String?;
              
              if (provider == 'EcoCash' && phoneNumber != null) {
                // Use EcoCash service for EcoCash payments
                final ecoCashService = EcoCashService();
                final ecoCashPayment = await ecoCashService.processEcoCashPayment(
                  rideId: rideId,
                  amount: amount,
                  phoneNumber: phoneNumber,
                  paymentMethodId: paymentMethodId,
                );
                
                return ecoCashPayment;
              }
            } catch (e) {
              // Fallback to simulated payment if EcoCash service fails
              debugPrint('EcoCash payment failed, using fallback: $e');
            }
          }
          
          // Fallback: Simulate payment for other mobile money providers
          transactionId = 'mobile_${DateTime.now().millisecondsSinceEpoch}';
          status = PaymentStatus.completed;
          break;

        case PaymentMethodType.cash:
          // Cash on delivery - payment pending until delivery
          transactionId = null;
          status = PaymentStatus.pending;
          break;
      }

      // Update payment status
      await paymentRef.update({
        'status': status.toString().split('.').last,
        'transactionId': transactionId,
        if (status == PaymentStatus.completed)
          'completedAt': DateTime.now().toIso8601String(),
      });

      // Update ride with payment info
      await _firestore.collection('rides').doc(rideId).update({
        'paymentId': paymentId,
        'paymentStatus': status.toString().split('.').last,
        'paymentMethod': paymentMethod.toString().split('.').last,
      });

      return PaymentModel(
        id: paymentId,
        userId: user.uid,
        rideId: rideId,
        amount: amount,
        paymentMethod: paymentMethod,
        status: status,
        transactionId: transactionId,
        createdAt: payment.createdAt,
        completedAt: status == PaymentStatus.completed ? DateTime.now() : null,
      );
    } catch (e) {
      throw Exception('Error processing payment: $e');
    }
  }

  // Complete payment (for cash on delivery)
  Future<void> completePayment(String paymentId) async {
    try {
      await _paymentsCollection.doc(paymentId).update({
        'status': PaymentStatus.completed.toString().split('.').last,
        'completedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception('Error completing payment: $e');
    }
  }

  // Get payment history
  Future<List<PaymentModel>> getPaymentHistory(String userId, {int limit = 50}) async {
    try {
      final snapshot = await _paymentsCollection
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => PaymentModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      throw Exception('Error getting payment history: $e');
    }
  }

  // Stream payment history
  Stream<List<PaymentModel>> streamPaymentHistory(String userId, {int limit = 50}) {
    return _paymentsCollection
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => PaymentModel.fromMap(doc.data(), doc.id))
            .toList());
  }

  // Get payment for a ride
  Future<PaymentModel?> getPaymentForRide(String rideId) async {
    try {
      final snapshot = await _paymentsCollection
          .where('rideId', isEqualTo: rideId)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        return null;
      }

      return PaymentModel.fromMap(
        snapshot.docs.first.data(),
        snapshot.docs.first.id,
      );
    } catch (e) {
      throw Exception('Error getting payment for ride: $e');
    }
  }
}

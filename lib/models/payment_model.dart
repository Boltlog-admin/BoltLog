import 'payment_method_model.dart';

class PaymentModel {
  final String? id;
  final String userId;
  final String rideId;
  final double amount;
  final PaymentMethodType paymentMethod;
  final PaymentStatus status;
  final String? transactionId; // From payment gateway
  final String? failureReason;
  final DateTime createdAt;
  final DateTime? completedAt;

  PaymentModel({
    this.id,
    required this.userId,
    required this.rideId,
    required this.amount,
    required this.paymentMethod,
    required this.status,
    this.transactionId,
    this.failureReason,
    required this.createdAt,
    this.completedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'rideId': rideId,
      'amount': amount,
      'paymentMethod': paymentMethod.toString().split('.').last,
      'status': status.toString().split('.').last,
      'transactionId': transactionId,
      'failureReason': failureReason,
      'createdAt': createdAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
    };
  }

  factory PaymentModel.fromMap(Map<String, dynamic> map, String id) {
    return PaymentModel(
      id: id,
      userId: map['userId'] as String,
      rideId: map['rideId'] as String,
      amount: (map['amount'] as num).toDouble(),
      paymentMethod: PaymentMethodType.values.firstWhere(
        (e) => e.toString().split('.').last == map['paymentMethod'],
        orElse: () => PaymentMethodType.cash,
      ),
      status: PaymentStatus.values.firstWhere(
        (e) => e.toString().split('.').last == map['status'],
        orElse: () => PaymentStatus.pending,
      ),
      transactionId: map['transactionId'] as String?,
      failureReason: map['failureReason'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      completedAt: map['completedAt'] != null
          ? DateTime.parse(map['completedAt'] as String)
          : null,
    );
  }
}

enum PaymentStatus {
  pending,      // Payment initiated but not completed
  processing,   // Payment being processed
  completed,    // Payment successful
  failed,       // Payment failed
  refunded,     // Payment refunded
  cancelled,    // Payment cancelled
}

class PaymentMethodModel {
  final String? id;
  final String userId;
  final PaymentMethodType type;
  final String? cardLast4; // For cards
  final String? cardBrand; // Visa, Mastercard, etc.
  final String? mobileMoneyNumber; // For mobile money
  final String? mobileMoneyProvider; // EcoCash, M-Pesa, etc.
  final bool isDefault;
  final DateTime createdAt;
  final DateTime? updatedAt;

  PaymentMethodModel({
    this.id,
    required this.userId,
    required this.type,
    this.cardLast4,
    this.cardBrand,
    this.mobileMoneyNumber,
    this.mobileMoneyProvider,
    this.isDefault = false,
    required this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'type': type.toString().split('.').last,
      'cardLast4': cardLast4,
      'cardBrand': cardBrand,
      'mobileMoneyNumber': mobileMoneyNumber,
      'mobileMoneyProvider': mobileMoneyProvider,
      'isDefault': isDefault,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory PaymentMethodModel.fromMap(Map<String, dynamic> map, String id) {
    return PaymentMethodModel(
      id: id,
      userId: map['userId'] as String,
      type: PaymentMethodType.values.firstWhere(
        (e) => e.toString().split('.').last == map['type'],
        orElse: () => PaymentMethodType.cash,
      ),
      cardLast4: map['cardLast4'] as String?,
      cardBrand: map['cardBrand'] as String?,
      mobileMoneyNumber: map['mobileMoneyNumber'] as String?,
      mobileMoneyProvider: map['mobileMoneyProvider'] as String?,
      isDefault: map['isDefault'] as bool? ?? false,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: map['updatedAt'] != null 
          ? DateTime.parse(map['updatedAt'] as String)
          : null,
    );
  }

  String get displayName {
    switch (type) {
      case PaymentMethodType.card:
        return '${cardBrand ?? 'Card'} •••• ${cardLast4 ?? ''}';
      case PaymentMethodType.mobileMoney:
        return '${mobileMoneyProvider ?? 'Mobile Money'} • ${mobileMoneyNumber ?? ''}';
      case PaymentMethodType.cash:
        return 'Cash on Delivery';
      default:
        return 'Unknown';
    }
  }

  String get icon {
    switch (type) {
      case PaymentMethodType.card:
        return 'credit_card';
      case PaymentMethodType.mobileMoney:
        return 'account_balance_wallet';
      case PaymentMethodType.cash:
        return 'money';
      default:
        return 'payment';
    }
  }
}

enum PaymentMethodType {
  card,
  mobileMoney,
  cash,
}

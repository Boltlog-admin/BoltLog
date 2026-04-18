class TransporterOfferModel {
  final String id;
  final String rideId;
  final String transporterId;
  final double? priceOffer;
  final String status; // 'pending', 'selected', 'rejected'
  final DateTime createdAt;
  final DateTime? updatedAt;

  TransporterOfferModel({
    required this.id,
    required this.rideId,
    required this.transporterId,
    this.priceOffer,
    this.status = 'pending',
    required this.createdAt,
    this.updatedAt,
  });

  factory TransporterOfferModel.fromMap(
      Map<String, dynamic> map, String id) {
    return TransporterOfferModel(
      id: id,
      rideId: map['rideId'] ?? '',
      transporterId: map['transporterId'] ?? '',
      priceOffer: map['priceOffer'] != null
          ? (map['priceOffer'] as num).toDouble()
          : null,
      status: map['status'] ?? 'pending',
      createdAt: DateTime.parse(
          map['createdAt'] ?? DateTime.now().toIso8601String()),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'])
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'rideId': rideId,
      'transporterId': transporterId,
      'priceOffer': priceOffer,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}


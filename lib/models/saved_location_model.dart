class SavedLocationModel {
  final String? id;
  final String userId;
  final String name; // e.g., "Home", "Work"
  final String address;
  final double latitude;
  final double longitude;
  final DateTime createdAt;

  SavedLocationModel({
    this.id,
    required this.userId,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'name': name,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory SavedLocationModel.fromMap(Map<String, dynamic> map, String id) {
    return SavedLocationModel(
      id: id,
      userId: map['userId'] ?? '',
      name: map['name'] ?? '',
      address: map['address'] ?? '',
      latitude: map['latitude']?.toDouble() ?? 0.0,
      longitude: map['longitude']?.toDouble() ?? 0.0,
      createdAt: DateTime.parse(map['createdAt'] ?? DateTime.now().toIso8601String()),
    );
  }
}


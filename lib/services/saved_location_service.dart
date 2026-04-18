import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/saved_location_model.dart';

class SavedLocationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Save a location
  Future<String> saveLocation(SavedLocationModel location) async {
    try {
      final docRef = await _firestore.collection('savedLocations').add(location.toMap());
      return docRef.id;
    } catch (e) {
      throw Exception('Error saving location: $e');
    }
  }

  // Get user's saved locations with pagination
  Stream<List<SavedLocationModel>> streamSavedLocations(String userId, {int limit = 20}) {
    return _firestore
        .collection('savedLocations')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => SavedLocationModel.fromMap(doc.data(), doc.id))
            .toList());
  }

  // Delete saved location
  Future<void> deleteLocation(String locationId) async {
    try {
      await _firestore.collection('savedLocations').doc(locationId).delete();
    } catch (e) {
      throw Exception('Error deleting location: $e');
    }
  }
}


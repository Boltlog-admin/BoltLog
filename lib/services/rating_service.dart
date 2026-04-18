import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/rating_model.dart';

class RatingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Submit a rating
  Future<String> submitRating(RatingModel rating) async {
    try {
      final docRef = await _firestore.collection('ratings').add(rating.toMap());
      return docRef.id;
    } catch (e) {
      throw Exception('Error submitting rating: $e');
    }
  }

  // Get ratings for a user with pagination
  Stream<List<RatingModel>> streamUserRatings(String userId, {int limit = 50}) {
    return _firestore
        .collection('ratings')
        .where('toUserId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => RatingModel.fromMap(doc.data(), doc.id))
            .toList());
  }

  // Get average rating for a user
  Future<double> getAverageRating(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('ratings')
          .where('toUserId', isEqualTo: userId)
          .get();

      if (snapshot.docs.isEmpty) return 0.0;

      double total = 0;
      for (var doc in snapshot.docs) {
        total += (doc.data()['rating'] as int).toDouble();
      }
      return total / snapshot.docs.length;
    } catch (e) {
      throw Exception('Error getting average rating: $e');
    }
  }

  // Check if user already rated this ride
  Future<bool> hasRated(String rideId, String fromUserId) async {
    try {
      final snapshot = await _firestore
          .collection('ratings')
          .where('rideId', isEqualTo: rideId)
          .where('fromUserId', isEqualTo: fromUserId)
          .get();
      return snapshot.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
}


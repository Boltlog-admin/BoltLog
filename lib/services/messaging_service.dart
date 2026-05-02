import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/message_model.dart';

/// Result of a messages stream update; includes cache metadata for offline UX.
class MessagesSnapshot {
  final List<MessageModel> messages;
  final bool isFromCache;

  MessagesSnapshot(this.messages, this.isFromCache);
}

class MessagingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Send a message (queued when offline; syncs when back online)
  Future<String> sendMessage(MessageModel message) async {
    try {
      final docRef = await _firestore
          .collection('rides')
          .doc(message.rideId)
          .collection('messages')
          .add(message.toMap());
      return docRef.id;
    } catch (e) {
      throw Exception('Error sending message: $e');
    }
  }

  /// Sender declined this transporter's offer/counter-offer; request is open again.
  /// Visible in ride chat for both parties.
  Future<String> sendSenderDeclinedServiceMessage({
    required String rideId,
    required String senderId,
    required String transporterId,
  }) async {
    final message = MessageModel(
      rideId: rideId,
      senderId: senderId,
      receiverId: transporterId,
      message:
          'Service update: the sender has declined this offer. The request is open again for other transporters.',
      timestamp: DateTime.now(),
      isRead: false,
    );
    return sendMessage(message);
  }

  /// Transporter declined the request; sender sees this in chat.
  Future<String> sendTransporterDeclinedServiceMessage({
    required String rideId,
    required String transporterId,
    required String senderId,
  }) async {
    final message = MessageModel(
      rideId: rideId,
      senderId: transporterId,
      receiverId: senderId,
      message:
          'Service update: I have declined this request. It is open again for other transporters.',
      timestamp: DateTime.now(),
      isRead: false,
    );
    return sendMessage(message);
  }

  /// Sends a persistent chat message when a transporter is selected for a delivery.
  /// Both sender and transporter see it in the ride chat.
  Future<String> sendTransporterSelectedMessage({
    required String rideId,
    required String senderId,
    required String transporterId,
  }) async {
    final message = MessageModel(
      rideId: rideId,
      senderId: senderId,
      receiverId: transporterId,
      message: 'A transporter has been selected for this delivery. You can chat here to coordinate pickup.',
      timestamp: DateTime.now(),
      isRead: false,
    );
    return sendMessage(message);
  }

  /// Transporter-side service message after pressing Accept while waiting
  /// for sender confirmation. Uses transporter as sender to satisfy rules.
  Future<String> sendTransporterAwaitingSenderMessage({
    required String rideId,
    required String senderId,
    required String transporterId,
  }) async {
    final message = MessageModel(
      rideId: rideId,
      senderId: transporterId,
      receiverId: senderId,
      message:
          'Service update: I accepted this request. Please confirm to start the live map and trip.',
      timestamp: DateTime.now(),
      isRead: false,
    );
    return sendMessage(message);
  }

  // Stream messages with cache metadata so UI can show offline/syncing state
  Stream<MessagesSnapshot> streamMessages(String rideId, {int limit = 100}) {
    return _firestore
        .collection('rides')
        .doc(rideId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .limitToLast(limit)
        .snapshots()
        .map((snapshot) {
      final messages = snapshot.docs
          .map((doc) => MessageModel.fromMap(doc.data(), doc.id))
          .toList();
      return MessagesSnapshot(messages, snapshot.metadata.isFromCache);
    });
  }

  // Mark message as read
  Future<void> markAsRead(String rideId, String messageId) async {
    try {
      await _firestore
          .collection('rides')
          .doc(rideId)
          .collection('messages')
          .doc(messageId)
          .update({'isRead': true});
    } catch (e) {
      throw Exception('Error marking message as read: $e');
    }
  }
}


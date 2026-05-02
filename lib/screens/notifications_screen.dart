import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/ride_model.dart';
import 'request_detail_screen.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1E40AF)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Notifications',
          style: GoogleFonts.inter(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E40AF),
          ),
        ),
        actions: [
          if (user != null)
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('notifications')
                  .where('userId', isEqualTo: user.uid)
                  .where('isRead', isEqualTo: false)
                  .snapshots(),
              builder: (context, snapshot) {
                final unreadCount = snapshot.data?.docs.length ?? 0;
                if (unreadCount == 0) return const SizedBox.shrink();
                
                return TextButton(
                  onPressed: () async {
                    // Mark all as read
                    final unreadDocs = snapshot.data?.docs ?? [];
                    final batch = FirebaseFirestore.instance.batch();
                    for (var doc in unreadDocs) {
                      batch.update(doc.reference, {'isRead': true});
                    }
                    await batch.commit();
                  },
                  child: Text(
                    'Mark all read',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF2563EB),
                      fontSize: 14,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: user == null
          ? const Center(child: Text('Please log in'))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('notifications')
                  .where('userId', isEqualTo: user.uid)
                  .orderBy('createdAt', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: GoogleFonts.inter(color: Colors.red),
                    ),
                  );
                }

                final notifications = snapshot.data?.docs ?? [];

                if (notifications.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.notifications_none,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No notifications',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'You\'ll see notifications here',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: notifications.length,
                  itemBuilder: (context, index) {
                    final doc = notifications[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final isRead = data['isRead'] as bool? ?? false;
                    final type = data['type'] as String? ?? 'general';
                    final title = data['title'] as String? ?? 'Notification';
                    final message = data['message'] as String? ?? '';
                    final createdAt = data['createdAt'] as String?;
                    final rideId = data['rideId'] as String?;

                    DateTime? dateTime;
                    if (createdAt != null) {
                      try {
                        dateTime = DateTime.parse(createdAt);
                      } catch (_) {}
                    }

                    IconData icon;
                    Color iconColor;
                    switch (type) {
                      case 'delivery_accepted':
                        icon = Icons.check_circle;
                        iconColor = Colors.green;
                        break;
                      case 'delivery_completed':
                        icon = Icons.local_shipping;
                        iconColor = Colors.blue;
                        break;
                      case 'message':
                        icon = Icons.message;
                        iconColor = Colors.orange;
                        break;
                      case 'offer':
                        icon = Icons.attach_money;
                        iconColor = Colors.purple;
                        break;
                      default:
                        icon = Icons.notifications;
                        iconColor = Colors.grey;
                    }

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: isRead ? 1 : 2,
                      color: isRead ? Colors.white : const Color(0xFF2563EB).withOpacity(0.05),
                      child: InkWell(
                        onTap: () async {
                          // Mark as read
                          if (!isRead) {
                            await doc.reference.update({'isRead': true});
                          }

                          // Navigate to relevant screen if rideId exists
                          if (rideId != null && context.mounted) {
                            // Fetch ride data first
                            final rideDoc = await FirebaseFirestore.instance
                                .collection('rides')
                                .doc(rideId)
                                .get();
                            
                            if (rideDoc.exists && context.mounted) {
                              final ride = RideModel.fromMap(
                                rideDoc.data()!,
                                rideDoc.id,
                              );
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => RequestDetailScreen(ride: ride),
                                ),
                              );
                            }
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: iconColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(icon, color: iconColor, size: 24),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            title,
                                            style: GoogleFonts.inter(
                                              fontSize: 16,
                                              fontWeight: isRead
                                                  ? FontWeight.w500
                                                  : FontWeight.bold,
                                              color: const Color(0xFF1E40AF),
                                            ),
                                          ),
                                        ),
                                        if (!isRead)
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: const BoxDecoration(
                                              color: Color(0xFF2563EB),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                      ],
                                    ),
                                    if (message.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        message,
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                    if (dateTime != null) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        _formatDate(dateTime),
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'Just now';
        }
        return '${difference.inMinutes}m ago';
      }
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

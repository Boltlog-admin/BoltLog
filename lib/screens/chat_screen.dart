import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/message_model.dart';
import '../models/ride_model.dart';
import '../services/app_resume_service.dart';
import '../services/messaging_service.dart';
import '../services/ride_service.dart';

class ChatScreen extends StatefulWidget {
  final RideModel ride;

  const ChatScreen({super.key, required this.ride});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final MessagingService _messagingService = MessagingService();
  final RideService _rideService = RideService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late Stream<MessagesSnapshot> _messageStream;

  @override
  void initState() {
    super.initState();
    _messageStream = _messagingService.streamMessages(widget.ride.id!);
    if (widget.ride.id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AppResumeService.instance.saveRideScreen(
          ride: widget.ride,
          screen: AppResumeService.screenChat,
        );
      });
    }
  }

  void _retryStream() {
    setState(() {
      _messageStream = _messagingService.streamMessages(widget.ride.id!);
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(RideModel currentRide) async {
    if (_messageController.text.trim().isEmpty) return;

    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    // Sender: driver, accepted transporter, or active negotiation (pending/open).
    final receiverId = currentUser.uid == currentRide.userId
        ? (currentRide.driverId ??
            currentRide.acceptedTransporterId ??
            currentRide.negotiatingTransporterId)
        : currentRide.userId;

    if (receiverId == null || receiverId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No transporter to message yet. Open this chat again once someone engages with your request.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final message = MessageModel(
      rideId: currentRide.id!,
      senderId: currentUser.uid,
      receiverId: receiverId,
      message: _messageController.text.trim(),
      timestamp: DateTime.now(),
    );

    try {
      await _messagingService.sendMessage(message);
      _messageController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending message: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _auth.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1E40AF)), // Blue-700
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Chat',
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E40AF), // Blue-700
          ),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<RideModel?>(
          stream: widget.ride.id != null
              ? _rideService.streamRideById(widget.ride.id!)
              : Stream.value(widget.ride),
          builder: (context, rideSnap) {
            final currentRide = rideSnap.data ?? widget.ride;
            final amount = currentRide.finalPrice ??
                currentRide.counterOffer ??
                currentRide.price;
            final isNegotiating = currentRide.priceStatus == 'pending' &&
                (currentRide.counterOffer != null || currentRide.price != null);
            final isSender = currentUser?.uid == currentRide.userId;
            final transporterRecipient = currentRide.driverId ??
                currentRide.acceptedTransporterId ??
                currentRide.negotiatingTransporterId;
            final senderCanSend =
                !isSender || (transporterRecipient != null && transporterRecipient.trim().isNotEmpty);

            return Column(
              children: [
                // Live amount bar so sender and transporter see negotiated amount quickly
                if (amount != null && amount > 0)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isNegotiating
                          ? const Color(0xFF2563EB).withOpacity(0.08)
                          : Colors.green.shade50,
                      border: Border(
                        bottom: BorderSide(
                          color: isNegotiating
                              ? const Color(0xFF2563EB).withOpacity(0.2)
                              : Colors.green.shade100,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isNegotiating ? Icons.handshake : Icons.check_circle,
                          size: 20,
                          color: isNegotiating
                              ? const Color(0xFF2563EB)
                              : Colors.green.shade700,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            currentRide.priceStatus == 'accepted'
                                ? 'Agreed amount: \$${amount.toStringAsFixed(2)}'
                                : (currentRide.counterOffer != null
                                    ? 'Current offer: \$${amount.toStringAsFixed(2)}'
                                    : 'Amount: \$${amount.toStringAsFixed(2)}'),
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: isNegotiating
                                  ? const Color(0xFF1E40AF)
                                  : Colors.green.shade800,
                            ),
                          ),
                        ),
                        if (isNegotiating &&
                            currentRide.price != null &&
                            currentRide.counterOffer != null &&
                            currentRide.price != currentRide.counterOffer)
                          Text(
                            'Original: \$${currentRide.price!.toStringAsFixed(2)}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                  ),
                // Messages list (persists offline; syncs when back online)
                Expanded(
                  child: StreamBuilder<MessagesSnapshot>(
                    stream: _messageStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.cloud_off, size: 48, color: Colors.grey.shade600),
                                const SizedBox(height: 16),
                                Text(
                                  'Connection issue. Conversation will continue when back online.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                FilledButton.icon(
                                  onPressed: _retryStream,
                                  icon: const Icon(Icons.refresh, size: 20),
                                  label: const Text('Retry'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF2563EB),
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      final data = snapshot.data;
                      final messages = data?.messages ?? [];
                      final isFromCache = data?.isFromCache ?? false;

                      if (messages.isEmpty) {
                        return Center(
                          child: Text(
                            'No messages yet',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (isFromCache)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              color: Colors.amber.shade50,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.sync, size: 16, color: Colors.amber.shade800),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Offline – showing saved messages. Will sync when back online.',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: Colors.amber.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: messages.length,
                              itemBuilder: (context, index) {
                                final message = messages[index];
                                final isMe = message.senderId == currentUser?.uid;
                                final transporterId = currentRide.driverId ??
                                    currentRide.acceptedTransporterId ??
                                    currentRide.negotiatingTransporterId;
                                final isTransporter = transporterId != null && message.senderId == transporterId;

                                return Align(
                                  alignment: isMe
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      if (!isMe) ...[
                                        CircleAvatar(
                                          radius: 16,
                                          backgroundColor: isTransporter
                                              ? const Color(0xFF2563EB).withOpacity(0.1)
                                              : Colors.grey.shade200,
                                          child: Icon(
                                            isTransporter
                                                ? Icons.local_shipping
                                                : Icons.person,
                                            size: 18,
                                            color: isTransporter
                                                ? const Color(0xFF2563EB)
                                                : Colors.grey.shade700,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      Container(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        constraints: BoxConstraints(
                                          maxWidth:
                                              MediaQuery.of(context).size.width * 0.7,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isMe
                                              ? const Color(0xFF2563EB)
                                              : Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              message.message,
                                              style: GoogleFonts.inter(
                                                fontSize: 14,
                                                color: isMe
                                                    ? Colors.white
                                                    : const Color(0xFF1E40AF),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                                              style: GoogleFonts.inter(
                                                fontSize: 10,
                                                color: isMe
                                                    ? Colors.white70
                                                    : Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                // Message input (sender waiting for transporters: read-only until one engages)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!senderCanSend)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            'You can send messages once a transporter is connected to this request.',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              enabled: senderCanSend,
                              decoration: InputDecoration(
                                hintText: senderCanSend
                                    ? 'Type a message...'
                                    : 'Waiting for a transporter...',
                                hintStyle: GoogleFonts.inter(
                                  color: Colors.grey.shade400,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF2563EB),
                                    width: 2,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed:
                                senderCanSend ? () => _sendMessage(currentRide) : null,
                            icon: Icon(
                              Icons.send,
                              color: senderCanSend
                                  ? const Color(0xFF2563EB)
                                  : Colors.grey.shade400,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: senderCanSend
                                  ? const Color(0xFF2563EB).withOpacity(0.1)
                                  : Colors.grey.shade200,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}


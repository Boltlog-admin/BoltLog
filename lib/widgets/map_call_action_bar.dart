import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/ride_model.dart';
import '../models/user_model.dart';
import '../services/user_service.dart';
import '../utils/phone_launch_utils.dart';

/// Sits **below** the map: phone icon opens a sheet to call sender and/or transporter.
/// Does not overlay the map routing UI.
class MapCallActionBar extends StatelessWidget {
  final RideModel ride;

  const MapCallActionBar({
    super.key,
    required this.ride,
  });

  Future<void> _showCallSheet(BuildContext context) async {
    final userService = UserService();
    final sender = await userService.getUser(ride.userId);
    final transporterId = ride.driverId ?? ride.acceptedTransporterId;
    final transporter =
        transporterId != null ? await userService.getUser(transporterId) : null;

    if (!context.mounted) return;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.phone_in_talk, color: Colors.blue.shade700, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Call',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1E40AF),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose who to call. Rates may apply.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 16),
                _CallRow(
                  label: 'Sender',
                  icon: Icons.person,
                  user: sender,
                  selfUid: currentUserId,
                  onCall: () async {
                    final ok = await launchTel(sender?.phoneNumber);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('No phone number on file for sender.'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 8),
                _CallRow(
                  label: 'Transporter',
                  icon: Icons.local_shipping,
                  user: transporter,
                  selfUid: currentUserId,
                  onCall: () async {
                    final ok = await launchTel(transporter?.phoneNumber);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('No phone number on file for transporter.'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showCallSheet(context),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.phone_in_talk, color: Colors.blue.shade800, size: 22),
              const SizedBox(width: 10),
              Text(
                'Call sender or transporter',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1E40AF),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.keyboard_arrow_up, color: Colors.grey.shade600, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final UserModel? user;
  final String? selfUid;
  final VoidCallback onCall;

  const _CallRow({
    required this.label,
    required this.icon,
    required this.user,
    required this.selfUid,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          backgroundColor: Colors.grey.shade200,
          child: Icon(icon, color: Colors.grey.shade600, size: 22),
        ),
        title: Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        subtitle: Text(
          'Not available for this trip yet',
          style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
        ),
        trailing: FilledButton.tonalIcon(
          onPressed: null,
          icon: const Icon(Icons.phone, size: 18),
          label: const Text('Call'),
        ),
      );
    }

    final effective = user!;
    final uid = effective.uid;
    final isSelf = selfUid != null && uid == selfUid;
    final phone = effective.phoneNumber;
    final hasPhone = phone != null && phone.trim().isNotEmpty;
    final name = effective.displayName?.trim().isNotEmpty == true
        ? effective.displayName!
        : label;

    String subtitleText;
    if (isSelf) {
      subtitleText = "That's you";
    } else if (hasPhone) {
      subtitleText = phone;
    } else {
      subtitleText = 'No phone on profile';
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF2563EB).withValues(alpha: 0.12),
        child: Icon(icon, color: const Color(0xFF2563EB), size: 22),
      ),
      title: Text(
        name,
        style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      subtitle: Text(
        subtitleText,
        style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade700),
      ),
      trailing: FilledButton.tonalIcon(
        onPressed: (isSelf || !hasPhone) ? null : onCall,
        icon: const Icon(Icons.phone, size: 18),
        label: const Text('Call'),
      ),
    );
  }
}

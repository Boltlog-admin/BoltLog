import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'terms_of_service_screen.dart';
import 'privacy_policy_screen.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
          'Help & Support',
          style: GoogleFonts.inter(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E40AF),
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Contact Support
            Text(
              'Contact Support',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E40AF),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.email, color: Color(0xFF2563EB)),
                    title: Text(
                      'Email Support',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                    ),
                    subtitle: const Text('support@boltlog.com'),
                    trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                    onTap: () async {
                      final uri = Uri.parse('mailto:support@boltlog.com');
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      }
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.phone, color: Color(0xFF2563EB)),
                    title: Text(
                      'Phone Support',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                    ),
                    subtitle: const Text('+263 77 123 4567'),
                    trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                    onTap: () async {
                      final uri = Uri.parse('tel:+263771234567');
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      }
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.chat_bubble_outline, color: Color(0xFF2563EB)),
                    title: Text(
                      'Live Chat',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                    ),
                    subtitle: const Text('Chat with our support team'),
                    trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Live chat coming soon'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // FAQ Section
            Text(
              'Frequently Asked Questions',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E40AF),
              ),
            ),
            const SizedBox(height: 12),
            _buildFAQItem(
              context,
              'How do I request a delivery?',
              'Go to the Home screen and tap "Request Transport". Fill in the pickup and dropoff locations, package details, and submit your request.',
            ),
            _buildFAQItem(
              context,
              'How do I accept a delivery as a transporter?',
              'View available requests in your Transporter Dashboard. Tap on a request to see details, then tap "Accept Offer" to accept it.',
            ),
            _buildFAQItem(
              context,
              'How is pricing calculated?',
              'Pricing is based on distance, transport type, and package details. The app automatically calculates the price when you enter locations.',
            ),
            _buildFAQItem(
              context,
              'Can I negotiate the price?',
              'Yes! Transporters can make counter-offers, and senders can accept or reject them through the app.',
            ),
            _buildFAQItem(
              context,
              'How do I check delivery status?',
              'Go to your Delivery History and tap an active delivery to open Request Details. Transporters can also open route details from Active Deliveries.',
            ),
            _buildFAQItem(
              context,
              'What payment methods are accepted?',
              'Currently, payments are processed through the app. We are working on adding more payment options.',
            ),
            const SizedBox(height: 24),

            // Report Issue
            Text(
              'Report an Issue',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E40AF),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: const Icon(Icons.bug_report, color: Color(0xFF2563EB)),
                title: Text(
                  'Report a Bug',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                ),
                subtitle: const Text('Found an issue? Let us know'),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  _showReportBugDialog(context);
                },
              ),
            ),
            const SizedBox(height: 24),

            // Legal
            Text(
              'Legal',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E40AF),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.description, color: Color(0xFF2563EB)),
                    title: Text(
                      'Terms of Service',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TermsOfServiceScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip, color: Color(0xFF2563EB)),
                    title: Text(
                      'Privacy Policy',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PrivacyPolicyScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFAQItem(BuildContext context, String question, String answer) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        title: Text(
          question,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w500,
            fontSize: 15,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              answer,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.grey.shade700,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showReportBugDialog(BuildContext context) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Report a Bug',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: 'Describe the issue...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: GoogleFonts.inter()),
          ),
          ElevatedButton(
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please describe the issue'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }

              try {
                final user = FirebaseAuth.instance.currentUser;
                await FirebaseFirestore.instance.collection('bugReports').add({
                  'userId': user?.uid ?? 'anonymous',
                  'userEmail': user?.email ?? 'unknown',
                  'description': text,
                  'status': 'open',
                  'createdAt': DateTime.now().toIso8601String(),
                  'platform': 'mobile',
                });

                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Thank you for reporting! We\'ll look into it.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error submitting report: ${e.toString()}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
            ),
            child: Text('Submit', style: GoogleFonts.inter()),
          ),
        ],
      ),
    );
  }
}

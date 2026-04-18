import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

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
          'Privacy Policy',
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E40AF),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Last Updated: ${DateTime.now().year}',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 24),
              _buildSection(
                '1. Information We Collect',
                'We collect information that you provide directly to us, including:\n\n• Name, email address, and phone number\n• Location data for delivery services\n• Payment information (processed securely)\n• Profile information and preferences',
              ),
              _buildSection(
                '2. How We Use Your Information',
                'We use the information we collect to:\n\n• Provide and improve our services\n• Process transactions and send related information\n• Send you technical notices and support messages\n• Respond to your comments and questions\n• Monitor and analyze trends and usage',
              ),
              _buildSection(
                '3. Information Sharing',
                'We do not sell your personal information. We may share your information only:\n\n• With transporters/senders as necessary to complete deliveries\n• With service providers who assist us in operating our platform\n• When required by law or to protect our rights',
              ),
              _buildSection(
                '4. Location Data',
                'We collect location data to facilitate delivery services. You can control location sharing through your device settings. Location data is only shared with relevant parties for delivery purposes.',
              ),
              _buildSection(
                '5. Data Security',
                'We implement appropriate security measures to protect your personal information. However, no method of transmission over the internet is 100% secure.',
              ),
              _buildSection(
                '6. Your Rights',
                'You have the right to:\n\n• Access your personal information\n• Correct inaccurate information\n• Request deletion of your information\n• Opt-out of certain data collection',
              ),
              _buildSection(
                '7. Cookies and Tracking',
                'We use cookies and similar tracking technologies to track activity on our service and hold certain information. You can instruct your browser to refuse all cookies.',
              ),
              _buildSection(
                '8. Children\'s Privacy',
                'Our service is not intended for children under 18. We do not knowingly collect personal information from children.',
              ),
              _buildSection(
                '9. Changes to Privacy Policy',
                'We may update our Privacy Policy from time to time. We will notify you of any changes by posting the new policy on this page.',
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'If you have any questions about this Privacy Policy, please contact us at support@boltlog.com',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E40AF),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.grey.shade700,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

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
          'Terms of Service',
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
                '1. Acceptance of Terms',
                'By accessing and using the Boltlog application, you accept and agree to be bound by the terms and provision of this agreement.',
              ),
              _buildSection(
                '2. Use License',
                'Permission is granted to temporarily use Boltlog for personal, non-commercial transitory viewing only. This is the grant of a license, not a transfer of title, and under this license you may not:\n\n• Modify or copy the materials\n• Use the materials for any commercial purpose\n• Attempt to decompile or reverse engineer any software\n• Remove any copyright or other proprietary notations',
              ),
              _buildSection(
                '3. User Accounts',
                'You are responsible for maintaining the confidentiality of your account and password. You agree to accept responsibility for all activities that occur under your account.',
              ),
              _buildSection(
                '4. Delivery Services',
                'Boltlog provides a platform connecting senders with transporters. We are not a transportation company and do not provide transportation services. We facilitate connections between users.',
              ),
              _buildSection(
                '5. Payment Terms',
                'All payments for delivery services are processed through the platform. Payment terms and fees are clearly displayed before service acceptance.',
              ),
              _buildSection(
                '6. User Conduct',
                'You agree not to use the service to:\n\n• Violate any laws or regulations\n• Infringe on the rights of others\n• Transmit harmful or malicious code\n• Interfere with the operation of the service',
              ),
              _buildSection(
                '7. Limitation of Liability',
                'Boltlog shall not be liable for any indirect, incidental, special, consequential, or punitive damages resulting from your use of the service.',
              ),
              _buildSection(
                '8. Changes to Terms',
                'Boltlog reserves the right to modify these terms at any time. Your continued use of the service after changes constitutes acceptance of the new terms.',
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'If you have any questions about these Terms of Service, please contact us at support@boltlog.com',
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

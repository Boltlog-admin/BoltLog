import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../config/testing_flags.dart';
import 'main_navigation.dart';
import 'transporter_navigation.dart';

/// Explains how **sender** vs **transporter** UIs are chosen and which shell each uses.
/// Shown on cold start when [TestingFlags.showRoleFlowOverview] and [kDebugMode].
class FlowOverviewScreen extends StatelessWidget {
  const FlowOverviewScreen({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sender vs transporter flow'),
        actions: [
          TextButton(
            onPressed: onContinue,
            child: const Text('Continue'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'How routing works',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'After sign-in, the splash step loads your profile from Firestore. '
                    'If role is "driver", you get the transporter shell; otherwise you get the sender shell.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final narrow = constraints.maxWidth < 560;
                      final sender = _RoleCard(
                        title: 'Sender (customer)',
                        color: theme.colorScheme.primaryContainer,
                        icon: Icons.local_shipping_outlined,
                        shell: 'MainNavigation',
                        tabs: const [
                          'Home — book / track deliveries',
                          'History — past rides',
                          'Profile',
                        ],
                      );
                      final transporter = _RoleCard(
                        title: 'Transporter (driver)',
                        color: theme.colorScheme.secondaryContainer,
                        icon: Icons.local_shipping,
                        shell: 'TransporterNavigation',
                        tabs: const [
                          'Dashboard — open requests & stats',
                          'Active — current jobs',
                          'Profile',
                        ],
                      );
                      if (narrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            sender,
                            const SizedBox(height: 16),
                            transporter,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: sender),
                          const SizedBox(width: 16),
                          Expanded(child: transporter),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Code path (high level)',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'main → AppInitializer → Permissions (mobile first launch) → '
                            'SplashScreen → UserService.getUser → '
                            'role.trim().toLowerCase() == "driver" ? '
                            'TransporterNavigation : MainNavigation',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (user != null) ...[
                    Text(
                      'Signed in as ${user.email ?? user.uid}. You can preview each shell:',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => const MainNavigation(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.home_outlined),
                          label: const Text('Preview sender shell'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => const TransporterNavigation(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.dashboard_outlined),
                          label: const Text('Preview transporter shell'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Use the system back gesture or app bar back to return here, then Continue.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ] else ...[
                    Text(
                      'Sign in to enable preview buttons. Otherwise tap Continue for the normal splash → role routing.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: onContinue,
                    child: const Text('Continue to app'),
                  ),
                  if (TestingFlags.showInternalQaBanner && kDebugMode) ...[
                    const SizedBox(height: 12),
                    Text(
                      TestingFlags.buildLabel,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.title,
    required this.color,
    required this.icon,
    required this.shell,
    required this.tabs,
  });

  final String title;
  final Color color;
  final IconData icon;
  final String shell;
  final List<String> tabs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Shell: $shell',
              style: theme.textTheme.labelLarge?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 12),
            ...tabs.map(
              (t) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ', style: theme.textTheme.bodyMedium),
                    Expanded(child: Text(t, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

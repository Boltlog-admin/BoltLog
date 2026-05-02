import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../config/testing_flags.dart';
import 'main_navigation.dart';
import 'splash_screen.dart';
import 'transporter_navigation.dart';

/// Opens the main app shell without permissions or email login (see [TestingFlags.skipPermissionsLoginForQa]).
///
/// Uses [FirebaseAuth.signInAnonymously] so most screens get a non-null [User]. Firestore
/// may still be empty until you create test data or rules allow anonymous reads/writes.
class QaBypassScreen extends StatefulWidget {
  const QaBypassScreen({super.key});

  @override
  State<QaBypassScreen> createState() => _QaBypassScreenState();
}

class _QaBypassScreenState extends State<QaBypassScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _enter());
  }

  Future<void> _enter() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
      if (!mounted) return;
      final asDriver = TestingFlags.qaBypassLaunchAsDriver;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => asDriver
              ? const TransporterNavigation()
              : const MainNavigation(),
        ),
      );
    } catch (e, st) {
      debugPrint('QA bypass: $e\n$st');
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('QA bypass failed')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _error!,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Enable Anonymous in Firebase Console → Authentication → Sign-in method, '
                'or turn off skipPermissionsLoginForQa in testing_flags.dart.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) => const SplashScreen(),
                    ),
                  );
                },
                child: const Text('Continue with normal splash / login'),
              ),
            ],
          ),
        ),
      );
    }

    final shell = TestingFlags.qaBypassLaunchAsDriver
        ? 'Transporter (driver shell)'
        : 'Sender (customer shell)';
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              TestingFlags.buildLabel,
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'QA bypass: $shell',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Anonymous sign-in…',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

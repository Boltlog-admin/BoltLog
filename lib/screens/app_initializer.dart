import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/testing_flags.dart';
import 'flow_overview_screen.dart';
import 'permissions_screen.dart';
import 'qa_bypass_screen.dart';
import 'splash_screen.dart';

/// Decides whether to show permissions screen (first launch) or splash.
class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  // Default true = show permissions immediately on first launch (right after install)
  bool _showPermissions = true;

  /// Debug-only sender vs transporter flow explainer before the rest of startup.
  bool _flowOverviewDismissed = false;

  static const _permissionsKey = 'permissions_requested_v1';

  @override
  void initState() {
    super.initState();
    if (!kDebugMode || !TestingFlags.showRoleFlowOverview) {
      _flowOverviewDismissed = true;
    }
    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    if (kIsWeb) {
      if (!mounted) return;
      setState(() => _showPermissions = false);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final requested = prefs.getBool(_permissionsKey) ?? false;
    if (!mounted) return;
    setState(() => _showPermissions = !requested);
  }

  @override
  Widget build(BuildContext context) {
    if (kDebugMode && TestingFlags.skipPermissionsLoginForQa) {
      return const QaBypassScreen();
    }
    if (!_flowOverviewDismissed) {
      return FlowOverviewScreen(
        onContinue: () => setState(() => _flowOverviewDismissed = true),
      );
    }
    if (_showPermissions) {
      return PermissionsScreen(child: const SplashScreen());
    }
    return const SplashScreen();
  }
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'active_ride_map_screen.dart';
import 'chat_screen.dart';
import 'home_screen.dart';
import 'ride_history_screen.dart';
import 'profile_screen.dart';
import '../services/app_resume_service.dart';
import '../services/notification_service.dart';
import '../services/ride_service.dart';
import 'request_detail_screen.dart';

class MainNavigation extends StatefulWidget {
  final bool showWelcomeMessage;
  final int initialTabIndex;
  final AppResumeSnapshot? resumeSnapshot;

  const MainNavigation({
    super.key,
    this.showWelcomeMessage = false,
    this.initialTabIndex = 0,
    this.resumeSnapshot,
  });

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> with RouteAware {
  late int _currentIndex;

  final RideService _rideService = RideService();

  final List<Widget> _screens = [
    const HomeScreen(),
    const RideHistoryScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTabIndex.clamp(0, 2);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (widget.showWelcomeMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created successfully! Welcome to Boltlog!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      await _handleColdStartNavigation();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      boltLogRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    boltLogRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _persistShell();
  }

  void _persistShell() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      AppResumeService.instance.saveSenderShell(uid, _currentIndex);
    }
  }

  Future<void> _saveFcmToken() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final notificationService = NotificationService();
      final token = await notificationService.getToken();
      if (token != null) await notificationService.saveTokenToUser(uid, token);
    } catch (_) {}
  }

  Future<void> _handleColdStartNavigation() async {
    final pendingRideId = NotificationService.getPendingRideId();
    if (pendingRideId != null && pendingRideId.isNotEmpty && mounted) {
      try {
        final ride = await _rideService.getRideById(pendingRideId);
        if (ride != null && mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => RequestDetailScreen(ride: ride),
            ),
          );
        }
      } catch (_) {}
      await _saveFcmToken();
      return;
    }

    final r = widget.resumeSnapshot;
    if (r != null && r.hasDeepScreen && r.rideId != null && mounted) {
      try {
        final ride = await _rideService.getRideById(r.rideId!);
        if (!mounted) return;
        if (ride == null ||
            ride.status == 'completed' ||
            ride.status == 'cancelled') {
          await AppResumeService.instance.clear();
        } else {
          if (r.screen == AppResumeService.screenRequestDetail) {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => RequestDetailScreen(ride: ride),
              ),
            );
          } else if (r.screen == AppResumeService.screenActiveMap) {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => ActiveRideMapScreen(ride: ride),
              ),
            );
          } else if (r.screen == AppResumeService.screenChat) {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => ChatScreen(ride: ride),
              ),
            );
          }
          await _saveFcmToken();
          return;
        }
      } catch (_) {
        await AppResumeService.instance.clear();
      }
    }

    _persistShell();
    await _saveFcmToken();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Keep all tabs mounted so Home (active orders, streams, scroll) survives tab switches.
      body: IndexedStack(
        index: _currentIndex,
        sizing: StackFit.expand,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
          _persistShell();
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history_rounded),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

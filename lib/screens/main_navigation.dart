import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'active_ride_map_screen.dart';
import 'chat_screen.dart';
import 'home_screen.dart';
import 'ride_history_screen.dart';
import 'profile_screen.dart';
import '../models/ride_model.dart';
import '../services/app_resume_service.dart';
import '../services/notification_service.dart';
import '../services/ride_service.dart';
import 'request_detail_screen.dart';
import '../theme/app_theme.dart';

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

  RideModel? _senderTravelRide(List<RideModel> rides) {
    for (final ride in rides) {
      final hasDriver = (ride.driverId?.trim().isNotEmpty ?? false);
      final travelling =
          ride.status == 'in_progress' || ride.status == 'parcel_collected';
      if (hasDriver && travelling) return ride;
    }
    return null;
  }

  void _selectTab(int index) {
    if (_currentIndex == index) return;
    setState(() {
      _currentIndex = index;
    });
    _persistShell();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          sizing: StackFit.expand,
          children: _screens,
        ),
      );
    }

    return StreamBuilder<List<RideModel>>(
      stream: _rideService.streamUserRides(uid),
      builder: (context, snapshot) {
        final rides = snapshot.data ?? const <RideModel>[];
        final travelRide = _senderTravelRide(rides);
        if (travelRide != null) {
          // Override sender shell with shared live travel map while trip is active.
          return ActiveRideMapScreen(ride: travelRide);
        }

        return Scaffold(
          // Keep all tabs mounted so Home (active orders, streams, scroll) survives tab switches.
          body: Stack(
            children: [
              IndexedStack(
                index: _currentIndex,
                sizing: StackFit.expand,
                children: _screens,
              ),
              Positioned(
                top: 8,
                right: 8,
                child: SafeArea(
                  child: Material(
                    color: AppColors.cardBackground,
                    elevation: 3,
                    shadowColor: Colors.black.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    child: PopupMenuButton<int>(
                      tooltip: 'Open navigation menu',
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        color: AppColors.primaryDark,
                      ),
                      color: AppColors.cardBackground,
                      surfaceTintColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.md),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      onSelected: _selectTab,
                      itemBuilder: (context) => const [
                        PopupMenuItem<int>(
                          value: 0,
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.home_outlined),
                            title: Text('Home'),
                          ),
                        ),
                        PopupMenuItem<int>(
                          value: 1,
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.history_outlined),
                            title: Text('History'),
                          ),
                        ),
                        PopupMenuItem<int>(
                          value: 2,
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.person_outline_rounded),
                            title: Text('Profile'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

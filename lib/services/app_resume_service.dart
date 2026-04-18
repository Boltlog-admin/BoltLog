import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import '../models/ride_model.dart';
import '../models/user_model.dart';

/// Persists last meaningful screen so cold start can return the user there.
/// Cleared on sign-out.
final RouteObserver<ModalRoute<void>> boltLogRouteObserver =
    RouteObserver<ModalRoute<void>>();

class AppResumeSnapshot {
  final String userId;
  /// `sender` or `driver` — which shell the user was in.
  final String appRole;
  /// `shell` | `request_detail` | `active_map` | `chat`
  final String screen;
  final int mainTabIndex;
  final String? rideId;

  const AppResumeSnapshot({
    required this.userId,
    required this.appRole,
    required this.screen,
    required this.mainTabIndex,
    this.rideId,
  });

  bool matches(String currentUid, UserModel? model) {
    if (userId != currentUid) return false;
    final isDriver = AppConstants.isDriverRole(model?.role);
    if (appRole == 'driver' && !isDriver) return false;
    if (appRole == 'sender' && isDriver) return false;
    return true;
  }

  /// Deep resume: not only the bottom tab on the shell.
  bool get hasDeepScreen =>
      screen != AppResumeService.screenShell &&
      rideId != null &&
      rideId!.isNotEmpty;
}

class AppResumeService {
  AppResumeService._();
  static final AppResumeService instance = AppResumeService._();

  static const screenShell = 'shell';
  static const screenRequestDetail = 'request_detail';
  static const screenActiveMap = 'active_map';
  static const screenChat = 'chat';

  static const _kUid = 'app_resume_v1_uid';
  static const _kRole = 'app_resume_v1_role';
  static const _kScreen = 'app_resume_v1_screen';
  static const _kTab = 'app_resume_v1_tab';
  static const _kRide = 'app_resume_v1_ride_id';

  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kUid);
    await p.remove(_kRole);
    await p.remove(_kScreen);
    await p.remove(_kTab);
    await p.remove(_kRide);
  }

  Future<void> saveSenderShell(String uid, int tabIndex) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUid, uid);
    await p.setString(_kRole, 'sender');
    await p.setString(_kScreen, screenShell);
    await p.setInt(_kTab, tabIndex.clamp(0, 2));
    await p.remove(_kRide);
  }

  Future<void> saveDriverShell(String uid, int tabIndex) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUid, uid);
    await p.setString(_kRole, 'driver');
    await p.setString(_kScreen, screenShell);
    await p.setInt(_kTab, tabIndex.clamp(0, 2));
    await p.remove(_kRide);
  }

  /// Call when opening request detail, live map, or chat (uses current shell tab from prefs).
  Future<void> saveRideScreen({
    required RideModel ride,
    required String screen,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || ride.id == null) return;
    final p = await SharedPreferences.getInstance();
    final role = uid == ride.userId ? 'sender' : 'driver';
    final tab = p.getInt(_kTab) ?? 0;
    await p.setString(_kUid, uid);
    await p.setString(_kRole, role);
    await p.setString(_kScreen, screen);
    await p.setString(_kRide, ride.id!);
    await p.setInt(_kTab, tab.clamp(0, 2));
  }

  Future<AppResumeSnapshot?> readSnapshot() async {
    final p = await SharedPreferences.getInstance();
    final uid = p.getString(_kUid);
    if (uid == null || uid.isEmpty) return null;
    final role = p.getString(_kRole);
    final screen = p.getString(_kScreen);
    if (role == null || screen == null) return null;
    final tabRaw = p.getInt(_kTab);
    int tab = tabRaw ?? 0;
    if (tab < 0) tab = 0;
    if (tab > 2) tab = 2;
    return AppResumeSnapshot(
      userId: uid,
      appRole: role,
      screen: screen,
      mainTabIndex: tab,
      rideId: p.getString(_kRide),
    );
  }

  Future<AppResumeSnapshot?> readSnapshotForUser(
    String uid,
    UserModel? model,
  ) async {
    final s = await readSnapshot();
    if (s == null || !s.matches(uid, model)) return null;
    return s;
  }
}

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Writes periodic heartbeats to [app_sessions] so ops can see which installs
/// are online (Firebase Console → Firestore → live updates, or admin clients).
class _PresenceLifecycleObserver extends WidgetsBindingObserver {
  _PresenceLifecycleObserver(this._onResumed);

  final VoidCallback _onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onResumed();
    }
  }
}

class AppPresenceService {
  AppPresenceService._();

  static final AppPresenceService instance = AppPresenceService._();

  static const _collection = 'app_sessions';
  static const _interval = Duration(seconds: 45);

  Timer? _heartbeatTimer;
  _PresenceLifecycleObserver? _lifecycle;
  bool _started = false;

  void start() {
    if (_started) {
      return;
    }
    _started = true;

    _lifecycle = _PresenceLifecycleObserver(_pulseIfLoggedIn);
    WidgetsBinding.instance.addObserver(_lifecycle!);

    FirebaseAuth.instance.authStateChanges().listen((user) {
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
      if (user == null) {
        return;
      }
      unawaited(_pulse(user));
      _heartbeatTimer = Timer.periodic(_interval, (_) {
        final u = FirebaseAuth.instance.currentUser;
        if (u != null) {
          unawaited(_pulse(u));
        }
      });
    });
  }

  void _pulseIfLoggedIn() {
    final u = FirebaseAuth.instance.currentUser;
    if (u != null) {
      unawaited(_pulse(u));
    }
  }

  Future<void> _pulse(User user) async {
    try {
      await FirebaseFirestore.instance
          .collection(_collection)
          .doc(user.uid)
          .set(
            {
              'lastSeenAt': FieldValue.serverTimestamp(),
              'email': user.email,
              'displayName': user.displayName,
              'platform': _platformLabel(),
            },
            SetOptions(merge: true),
          );
    } catch (e, st) {
      debugPrint('AppPresenceService: heartbeat failed: $e\n$st');
    }
  }

  static String _platformLabel() {
    if (kIsWeb) {
      return 'web';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }
}

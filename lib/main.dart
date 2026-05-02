import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'firebase_options.dart';
import 'screens/app_initializer.dart';
import 'services/notification_service.dart';
import 'services/app_presence_service.dart';
import 'services/app_resume_service.dart';
import 'services/connectivity_service.dart';
import 'services/theme_service.dart';
import 'config/testing_flags.dart';
import 'theme/app_theme.dart';

/// Background FCM handler (app terminated or in background). Must be a top-level function.
/// The [notification] payload is shown by the OS; Firestore `notifications` rows are
/// already written before the Cloud Function sends FCM, so we do not duplicate writes here.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('Background FCM messageId=${message.messageId} data=${message.data}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Crashlytics is not used on web the same way as mobile; still surface errors in debug.
  FlutterError.onError = (errorDetails) {
    if (kIsWeb) {
      FlutterError.presentError(errorDetails);
    } else {
      FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
    }
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    if (!kIsWeb) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    }
    return true;
  };
  
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    
    // Firestore offline persistence must be set before any Firestore use.
    // Enables cached reads when offline and queued writes that sync when back online.
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
      debugPrint('Firestore offline persistence enabled');
    } catch (e) {
      debugPrint('Firestore persistence error: $e');
    }
    
    // Background FCM handler is for Android/iOS only (not web).
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    }
    
    // Initialize Notification Service
    try {
      final notificationService = NotificationService();
      await notificationService.initialize();
      debugPrint('Push notifications service initialized');
    } catch (e) {
      debugPrint('Push notifications initialization error: $e');
      // Continue anyway - notifications are optional
    }
    
    // Initialize Connectivity Service
    try {
      ConnectivityService();
      debugPrint('Connectivity service initialized');
    } catch (e) {
      debugPrint('Connectivity service initialization error: $e');
    }

    AppPresenceService.instance.start();
  } catch (e) {
    // If Firebase initialization fails, log the error
    debugPrint('Firebase initialization error: $e');
    if (!kIsWeb) {
      FirebaseCrashlytics.instance.recordError(e, null, fatal: false);
    }
    // Continue anyway - the app will show errors when trying to use Firebase
  }
  
  // Load saved theme mode before starting the app
  await ThemeService.init();

  runApp(const BoltlogApp());
}

class BoltlogApp extends StatelessWidget {
  const BoltlogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.themeMode,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Boltlog',
          navigatorObservers: [boltLogRouteObserver],
          debugShowCheckedModeBanner:
              kDebugMode && TestingFlags.showInternalQaBanner,
          locale: const Locale('en', 'US'),
          supportedLocales: const [
            Locale('en', 'US'),
          ],
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          home: const AppInitializer(),
        );
      },
    );
  }
}

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
    'default',
    'Boltlog alerts',
    description: 'New requests, offers, and delivery updates',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
    showBadge: true,
  );

  /// Pending notification from tap (cold start or background). Check after app loads and navigate.
  static String? pendingRideId;
  static String? pendingNotificationType;

  static String? getPendingRideId() {
    final id = pendingRideId;
    pendingRideId = null;
    return id;
  }

  Future<void> initialize() async {
    if (kIsWeb) {
      debugPrint(
        'NotificationService: push/local notifications are not initialized on web',
      );
      return;
    }

    await _initLocalNotifications();

    if (Platform.isIOS) {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      debugPrint('User granted notification permission');

      String? token = await _messaging.getToken();
      if (token != null) {
        debugPrint('FCM Token: $token');
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) await saveTokenToUser(uid, token);
      }

      _messaging.onTokenRefresh.listen((newToken) async {
        debugPrint('FCM Token refreshed: $newToken');
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) await saveTokenToUser(uid, newToken);
      });
    } else {
      debugPrint('User declined or has not accepted notification permission');
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      debugPrint('Got a message whilst in the foreground!');
      debugPrint('Message data: ${message.data}');
      // Android: show a heads-up channel notification. iOS: system banner via
      // setForegroundNotificationPresentationOptions. Firestore `notifications`
      // docs are already created by the app before FCM is sent — do not duplicate.
      if (Platform.isIOS) {
        return;
      }
      await _showLocalNotification(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('onMessageOpenedApp: ${message.data}');
      _setPendingFromData(message.data);
    });

    RemoteMessage? initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('App opened from notification: ${initialMessage.data}');
      _setPendingFromData(initialMessage.data);
    }
  }

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        final payload = details.payload;
        if (payload != null && payload.isNotEmpty) {
          try {
            final rideId = Uri.splitQueryString(payload)['rideId'];
            if (rideId != null && rideId.isNotEmpty) {
              pendingRideId = rideId;
            }
          } catch (_) {}
        }
      },
    );

    final androidPlugin = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_androidChannel);

    if (Platform.isAndroid) {
      await androidPlugin?.requestNotificationsPermission();
    }
  }

  void _setPendingFromData(Map<String, dynamic> data) {
    final rideId = data['rideId'] as String?;
    if (rideId != null && rideId.isNotEmpty) {
      pendingRideId = rideId;
      pendingNotificationType = data['type'] as String?;
    }
  }

  Future<void> saveTokenToUser(String userId, String token) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'fcmToken': token,
        'fcmTokenUpdatedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error saving FCM token: $e');
    }
  }

  Future<void> createNotification({
    required String userId,
    required String type,
    required String title,
    required String message,
    String? rideId,
    Map<String, dynamic>? data,
  }) async {
    try {
      await _firestore.collection('notifications').add({
        'userId': userId,
        'type': type,
        'title': title,
        'message': message,
        'rideId': rideId,
        'data': data ?? {},
        'isRead': false,
        'createdAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error creating notification: $e');
    }
  }

  Future<void> notifyRideAccepted(String userId, String rideId, String driverName) async {
    await createNotification(
      userId: userId,
      type: 'delivery_accepted',
      title: 'Delivery Accepted',
      message: '$driverName has accepted your delivery request',
      rideId: rideId,
    );
  }

  Future<void> notifyRideStatusChange(String userId, String rideId, String status) async {
    String title = 'Delivery Update';
    String message = '';

    switch (status) {
      case 'in_progress':
        message = 'Driver is on the way to collect your parcel';
        break;
      case 'parcel_collected':
        message = 'Your parcel has been collected';
        break;
      case 'completed':
        message = 'Your parcel has been delivered';
        break;
      default:
        message = 'Delivery status updated';
    }

    await createNotification(
      userId: userId,
      type: 'delivery_status',
      title: title,
      message: message,
      rideId: rideId,
      data: {'status': status},
    );
  }

  Future<void> notifyNewMessage(String userId, String rideId, String senderName) async {
    await createNotification(
      userId: userId,
      type: 'message',
      title: 'New Message',
      message: '$senderName sent you a message',
      rideId: rideId,
    );
  }

  Future<void> notifyNewOffer(String userId, String rideId, String transporterName) async {
    await createNotification(
      userId: userId,
      type: 'offer',
      title: 'New Offer',
      message: '$transporterName made an offer on your request',
      rideId: rideId,
    );
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title ??
        message.data['title'] as String? ??
        'Boltlog';
    final body = notification?.body ??
        message.data['message'] as String? ??
        '';

    final rideId = message.data['rideId'] as String? ?? '';
    final payload = 'rideId=${Uri.encodeQueryComponent(rideId)}';

    try {
      await _local.show(
        message.hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannel.id,
            _androidChannel.name,
            channelDescription: _androidChannel.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: payload,
      );
    } catch (e) {
      debugPrint('Local notification show failed: $e');
    }
  }

  Future<String?> getToken() async {
    return await _messaging.getToken();
  }
}

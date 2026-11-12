import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'backend_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'notification_tap_inbox.dart';
import 'notification_account_sync.dart';
import '../config/app_environment.dart';
import 'push_device_registration.dart';
import 'spark_backend_service.dart';

enum NotificationReadiness {
  checking,
  ready,
  denied,
  channelDisabled,
  unavailable,
}

/// Delivery status categories for push notifications
enum PushStatus {
  sent,
  noTokens,
  missingCredentials,
  authFailed,
  networkError,
  notSent,
}

/// Structured feedback model for push notification dispatch outcomes
class PushResult {
  final bool success;
  final PushStatus status;
  final String message;
  final int deliveredCount;

  const PushResult({
    required this.success,
    required this.status,
    required this.message,
    this.deliveredCount = 0,
  });

  static const PushResult notSentDisabled = PushResult(
    success: false,
    status: PushStatus.notSent,
    message: 'Push notification was disabled by administrator',
  );
}

/// Top-level background handler — must be outside any class (Dart isolate requirement).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM] Background message received: ${message.messageId}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  static NotificationService get instance => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  final readiness = ValueNotifier(NotificationReadiness.checking);
  final _tapInbox = NotificationTapInbox();
  final Set<String> _shownMessageIds = {};
  Future<void>? _initialization;
  int _tapGeneration = 0;
  int _notificationId = DateTime.now().millisecondsSinceEpoch % 0x7fffffff;
  static bool get testPushEnabled =>
      const bool.fromEnvironment('SPARK_PROOF_PUSH_ENABLED') &&
      AppEnvironment.isFieldTest;
  static bool get managedPushEnabled =>
      AppEnvironment.mainBackendRequested || testPushEnabled;
  bool get _enabled => AppEnvironment.pushEnabled || managedPushEnabled;
  late final _testDevices = PushDeviceRegistration.platform(
    () => FirebaseAuth.instance.currentUser?.uid,
  );
  bool _matchesAccount(Map<String, dynamic> data) =>
      notificationMatchesAccount(data, FirebaseAuth.instance.currentUser?.uid);
  void _receiveTap(Map<String, dynamic> data) {
    if (FirebaseAuth.instance.currentUser != null && !_matchesAccount(data))
      return;
    _tapInbox.receive(data);
  }

  int setOnNotificationTap(void Function(Map<String, dynamic>?) callback) {
    final generation = ++_tapGeneration;
    _tapInbox.detach();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (generation == _tapGeneration) {
        _tapInbox.attach((data) {
          if (_matchesAccount(data)) callback(data);
        });
      }
    });
    return generation;
  }

  void clearOnNotificationTap(int owner) {
    if (owner != _tapGeneration) {
      return;
    }
    _tapGeneration++;
    _tapInbox.detach();
  }

  Map<String, dynamic> _decodePayload(String? payload) {
    if (payload == null || payload.isEmpty) {
      return {};
    }
    try {
      return Map<String, dynamic>.from(jsonDecode(payload) as Map);
    } catch (_) {
      return {'alertId': payload};
    }
  }

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    if (!_enabled) {
      readiness.value = NotificationReadiness.unavailable;
      return;
    }
    if (managedPushEnabled) SparkBackendService.validateConfiguration();
    final android = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    try {
      await android
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              'safepaths_alerts',
              'SafePaths Alerts',
              description: 'Broadcast alerts from SafePaths DRRMO',
              importance: Importance.max,
              playSound: true,
              enableVibration: true,
            ),
          )
          .timeout(const Duration(seconds: 5));
      await android
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              'safepaths_reports',
              'SafePaths Private Updates',
              description: 'Updates saved to your report and feedback history',
              importance: Importance.high,
            ),
          )
          .timeout(const Duration(seconds: 5));
      await _localNotifications
          .initialize(
            const InitializationSettings(
              android: AndroidInitializationSettings('@mipmap/launcher_icon'),
            ),
            onDidReceiveNotificationResponse: (details) =>
                _receiveTap(_decodePayload(details.payload)),
          )
          .timeout(const Duration(seconds: 5));
      final launch = await _localNotifications
          .getNotificationAppLaunchDetails()
          .timeout(const Duration(seconds: 3));
      if (launch?.didNotificationLaunchApp ?? false) {
        _receiveTap(_decodePayload(launch?.notificationResponse?.payload));
      }
    } catch (_) {
      readiness.value = NotificationReadiness.unavailable;
    }

    // Install remote handlers even when local notification setup/permission fails.
    final messaging = FirebaseMessaging.instance;
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) {
        return;
      }
      if (!_matchesAccount(message.data)) return;
      final id = message.data['eventId'] ?? message.messageId;
      if (id != null && !_shownMessageIds.add(id)) {
        return;
      }
      if (_shownMessageIds.length > 100) {
        _shownMessageIds.remove(_shownMessageIds.first);
      }
      unawaited(
        showLocalNotification(
          title: notification.title ?? 'SafePaths Alert',
          body: notification.body ?? '',
          payload: jsonEncode(message.data),
          eventId: message.data['eventId'],
        ).catchError((Object _) {
          readiness.value = NotificationReadiness.unavailable;
        }),
      );
    });
    FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _receiveTap(message.data),
    );
    messaging.onTokenRefresh.listen(_saveFcmToken);
    watchVerifiedNotificationAccount(
      FirebaseAuth.instance.userChanges(),
      syncFcmToken,
    );
    String? previousUid = FirebaseAuth.instance.currentUser?.uid;
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user?.uid != previousUid) {
        previousUid = user?.uid;
        _tapInbox.retainForAccount(user?.uid);
        unawaited(_localNotifications.cancelAll().catchError((Object _) {}));
      }
    });
    try {
      final initial = await messaging.getInitialMessage().timeout(
        const Duration(seconds: 5),
      );
      if (initial != null) {
        _receiveTap(initial.data);
      }
    } catch (_) {}
    await refreshReadiness(requestPermission: true);
    unawaited(syncFcmToken());
    try {
      if (!managedPushEnabled)
        await messaging
            .subscribeToTopic('safepaths_alerts')
            .timeout(const Duration(seconds: 5));
    } catch (_) {
      readiness.value = NotificationReadiness.unavailable;
    }
  }

  Future<void> refreshReadiness({bool requestPermission = false}) async {
    if (!_enabled) {
      readiness.value = NotificationReadiness.unavailable;
      return;
    }
    readiness.value = NotificationReadiness.checking;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings =
          await (requestPermission
                  ? messaging.requestPermission(
                      alert: true,
                      badge: true,
                      sound: true,
                    )
                  : messaging.getNotificationSettings())
              .timeout(const Duration(seconds: 5));
      final authorized =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      final android = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final enabled = await android?.areNotificationsEnabled().timeout(
        const Duration(seconds: 3),
      );
      if (!authorized || enabled == false) {
        readiness.value = NotificationReadiness.denied;
        return;
      }
      final channels = await android?.getNotificationChannels().timeout(
        const Duration(seconds: 3),
      );
      final disabled =
          channels?.any(
            (channel) =>
                channel.id ==
                    (managedPushEnabled
                        ? 'safepaths_reports'
                        : 'safepaths_alerts') &&
                channel.importance == Importance.none,
          ) ??
          false;
      readiness.value = disabled
          ? NotificationReadiness.channelDisabled
          : NotificationReadiness.ready;
    } catch (_) {
      readiness.value = NotificationReadiness.unavailable;
    } finally {
      if (managedPushEnabled) unawaited(syncFcmToken());
    }
  }

  /// Ensures current device's FCM token is retrieved and saved to the current user's Firestore record.
  Future<void> syncFcmToken() async {
    if (!_enabled) {
      return;
    }
    try {
      final account = FirebaseAuth.instance.currentUser;
      if (account == null || !account.emailVerified || account.isAnonymous)
        return;
      if (managedPushEnabled &&
          readiness.value != NotificationReadiness.ready) {
        await _testDevices.update(uid: account.uid, enabled: false);
        return;
      }
      final token = await FirebaseMessaging.instance.getToken().timeout(
        const Duration(seconds: 5),
      );
      if (token != null && token.isNotEmpty) {
        await _saveFcmToken(token);
      }
    } catch (e) {
      debugPrint('[FCM] Device registration could not be confirmed.');
    }
  }

  /// Show a heads-up local notification (foreground use).
  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
    String? eventId,
  }) async {
    final typedEvent =
        eventId != null && RegExp(r'^[a-f0-9]{64}$').hasMatch(eventId);
    final broadcast = _decodePayload(payload)['type'] == 'broadcast_update';
    final reportEvent =
        !broadcast &&
        eventId != null &&
        RegExp(r'^[a-f0-9]{64}$').hasMatch(eventId);
    final androidDetails = AndroidNotificationDetails(
      reportEvent ? 'safepaths_reports' : 'safepaths_alerts',
      reportEvent ? 'SafePaths Private Updates' : 'SafePaths Alerts',
      channelDescription: reportEvent
          ? 'Updates saved to your report and feedback history'
          : 'Broadcast alerts from SafePaths',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/launcher_icon',
      tag: typedEvent ? eventId : null,
      visibility: NotificationVisibility.private,
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      typedEvent
          ? int.parse(eventId.substring(0, 7), radix: 16)
          : (_notificationId = (_notificationId + 1) % 0x7fffffff),
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  Future<PushResult> sendPushToTopic({
    required String title,
    required String body,
    Map<String, String>? data,
  }) => _sendPush({'title': title, 'body': body, 'data': data});

  Future<PushResult> sendPushToUser({
    required String userId,
    required String title,
    required String body,
    Map<String, String>? data,
  }) =>
      _sendPush({'userId': userId, 'title': title, 'body': body, 'data': data});

  Future<PushResult> _sendPush(Map<String, dynamic> payload) async {
    if (!AppEnvironment.pushEnabled) {
      return PushResult.notSentDisabled;
    }
    try {
      final result = await BackendService.call('sendNotification', payload);
      final count = result['acceptedCount'] as int? ?? 0;
      return PushResult(
        success: count > 0,
        status: count > 0 ? PushStatus.sent : PushStatus.noTokens,
        message: count > 0
            ? 'Push accepted for sending; device receipt is not confirmed.'
            : 'No registered devices. Message remains available in the app.',
        deliveredCount: count,
      );
    } catch (_) {
      return const PushResult(
        success: false,
        status: PushStatus.networkError,
        message: 'Push unavailable. Message remains available in the app.',
      );
    }
  }

  Future<void> clearDeviceToken() async {
    _tapGeneration++;
    _tapInbox.clear();
    if (!_enabled) {
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }
    try {
      await _localNotifications.cancelAll().timeout(const Duration(seconds: 3));
    } catch (_) {}
    if (managedPushEnabled) {
      try {
        await _testDevices
            .update(uid: user.uid, enabled: false)
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    String? token;
    try {
      token = await FirebaseMessaging.instance.getToken().timeout(
        const Duration(seconds: 3),
      );
    } catch (_) {}
    if (token != null && !managedPushEnabled) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
              'fcmTokens': FieldValue.arrayRemove([token]),
            })
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    try {
      await FirebaseMessaging.instance.deleteToken().timeout(
        const Duration(seconds: 3),
      );
    } catch (_) {}
  }

  /// Save the FCM token to the user's Firestore document.
  Future<void> _saveFcmToken(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.isAnonymous || !user.emailVerified) {
        return;
      }
      final uid = user.uid;
      if (managedPushEnabled) {
        await _testDevices.update(
          uid: uid,
          token: token,
          enabled: readiness.value == NotificationReadiness.ready,
        );
        return;
      }
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({
            'fcmTokens': FieldValue.arrayUnion([token]),
            'lastFcmTokenUpdate': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 5));
      debugPrint('[FCM] Device registration saved.');
    } catch (e) {
      debugPrint('[FCM] Device registration could not be confirmed.');
    }
  }
}

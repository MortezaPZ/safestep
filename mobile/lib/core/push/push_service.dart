import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/device_registrar.dart';

/// هندلر پس‌زمینه باید سطح بالا باشد تا ایزولیت جدا بتواند پیدایش کند.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('FCM پس‌زمینه: ${message.messageId}');
}

class PushStatus {
  const PushStatus({required this.available, required this.reason});

  final bool available;
  final String reason;
}

class PushService {
  PushService(this._registrar);

  final DeviceRegistrar _registrar;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  bool _available = false;
  String _reason = 'پیکربندی Firebase لازم است';

  bool get available => _available;
  String get reason => _reason;

  Future<void> initialize({void Function(String alertId)? onOpenAlert}) async {
    try {
      await Firebase.initializeApp();
    } catch (error) {
      _available = false;
      _reason = 'غیرفعال — پیکربندی Firebase لازم است';
      debugPrint('Firebase در دسترس نیست: $error');
      return;
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await _local.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final String? payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          onOpenAlert?.call(payload);
        }
      },
    );

    const AndroidNotificationChannel sos = AndroidNotificationChannel(
      'safestep_sos',
      'هشدار اضطراری',
      description: 'هشدار SOS و رویدادهای بحرانی',
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('sos_alert'),
    );
    const AndroidNotificationChannel alerts = AndroidNotificationChannel(
      'safestep_alerts',
      'هشدارها',
      description: 'خروج از محدوده و هشدارهای عادی',
      importance: Importance.high,
    );

    final AndroidFlutterLocalNotificationsPlugin? android =
        _local.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(sos);
    await android?.createNotificationChannel(alerts);
    await android?.requestNotificationsPermission();

    final NotificationSettings settings =
        await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      _available = false;
      _reason = 'مجوز اعلان رد شد';
      return;
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      unawaited(_showLocal(message));
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final String? alertId = message.data['alertId']?.toString();
      if (alertId != null && alertId.isNotEmpty) onOpenAlert?.call(alertId);
    });

    FirebaseMessaging.instance.onTokenRefresh.listen((String token) {
      unawaited(_registrar.registerCurrentDevice(pushToken: token));
    });

    final String? token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _registrar.registerCurrentDevice(pushToken: token);
    }

    _available = true;
    _reason = 'فعال';
  }

  Future<void> _showLocal(RemoteMessage message) async {
    final RemoteNotification? n = message.notification;
    final bool critical = message.data['severity'] == 'critical';
    await _local.show(
      n.hashCode,
      n?.title ?? 'هم‌قدم',
      n?.body ?? '',
      NotificationDetails(
        android: AndroidNotificationDetails(
          critical ? 'safestep_sos' : 'safestep_alerts',
          critical ? 'هشدار اضطراری' : 'هشدارها',
          importance: critical ? Importance.max : Importance.high,
          priority: critical ? Priority.max : Priority.high,
          sound: critical
              ? const RawResourceAndroidNotificationSound('sos_alert')
              : null,
        ),
      ),
      payload: message.data['alertId']?.toString(),
    );
  }
}

final Provider<PushService> pushServiceProvider = Provider<PushService>((ref) {
  return PushService(ref.watch(deviceRegistrarProvider));
});

final StateProvider<PushStatus> pushStatusProvider =
    StateProvider<PushStatus>((ref) {
  return const PushStatus(
    available: false,
    reason: 'غیرفعال — پیکربندی Firebase لازم است',
  );
});

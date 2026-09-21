import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/device_registrar.dart';

class PushStatus {
  const PushStatus({required this.available, required this.reason});

  final bool available;
  final String reason;
}

/// اعلان محلی برای دمو؛ FCM روی این بیلد لازم نیست.
class PushService {
  PushService(this._registrar);

  final DeviceRegistrar _registrar;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  bool _available = false;
  String _reason = 'اعلان ابری پیکربندی نشده';

  bool get available => _available;
  String get reason => _reason;

  Future<void> initialize({void Function(String alertId)? onOpenAlert}) async {
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

    try {
      await _registrar.registerCurrentDevice();
    } catch (error) {
      debugPrint('ثبت دستگاه: $error');
    }

    _available = true;
    _reason = 'اعلان محلی فعال است';
  }
}

final Provider<PushService> pushServiceProvider = Provider<PushService>((ref) {
  return PushService(ref.watch(deviceRegistrarProvider));
});

final StateProvider<PushStatus> pushStatusProvider =
    StateProvider<PushStatus>((ref) {
  return const PushStatus(
    available: false,
    reason: 'اعلان ابری پیکربندی نشده',
  );
});

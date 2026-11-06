import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../device/device_registrar.dart';
import 'alert_notification_policy.dart';
import 'fall_notification_payload.dart';

class PushStatus {
  const PushStatus({required this.available, required this.reason});

  final bool available;
  final String reason;
}

typedef FallNotificationActionHandler = void Function(
  FallNotificationPayload payload,
  String feedback,
);

@visibleForTesting
AndroidNotificationDetails buildFallCheckAndroidDetails(DateTime deadline) {
  return AndroidNotificationDetails(
    'safestep_fall_check',
    'بررسی سقوط',
    channelDescription: 'هشدار فوری پس از تشخیص احتمال سقوط',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.alarm,
    fullScreenIntent: true,
    ongoing: true,
    autoCancel: false,
    onlyAlertOnce: true,
    visibility: NotificationVisibility.public,
    showWhen: true,
    when: deadline.millisecondsSinceEpoch,
    usesChronometer: true,
    chronometerCountDown: true,
    actions: const <AndroidNotificationAction>[
      AndroidNotificationAction(
        'fall_ok',
        'حالم خوب است',
        showsUserInterface: true,
      ),
      AndroidNotificationAction(
        'fall_help',
        'کمک می‌خواهم',
        showsUserInterface: true,
      ),
    ],
  );
}

/// اعلان محلی برای دمو؛ FCM روی این بیلد لازم نیست.
class PushService {
  PushService([this._registrar]);

  static const int _fallNotificationId = 8204;

  final DeviceRegistrar? _registrar;
  final AlertNotificationDeduplicator _alertDeduplicator =
      AlertNotificationDeduplicator();
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  bool _available = false;
  bool _ready = false;
  String _reason = 'اعلان ابری پیکربندی نشده';
  void Function(String alertId)? _onOpenAlert;
  void Function(FallNotificationPayload payload)? _onOpenFallNotification;
  FallNotificationActionHandler? _onFallAction;

  bool get available => _available;
  String get reason => _reason;

  Future<void> initialize({
    void Function(String alertId)? onOpenAlert,
    void Function(FallNotificationPayload payload)? onOpenFallNotification,
    FallNotificationActionHandler? onFallAction,
  }) async {
    if (onOpenAlert != null) _onOpenAlert = onOpenAlert;
    if (onOpenFallNotification != null) {
      _onOpenFallNotification = onOpenFallNotification;
    }
    if (onFallAction != null) _onFallAction = onFallAction;
    if (_ready) return;
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    final DarwinInitializationSettings darwinInit =
        DarwinInitializationSettings(
      notificationCategories: <DarwinNotificationCategory>[
        DarwinNotificationCategory(
          'fall_check_actions_v1',
          actions: <DarwinNotificationAction>[
            DarwinNotificationAction.plain(
              'fall_ok',
              'حالم خوب است',
              options: <DarwinNotificationActionOption>{
                DarwinNotificationActionOption.foreground,
              },
            ),
            DarwinNotificationAction.plain(
              'fall_help',
              'کمک می‌خواهم',
              options: <DarwinNotificationActionOption>{
                DarwinNotificationActionOption.foreground,
              },
            ),
          ],
        ),
      ],
    );
    await _local.initialize(
      InitializationSettings(android: androidInit, iOS: darwinInit),
      onDidReceiveNotificationResponse: _handleNotificationResponse,
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
    const AndroidNotificationChannel falls = AndroidNotificationChannel(
      'safestep_fall_check',
      'بررسی سقوط',
      description: 'هشدار فوری پس از تشخیص احتمال سقوط',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    final AndroidFlutterLocalNotificationsPlugin? android =
        _local.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(sos);
    await android?.createNotificationChannel(alerts);
    await android?.createNotificationChannel(falls);
    final bool? androidPermission =
        android == null ? null : await android.requestNotificationsPermission();
    final bool? androidEnabled = await android?.areNotificationsEnabled();
    final ph.PermissionStatus? otherPlatformPermission =
        android == null ? await ph.Permission.notification.request() : null;

    try {
      await _registrar?.registerCurrentDevice();
    } catch (error) {
      debugPrint('ثبت دستگاه: $error');
    }

    _available = androidEnabled ??
        androidPermission ??
        ((otherPlatformPermission?.isGranted ?? false) ||
            (otherPlatformPermission?.isProvisional ?? false));
    _ready = true;
    _reason =
        _available ? 'اعلان محلی فعال است' : 'مجوز نمایش اعلان داده نشده است';

    final NotificationAppLaunchDetails? launch =
        await _local.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true &&
        launch?.notificationResponse != null) {
      _handleNotificationResponse(launch!.notificationResponse!);
    }
  }

  void _handleNotificationResponse(NotificationResponse response) {
    final FallNotificationPayload? fall =
        FallNotificationPayload.tryParse(response.payload);
    if (fall != null) {
      switch (response.actionId) {
        case 'fall_ok':
          _onFallAction?.call(fall, 'false_alarm');
          return;
        case 'fall_help':
          _onFallAction?.call(fall, 'confirmed');
          return;
        default:
          _onOpenFallNotification?.call(fall);
          return;
      }
    }

    final String? alertId = response.payload;
    if (alertId != null && alertId.isNotEmpty) _onOpenAlert?.call(alertId);
  }

  /// اعلان قابل‌اقدام برای همان رخداد سقوطی که صفحه‌ی شمارش معکوس نشان می‌دهد.
  Future<void> showFallCheckNotification({
    required String eventId,
    required DateTime startedAt,
    required DateTime deadline,
  }) async {
    if (!_ready) {
      await initialize(
        onOpenAlert: _onOpenAlert,
        onOpenFallNotification: _onOpenFallNotification,
        onFallAction: _onFallAction,
      );
    }
    if (!_available) return;
    final FallNotificationPayload payload = FallNotificationPayload(
      eventId: eventId,
      startedAt: startedAt,
      deadline: deadline,
    );
    final AndroidNotificationDetails android =
        buildFallCheckAndroidDetails(deadline);
    const DarwinNotificationDetails darwin = DarwinNotificationDetails(
      categoryIdentifier: 'fall_check_actions_v1',
      interruptionLevel: InterruptionLevel.timeSensitive,
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentSound: true,
    );
    await _local.show(
      _fallNotificationId,
      'احتمال سقوط',
      'اگر حالتان خوب است یا به کمک نیاز دارید، یکی از گزینه‌ها را انتخاب کنید.',
      NotificationDetails(android: android, iOS: darwin),
      payload: payload.encode(),
    );
  }

  Future<void> cancelFallCheckNotification() =>
      _local.cancel(_fallNotificationId);

  /// System notification for a new alert received over the live socket.
  Future<void> showAlertNotification({
    required String alertId,
    required String type,
    required String severity,
    required String title,
    required String body,
  }) async {
    if (!_ready) {
      await initialize(
        onOpenAlert: _onOpenAlert,
        onOpenFallNotification: _onOpenFallNotification,
        onFallAction: _onFallAction,
      );
    }
    if (!_available || !_alertDeduplicator.reserve(alertId)) return;

    final AndroidNotificationDetails android = buildAlertAndroidDetails(
      severity: severity,
      type: type,
    );
    final DarwinNotificationDetails darwin = DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentSound: true,
      interruptionLevel: severity == 'critical'
          ? InterruptionLevel.timeSensitive
          : InterruptionLevel.active,
      threadIdentifier: 'alert_$type',
    );
    try {
      await _local.show(
        notificationIdForAlert(alertId),
        title,
        body,
        NotificationDetails(android: android, iOS: darwin),
        payload: alertId,
      );
    } catch (_) {
      _alertDeduplicator.allowRetry(alertId);
      rethrow;
    }
  }

  Future<String> enableAndConfirm() async {
    await initialize();
    if (!_available) return _reason;
    const AndroidNotificationDetails android = AndroidNotificationDetails(
      'safestep_alerts',
      'هشدارها',
      channelDescription: 'خروج از محدوده و هشدارهای عادی',
      importance: Importance.high,
      priority: Priority.high,
    );
    await _local.show(
      1,
      'هم‌قدم',
      'اعلان محلی آزمایشی نمایش داده شد',
      const NotificationDetails(android: android),
    );
    return _reason;
  }
}

Future<PushStatus> enablePushAndReadStatus(PushService service) async {
  final String reason = await service.enableAndConfirm();
  return PushStatus(available: service.available, reason: reason);
}

String pushPermissionFeedback(PushStatus status) =>
    status.available ? 'اعلان محلی آزمایشی نمایش داده شد' : status.reason;

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

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../device/device_registrar.dart';
import '../../features/alerts/data/alerts_repository.dart';
import 'alert_notification_policy.dart';
import 'fcm_alert_payload.dart';
import 'fcm_token_registration.dart';
import 'firebase_config_guard.dart';
import 'firebase_push_runtime.dart';
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
  PushService([
    this._registrar,
    this._receiptRepository,
    FcmTokenRegistration? tokenRegistration,
  ]) : _tokenRegistrationOverride = tokenRegistration;

  static const int _fallNotificationId = 8204;

  final DeviceRegistrar? _registrar;
  final AlertsRepository? _receiptRepository;
  final FcmTokenRegistration? _tokenRegistrationOverride;
  late final FcmTokenRegistration _tokenRegistration =
      _tokenRegistrationOverride ??
          FcmTokenRegistration(
            readToken: () async =>
                _firebaseReady ? _messaging?.getToken() : null,
            registerCurrentDevice: (String token) async {
              return await _registrar?.registerCurrentDevice(
                      pushToken: token) ??
                  false;
            },
          );
  late final FcmAlertDeliveryProcessor _fcmAlertProcessor =
      FcmAlertDeliveryProcessor(
    activeUserId: () => _tokenRegistration.activeAccountId,
    showLocalNotification: (FcmAlertPayload alert) => showAlertNotification(
      alertId: alert.alertId,
      type: '',
      severity: alert.severity,
      title: alert.title,
      body: alert.body,
    ),
    recordReceipt: (String alertId) {
      final AlertsRepository? repository = _receiptRepository;
      if (repository == null) {
        throw StateError('AlertsRepository is not configured');
      }
      return repository.recordDeliveryReceipt(alertId);
    },
  );
  final AlertNotificationDeduplicator _alertDeduplicator =
      AlertNotificationDeduplicator();
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  bool _available = false;
  bool _ready = false;
  bool _firebaseReady = false;
  String _firebaseReason = 'پیکربندی Firebase موجود نیست';
  String _reason = 'اعلان محلی آماده نیست';
  FirebaseMessaging? _messaging;
  StreamSubscription<RemoteMessage>? _foregroundMessages;
  StreamSubscription<RemoteMessage>? _openedMessages;
  StreamSubscription<String>? _tokenRefreshes;
  void Function(String alertId)? _onOpenAlert;
  void Function(FallNotificationPayload payload)? _onOpenFallNotification;
  FallNotificationActionHandler? _onFallAction;

  bool get available => _available;
  String get reason => _reason;
  bool get firebaseAvailable => _firebaseReady;
  String get firebaseReason => _firebaseReason;

  /// Associates the current Firebase token with the account authenticated by
  /// the API client's bearer token. The account id fences stale async work.
  Future<void> syncTokenForCurrentAccount({required String userId}) =>
      _tokenRegistration.setCurrentAccount(userId);

  /// Stops token refresh events from registering against a signed-out session.
  Future<void> clearCurrentAccount({required String userId}) async {
    if (_tokenRegistration.activeAccountId == userId) {
      await _tokenRegistration.setCurrentAccount(null);
    }
  }

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

    _available = androidEnabled ??
        androidPermission ??
        ((otherPlatformPermission?.isGranted ?? false) ||
            (otherPlatformPermission?.isProvisional ?? false));
    _ready = true;
    await _initializeFirebaseMessaging();
    _reason = _available
        ? (_firebaseReady
            ? 'مجوز و نمایش اعلان محلی فعال است'
            : 'اعلان محلی فعال است؛ Firebase پیکربندی نشده است')
        : 'مجوز نمایش اعلان داده نشده است';

    final NotificationAppLaunchDetails? launch =
        await _local.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true &&
        launch?.notificationResponse != null) {
      _handleNotificationResponse(launch!.notificationResponse!);
    }
  }

  Future<void> _initializeFirebaseMessaging() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      _firebaseReason = 'اعلان ابری فقط در Android و iOS پشتیبانی می‌شود';
      return;
    }

    final bool initialized = await initializeFirebaseSafely(() async {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    });
    if (!initialized) {
      _firebaseReason = 'فایل تنظیمات واقعی Firebase نصب نشده است';
      return;
    }

    try {
      _messaging = FirebaseMessaging.instance;
      FirebaseMessaging.onBackgroundMessage(
        firebaseMessagingBackgroundHandler,
      );

      try {
        await _messaging!.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      } catch (error) {
        debugPrint('درخواست اجازه Firebase انجام نشد: $error');
      }

      if (Platform.isIOS) {
        await _messaging!.setForegroundNotificationPresentationOptions(
          alert: false,
          badge: false,
          sound: false,
        );
      }

      _foregroundMessages ??= FirebaseMessaging.onMessage.listen(
        (RemoteMessage message) => unawaited(
          _handleFirebaseMessage(message, showLocal: true).catchError(
            (Object error) => debugPrint('پیام Firebase پردازش نشد: $error'),
          ),
        ),
      );
      _openedMessages ??= FirebaseMessaging.onMessageOpenedApp.listen(
        (RemoteMessage message) => unawaited(
          _handleFirebaseMessage(
            message,
            showLocal: false,
            openAlert: true,
          ).catchError(
            (Object error) =>
                debugPrint('بازکردن اعلان Firebase شکست خورد: $error'),
          ),
        ),
      );
      _tokenRefreshes ??= _messaging!.onTokenRefresh.listen(
        (String token) => unawaited(
          _tokenRegistration.tokenRefreshed(token).catchError(
                (Object error) => debugPrint('ثبت توکن تازه شکست خورد: $error'),
              ),
        ),
      );

      _firebaseReady = true;
      _firebaseReason = 'Firebase آماده است';
      try {
        await _tokenRegistration.syncCurrentToken();
      } catch (error) {
        debugPrint('ثبت توکن اولیه شکست خورد: $error');
      }

      try {
        final RemoteMessage? initial = await _messaging!.getInitialMessage();
        if (initial != null) {
          unawaited(
            _handleFirebaseMessage(
              initial,
              showLocal: false,
              openAlert: true,
            ).catchError((Object error) {
              debugPrint('اعلان شروع Firebase پردازش نشد: $error');
            }),
          );
        }
      } catch (error) {
        debugPrint('اعلان آغازین Firebase در دسترس نبود: $error');
      }
    } catch (error) {
      _firebaseReady = false;
      _firebaseReason = 'Firebase در این نصب در دسترس نیست';
      debugPrint('راه‌اندازی Firebase انجام نشد: $error');
    }
  }

  Future<void> _handleFirebaseMessage(
    RemoteMessage message, {
    required bool showLocal,
    bool openAlert = false,
  }) async {
    final FcmAlertPayload? alert = await _fcmAlertProcessor.handle(
      message.data,
      showLocal: showLocal,
    );
    if (openAlert && alert != null) _onOpenAlert?.call(alert.alertId);
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
  return PushService(
    ref.watch(deviceRegistrarProvider),
    ref.watch(alertsRepositoryProvider),
  );
});

final StateProvider<PushStatus> pushStatusProvider =
    StateProvider<PushStatus>((ref) {
  return const PushStatus(
    available: false,
    reason: 'اعلان ابری پیکربندی نشده',
  );
});

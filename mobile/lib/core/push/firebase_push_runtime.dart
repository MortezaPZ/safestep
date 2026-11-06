import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/alerts/data/alerts_repository.dart';
import '../network/api_client.dart';
import '../network/server_origin.dart';
import '../storage/token_store.dart';
import 'alert_notification_policy.dart';
import 'fcm_alert_payload.dart';
import 'firebase_config_guard.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final bool firebaseReady = await initializeFirebaseSafely(() async {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
  });
  if (!firebaseReady) return;

  final FcmAlertPayload? alert = FcmAlertPayload.tryParse(message.data);
  if (alert == null) return;
  final TokenStore tokenStore = _backgroundTokenStore();
  final String? userId = await _activeSessionUserId(tokenStore);
  if (userId == null || userId != alert.recipientUserId) return;

  final FcmAlertDeliveryProcessor processor = FcmAlertDeliveryProcessor(
    activeUserId: () => userId,
    showLocalNotification: (FcmAlertPayload current) async {
      if (await _activeSessionUserId(tokenStore) != current.recipientUserId) {
        return;
      }
      await _showAndroidAlertNotification(current);
    },
    recordReceipt: (String alertId) =>
        _recordDeliveryReceipt(alertId, userId, tokenStore),
  );
  await processor.handle(message.data, showLocal: Platform.isAndroid);
}

Future<void> _showAndroidAlertNotification(FcmAlertPayload alert) async {
  if (!Platform.isAndroid) return;

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

  final FlutterLocalNotificationsPlugin local =
      FlutterLocalNotificationsPlugin();
  await local.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  final AndroidFlutterLocalNotificationsPlugin? android =
      local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannel(sos);
  await android?.createNotificationChannel(alerts);
  await local.show(
    notificationIdForAlert(alert.alertId),
    alert.title,
    alert.body,
    NotificationDetails(
      android: buildAlertAndroidDetails(severity: alert.severity, type: ''),
    ),
    payload: alert.alertId,
  );
}

TokenStore _backgroundTokenStore() {
  return TokenStore(
    const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    ),
  );
}

Future<String?> _activeSessionUserId(TokenStore tokenStore) async {
  if (await tokenStore.isPushSignedOut()) return null;
  final String? accessToken = await tokenStore.readAccessToken();
  if (accessToken == null || accessToken.isEmpty) return null;
  final Map<String, dynamic>? user = await tokenStore.readUser();
  final Object? id = user?['id'];
  return id is String && id.isNotEmpty ? id : null;
}

Future<void> _recordDeliveryReceipt(
  String alertId,
  String expectedUserId,
  TokenStore tokenStore,
) async {
  if (await _activeSessionUserId(tokenStore) != expectedUserId) return;

  await ServerOrigin.loadSaved();
  final ApiClient api = ApiClient(
    tokenStore: tokenStore,
    onSessionExpired: () {},
  );
  await AlertsRepository(api).recordDeliveryReceipt(alertId);
}

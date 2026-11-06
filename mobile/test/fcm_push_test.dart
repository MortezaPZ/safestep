import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:safestep/core/push/fcm_alert_payload.dart';
import 'package:safestep/core/push/fcm_token_registration.dart';
import 'package:safestep/core/push/firebase_config_guard.dart';

Map<String, dynamic> _alertData({
  String id = 'alert-1',
  String recipient = 'account-a',
}) =>
    <String, dynamic>{
      'alertId': id,
      'title': 'هشدار اضطراری',
      'body': 'برای بررسی وضعیت اقدام کنید',
      'severity': 'critical',
      'recipientUserId': recipient,
    };

void main() {
  test('parses only addressed FCM data alerts', () {
    final FcmAlertPayload? alert = FcmAlertPayload.tryParse(_alertData());
    expect(alert?.alertId, 'alert-1');
    expect(alert?.recipientUserId, 'account-a');
    expect(FcmAlertPayload.tryParse(<String, dynamic>{'alertId': 'alert-1'}),
        isNull);
    expect(
      FcmAlertPayload.tryParse(_alertData(recipient: '')),
      isNull,
    );
  });

  test('rejects a prior account alert and deduplicates successful callbacks',
      () async {
    String? activeUserId = 'account-a';
    final List<String> calls = <String>[];
    final FcmAlertDeliveryProcessor processor = FcmAlertDeliveryProcessor(
      activeUserId: () => activeUserId,
      showLocalNotification: (FcmAlertPayload alert) async {
        calls.add('show:${alert.alertId}');
      },
      recordReceipt: (String alertId) async {
        calls.add('receipt:$alertId');
      },
    );

    await processor.handle(_alertData(recipient: 'account-b'));
    expect(calls, isEmpty);

    await processor.handle(_alertData());
    await processor.handle(_alertData());
    expect(calls, <String>['show:alert-1', 'receipt:alert-1']);

    activeUserId = null;
    await processor.handle(_alertData(id: 'alert-2'));
    expect(calls, hasLength(2));
  });

  test('retries a failed receipt without displaying the alert twice', () async {
    int shows = 0;
    int receipts = 0;
    final FcmAlertDeliveryProcessor processor = FcmAlertDeliveryProcessor(
      activeUserId: () => 'account-a',
      showLocalNotification: (_) async {
        shows++;
      },
      recordReceipt: (_) async {
        receipts++;
        if (receipts == 1) throw StateError('offline');
      },
    );

    await processor.handle(_alertData());
    await processor.handle(_alertData());

    expect(shows, 1);
    expect(receipts, 2);
  });

  test('missing native Firebase configuration is a recoverable startup path',
      () async {
    expect(
      await initializeFirebaseSafely(
        () async => throw StateError('no Firebase app options'),
      ),
      isFalse,
    );
    expect(await initializeFirebaseSafely(() async {}), isTrue);
  });

  test('login, token refresh, account switch, and logout stay account scoped',
      () async {
    String? currentToken = 'token-1';
    final Map<String, String> tokenOwner = <String, String>{};
    final List<String> registrations = <String>[];
    late FcmTokenRegistration registration;
    registration = FcmTokenRegistration(
      readToken: () async => currentToken,
      registerCurrentDevice: (String token) async {
        final String account = registration.activeAccountId!;
        registrations.add('$account:$token');
        tokenOwner.removeWhere((String _, String value) => value == token);
        tokenOwner[token] = account;
        return true;
      },
    );

    await registration.setCurrentAccount('account-a');
    expect(registrations, <String>['account-a:token-1']);

    currentToken = 'token-2';
    await registration.tokenRefreshed(currentToken);
    expect(registrations.last, 'account-a:token-2');

    await registration.setCurrentAccount(null);
    await registration.tokenRefreshed('token-after-logout');
    expect(registrations, hasLength(2));

    await registration.setCurrentAccount('account-b');
    expect(registrations.last, 'account-b:token-2');
    expect(tokenOwner['token-2'], 'account-b');
  });

  test('logout drains an in-flight registration before device removal',
      () async {
    final Completer<bool> firstRequest = Completer<bool>();
    final List<String> requests = <String>[];
    late FcmTokenRegistration registration;
    String currentBearerAccount = 'account-a';
    registration = FcmTokenRegistration(
      readToken: () async => 'token-1',
      registerCurrentDevice: (String token) {
        final String account = currentBearerAccount;
        requests.add(account);
        if (account == 'account-a') return firstRequest.future;
        return Future<bool>.value(true);
      },
    );

    final Future<void> registering =
        registration.setCurrentAccount('account-a');
    await Future<void>.delayed(Duration.zero);
    currentBearerAccount = 'signed-out';
    var drained = false;
    final Future<void> logout =
        registration.setCurrentAccount(null).then((_) => drained = true);
    await Future<void>.delayed(Duration.zero);
    expect(drained, isFalse);

    firstRequest.complete(true);
    await Future.wait(<Future<void>>[registering, logout]);
    expect(drained, isTrue);
    expect(requests, <String>['account-a']);
  });
}

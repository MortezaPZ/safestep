import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:safestep/core/push/alert_notification_policy.dart';
import 'package:safestep/core/push/fall_notification_payload.dart';
import 'package:safestep/core/push/push_service.dart';

class _StubPushService extends PushService {
  _StubPushService({required this.allowed, required this.message}) : super();

  final bool allowed;
  final String message;

  @override
  bool get available => allowed;

  @override
  Future<String> enableAndConfirm() async => message;
}

void main() {
  test('alert notification policy deduplicates socket reconnect echoes', () {
    final AlertNotificationDeduplicator deduplicator =
        AlertNotificationDeduplicator(capacity: 2);

    expect(deduplicator.reserve('alert-1'), isTrue);
    expect(deduplicator.reserve('alert-1'), isFalse);
    expect(deduplicator.reserve('alert-2'), isTrue);
    expect(deduplicator.reserve('alert-3'), isTrue);
    expect(deduplicator.reserve('alert-1'), isTrue);
  });

  test('alert notification can be retried if local display failed', () {
    final AlertNotificationDeduplicator deduplicator =
        AlertNotificationDeduplicator();

    expect(deduplicator.reserve('alert-1'), isTrue);
    deduplicator.allowRetry('alert-1');
    expect(deduplicator.reserve('alert-1'), isTrue);
  });

  test('critical alerts use the emergency channel and stable OS row id', () {
    final AndroidNotificationDetails details = buildAlertAndroidDetails(
      severity: 'critical',
      type: 'location',
    );

    expect(details.channelId, 'safestep_sos');
    expect(details.importance, Importance.max);
    expect(details.priority, Priority.max);
    expect(
      notificationIdForAlert('alert-42'),
      notificationIdForAlert('alert-42'),
    );
    expect(notificationIdForAlert('alert-42'), isNot(0));
  });

  test('ordinary alerts use high priority alerts channel', () {
    final AndroidNotificationDetails details = buildAlertAndroidDetails(
      severity: 'warning',
      type: 'geofence_exit',
    );

    expect(details.channelId, 'safestep_alerts');
    expect(details.importance, Importance.high);
    expect(details.priority, Priority.high);
  });

  test('fall alert chronometer counts down to the incident deadline', () {
    final DateTime deadline = DateTime.utc(2026, 11, 6, 12, 0, 30);
    final AndroidNotificationDetails details =
        buildFallCheckAndroidDetails(deadline);

    expect(details.when, deadline.millisecondsSinceEpoch);
    expect(details.usesChronometer, isTrue);
    expect(details.chronometerCountDown, isTrue);
    expect(details.actions?.map((AndroidNotificationAction a) => a.id),
        <String>['fall_ok', 'fall_help']);
  });

  test('fall notification payload keeps the same event and original deadline',
      () {
    final DateTime startedAt = DateTime.utc(2026, 11, 6, 12);
    final FallNotificationPayload original = FallNotificationPayload(
      eventId: 'fall-event-1',
      startedAt: startedAt,
      deadline: startedAt.add(const Duration(seconds: 30)),
    );

    final FallNotificationPayload? parsed =
        FallNotificationPayload.tryParse(original.encode());

    expect(parsed?.eventId, 'fall-event-1');
    expect(parsed?.startedAt, startedAt.toLocal());
    expect(parsed?.deadline, original.deadline.toLocal());
    expect(parsed?.remainingSeconds(startedAt.add(const Duration(seconds: 7))),
        23);
  });

  test('does not describe notifications as enabled when permission is denied',
      () async {
    final PushStatus status = await enablePushAndReadStatus(
      _StubPushService(allowed: false, message: 'مجوز اعلان داده نشده است'),
    );

    expect(status.available, isFalse);
    expect(pushPermissionFeedback(status), 'مجوز اعلان داده نشده است');
  });

  test(
      'reports local notification readiness only after permission is available',
      () async {
    final PushStatus status = await enablePushAndReadStatus(
      _StubPushService(allowed: true, message: 'اعلان محلی فعال است'),
    );

    expect(status.available, isTrue);
    expect(pushPermissionFeedback(status), 'اعلان محلی آزمایشی نمایش داده شد');
  });
}

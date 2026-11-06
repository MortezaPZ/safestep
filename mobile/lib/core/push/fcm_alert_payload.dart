/// Alert data contract shared by Firebase callbacks and the local notifier.
///
/// Android FCM messages are data-only so the app can display a single local
/// notification. iOS keeps its APNs alert; this parser is still used for any
/// callback iOS actually delivers.
class FcmAlertPayload {
  const FcmAlertPayload({
    required this.alertId,
    required this.title,
    required this.body,
    required this.severity,
    required this.recipientUserId,
  });

  final String alertId;
  final String title;
  final String body;
  final String severity;
  final String recipientUserId;

  static FcmAlertPayload? tryParse(Map<String, dynamic> data) {
    final Object? rawId = data['alertId'];
    final Object? rawTitle = data['title'];
    final Object? rawBody = data['body'];
    final Object? rawSeverity = data['severity'];
    final Object? rawRecipient = data['recipientUserId'];
    if (rawId is! String || rawId.trim().isEmpty) return null;
    if (rawTitle is! String || rawTitle.trim().isEmpty) return null;
    if (rawBody is! String || rawSeverity is! String || rawSeverity.isEmpty) {
      return null;
    }
    if (rawRecipient is! String || rawRecipient.trim().isEmpty) return null;
    return FcmAlertPayload(
      alertId: rawId.trim(),
      title: rawTitle.trim(),
      body: rawBody,
      severity: rawSeverity.trim(),
      recipientUserId: rawRecipient.trim(),
    );
  }
}

/// Invokes a local notice and the authenticated receipt callback at most once
/// per successful action. Failed actions remain eligible for an FCM retry.
class FcmAlertDeliveryProcessor {
  FcmAlertDeliveryProcessor({
    required Future<void> Function(FcmAlertPayload alert) showLocalNotification,
    required Future<void> Function(String alertId) recordReceipt,
    required this.activeUserId,
  })  : _showLocalNotification = showLocalNotification,
        _recordReceipt = recordReceipt;

  final Future<void> Function(FcmAlertPayload alert) _showLocalNotification;
  final Future<void> Function(String alertId) _recordReceipt;
  final String? Function() activeUserId;
  final Set<String> _shownAlertIds = <String>{};
  final Set<String> _receivedAlertIds = <String>{};
  final Map<String, Future<void>> _inFlight = <String, Future<void>>{};

  Future<FcmAlertPayload?> handle(
    Map<String, dynamic> data, {
    bool showLocal = true,
  }) async {
    final FcmAlertPayload? alert = FcmAlertPayload.tryParse(data);
    if (alert == null) return null;
    if (activeUserId() != alert.recipientUserId) return null;

    final Future<void>? active = _inFlight[alert.alertId];
    if (active != null) {
      await active;
      return alert;
    }

    final Future<void> operation = _process(alert, showLocal: showLocal);
    _inFlight[alert.alertId] = operation;
    try {
      await operation;
    } finally {
      _inFlight.remove(alert.alertId);
    }
    return alert;
  }

  Future<void> _process(
    FcmAlertPayload alert, {
    required bool showLocal,
  }) async {
    if (showLocal && !_shownAlertIds.contains(alert.alertId)) {
      try {
        await _showLocalNotification(alert);
        _shownAlertIds.add(alert.alertId);
      } catch (_) {
        // Keep it retryable if FCM delivers the same alert again.
      }
    }

    if (!_receivedAlertIds.contains(alert.alertId)) {
      try {
        await _recordReceipt(alert.alertId);
        _receivedAlertIds.add(alert.alertId);
      } catch (_) {
        // The endpoint is idempotent; allow a later callback to retry it.
      }
    }
  }
}

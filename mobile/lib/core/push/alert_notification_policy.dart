import 'dart:collection';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class AlertNotificationDeduplicator {
  AlertNotificationDeduplicator({this.capacity = 100});

  final int capacity;
  final LinkedHashSet<String> _shownIds = LinkedHashSet<String>();

  bool reserve(String alertId) {
    if (!_shownIds.add(alertId)) return false;
    while (_shownIds.length > capacity) {
      _shownIds.remove(_shownIds.first);
    }
    return true;
  }

  void allowRetry(String alertId) => _shownIds.remove(alertId);
}

AndroidNotificationDetails buildAlertAndroidDetails({
  required String severity,
  required String type,
}) {
  final bool critical =
      severity == 'critical' || type == 'sos' || type == 'fall_detected';
  return AndroidNotificationDetails(
    critical ? 'safestep_sos' : 'safestep_alerts',
    critical ? 'هشدار اضطراری' : 'هشدارها',
    channelDescription: critical
        ? 'هشدار SOS و رویدادهای بحرانی'
        : 'خروج از محدوده و هشدارهای عادی',
    importance: critical ? Importance.max : Importance.high,
    priority: critical ? Priority.max : Priority.high,
    category: critical
        ? AndroidNotificationCategory.alarm
        : AndroidNotificationCategory.event,
    playSound: true,
    enableVibration: critical,
  );
}

int notificationIdForAlert(String alertId) {
  // Stable FNV-1a 31-bit id: duplicate deliveries update the same OS row.
  int hash = 0x811c9dc5;
  for (final int codeUnit in alertId.codeUnits) {
    hash = ((hash ^ codeUnit) * 0x01000193) & 0x7fffffff;
  }
  return hash == 0 ? 1 : hash;
}

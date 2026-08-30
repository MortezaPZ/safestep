import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../auth/domain/auth_models.dart';

/// یک هشدار.
@immutable
class AlertItem {
  const AlertItem({
    required this.id,
    required this.type,
    required this.severity,
    required this.title,
    required this.body,
    required this.createdAt,
    this.subjectName,
    this.subjectId,
    this.zoneName,
    this.isRead = false,
    this.resolvedAt,
  });

  final String id;
  final String type;
  final String severity;
  final String title;
  final String body;
  final DateTime createdAt;
  final String? subjectName;
  final String? subjectId;
  final String? zoneName;
  final bool isRead;
  final DateTime? resolvedAt;

  bool get isCritical => severity == 'critical';
  bool get isResolved => resolvedAt != null;

  /// برچسب فارسی نوع هشدار.
  ///
  /// `fall_detected` از همین حالا پشتیبانی می‌شود گرچه هیچ منطقی در فاز
  /// اول تولیدش نمی‌کند — تا در فاز سوم، رابط کاربری نیازی به تغییر
  /// نداشته باشد.
  String get typeLabel {
    switch (type) {
      case 'sos':
        return 'درخواست کمک';
      case 'zone_exit':
        return 'خروج از محدوده';
      case 'zone_enter':
        return 'بازگشت به محدوده';
      case 'long_stop':
        return 'توقف طولانی';
      case 'gps_lost':
        return 'قطع موقعیت';
      case 'low_battery':
        return 'باتری کم';
      case 'fall_detected':
        return 'تشخیص سقوط';
      default:
        return 'هشدار';
    }
  }

  factory AlertItem.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? subject = Json.mapOrNull(json['subject']);

    return AlertItem(
      id: Json.str(json, 'id'),
      type: Json.str(json, 'type', 'unknown'),
      severity: Json.str(json, 'severity', 'info'),
      title: Json.str(json, 'title', 'هشدار'),
      body: Json.str(json, 'body'),
      createdAt: Json.date(json, 'createdAt') ?? DateTime.now(),
      subjectName: subject == null ? null : Json.strOrNull(subject, 'fullName'),
      subjectId: subject == null ? null : Json.strOrNull(subject, 'id'),
      zoneName: Json.strOrNull(json, 'zoneName'),
      isRead: Json.boolOf(json, 'isRead'),
      resolvedAt: Json.date(json, 'resolvedAt'),
    );
  }
}

/// نتیجه‌ی فهرست هشدارها.
@immutable
class AlertsPage {
  const AlertsPage({
    this.alerts = const <AlertItem>[],
    this.unreadCount = 0,
    this.countsByType = const <String, int>{},
  });

  final List<AlertItem> alerts;
  final int unreadCount;
  final Map<String, int> countsByType;
}

class AlertsRepository {
  AlertsRepository(this._api);

  final ApiClient _api;

  Future<AlertsPage> list({
    String? subjectId,
    List<String>? types,
    bool unreadOnly = false,
    int limit = 100,
  }) async {
    return _api.get<AlertsPage>(
      ApiEndpoints.alerts,
      (dynamic data) {
        if (data is! Map<String, dynamic>) return const AlertsPage();

        final Map<String, int> counts = <String, int>{};
        final Object? rawCounts = data['countsByType'];
        if (rawCounts is Map) {
          rawCounts.forEach((Object? key, Object? value) {
            if (key is String && value is num) counts[key] = value.toInt();
          });
        }

        return AlertsPage(
          alerts: Json.mapList(data['alerts'])
              .map(AlertItem.fromJson)
              .toList(growable: false),
          unreadCount: Json.intOf(data, 'unreadCount'),
          countsByType: counts,
        );
      },
      query: <String, dynamic>{
        if (subjectId != null) 'userId': subjectId,
        if (types != null && types.isNotEmpty) 'types': types.join(','),
        if (unreadOnly) 'unreadOnly': 'true',
        'limit': limit,
      },
    );
  }

  /// علامت‌گذاری به‌عنوان خوانده‌شده.
  ///
  /// این فقط یک پرچم رابط کاربری نیست: سرور همین لحظه را به‌عنوان
  /// «زمان اطلاعِ انسان» در جدول `alert_deliveries` ثبت می‌کند — همان
  /// عددی که در فصل ارزیابی، تأخیر واقعی سامانه را می‌سازد.
  Future<void> markRead(String alertId) async {
    await _api.post<void>(ApiEndpoints.alertRead(alertId), (dynamic _) {});
  }

  Future<void> markAllRead() async {
    await _api.post<void>(ApiEndpoints.alertsReadAll, (dynamic _) {});
  }

  /// بستن یک هشدار — «رسیدگی شد».
  Future<void> resolve(String alertId) async {
    await _api.post<void>(ApiEndpoints.alertResolve(alertId), (dynamic _) {});
  }
}

final Provider<AlertsRepository> alertsRepositoryProvider =
    Provider<AlertsRepository>((ref) {
  return AlertsRepository(ref.watch(apiClientProvider));
});

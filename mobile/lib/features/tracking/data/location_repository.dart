import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/utils/app_exception.dart';
import '../../auth/domain/auth_models.dart';
import '../domain/location_sample.dart';

/// وضعیت خودِ کاربر، همان چیزی که سرور در `/locations/status` برمی‌گرداند.
class OwnStatus {
  const OwnStatus({
    this.sharingEnabled = true,
    this.viewerCount = 0,
    this.viewerNames = const <String>[],
    this.batteryLevel,
    this.lastRecordedAt,
    this.zoneStatus = 'unknown',
    this.statusReason,
    this.gpsStale = false,
    this.isSimulated = false,
  });

  final bool sharingEnabled;
  final int viewerCount;
  final List<String> viewerNames;
  final int? batteryLevel;
  final DateTime? lastRecordedAt;

  /// خلاصه‌ی وضعیت نسبت به محدوده‌های امن: `inside` | `outside` | `unknown`
  final String zoneStatus;

  /// توضیح فارسیِ آماده‌ی نمایش که سرور می‌سازد
  final String? statusReason;

  /// آیا آخرین موقعیت قدیمی است (سرور تشخیص قطع GPS داده)
  final bool gpsStale;

  final bool isSimulated;

  factory OwnStatus.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? sharing = Json.mapOrNull(json['sharing']);
    // سرور آخرین موقعیت را با کلید `location` برمی‌گرداند
    final Map<String, dynamic>? ping = Json.mapOrNull(json['location']);
    final Map<String, dynamic>? gps = Json.mapOrNull(json['gps']);

    final List<String> names = <String>[];
    if (sharing != null) {
      for (final Map<String, dynamic> viewer in Json.mapList(sharing['viewers'])) {
        final String name = Json.str(viewer, 'fullName');
        if (name.isNotEmpty) names.add(name);
      }
    }

    return OwnStatus(
      sharingEnabled: sharing == null ? true : Json.boolOf(sharing, 'enabled', true),
      viewerCount: sharing == null ? 0 : Json.intOf(sharing, 'viewerCount'),
      viewerNames: names,
      batteryLevel: Json.intOrNull(json, 'batteryLevel'),
      lastRecordedAt: ping == null ? null : Json.date(ping, 'recordedAt'),
      zoneStatus: Json.str(json, 'status', 'unknown'),
      statusReason: Json.strOrNull(json, 'statusReason'),
      gpsStale: gps == null ? false : Json.boolOf(gps, 'isStale'),
      isSimulated: ping == null ? false : Json.boolOf(ping, 'isSimulated'),
    );
  }
}

/// نتیجه‌ی ارسال یک دسته از صف.
class BatchResult {
  const BatchResult({required this.accepted, required this.duplicates});

  final int accepted;
  final int duplicates;
}

class LocationRepository {
  LocationRepository(this._api);

  final ApiClient _api;

  /// ارسال یک نمونه‌ی زنده.
  Future<void> sendPing(LocationSample sample) async {
    await _api.post<void>(
      ApiEndpoints.ping,
      (dynamic _) {},
      body: sample.toJson(),
    );
  }

  /// تخلیه‌ی دسته‌ای صف آفلاین.
  Future<BatchResult> sendBatch(List<LocationSample> samples) async {
    return _api.post<BatchResult>(
      ApiEndpoints.batch,
      (dynamic data) {
        final Map<String, dynamic>? map =
            data is Map<String, dynamic> ? data : null;
        return BatchResult(
          accepted: map == null ? 0 : Json.intOf(map, 'accepted'),
          duplicates: map == null ? 0 : Json.intOf(map, 'duplicates'),
        );
      },
      body: <String, dynamic>{
        'pings': samples
            .map((LocationSample s) => s.copyWith(isQueuedReplay: true).toJson())
            .toList(),
      },
    );
  }

  Future<OwnStatus> ownStatus() async {
    return _api.get<OwnStatus>(
      ApiEndpoints.locationStatus,
      (dynamic data) {
        if (data is! Map<String, dynamic>) {
          throw const AppException(
            message: 'پاسخ سرور قابل خواندن نبود.',
            code: 'BAD_PAYLOAD',
          );
        }
        return OwnStatus.fromJson(data);
      },
    );
  }

  /// روشن یا خاموش کردن اشتراک‌گذاری موقعیت.
  ///
  /// این تنها کلیدی است که کاربر اصلی برای پس گرفتن حریم خصوصی‌اش دارد و
  /// باید فوری اثر کند — سرور با خاموش شدنش، هم پخش زنده و هم هشدارهای
  /// مبتنی بر موقعیت را متوقف می‌کند، ولی SOS همچنان کار می‌کند.
  Future<bool> setSharing(bool enabled) async {
    return _api.put<bool>(
      ApiEndpoints.sharing,
      (dynamic data) {
        final Map<String, dynamic>? settings = data is Map<String, dynamic>
            ? Json.mapOrNull(data['settings'])
            : null;
        return settings == null
            ? enabled
            : Json.boolOf(settings, 'locationSharingEnabled', enabled);
      },
      body: <String, dynamic>{'enabled': enabled},
    );
  }
}

final Provider<LocationRepository> locationRepositoryProvider =
    Provider<LocationRepository>((ref) {
  return LocationRepository(ref.watch(apiClientProvider));
});

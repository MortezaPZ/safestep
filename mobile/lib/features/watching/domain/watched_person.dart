import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../auth/domain/auth_models.dart';
import '../../pairing/domain/pairing_models.dart';

/// وضعیت یک فرد تحت پایش، از دید مراقب.
///
/// ── چرا `hidden` یک حالت درجه‌یک است ─────────────────────────────────────
/// وقتی کاربر اصلی اشتراک‌گذاری را خاموش می‌کند، سرور به‌جای خطا یک پاسخ
/// موفق با `hidden: true` و یک پیام محترمانه برمی‌گرداند. این تصمیم عمدی
/// است: «خطا» به مراقب حس می‌دهد چیزی خراب شده و باید درستش کند، در حالی
/// که این یک انتخابِ معتبرِ کاربر اصلی است و باید همان‌طور هم نمایش داده
/// شود.
@immutable
class WatchedPerson {
  const WatchedPerson({
    required this.userId,
    required this.person,
    this.permissions = const <SharePermission>[],
    this.hidden = false,
    this.hiddenMessage,
    this.location,
    this.zoneStatus = 'unknown',
    this.zoneNames = const <String>[],
    this.gpsStale = false,
    this.silentSeconds = 0,
    this.isOnline = false,
    this.guardianshipId,
  });

  final String userId;
  final RelatedPerson person;
  final List<SharePermission> permissions;

  /// کاربر اشتراک‌گذاری را خاموش کرده است
  final bool hidden;
  final String? hiddenMessage;

  final TrackPoint? location;

  /// `inside` | `outside` | `unknown`
  final String zoneStatus;

  /// نام محدوده‌هایی که فرد داخلشان است
  final List<String> zoneNames;

  /// آخرین موقعیت قدیمی است (سرور تشخیص قطع GPS داده)
  final bool gpsStale;
  final int silentSeconds;

  /// اتصال زنده‌ی WebSocket دارد
  final bool isOnline;

  final String? guardianshipId;

  bool get hasLocation => location != null;

  factory WatchedPerson.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? userJson = Json.mapOrNull(json['user']);
    final Map<String, dynamic>? locationJson = Json.mapOrNull(json['location']);
    final Map<String, dynamic>? statusJson = Json.mapOrNull(json['status']);
    final Map<String, dynamic>? gpsJson = Json.mapOrNull(json['gps']);

    final List<String> zoneNames = <String>[];
    if (statusJson != null) {
      for (final Map<String, dynamic> zone
          in Json.mapList(statusJson['insideZones'])) {
        final String name = Json.str(zone, 'zoneName');
        if (name.isNotEmpty) zoneNames.add(name);
      }
    }

    return WatchedPerson(
      userId: Json.str(json, 'userId'),
      person: RelatedPerson.tryFrom(userJson) ??
          RelatedPerson(id: Json.str(json, 'userId'), fullName: 'بدون نام'),
      permissions: SharePermission.parseList(Json.strList(json, 'permissions')),
      hidden: Json.boolOf(json, 'hidden'),
      hiddenMessage: Json.strOrNull(json, 'message'),
      location:
          locationJson == null ? null : TrackPoint.fromJson(locationJson),
      // در پاسخ فهرست پایش، `status` یک شیء است (نه رشته مثل
      // ‎/locations/status‎). این تفاوت در قرارداد سرور واقعی است.
      zoneStatus:
          statusJson == null ? 'unknown' : Json.str(statusJson, 'status', 'unknown'),
      zoneNames: zoneNames,
      gpsStale: gpsJson != null && Json.boolOf(gpsJson, 'isStale'),
      silentSeconds: gpsJson == null ? 0 : Json.intOf(gpsJson, 'silentSeconds'),
      isOnline: Json.boolOf(json, 'isOnline'),
      guardianshipId: Json.strOrNull(json, 'guardianshipId'),
    );
  }

  WatchedPerson copyWith({TrackPoint? location, bool? isOnline}) {
    return WatchedPerson(
      userId: userId,
      person: person,
      permissions: permissions,
      hidden: hidden,
      hiddenMessage: hiddenMessage,
      location: location ?? this.location,
      zoneStatus: zoneStatus,
      zoneNames: zoneNames,
      gpsStale: gpsStale,
      silentSeconds: silentSeconds,
      isOnline: isOnline ?? this.isOnline,
      guardianshipId: guardianshipId,
    );
  }
}

/// یک نقطه از مسیر.
@immutable
class TrackPoint {
  const TrackPoint({
    required this.lat,
    required this.lng,
    required this.recordedAt,
    this.accuracyM,
    this.speedMps,
    this.batteryLevel,
    this.isSimulated = false,
  });

  final double lat;
  final double lng;
  final DateTime recordedAt;
  final double? accuracyM;
  final double? speedMps;
  final int? batteryLevel;
  final bool isSimulated;

  factory TrackPoint.fromJson(Map<String, dynamic> json) {
    return TrackPoint(
      lat: Json.dbl(json, 'lat'),
      lng: Json.dbl(json, 'lng'),
      recordedAt: Json.date(json, 'recordedAt') ?? DateTime.now(),
      accuracyM: Json.dblOrNull(json, 'accuracyM'),
      speedMps: Json.dblOrNull(json, 'speedMps'),
      batteryLevel: Json.intOrNull(json, 'batteryLevel'),
      isSimulated: Json.boolOf(json, 'isSimulated'),
    );
  }
}

/// یک روز از تاریخچه — ورودی انتخابگر روز.
@immutable
class HistoryDay {
  const HistoryDay({
    required this.day,
    required this.pingCount,
    this.firstAt,
    this.lastAt,
    this.hasSimulated = false,
  });

  final DateTime day;
  final int pingCount;
  final DateTime? firstAt;
  final DateTime? lastAt;
  final bool hasSimulated;

  factory HistoryDay.fromJson(Map<String, dynamic> json) {
    return HistoryDay(
      day: Json.date(json, 'day') ?? DateTime.now(),
      pingCount: Json.intOf(json, 'pingCount'),
      firstAt: Json.date(json, 'firstAt'),
      lastAt: Json.date(json, 'lastAt'),
      hasSimulated: Json.boolOf(json, 'hasSimulated'),
    );
  }
}

/// نتیجه‌ی تاریخچه‌ی یک بازه.
@immutable
class HistoryResult {
  const HistoryResult({
    this.points = const <TrackPoint>[],
    this.hidden = false,
    this.pingCount = 0,
    this.firstAt,
    this.lastAt,
    this.avgSpeedMps,
    this.minBattery,
  });

  final List<TrackPoint> points;
  final bool hidden;
  final int pingCount;
  final DateTime? firstAt;
  final DateTime? lastAt;
  final double? avgSpeedMps;
  final int? minBattery;

  bool get isEmpty => points.isEmpty;

  /// طول تقریبی مسیر بر حسب متر.
  ///
  /// با فرمول هاورساین محاسبه می‌شود — همان فرمولی که سرور برای Geofence
  /// استفاده می‌کند. اینجا هم تکرار شده تا نمایش «مسافت امروز» یک
  /// رفت‌وبرگشت اضافه به سرور نخواهد.
  double get distanceM {
    if (points.length < 2) return 0;

    double total = 0;
    for (int i = 1; i < points.length; i++) {
      total += _haversine(points[i - 1], points[i]);
    }
    return total;
  }

  factory HistoryResult.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? stats = Json.mapOrNull(json['stats']);

    return HistoryResult(
      points: Json.mapList(json['points'])
          .map(TrackPoint.fromJson)
          .toList(growable: false),
      hidden: Json.boolOf(json, 'hidden'),
      pingCount: stats == null ? 0 : Json.intOf(stats, 'pingCount'),
      firstAt: stats == null ? null : Json.date(stats, 'firstAt'),
      lastAt: stats == null ? null : Json.date(stats, 'lastAt'),
      avgSpeedMps: stats == null ? null : Json.dblOrNull(stats, 'avgSpeedMps'),
      minBattery: stats == null ? null : Json.intOrNull(stats, 'minBattery'),
    );
  }

  static double _haversine(TrackPoint a, TrackPoint b) {
    const double earthRadiusM = 6371000;

    double toRad(double degrees) => degrees * math.pi / 180;

    final double dLat = toRad(b.lat - a.lat);
    final double dLng = toRad(b.lng - a.lng);
    final double lat1 = toRad(a.lat);
    final double lat2 = toRad(b.lat);

    final double h = math.pow(math.sin(dLat / 2), 2).toDouble() +
        math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLng / 2), 2).toDouble();

    return 2 * earthRadiusM * math.asin(math.sqrt(h).clamp(0.0, 1.0));
  }
}

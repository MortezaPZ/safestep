import 'package:flutter/foundation.dart';

/// یک نمونه‌ی موقعیت، از لحظه‌ی خوانده شدن از GPS تا لحظه‌ی رسیدن به سرور.
///
/// ── چرا `clientUuid` از همین‌جا ساخته می‌شود ────────────────────────────
/// شناسه در **لحظه‌ی ثبت روی گوشی** ساخته می‌شود، نه هنگام ارسال. اگر
/// هنگام ارسال ساخته شود، یک نمونه‌ی تکراری با دو شناسه‌ی متفاوت به سرور
/// می‌رسد و ایندکس یکتای دیتابیس هیچ کاری نمی‌تواند بکند.
///
/// سناریوی واقعی که این را لازم می‌کند: اپ نمونه را می‌فرستد، سرور ذخیره
/// می‌کند، و درست پیش از رسیدن پاسخ، اینترنت قطع می‌شود. اپ فکر می‌کند
/// ارسال شکست خورده و دوباره می‌فرستد.
@immutable
class LocationSample {
  const LocationSample({
    required this.clientUuid,
    required this.lat,
    required this.lng,
    required this.recordedAt,
    this.accuracyM,
    this.speedMps,
    this.headingDeg,
    this.batteryLevel,
    this.provider,
    this.isQueuedReplay = false,
  });

  /// شناسه‌ی یکتای این نمونه — پایه‌ی بی‌اثرسازی تکرار در سرور
  final String clientUuid;

  final double lat;
  final double lng;

  /// زمان خوانده شدن از حسگر (نه زمان ارسال)
  final DateTime recordedAt;

  final double? accuracyM;
  final double? speedMps;
  final double? headingDeg;
  final int? batteryLevel;

  /// gps | fused | network — برای تفکیک خطای GPS خالص از موقعیت ترکیبی
  final String? provider;

  /// آیا این نمونه از صف آفلاین و با تأخیر فرستاده می‌شود؟
  final bool isQueuedReplay;

  /// بدنه‌ی JSON برای ارسال به سرور.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'clientUuid': clientUuid,
        'lat': lat,
        'lng': lng,
        'recordedAt': recordedAt.toUtc().toIso8601String(),
        if (accuracyM != null) 'accuracyM': accuracyM,
        if (speedMps != null) 'speedMps': speedMps,
        if (headingDeg != null) 'headingDeg': headingDeg,
        if (batteryLevel != null) 'batteryLevel': batteryLevel,
        if (provider != null) 'provider': provider,
        'isQueuedReplay': isQueuedReplay,
      };

  /// ردیف دیتابیس محلی.
  Map<String, Object?> toRow() => <String, Object?>{
        'client_uuid': clientUuid,
        'lat': lat,
        'lng': lng,
        'recorded_at': recordedAt.toUtc().millisecondsSinceEpoch,
        'accuracy_m': accuracyM,
        'speed_mps': speedMps,
        'heading_deg': headingDeg,
        'battery_level': batteryLevel,
        'provider': provider,
      };

  factory LocationSample.fromRow(Map<String, Object?> row) {
    return LocationSample(
      clientUuid: row['client_uuid'] as String,
      lat: (row['lat'] as num).toDouble(),
      lng: (row['lng'] as num).toDouble(),
      recordedAt: DateTime.fromMillisecondsSinceEpoch(
        row['recorded_at'] as int,
        isUtc: true,
      ).toLocal(),
      accuracyM: (row['accuracy_m'] as num?)?.toDouble(),
      speedMps: (row['speed_mps'] as num?)?.toDouble(),
      headingDeg: (row['heading_deg'] as num?)?.toDouble(),
      batteryLevel: row['battery_level'] as int?,
      provider: row['provider'] as String?,
      // هر چیزی که از صف بیرون می‌آید، طبق تعریف یک ارسال تأخیری است
      isQueuedReplay: true,
    );
  }

  LocationSample copyWith({bool? isQueuedReplay, int? batteryLevel}) {
    return LocationSample(
      clientUuid: clientUuid,
      lat: lat,
      lng: lng,
      recordedAt: recordedAt,
      accuracyM: accuracyM,
      speedMps: speedMps,
      headingDeg: headingDeg,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      provider: provider,
      isQueuedReplay: isQueuedReplay ?? this.isQueuedReplay,
    );
  }
}

/// وضعیت مجوز موقعیت — سه حالتی که رفتار اپ را تعیین می‌کنند.
///
/// اندروید و iOS حالت‌های ریزتری دارند، ولی از دید کاربر فقط این‌ها مهم‌اند:
/// یا می‌شود ردیابی کرد، یا باید چیزی روشن شود، یا کاربر گفته «نه» و باید
/// به تنظیمات برود.
enum LocationPermissionState {
  /// همه‌چیز آماده است
  granted,

  /// فقط هنگام باز بودن اپ — ردیابی پس‌زمینه کار نمی‌کند
  whileInUseOnly,

  /// کاربر رد کرده، ولی می‌شود دوباره پرسید
  denied,

  /// کاربر «دیگر نپرس» زده — تنها راه، رفتن به تنظیمات سیستم است
  permanentlyDenied,

  /// خودِ سرویس مکان گوشی خاموش است
  serviceDisabled,
}

/// وضعیت کلی ردیابی، همان چیزی که روی صفحه نشان داده می‌شود.
enum TrackingStatus {
  /// خاموش — کاربر روشنش نکرده یا اشتراک‌گذاری را قطع کرده
  off,

  /// در حال آماده‌سازی (گرفتن مجوز، اولین قفل GPS)
  starting,

  /// فعال و در حال ارسال
  live,

  /// فعال، ولی ارسال ممکن نیست و داده در صف می‌ماند
  offline,

  /// متوقف به‌دلیل مشکل مجوز یا خاموش بودن مکان‌یاب
  blocked,
}

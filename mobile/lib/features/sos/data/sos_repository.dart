import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../auth/domain/auth_models.dart';

/// نتیجه‌ی فعال شدن هشدار اضطراری.
class SosResult {
  const SosResult({
    required this.alertId,
    required this.recipientCount,
    required this.recipientNames,
    this.locationSource = 'unknown',
    this.isStale = false,
  });

  final String alertId;
  final int recipientCount;
  final List<String> recipientNames;

  /// `live` یا `last_known` — سرور می‌گوید موقعیت از کجا آمده
  final String locationSource;

  /// آیا موقعیت قدیمی بوده است
  final bool isStale;

  bool get deliveredToSomeone => recipientCount > 0;

  factory SosResult.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? alert = Json.mapOrNull(json['alert']);

    final List<String> names = <String>[];
    for (final Map<String, dynamic> person in Json.mapList(json['recipients'])) {
      final String name = Json.str(person, 'fullName');
      if (name.isNotEmpty) names.add(name);
    }

    // سرور اطلاعات موقعیت را در یک شیء تودرتو برمی‌گرداند
    final Map<String, dynamic>? location = Json.mapOrNull(json['location']);

    return SosResult(
      alertId: alert == null ? '' : Json.str(alert, 'id'),
      recipientCount: names.length,
      recipientNames: names,
      locationSource:
          location == null ? 'none' : Json.str(location, 'source', 'none'),
      isStale: location != null && Json.boolOf(location, 'isStale'),
    );
  }
}

class SosRepository {
  SosRepository(this._api);

  final ApiClient _api;

  /// فعال کردن هشدار اضطراری.
  ///
  /// ── چرا مختصات اختیاری است ─────────────────────────────────────────────
  /// اگر قفل GPS در چند ثانیه به دست نیامد، درخواست **بدون مختصات**
  /// فرستاده می‌شود و سرور از آخرین موقعیت شناخته‌شده استفاده می‌کند و
  /// صریحاً برچسب «قدیمی» می‌زند. منتظر ماندن برای موقعیت دقیق در وضعیت
  /// اضطراری، بدترین انتخاب ممکن است.
  ///
  /// مهلت این درخواست هم عمداً کوتاه‌تر از بقیه است.
  Future<SosResult> trigger({
    double? lat,
    double? lng,
    double? accuracyM,
    int? batteryLevel,
    String? note,
  }) async {
    return _api.post<SosResult>(
      ApiEndpoints.sos,
      (dynamic data) {
        if (data is! Map<String, dynamic>) {
          return const SosResult(
            alertId: '',
            recipientCount: 0,
            recipientNames: <String>[],
          );
        }
        return SosResult.fromJson(data);
      },
      body: <String, dynamic>{
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (accuracyM != null) 'accuracyM': accuracyM,
        if (batteryLevel != null) 'batteryLevel': batteryLevel,
        if (note != null && note.isNotEmpty) 'note': note,
      },
      timeout: AppConfig.sosTimeout,
    );
  }

  /// فهرست کسانی که هشدار اضطراری به آن‌ها می‌رسد.
  ///
  /// پیش از فشردن دکمه نمایش داده می‌شود: کاربر باید بداند درخواست کمکش به
  /// چه کسی می‌رسد. اگر فهرست خالی باشد، باید همان‌جا بفهمد — نه در لحظه‌ی
  /// اضطرار.
  Future<List<String>> emergencyContacts() async {
    return _api.get<List<String>>(
      ApiEndpoints.sosContacts,
      (dynamic data) {
        if (data is! Map<String, dynamic>) return const <String>[];

        final List<String> names = <String>[];
        for (final Map<String, dynamic> person
            in Json.mapList(data['contacts'])) {
          final String name = Json.str(person, 'fullName');
          if (name.isNotEmpty) names.add(name);
        }
        return names;
      },
    );
  }
}

final Provider<SosRepository> sosRepositoryProvider = Provider<SosRepository>((ref) {
  return SosRepository(ref.watch(apiClientProvider));
});

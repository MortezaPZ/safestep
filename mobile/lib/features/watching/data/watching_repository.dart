import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/utils/app_exception.dart';
import '../../auth/domain/auth_models.dart';
import '../domain/watched_person.dart';

/// APIهای سمت مراقب.
class WatchingRepository {
  WatchingRepository(this._api);

  final ApiClient _api;

  /// فهرست افراد تحت پایش، به‌همراه آخرین موقعیت و وضعیتشان.
  ///
  /// یک درخواست، همه‌ی اطلاعات صفحه‌ی خانه‌ی مراقب را می‌دهد. جایگزینش
  /// یک درخواست برای فهرست و N درخواست برای موقعیت هر نفر بود.
  Future<List<WatchedPerson>> watchList() async {
    return _api.get<List<WatchedPerson>>(
      ApiEndpoints.watching,
      (dynamic data) {
        if (data is! Map<String, dynamic>) return const <WatchedPerson>[];
        return Json.mapList(data['watching'])
            .map(WatchedPerson.fromJson)
            .toList(growable: false);
      },
    );
  }

  /// موقعیت فعلی یک فرد مشخص.
  Future<WatchedPerson> currentLocation(String userId) async {
    return _api.get<WatchedPerson>(
      ApiEndpoints.currentLocation,
      (dynamic data) {
        if (data is! Map<String, dynamic>) {
          throw const AppException(
            message: 'پاسخ سرور قابل خواندن نبود.',
            code: 'BAD_PAYLOAD',
          );
        }
        return WatchedPerson.fromJson(data);
      },
      query: <String, dynamic>{'userId': userId},
    );
  }

  /// روزهایی که برایشان تاریخچه وجود دارد.
  Future<List<HistoryDay>> historyDays(String userId) async {
    return _api.get<List<HistoryDay>>(
      ApiEndpoints.historyDays,
      (dynamic data) {
        if (data is! Map<String, dynamic>) return const <HistoryDay>[];
        return Json.mapList(data['days'])
            .map(HistoryDay.fromJson)
            .toList(growable: false);
      },
      query: <String, dynamic>{'userId': userId},
    );
  }

  /// تاریخچه‌ی مسیر یک بازه.
  ///
  /// سقف نقاط عمداً محدود است: یک روز پینگ هر ۳۰ ثانیه یعنی حدود ۲۸۰۰
  /// نقطه که هم پاسخ را سنگین می‌کند و هم رسم چندهزار نقطه روی نقشه،
  /// گوشی‌های ضعیف را کند می‌کند.
  Future<HistoryResult> history({
    required String userId,
    required DateTime from,
    required DateTime to,
    int limit = 2000,
  }) async {
    return _api.get<HistoryResult>(
      ApiEndpoints.history,
      (dynamic data) {
        if (data is! Map<String, dynamic>) return const HistoryResult();
        return HistoryResult.fromJson(data);
      },
      query: <String, dynamic>{
        'userId': userId,
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
        'limit': limit,
      },
    );
  }
}

final Provider<WatchingRepository> watchingRepositoryProvider =
    Provider<WatchingRepository>((ref) {
  return WatchingRepository(ref.watch(apiClientProvider));
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/utils/app_exception.dart';
import '../../auth/domain/auth_models.dart';
import '../domain/pairing_models.dart';

/// دسترسی به APIهای سرپرستی و کد دعوت.
class PairingRepository {
  PairingRepository(this._api);

  final ApiClient _api;

  /// ساخت کد دعوت تازه.
  ///
  /// پاسخ سرور دو بخش دارد: `code` (که فقط همین یک بار برمی‌گردد) و
  /// `invite` (فراداده‌ی ماندگار). اینجا در یک شیء ادغام می‌شوند تا لایه‌ی
  /// بالاتر مجبور نباشد این جزئیات را بشناسد.
  Future<InviteCode> createInvite(List<SharePermission> permissions) async {
    return _api.post<InviteCode>(
      ApiEndpoints.invites,
      (dynamic data) {
        final Map<String, dynamic> map = _asMap(data);
        final Map<String, dynamic>? invite = Json.mapOrNull(map['invite']);

        if (invite == null) {
          throw const AppException(
            message: 'پاسخ سرور معتبر نبود.',
            code: 'BAD_PAYLOAD',
          );
        }

        final InviteCode parsed = InviteCode.fromJson(invite);

        return InviteCode(
          id: parsed.id,
          code: Json.strOrNull(map, 'code'),
          permissions: parsed.permissions,
          expiresAt: parsed.expiresAt,
          isUsed: parsed.isUsed,
          createdAt: parsed.createdAt,
        );
      },
      body: <String, dynamic>{
        'permissions': permissions.map((SharePermission p) => p.wire).toList(),
      },
    );
  }

  Future<List<InviteCode>> listInvites() async {
    return _api.get<List<InviteCode>>(
      ApiEndpoints.invites,
      (dynamic data) {
        return Json.mapList(_asMap(data)['invites'])
            .map(InviteCode.fromJson)
            .toList(growable: false);
      },
    );
  }

  Future<void> cancelInvite(String id) async {
    await _api.delete<void>(ApiEndpoints.invite(id), (dynamic _) {});
  }

  /// مصرف کد دعوت — سمت مراقب.
  Future<Guardianship> redeem(String code) async {
    return _api.post<Guardianship>(
      ApiEndpoints.redeem,
      (dynamic data) {
        final Map<String, dynamic>? guardianship =
            Json.mapOrNull(_asMap(data)['guardianship']);

        if (guardianship == null) {
          throw const AppException(
            message: 'پاسخ سرور معتبر نبود.',
            code: 'BAD_PAYLOAD',
          );
        }
        return Guardianship.fromJson(guardianship);
      },
      body: <String, dynamic>{'code': code},
    );
  }

  Future<GuardianshipLists> list() async {
    return _api.get<GuardianshipLists>(
      ApiEndpoints.guardianships,
      (dynamic data) => GuardianshipLists.fromJson(_asMap(data)),
    );
  }

  /// تغییر سطح دسترسی یک مراقب — فقط کاربر اصلی می‌تواند.
  Future<Guardianship> updatePermissions(
    String guardianshipId,
    List<SharePermission> permissions,
  ) async {
    return _api.patch<Guardianship>(
      ApiEndpoints.guardianship(guardianshipId),
      (dynamic data) {
        final Map<String, dynamic>? updated =
            Json.mapOrNull(_asMap(data)['guardianship']);
        if (updated == null) {
          throw const AppException(
            message: 'پاسخ سرور معتبر نبود.',
            code: 'BAD_PAYLOAD',
          );
        }
        return Guardianship.fromJson(updated);
      },
      body: <String, dynamic>{
        'permissions': permissions.map((SharePermission p) => p.wire).toList(),
      },
    );
  }

  /// قطع رابطه.
  ///
  /// هر دو طرف می‌توانند قطع کنند — کاربر اصلی حق دارد دسترسی را پس بگیرد،
  /// و مراقب حق دارد از مسئولیت کنار برود.
  Future<void> revoke(String guardianshipId) async {
    await _api.delete<void>(
      ApiEndpoints.guardianship(guardianshipId),
      (dynamic _) {},
    );
  }

  static Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    throw const AppException(
      message: 'پاسخ سرور قابل خواندن نبود.',
      code: 'BAD_PAYLOAD',
    );
  }
}

final Provider<PairingRepository> pairingRepositoryProvider =
    Provider<PairingRepository>((ref) {
  return PairingRepository(ref.watch(apiClientProvider));
});

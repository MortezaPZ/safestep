import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../network/api_client.dart';
import '../network/api_endpoints.dart';
import '../storage/token_store.dart';

/// ثبت دستگاه در سرور.
///
/// ── چرا `installId` و نه توکن FCM ───────────────────────────────────────
/// توکن FCM با پاک کردن داده‌ی اپ، نصب مجدد، یا گاهی خودبه‌خود عوض می‌شود.
/// اگر یکتاسازی دستگاه فقط بر آن استوار باشد، فهرست دستگاه‌های کاربر بعد از
/// چند ماه پر از ردیف مرده می‌شود و نوتیفیکیشن به توکن‌های باطل می‌رود.
///
/// `installId` یک UUID است که همین‌جا ساخته و در Keychain/Keystore ذخیره
/// می‌شود؛ با خروج از حساب هم پاک نمی‌شود چون همان گوشی است.
///
/// ── چرا اصلاً در گام ۴ ──────────────────────────────────────────────────
/// ثبت دستگاه به نوتیفیکیشن گره نخورده است: پنل ادمین از همین داده
/// می‌فهمد چه کسی با چه نسخه‌ای از اپ کار می‌کند، و در گام ۵ همین ردیف است
/// که سطح باتری را نگه می‌دارد.
class DeviceRegistrar {
  DeviceRegistrar(this._api, this._tokenStore);

  final ApiClient _api;
  final TokenStore _tokenStore;

  static const Uuid _uuid = Uuid();

  /// ثبت یا به‌روزرسانی دستگاه جاری.
  ///
  /// شکستش هرگز جریان ورود را متوقف نمی‌کند: کاربری که وارد شده، نباید
  /// به‌خاطر خطای یک درخواست جانبی بیرون بماند.
  Future<void> registerCurrentDevice({String? pushToken}) async {
    try {
      final String installId = await _tokenStore.installId(() => _uuid.v4());
      final _DeviceInfo info = await _collect();

      await _api.post<void>(
        ApiEndpoints.devices,
        (dynamic _) {},
        body: <String, dynamic>{
          'platform': info.platform,
          'installId': installId,
          'deviceName': info.name,
          'model': info.model,
          'osVersion': info.osVersion,
          'appVersion': info.appVersion,
          if (pushToken != null) 'pushToken': pushToken,
        },
      );
    } catch (_) {
      // بی‌صدا. این یک عملیات کمکی است، نه بخشی از مسیر بحرانی.
    }
  }

  Future<_DeviceInfo> _collect() async {
    final DeviceInfoPlugin plugin = DeviceInfoPlugin();
    final PackageInfo package = await PackageInfo.fromPlatform();

    if (Platform.isAndroid) {
      final AndroidDeviceInfo android = await plugin.androidInfo;
      return _DeviceInfo(
        platform: 'android',
        name: android.model,
        model: '${android.manufacturer} ${android.model}',
        osVersion: 'Android ${android.version.release}',
        appVersion: package.version,
      );
    }

    if (Platform.isIOS) {
      final IosDeviceInfo ios = await plugin.iosInfo;
      return _DeviceInfo(
        platform: 'ios',
        name: ios.name,
        model: ios.utsname.machine,
        osVersion: 'iOS ${ios.systemVersion}',
        appVersion: package.version,
      );
    }

    return _DeviceInfo(
      platform: 'web',
      name: 'نامشخص',
      model: null,
      osVersion: null,
      appVersion: package.version,
    );
  }
}

class _DeviceInfo {
  const _DeviceInfo({
    required this.platform,
    required this.name,
    required this.model,
    required this.osVersion,
    required this.appVersion,
  });

  final String platform;
  final String name;
  final String? model;
  final String? osVersion;
  final String appVersion;
}

final Provider<DeviceRegistrar> deviceRegistrarProvider =
    Provider<DeviceRegistrar>((ref) {
  return DeviceRegistrar(
    ref.watch(apiClientProvider),
    ref.watch(tokenStoreProvider),
  );
});

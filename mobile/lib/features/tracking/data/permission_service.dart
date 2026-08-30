import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../domain/location_sample.dart';

/// مدیریت مجوزهای موقعیت.
///
/// ── چرا این‌قدر پیچیده است ──────────────────────────────────────────────
/// از اندروید ۱۱ به بعد، مجوز «همیشه» را **نمی‌توان در یک مرحله گرفت**.
/// سیستم‌عامل اول فقط «هنگام استفاده» را نشان می‌دهد و درخواست «همیشه»
/// باید در یک گفت‌وگوی جداگانه و بعد از آن انجام شود. اگر هر دو را با هم
/// بخواهیم، دیالوگ دوم اصلاً ظاهر نمی‌شود و اپ بی‌سروصدا بدون مجوز
/// پس‌زمینه می‌ماند.
///
/// ── و چرا ترتیب اهمیت دارد ──────────────────────────────────────────────
/// پیش از هر درخواستی، باید توضیح دهیم چرا. کاربری که بدون توضیح با
/// دیالوگ «همیشه به موقعیت شما دسترسی داشته باشد؟» روبه‌رو شود، «نه»
/// می‌زند — و «نه»ی دوم در اندروید یعنی «دیگر نپرس»، که تنها راه جبرانش
/// رفتن دستی به تنظیمات سیستم است.
///
/// برای همین این کلاس فقط وضعیت را برمی‌گرداند و **خودش دیالوگ توضیحی
/// نشان نمی‌دهد**؛ آن کار لایه‌ی رابط کاربری است که پیش از صدا زدن این
/// توابع انجامش می‌دهد.
class LocationPermissionService {
  const LocationPermissionService();

  /// وضعیت فعلی، بدون هیچ درخواستی.
  Future<LocationPermissionState> check() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationPermissionState.serviceDisabled;
    }

    final LocationPermission permission = await Geolocator.checkPermission();
    return _map(permission, await _hasBackground());
  }

  /// درخواست مجوز پایه (هنگام استفاده).
  ///
  /// این همان چیزی است که برای دیدن موقعیت روی نقشه و برای SOS کافی است.
  Future<LocationPermissionState> requestForeground() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationPermissionState.serviceDisabled;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return _map(permission, await _hasBackground());
  }

  /// درخواست مجوز پس‌زمینه («همیشه»).
  ///
  /// باید **پس از** گرفتن مجوز پایه صدا زده شود. اگر مجوز پایه نباشد،
  /// درخواست پس‌زمینه بی‌اثر است و فقط یک «نه»ی دیگر ثبت می‌کند.
  Future<LocationPermissionState> requestBackground() async {
    final LocationPermissionState base = await check();

    if (base == LocationPermissionState.serviceDisabled ||
        base == LocationPermissionState.permanentlyDenied) {
      return base;
    }

    if (base == LocationPermissionState.denied) {
      // هنوز مجوز پایه نداریم؛ درخواست پس‌زمینه معنا ندارد
      return base;
    }

    // در iOS، `always` از طریق همان API درخواست می‌شود؛ در اندروید
    // permission_handler مجوز جداگانه‌ی locationAlways را می‌گیرد.
    if (Platform.isAndroid) {
      final ph.PermissionStatus status = await ph.Permission.locationAlways.request();
      if (status.isPermanentlyDenied) {
        // کاربر «همیشه» را رد کرده، ولی مجوز پایه سر جایش است:
        // ردیابی فقط هنگام باز بودن اپ کار می‌کند
        return LocationPermissionState.whileInUseOnly;
      }
      return status.isGranted
          ? LocationPermissionState.granted
          : LocationPermissionState.whileInUseOnly;
    }

    final LocationPermission permission = await Geolocator.requestPermission();
    return _map(permission, await _hasBackground());
  }

  /// باز کردن تنظیمات اپ — تنها راه پس از «دیگر نپرس».
  Future<bool> openAppSettings() => ph.openAppSettings();

  /// باز کردن تنظیمات مکان سیستم — وقتی خودِ GPS خاموش است.
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  Future<bool> _hasBackground() async {
    if (!Platform.isAndroid) return true;
    return ph.Permission.locationAlways.isGranted;
  }

  static LocationPermissionState _map(
    LocationPermission permission,
    bool hasBackground,
  ) {
    switch (permission) {
      case LocationPermission.always:
        return LocationPermissionState.granted;

      case LocationPermission.whileInUse:
        return hasBackground
            ? LocationPermissionState.granted
            : LocationPermissionState.whileInUseOnly;

      case LocationPermission.denied:
        return LocationPermissionState.denied;

      case LocationPermission.deniedForever:
        return LocationPermissionState.permanentlyDenied;

      case LocationPermission.unableToDetermine:
        return LocationPermissionState.denied;
    }
  }
}

final Provider<LocationPermissionService> locationPermissionServiceProvider =
    Provider<LocationPermissionService>((ref) => const LocationPermissionService());

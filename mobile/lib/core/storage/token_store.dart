import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// نگهداری توکن‌ها و شناسه‌ی نصب.
///
/// ── چرا SecureStorage و نه SharedPreferences ────────────────────────────
/// توکن refresh سی روز اعتبار دارد و هرکس آن را داشته باشد، می‌تواند به
/// موقعیت زنده‌ی یک انسان دسترسی بگیرد. SharedPreferences روی اندروید یک
/// فایل XML ساده در حافظه‌ی خصوصی اپ است: روی گوشی روت‌شده یا از طریق
/// پشتیبان‌گیری، خواندنش کار سختی نیست.
///
/// `flutter_secure_storage` روی اندروید از Keystore و روی iOS از Keychain
/// استفاده می‌کند — یعنی کلید رمزگذاری در سخت‌افزار می‌ماند و حتی با
/// دسترسی به فایل‌سیستم هم بازیابی نمی‌شود.
///
/// ── شناسه‌ی نصب هم اینجاست، ولی نه به دلیل امنیتی ───────────────────────
/// `installId` راز نیست؛ اینجا نگه داشته می‌شود چون باید همان دوام را
/// داشته باشد. اگر با پاک شدن حافظه‌ی معمولی اپ از بین برود، هر بار یک
/// «دستگاه جدید» ثبت می‌شود و فهرست دستگاه‌های کاربر پر از ردیف مرده
/// می‌شود.
class TokenStore {
  TokenStore(this._storage);

  final FlutterSecureStorage _storage;

  static const String _kAccess = 'auth.accessToken';
  static const String _kRefresh = 'auth.refreshToken';
  static const String _kUser = 'auth.user';
  static const String _kInstallId = 'device.installId';

  /* ─────────────────────── توکن‌ها ─────────────────────── */

  Future<String?> readAccessToken() => _read(_kAccess);
  Future<String?> readRefreshToken() => _read(_kRefresh);

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _kAccess, value: accessToken);
    await _storage.write(key: _kRefresh, value: refreshToken);
  }

  /// فقط توکن دسترسی — پس از تازه‌سازی وقتی سرور توکن refresh تازه نداده.
  Future<void> saveAccessToken(String accessToken) =>
      _storage.write(key: _kAccess, value: accessToken);

  /* ─────────────────────── کاربر ─────────────────────── */

  /// نسخه‌ی محلی پروفایل کاربر.
  ///
  /// با آن، اپ می‌تواند بلافاصله پس از باز شدن، صفحه‌ی درست (کاربر اصلی یا
  /// مراقب) را نشان دهد؛ بدون آنکه منتظر پاسخ `/auth/me` بماند. اعتبارسنجی
  /// واقعی در پس‌زمینه انجام می‌شود.
  Future<Map<String, dynamic>?> readUser() async {
    final String? raw = await _read(_kUser);
    if (raw == null || raw.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      // داده‌ی خراب نباید ورود را بشکند؛ نادیده گرفته و از سرور خوانده می‌شود
      return null;
    }
  }

  Future<void> saveUser(Map<String, dynamic> user) =>
      _storage.write(key: _kUser, value: jsonEncode(user));

  /* ─────────────────────── شناسه‌ی نصب ─────────────────────── */

  /// شناسه‌ی نصب؛ اگر نبود، ساخته و ذخیره می‌شود.
  Future<String> installId(String Function() generate) async {
    final String? existing = await _read(_kInstallId);
    if (existing != null && existing.isNotEmpty) return existing;

    final String created = generate();
    await _storage.write(key: _kInstallId, value: created);
    return created;
  }

  /* ─────────────────────── پاک‌سازی ─────────────────────── */

  /// خروج از حساب.
  ///
  /// `installId` عمداً پاک **نمی‌شود**: همان گوشی است، فقط کاربرش عوض شده.
  /// پاک کردنش یعنی ساختن یک ردیف دستگاه جدید در هر بار ورود.
  Future<void> clearSession() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kUser);
  }

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      // روی بعضی دستگاه‌های اندروید، خواندن Keystore پس از بازیابی پشتیبان
      // با خطا مواجه می‌شود. در آن حالت رفتار درست «کاربر وارد نشده» است،
      // نه کرش کردن اپ در اولین اجرا.
      return null;
    }
  }
}

/* ═══════════════════════════ Providerها ═══════════════════════════ */

final Provider<FlutterSecureStorage> secureStorageProvider =
    Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage(
    // بدون این، روی اندروید ۶ به پایین از رمزگذاری قدیمی استفاده می‌شود
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      // توکن پس از اولین باز شدن قفل گوشی در دسترس است — لازم است، چون
      // سرویس پس‌زمینه‌ی موقعیت باید بتواند بدون باز بودن اپ درخواست بفرستد
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );
});

final Provider<TokenStore> tokenStoreProvider = Provider<TokenStore>((ref) {
  return TokenStore(ref.watch(secureStorageProvider));
});

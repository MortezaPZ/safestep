import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/storage/token_store.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/fa.dart';
import '../domain/auth_models.dart';

/// دسترسی به APIهای احراز هویت.
///
/// این لایه دو کار می‌کند و نه بیشتر: تماس با سرور، و ذخیره یا پاک کردن
/// توکن. هیچ تصمیم رابط کاربری اینجا گرفته نمی‌شود — آن کار کنترلر است.
class AuthRepository {
  AuthRepository(this._api, this._tokenStore);

  final ApiClient _api;
  final TokenStore _tokenStore;

  Future<AuthSession> register({
    required String phone,
    required String password,
    required String fullName,
    required UserRole role,
    String? verificationToken,
  }) async {
    final AuthSession session = await _api.post<AuthSession>(
      ApiEndpoints.register,
      (dynamic data) => AuthSession.fromJson(_asMap(data)),
      body: <String, dynamic>{
        'phone': Fa.normalizePhone(phone),
        'password': password,
        'fullName': fullName.trim(),
        'role': role == UserRole.guardian ? 'guardian' : 'primary',
        if (verificationToken != null) 'verificationToken': verificationToken,
      },
    );

    await _persist(session);
    return session;
  }

  Future<AuthSession> login({
    required String phone,
    required String password,
  }) async {
    final AuthSession session = await _api.post<AuthSession>(
      ApiEndpoints.login,
      (dynamic data) => AuthSession.fromJson(_asMap(data)),
      body: <String, dynamic>{
        'phone': Fa.normalizePhone(phone),
        'password': password,
      },
    );

    await _persist(session);
    return session;
  }

  /// خواندن پروفایل کاربرِ واردشده.
  ///
  /// اگر توکن منقضی باشد، میان‌افزار `ApiClient` خودش تازه‌سازی می‌کند و
  /// این تابع اصلاً متوجه نمی‌شود.
  Future<AppUser> me() async {
    return _api.get<AppUser>(
      ApiEndpoints.me,
      (dynamic data) {
        final Map<String, dynamic> map = _asMap(data);
        final Map<String, dynamic>? user = Json.mapOrNull(map['user']);
        if (user == null) {
          throw const AppException(
            message: 'پاسخ سرور معتبر نبود.',
            code: 'BAD_PAYLOAD',
          );
        }
        return AppUser.fromJson(user);
      },
    );
  }

  Future<UserSettings> settings() async {
    return _api.get<UserSettings>(
      ApiEndpoints.settings,
      (dynamic data) {
        final Map<String, dynamic> map = _asMap(data);
        final Map<String, dynamic>? settings = Json.mapOrNull(map['settings']);
        return settings == null
            ? const UserSettings()
            : UserSettings.fromJson(settings);
      },
    );
  }

  /// همگام‌سازی ترجیحات دسترس‌پذیری با سرور.
  ///
  /// چرا اصلاً روی سرور: کاربری که متن را دو برابر کرده، با تعویض گوشی
  /// نباید دوباره با متن ریز روبه‌رو شود — همان کاربری که اصلاً به این
  /// تنظیم نیاز داشته.
  Future<UserSettings> updateAccessibility({
    double? textScale,
    bool? highContrastEnabled,
    bool? hapticFeedbackEnabled,
  }) async {
    return _api.patch<UserSettings>(
      ApiEndpoints.settings,
      (dynamic data) {
        final Map<String, dynamic>? settings =
            Json.mapOrNull(_asMap(data)['settings']);
        return settings == null
            ? const UserSettings()
            : UserSettings.fromJson(settings);
      },
      body: <String, dynamic>{
        if (textScale != null) 'textScale': textScale,
        if (highContrastEnabled != null) 'highContrastEnabled': highContrastEnabled,
        if (hapticFeedbackEnabled != null) 'hapticFeedbackEnabled': hapticFeedbackEnabled,
      },
    );
  }

  /// خروج از حساب.
  ///
  /// توکن‌های محلی **در هر حالت** پاک می‌شوند، حتی اگر تماس با سرور شکست
  /// بخورد. کاربری که «خروج» را زده، انتظار دارد از حساب بیرون بیاید؛
  /// نگه داشتن توکن به‌خاطر قطعی اینترنت، همان چیزی است که او نمی‌خواهد.
  Future<void> logout() async {
    final String? refreshToken = await _tokenStore.readRefreshToken();

    try {
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _api.post<void>(
          ApiEndpoints.logout,
          (dynamic _) {},
          body: <String, dynamic>{'refreshToken': refreshToken},
        );
      }
    } catch (_) {
      // شکست ابطال سمت سرور نباید جلوی خروج محلی را بگیرد
    } finally {
      await _tokenStore.clearSession();
    }
  }

  /// خواندن نشست ذخیره‌شده هنگام باز شدن اپ.
  ///
  /// کاربرِ محلی بلافاصله برگردانده می‌شود تا صفحه‌ی درست بدون انتظار نمایش
  /// داده شود؛ اعتبارسنجی واقعی با `me()` جداگانه انجام می‌شود.
  Future<AppUser?> restoreLocalUser() async {
    final String? token = await _tokenStore.readRefreshToken();
    if (token == null || token.isEmpty) return null;

    final Map<String, dynamic>? cached = await _tokenStore.readUser();
    if (cached == null) return null;

    return AppUser.fromJson(cached);
  }

  Future<void> cacheUser(AppUser user) => _tokenStore.saveUser(user.toJson());

  Future<void> clearLocal() => _tokenStore.clearSession();

  Future<Map<String, dynamic>> publicConfig() {
    return _api.get<Map<String, dynamic>>(
      ApiEndpoints.publicConfig,
      (dynamic data) => data is Map<String, dynamic> ? data : <String, dynamic>{},
    );
  }

  Future<String?> requestOtp(String phone, String purpose) async {
    final Map<String, dynamic> data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.otpRequest,
      (dynamic d) => d is Map<String, dynamic> ? d : <String, dynamic>{},
      body: <String, dynamic>{
        'phone': Fa.normalizePhone(phone),
        'purpose': purpose,
      },
    );
    return data['hint'] as String?;
  }

  Future<String> verifyOtp(String phone, String code, String purpose) {
    return _api.post<String>(
      ApiEndpoints.otpVerify,
      (dynamic d) {
        if (d is Map<String, dynamic> && d['verificationToken'] is String) {
          return d['verificationToken'] as String;
        }
        throw const AppException(message: 'تأیید شماره ناموفق بود.', code: 'OTP');
      },
      body: <String, dynamic>{
        'phone': Fa.normalizePhone(phone),
        'code': code,
        'purpose': purpose,
      },
    );
  }

  Future<void> _persist(AuthSession session) async {
    await _tokenStore.saveTokens(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );
    await _tokenStore.saveUser(session.user.toJson());
  }

  static Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    throw const AppException(
      message: 'پاسخ سرور قابل خواندن نبود.',
      code: 'BAD_PAYLOAD',
    );
  }
}

final Provider<AuthRepository> authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(tokenStoreProvider),
  );
});

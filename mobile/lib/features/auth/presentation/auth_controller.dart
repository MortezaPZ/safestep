import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/accessibility/accessibility_settings.dart';
import '../../../core/device/device_registrar.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/app_exception.dart';
import '../data/auth_repository.dart';
import '../domain/auth_models.dart';

/// وضعیت احراز هویت.
///
/// `unknown` حالت واقعی و مهمی است، نه مقدار اولیه‌ی بی‌معنا: تا وقتی
/// خواندن توکن از Keychain تمام نشده، نمی‌دانیم کاربر وارد هست یا نه. اگر
/// این حالت را نداشته باشیم، روتر لحظه‌ای کاربرِ واردشده را به صفحه‌ی ورود
/// می‌فرستد و بعد برمی‌گرداند — پرشی که هم زشت است و هم گیج‌کننده.
enum AuthStatus { unknown, authenticated, unauthenticated }

@immutable
class AuthState {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.settings,
    this.busy = false,
    this.error,
  });

  final AuthStatus status;
  final AppUser? user;
  final UserSettings? settings;

  /// در حال انجام عملیاتِ کاربرآغازشده (ورود، ثبت‌نام، خروج)
  final bool busy;

  final AppException? error;

  bool get isAuthenticated => status == AuthStatus.authenticated && user != null;
  bool get isReady => status != AuthStatus.unknown;

  AuthState copyWith({
    AuthStatus? status,
    AppUser? user,
    UserSettings? settings,
    bool? busy,
    AppException? error,
    bool clearError = false,
    bool clearUser = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: clearUser ? null : (user ?? this.user),
      settings: clearUser ? null : (settings ?? this.settings),
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/* ═══════════════════════════ کنترلر ═══════════════════════════ */

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._ref) : super(const AuthState());

  final Ref _ref;

  AuthRepository get _repository => _ref.read(authRepositoryProvider);

  /* ─────────────────────── بازیابی نشست ─────────────────────── */

  /// خواندن نشست ذخیره‌شده هنگام باز شدن اپ.
  ///
  /// دو مرحله دارد و ترتیبش عمدی است:
  ///
  /// ۱) کاربرِ ذخیره‌شده‌ی محلی بی‌درنگ اعمال می‌شود تا اپ بلافاصله صفحه‌ی
  ///    درست را نشان دهد.
  /// ۲) اعتبار توکن در پس‌زمینه با `/auth/me` بررسی می‌شود.
  ///
  /// اگر مرحله‌ی دوم شکست بخورد **به‌دلیل شبکه**، کاربر بیرون انداخته
  /// نمی‌شود: کسی که در آسانسور اپ را باز می‌کند نباید از حسابش خارج شود.
  /// فقط ۴۰۱ (که میان‌افزار هم نتوانسته با تازه‌سازی درستش کند) یعنی پایان
  /// نشست.
  Future<void> restore() async {
    final AppUser? cached = await _repository.restoreLocalUser();

    if (cached == null) {
      state = state.copyWith(status: AuthStatus.unauthenticated, clearUser: true);
      return;
    }

    state = state.copyWith(status: AuthStatus.authenticated, user: cached);

    try {
      final AppUser fresh = await _repository.me();
      await _repository.cacheUser(fresh);
      state = state.copyWith(user: fresh);
      await _afterSignIn();
    } on AppException catch (error) {
      if (error.kind == AppErrorKind.auth) {
        await _forceSignOut();
      }
      // خطای شبکه: همان کاربر محلی نگه داشته می‌شود
    }
  }

  /* ─────────────────────── ورود و ثبت‌نام ─────────────────────── */

  Future<bool> login({required String phone, required String password}) async {
    state = state.copyWith(busy: true, clearError: true);

    try {
      final AuthSession session = await _repository.login(
        phone: phone,
        password: password,
      );

      state = AuthState(
        status: AuthStatus.authenticated,
        user: session.user,
        settings: session.settings,
      );

      await _afterSignIn();
      return true;
    } on AppException catch (error) {
      state = state.copyWith(busy: false, error: error);
      return false;
    }
  }

  Future<bool> register({
    required String phone,
    required String password,
    required String fullName,
    required UserRole role,
    String? verificationToken,
  }) async {
    state = state.copyWith(busy: true, clearError: true);

    try {
      final AuthSession session = await _repository.register(
        phone: phone,
        password: password,
        fullName: fullName,
        role: role,
        verificationToken: verificationToken,
      );
    state = state.copyWith(busy: true, clearError: true);

    try {
      final AuthSession session = await _repository.register(
        phone: phone,
        password: password,
        fullName: fullName,
        role: role,
      );

      state = AuthState(
        status: AuthStatus.authenticated,
        user: session.user,
        settings: session.settings,
      );

      await _afterSignIn();
      return true;
    } on AppException catch (error) {
      state = state.copyWith(busy: false, error: error);
      return false;
    }
  }

  /* ─────────────────────── خروج ─────────────────────── */

  Future<void> logout() async {
    state = state.copyWith(busy: true);
    await _repository.logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// خروج اجباری — وقتی سرور نشست را باطل کرده است.
  Future<void> _forceSignOut() async {
    await _repository.clearLocal();
    state = const AuthState(
      status: AuthStatus.unauthenticated,
      error: AppException.unauthorized,
    );
  }

  /// از میان‌افزار شبکه صدا زده می‌شود، وقتی تازه‌سازی توکن هم شکست خورده.
  Future<void> handleSessionExpired() async {
    if (state.status != AuthStatus.authenticated) return;
    await _forceSignOut();
  }

  /* ─────────────────────── پس از ورود ─────────────────────── */

  /// کارهایی که پس از هر ورود موفق انجام می‌شوند.
  ///
  /// هیچ‌کدام بحرانی نیستند و شکستشان ورود را باطل نمی‌کند — برای همین
  /// هرکدام جداگانه محافظت شده‌اند.
  Future<void> _afterSignIn() async {
    state = state.copyWith(busy: false);

    // ثبت دستگاه (بی‌صدا شکست می‌خورد)
    await _ref.read(deviceRegistrarProvider).registerCurrentDevice();

    // ترجیحات دسترس‌پذیریِ ذخیره‌شده روی سرور، روی تنظیم محلی اعمال می‌شود.
    // جهت همگام‌سازی فقط همین یک بار سرور→اپ است؛ در ادامه‌ی کار برعکس
    // می‌شود، وگرنه تغییرِ کاربر با پاسخِ درخواستِ در راه بازنویسی می‌شد.
    try {
      final UserSettings settings = await _repository.settings();
      state = state.copyWith(settings: settings);

      await _ref.read(accessibilityProvider.notifier).applyRemote(
            textScale: settings.textScale,
            highContrast: settings.highContrastEnabled,
            hapticFeedback: settings.hapticFeedbackEnabled,
          );
    } catch (_) {
      // تنظیمات محلی همان‌طور که هست می‌ماند
    }
  }

  /// ارسال ترجیحات دسترس‌پذیری به سرور — از صفحه‌ی تنظیمات صدا زده می‌شود.
  Future<void> pushAccessibilitySettings() async {
    if (!state.isAuthenticated) return;

    final AccessibilitySettings local = _ref.read(accessibilityProvider);

    try {
      await _repository.updateAccessibility(
        textScale: local.textScale,
        highContrastEnabled: local.highContrast,
        hapticFeedbackEnabled: local.hapticFeedback,
      );
    } catch (_) {
      // همگام‌سازی ترجیحات، هرگز نباید به کاربر خطا نشان دهد
    }
  }

  void clearError() {
    if (state.error != null) state = state.copyWith(clearError: true);
  }
}

/* ═══════════════════════════ Providerها ═══════════════════════════ */

final StateNotifierProvider<AuthController, AuthState> authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  final AuthController controller = AuthController(ref);

  // پل بین میان‌افزار شبکه و کنترلر: وقتی تازه‌سازی توکن شکست بخورد،
  // `ApiClient` شمارنده را زیاد می‌کند و اینجا کاربر بیرون برده می‌شود.
  ref.listen<int>(sessionExpiredSignalProvider, (int? previous, int next) {
    if (previous != null && next > previous) {
      unawaited(controller.handleSessionExpired());
    }
  });

  return controller;
});

/// میان‌بُرهای پرکاربرد، تا صفحه‌ها کل وضعیت را `watch` نکنند و بی‌دلیل
/// بازسازی نشوند.
final Provider<AppUser?> currentUserProvider = Provider<AppUser?>((ref) {
  return ref.watch(authControllerProvider).user;
});

final Provider<bool> isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authControllerProvider).isAuthenticated;
});
